import Accelerate
import CoreAudio
import Foundation
import IRSKit

/// Wires the four pieces together:
///
///     system audio ──▶ process tap ──▶ ring buffer ──▶ IRS convolver ──▶ output unit
///
/// The tap mutes the original audio at the hardware while it is being read, so
/// what leaves the machine is only the convolved signal.
final class AudioEngine: @unchecked Sendable {
    enum State: Equatable {
        case stopped
        case starting
        case running
        case failed(String)
    }

    let processor = IRSProcessor(blockSize: 256)
    let inputLevel = AtomicLevel(0)
    let outputLevel = AtomicLevel(0)
    /// Incremented by every render callback; watched by the UI's safety net.
    let renderCallbacks = AtomicLevel(0)
    /// Frames delivered by the tap, which proves capture is alive even when the
    /// machine is silent or the output path is not running.
    let capturedFrames = AtomicLevel(0)
    /// Largest buffers seen on each side. The real device buffer size is not
    /// always what the HAL reports up front, so it is measured instead.
    let maxTapFrames = AtomicLevel(0)
    let maxRenderFrames = AtomicLevel(0)

    private(set) var state: State = .stopped
    private(set) var sampleRate: Double = 48_000
    private(set) var sourceDescription = "—"
    private(set) var captureFormatDescription = "—"
    private(set) var impulseResponseName: String?
    private(set) var impulseResponseError: String?

    /// Diagnostics, refreshed from the UI timer.
    private(set) var ringFill = 0
    private(set) var driftDrops = 0
    /// True once playback has begun. Core Audio idles the hardware when nothing
    /// is playing, so callbacks can legitimately stop on a silent machine.
    private(set) var outputStarted = false
    /// Frames the ring had to fabricate or discard; both should stay at zero.
    var missingFrames: Int { Int(ring?.missingFrames.load() ?? 0) }
    var droppedFrames: Int { Int(ring?.droppedFrames.load() ?? 0) }
    var onStateChange: ((State) -> Void)?

    private var selectedIR: URL?
    var normalizeImpulseResponse = true {
        didSet { reloadImpulseResponse() }
    }
    var impulseResponseURL: URL? {
        get { selectedIR }
        set {
            guard selectedIR != newValue else { return }
            selectedIR = newValue
            reloadImpulseResponse()
        }
    }

    private var tap: SystemAudioTap?
    private var capture: TapCapture?
    private var output: OutputUnit?
    private var ring: AudioRingBuffer?

    private let scratchCapacity = 16_384
    private let scratchLeft: UnsafeMutablePointer<Float>
    private let scratchRight: UnsafeMutablePointer<Float>
    private let renderLeft: UnsafeMutablePointer<Float>
    private let renderRight: UnsafeMutablePointer<Float>

    /// Ring occupancy to hold: enough to cover one buffer from each side plus a
    /// little jitter margin, measured from what the devices actually deliver.
    var bufferTargetFrames: Int {
        let tap = Int(maxTapFrames.load())
        let render = Int(maxRenderFrames.load())
        let base = max(tap, 256)
        let other = render > 0 ? render : base
        return base + other
    }
    private var generation = 0
    private var driftCounter = 0
    /// Setup runs on its own queue: creating the tap can block inside Core Audio
    /// while macOS waits for the system-audio permission prompt, and the menu bar
    /// UI must stay alive (and quittable) while that happens.
    private var setupQueue: DispatchQueue?
    private(set) var isWaitingForPermission = false
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var deviceChangeWorkItem: DispatchWorkItem?
    private let loadQueue = DispatchQueue(label: "com.asep.irsverb.ir-loader", qos: .userInitiated)

    init() {
        scratchLeft = UnsafeMutablePointer<Float>.allocate(capacity: scratchCapacity)
        scratchRight = UnsafeMutablePointer<Float>.allocate(capacity: scratchCapacity)
        renderLeft = UnsafeMutablePointer<Float>.allocate(capacity: scratchCapacity)
        renderRight = UnsafeMutablePointer<Float>.allocate(capacity: scratchCapacity)
        scratchLeft.initialize(repeating: 0, count: scratchCapacity)
        scratchRight.initialize(repeating: 0, count: scratchCapacity)
        renderLeft.initialize(repeating: 0, count: scratchCapacity)
        renderRight.initialize(repeating: 0, count: scratchCapacity)
        installDeviceListener()
    }

