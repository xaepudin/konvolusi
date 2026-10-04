import Foundation
import Synchronization

/// A ready-to-use stereo convolution pair built from one impulse response.
///
/// Instances are immutable, so once built they can be handed to the audio
/// thread and swapped atomically (`IRSProcessor`).
public final class ConvolverPair: @unchecked Sendable {
    public let left: PartitionedConvolver
    public let right: PartitionedConvolver
    public let blockSize: Int
    public let name: String
    public let isStereo: Bool

    public init(impulseResponse: ImpulseResponse, blockSize: Int = 256) {
        let leftIR = impulseResponse.channels.first ?? []
        let rightIR = impulseResponse.channelCount > 1 ? impulseResponse.channels[1] : leftIR
        self.left = PartitionedConvolver(impulseResponse: leftIR, blockSize: blockSize)
        self.right = PartitionedConvolver(impulseResponse: rightIR, blockSize: blockSize)
        self.blockSize = blockSize
        self.name = impulseResponse.name
        self.isStereo = impulseResponse.channelCount > 1
    }

    public var latency: Int { blockSize }

    public func reset() {
        left.reset()
        right.reset()
    }

    public func process(inputLeft: UnsafePointer<Float>,
                        inputRight: UnsafePointer<Float>,
                        outputLeft: UnsafeMutablePointer<Float>,
                        outputRight: UnsafeMutablePointer<Float>,
                        frameCount: Int) {
        left.process(input: inputLeft, output: outputLeft, frameCount: frameCount)
        right.process(input: inputRight, output: outputRight, frameCount: frameCount)
    }
}

/// Real-time processor: two partitioned convolvers plus dry/wet, output gain and
/// bypass. Loading a new impulse response is done from a control thread and
/// published to the audio thread through an atomic pointer swap.
public final class IRSProcessor: @unchecked Sendable {
    public let blockSize: Int

    private let pairSlot = Atomic<UInt>(0)          // Unmanaged<ConvolverPair> bit pattern
    private var retired: [(pair: ConvolverPair, at: Date)] = []
    private static let retireLimit = 8
    private static let retireAge: TimeInterval = 5

    private let wetBits = Atomic<UInt32>(Float(1).bitPattern)
    private let gainBits = Atomic<UInt32>(Float(1).bitPattern)
    private let bypassBits = Atomic<UInt32>(0)

    // Dry signal delay so that dry and wet stay time aligned through the block engine.
    private var dryLeft: UnsafeMutablePointer<Float>
    private var dryRight: UnsafeMutablePointer<Float>
    private var dryIndex = 0

    public private(set) var impulseResponseName: String?
    public private(set) var impulseResponseLatency: Int = 0

    public init(blockSize: Int = 256) {
        self.blockSize = blockSize
        dryLeft = UnsafeMutablePointer<Float>.allocate(capacity: blockSize)
        dryRight = UnsafeMutablePointer<Float>.allocate(capacity: blockSize)
        dryLeft.initialize(repeating: 0, count: blockSize)
        dryRight.initialize(repeating: 0, count: blockSize)
    }

    deinit {
        dryLeft.deallocate()
        dryRight.deallocate()
        if let pair = currentPair() {
            Unmanaged.passUnretained(pair).release()
        }
    }

    // MARK: - Parameters (control thread writes, audio thread reads)

    /// Wet amount, 0 = fully dry, 1 = fully convolved.
    public var wet: Float {
        get { Float(bitPattern: wetBits.load(ordering: .relaxed)) }
        set { wetBits.store(newValue.clamped(to: 0...1).bitPattern, ordering: .relaxed) }
    }

    /// Linear output gain.
    public var gain: Float {
        get { Float(bitPattern: gainBits.load(ordering: .relaxed)) }
        set { gainBits.store(max(0, newValue).bitPattern, ordering: .relaxed) }
    }

    public var gainDecibels: Float {
        get { gain <= 0 ? -120 : 20 * log10(gain) }
        set { gain = pow(10, newValue / 20) }
    }

    public var isBypassed: Bool {
        get { bypassBits.load(ordering: .relaxed) != 0 }
        set { bypassBits.store(newValue ? 1 : 0, ordering: .relaxed) }
    }