    deinit {
        if let deviceListener {
            var address = caAddress(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(CoreAudio.systemObject, &address, DispatchQueue.main, deviceListener)
        }
        stop()
        scratchLeft.deallocate()
        scratchRight.deallocate()
        renderLeft.deallocate()
        renderRight.deallocate()
    }

    // MARK: - Lifecycle

    func start() {
        stop()
        generation += 1
        let token = generation
        let began = Date()
        state = .starting
        isWaitingForPermission = false
        onStateChange?(state)
        AppLog.write("engine starting (token \(token))")

        // A previous attempt may still be stuck inside Core Audio; a fresh queue
        // keeps that from blocking this one.
        let queue = DispatchQueue(label: "com.asep.irsverb.engine-setup.\(token)", qos: .userInitiated)
        setupQueue = queue
        queue.async { [weak self] in
            self?.performSetup(token: token, began: began)
        }
    }

    /// Blocking part of the startup, off the main thread.
    private func performSetup(token: Int, began: Date) {
        do {
            let tap = try SystemAudioTap()
            let rate = tap.sampleRate
            let ring = AudioRingBuffer(capacity: 32_768)
            let capture = TapCapture(deviceID: tap.aggregateDeviceID,
                                     format: tap.streamFormat,
                                     ring: ring,
                                     level: inputLevel,
                                     frameCounter: capturedFrames,
                                     maxCallbackFrames: maxTapFrames)
            let output = try OutputUnit(engine: self, sampleRate: rate)
            try capture.start()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.generation == token else {
                    // A stop or a newer start overtook this attempt: undo it.
                    AppLog.write("engine setup for token \(token) discarded")
                    capture.stop()
                    output.stop()
                    tap.destroy()
                    return
                }
                self.tap = tap
                self.ring = ring
                self.capture = capture
                self.output = output
                self.sampleRate = rate
                self.sourceDescription = CoreAudio.deviceName(CoreAudio.defaultOutputDevice())
                self.captureFormatDescription = CoreAudio.describe(tap.streamFormat)
                self.driftDrops = 0
                self.processor.reset()
                self.performImpulseResponseLoad()
                self.startOutputWhenReady(token: token, began: began)
                self.state = .running
                self.onStateChange?(self.state)
                AppLog.write("engine running: \(Int(rate)) Hz, tap \(self.captureFormatDescription), "
                    + "device '\(self.sourceDescription)', buffer target \(self.bufferTargetFrames), "
                    + "added latency \(Int(self.totalLatencyMilliseconds)) ms")
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.isWaitingForPermission = true
                self.state = .failed(error.localizedDescription)
                self.onStateChange?(self.state)
                AppLog.write("engine failed: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        generation += 1
        deviceChangeWorkItem?.cancel()
        deviceChangeWorkItem = nil
        output?.stop()
        output = nil
        capture?.stop()
        capture = nil
        // Destroying the tap releases the hardware mute.
        tap?.destroy()
        tap = nil
        ring = nil
        outputStarted = false
        isWaitingForPermission = false
        processor.reset()
        inputLevel.store(0)
        outputLevel.store(0)
        ringFill = 0
        if state != .stopped {
            state = .stopped
            onStateChange?(state)
            AppLog.write("engine stopped")
        }
    }

    func restart() {
        start()
    }

    func toggle() {
        if state == .running { stop() } else { start() }
    }

    /// Waits for the tap to come alive and fill the ring, then starts playback.
    ///
    /// Core Audio can take a second or two to deliver the first tap buffers, so
    /// this waits on evidence (captured frames) rather than a fixed delay, and
    /// gives up rather than leaving the system silent forever.
    private func startOutputWhenReady(token: Int, began: Date, ticks: Int = 0) {
        guard generation == token, let ring, let output else { return }
        let captured = capturedFrames.load()
        let target = bufferTargetFrames
        let ready = captured > 0 && ring.fill >= target
        // Silence is normal: Core Audio only delivers tap buffers once something
        // is playing, so this waits for first audio rather than giving up. The
        // cap is only a safety valve for a machine that never plays anything.
        let gaveUp = ticks >= 6000       // ~60 s
        let tapDelay = Date().timeIntervalSince(began)

        guard ready || gaveUp else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                self?.startOutputWhenReady(token: token, began: began, ticks: ticks + 1)
            }
            return
        }

        // Drop the startup backlog before anything is audible: the tap fills the
        // ring for a second or two while the output unit is being prepared, and
        // that backlog would otherwise be permanent latency. Nothing has been
        // played yet, so trimming here is inaudible.
        let excess = ring.fill - target
        if excess > 0 { ring.dropOldest(excess) }

        do {
            try output.start()
            outputStarted = true
            AppLog.write(String(format: "output started after %.2fs (captured %.0f frames, tap buffer %.0f, "
                                + "trimmed %d frames, fill %d%@)",
                                tapDelay, captured, maxTapFrames.load(), max(0, excess), ring.fill,
                                ready ? "" : ", gave up waiting"))
        } catch {
            // Never leave the system muted with nothing playing: stop the whole
            // engine so the tap is destroyed and audio is restored.
            let message = error.localizedDescription
            AppLog.write("output unit failed to start: \(message)")
            stop()
            state = .failed("Playback could not start: \(message)")
            onStateChange?(state)
        }
    }

    private func installDeviceListener() {
        var address = caAddress(kAudioHardwarePropertyDefaultOutputDevice)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.handleDefaultDeviceChange() }
        }
        let status = AudioObjectAddPropertyListenerBlock(CoreAudio.systemObject, &address, DispatchQueue.main, block)
        if status == noErr { deviceListener = block }
    }

    private func handleDefaultDeviceChange() {
        guard state == .running else { return }
        // A device switch fires several notifications in a row.
        deviceChangeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .running else { return }
            self.start()
        }
        deviceChangeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    // MARK: - Impulse response

    /// Loads, resamples to the running sample rate and publishes the impulse
    /// response. Called on the control thread; the audio thread only ever sees
    /// a finished, immutable convolver pair.
    func reloadImpulseResponse() {
        // While stopped the load is deferred: start() reloads at the rate the
        // tap actually reports, so doing it twice would be wasted work.
        guard state == .running else { return }
        performImpulseResponseLoad()
    }

    private func performImpulseResponseLoad() {
        let url = selectedIR
        let rate = sampleRate
        let normalize = normalizeImpulseResponse
        loadQueue.async { [weak self] in
            guard let self else { return }
            guard let url else {
                self.processor.unload()
                DispatchQueue.main.async {
                    self.impulseResponseName = nil
                    self.impulseResponseError = nil
                }
                return
            }
            do {
                let response = try IRFile.load(url: url, targetSampleRate: rate, normalize: normalize)
                self.processor.load(response)
                AppLog.write("loaded impulse response '\(response.name)' "
                    + "\(response.frameCount) taps, \(response.channelCount)ch, "
                    + "\(String(format: "%.2f", response.duration))s at \(Int(rate)) Hz")
                DispatchQueue.main.async {
                    self.impulseResponseName = response.name
                    self.impulseResponseError = nil
                }
            } catch {
                AppLog.write("impulse response failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.impulseResponseError = error.localizedDescription
                }
            }
        }
    }

    /// Impulse response length in frames, for the UI's latency readout.
    var totalLatencyFrames: Int {
        // Occupancy actually measured by the audio thread is the honest number.
        processor.latency + max(ringFill, bufferTargetFrames)
    }

    var totalLatencyMilliseconds: Double {
        sampleRate > 0 ? Double(totalLatencyFrames) / sampleRate * 1000 : 0
    }

    // MARK: - Audio thread

    /// Called by the output unit. Pulls from the ring, convolves, and writes the
    /// result into Core Audio's buffers.
    func renderOutput(frameCount: Int, ioData: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let isFirstCallback = renderCallbacks.load() == 0
        if isFirstCallback { AppLog.write("first render callback (\(frameCount) frames)") }
        renderCallbacks.store(renderCallbacks.load() + 1)
        maxRenderFrames.storeMaximum(Float(frameCount))
        let list = UnsafeMutableAudioBufferListPointer(ioData)
        guard let ring, list.count >= 1, let firstData = list[0].mData else {
            for buffer in list {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            return noErr
        }
        let left = firstData.assumingMemoryBound(to: Float.self)
        let right: UnsafeMutablePointer<Float>
        if list.count >= 2, let secondData = list[1].mData {
            right = secondData.assumingMemoryBound(to: Float.self)
        } else {
            right = left
        }

        // The tap keeps filling the ring while the output unit is starting up,
        // so the real backlog is whatever accumulated by the first callback.
        // Trimming here is inaudible: nothing has been played yet.
        if isFirstCallback {
            let excess = ring.fill - bufferTargetFrames
            if excess > 0 {
                ring.dropOldest(excess)
                AppLog.write("trimmed \(excess) startup frames at first render (buffer \(ring.fill))")
            }
        }

        var offset = 0
        while offset < frameCount {
            let count = min(scratchCapacity, frameCount - offset)
            let received = ring.read(into: scratchLeft, scratchRight, count: count)
            if received < count {
                let missing = count - received
                memset(scratchLeft + received, 0, missing * MemoryLayout<Float>.size)
                memset(scratchRight + received, 0, missing * MemoryLayout<Float>.size)
            }
            processor.process(inputLeft: scratchLeft, inputRight: scratchRight,
                              outputLeft: renderLeft, outputRight: renderRight,
                              frameCount: count)
            memcpy(left + offset, renderLeft, count * MemoryLayout<Float>.size)
            memcpy(right + offset, renderRight, count * MemoryLayout<Float>.size)

            var rms: Float = 0
            vDSP_rmsqv(renderLeft, 1, &rms, vDSP_Length(count))
            outputLevel.store(rms)
            offset += count
        }

        applyDriftControl(ring: ring)
        return noErr
    }

    /// Both devices share the same hardware clock in the common case, so the
    /// ring stays put. If it does drift, trim a single frame at a time rather
    /// than letting latency creep.
    private func applyDriftControl(ring: AudioRingBuffer) {
        let fill = ring.fill
        ringFill = fill
        let target = max(bufferTargetFrames, 256)
        let highWater = target + target / 2
        if fill > highWater {
            driftCounter += 1
            if driftCounter > 4 {
                ring.dropOldest(1)
                driftDrops += 1
                driftCounter = 0
            }
        } else {
            driftCounter = 0
        }
    }
}