    /// Latency of the active impulse response, in samples (0 when none is loaded).
    public var latency: Int { currentPair()?.latency ?? 0 }

    // MARK: - Impulse response management

    private func currentPair() -> ConvolverPair? {
        let bits = pairSlot.load(ordering: .acquiring)
        guard let pointer = UnsafeMutableRawPointer(bitPattern: bits) else { return nil }
        return Unmanaged<ConvolverPair>.fromOpaque(pointer).takeUnretainedValue()
    }

    /// Publishes a new impulse response to the audio thread. Safe to call while
    /// audio is running; the previous response is kept alive for a few seconds
    /// so any in-flight render callback can finish with it.
    public func load(_ impulseResponse: ImpulseResponse) {
        let pair = ConvolverPair(impulseResponse: impulseResponse, blockSize: blockSize)
        let newBits = UInt(bitPattern: Unmanaged.passRetained(pair).toOpaque())
        let oldBits = pairSlot.exchange(newBits, ordering: .acquiringAndReleasing)
        if let pointer = UnsafeMutableRawPointer(bitPattern: oldBits) {
            let old = Unmanaged<ConvolverPair>.fromOpaque(pointer).takeUnretainedValue()
            retired.append((old, Date()))
        }
        impulseResponseName = pair.name
        impulseResponseLatency = pair.latency
        collectRetired()
        reset()
    }

    public func unload() {
        let oldBits = pairSlot.exchange(0, ordering: .acquiringAndReleasing)
        if let pointer = UnsafeMutableRawPointer(bitPattern: oldBits) {
            let old = Unmanaged<ConvolverPair>.fromOpaque(pointer).takeUnretainedValue()
            retired.append((old, Date()))
        }
        impulseResponseName = nil
        impulseResponseLatency = 0
        collectRetired()
    }

    private func collectRetired() {
        let cutoff = Date().addingTimeInterval(-Self.retireAge)
        while retired.count > Self.retireLimit, let first = retired.first, first.at < cutoff {
            retired.removeFirst()
        }
    }

    public func reset() {
        currentPair()?.reset()
        dryLeft.update(repeating: 0, count: blockSize)
        dryRight.update(repeating: 0, count: blockSize)
        dryIndex = 0
    }

    // MARK: - Audio thread

    /// Processes `frameCount` frames. When no impulse response is loaded this is
    /// a gapless, latency-free pass-through (times gain).
    public func process(inputLeft: UnsafePointer<Float>,
                        inputRight: UnsafePointer<Float>,
                        outputLeft: UnsafeMutablePointer<Float>,
                        outputRight: UnsafeMutablePointer<Float>,
                        frameCount: Int) {
        let pair = currentPair()
        let wetAmount = Float(bitPattern: wetBits.load(ordering: .relaxed))
        let gain = Float(bitPattern: gainBits.load(ordering: .relaxed))
        let bypassed = bypassBits.load(ordering: .relaxed) != 0

        guard let pair, !bypassed else {
            for frame in 0..<frameCount {
                outputLeft[frame] = inputLeft[frame] * gain
                outputRight[frame] = inputRight[frame] * gain
            }
            return
        }

        if wetAmount > 0 {
            pair.process(inputLeft: inputLeft, inputRight: inputRight,
                         outputLeft: outputLeft, outputRight: outputRight,
                         frameCount: frameCount)
        }

        // The dry signal always runs through the block-sized delay line while an
        // impulse response is loaded, so sweeping wet/dry never shifts in time.
        let dryAmount = max(0, 1 - wetAmount)
        for frame in 0..<frameCount {
            let delayedLeft = dryLeft[dryIndex]
            let delayedRight = dryRight[dryIndex]
            dryLeft[dryIndex] = inputLeft[frame]
            dryRight[dryIndex] = inputRight[frame]
            dryIndex += 1
            if dryIndex == blockSize { dryIndex = 0 }

            if dryAmount > 0 {
                outputLeft[frame] = (outputLeft[frame] * wetAmount + delayedLeft * dryAmount) * gain
                outputRight[frame] = (outputRight[frame] * wetAmount + delayedRight * dryAmount) * gain
            } else {
                outputLeft[frame] *= gain
                outputRight[frame] *= gain
            }
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
