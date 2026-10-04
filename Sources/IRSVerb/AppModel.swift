import AppKit
import Combine
import Foundation
import IRSKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    struct ImpulseResponseItem: Identifiable, Hashable {
        let url: URL
        var id: URL { url }
        var name: String { url.deletingPathExtension().lastPathComponent }
    }

    @Published private(set) var items: [ImpulseResponseItem] = []
    @Published var selectedURL: URL? {
        didSet {
            guard selectedURL != oldValue else { return }
            engine.impulseResponseURL = selectedURL
            UserDefaults.standard.set(selectedURL?.path, forKey: Keys.selected)
            refreshInfo()
        }
    }
    @Published var wet: Double = 1 {
        didSet { engine.processor.wet = Float(wet) }
    }
    @Published var gainDB: Double = 0 {
        didSet { engine.processor.gainDecibels = Float(gainDB) }
    }
    @Published var bypassed = false {
        didSet { engine.processor.isBypassed = bypassed }
    }
    @Published var normalize = true {
        didSet { engine.normalizeImpulseResponse = normalize }
    }

    @Published private(set) var errorMessage: String?
    @Published private(set) var hintMessage: String?
    @Published private(set) var infoLines: [String] = []
    @Published private(set) var isPreparingLibrary = false

    /// Meter levels are published here, never through `AppModel`, so the menu bar
    /// scene is not invalidated twenty times a second.
    let meters = MeterStore()
    let status = StatusStore()

    var isRunning: Bool { status.isRunning }

    let engine = AudioEngine()
    private(set) var folderURL: URL

    private var healthTimer: Timer?
    private var meterTimer: Timer?
    private var panelVisible = false
    private var silenceHintActive = false
    private var silentCallbacks = 0
    private var stalledTicks = 0
    private var lastCallbackCount: Float = 0
    private var lastCapturedFrames: Float = 0
    private var hasStarted = false
    private static var instanceCount = 0

    private enum Keys {
        static let folder = "IRSFolder"
        static let selected = "SelectedIR"
        static let wet = "Wet"
        static let gain = "GainDB"
        static let bypass = "Bypassed"
        static let normalize = "Normalize"
        static let seeded = "SeededDemoLibrary"
    }

    init() {
        Self.instanceCount += 1
        AppLog.write("AppModel #\(Self.instanceCount) init (bundle \(Bundle.main.bundleIdentifier ?? "-"))")

        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: Keys.folder) {
            folderURL = URL(fileURLWithPath: saved)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            folderURL = base.appendingPathComponent("IRSVerb/Impulse Responses")
        }

        wet = defaults.object(forKey: Keys.wet) as? Double ?? 1
        gainDB = defaults.object(forKey: Keys.gain) as? Double ?? 0
        bypassed = defaults.bool(forKey: Keys.bypass)
        normalize = defaults.object(forKey: Keys.normalize) as? Bool ?? true

        if let path = defaults.string(forKey: Keys.selected) {
            selectedURL = URL(fileURLWithPath: path)
        }
        // Deliberately no engine, timer or file work here: SwiftUI is allowed to
        // evaluate the StateObject closure more than once, and starting audio IO
        // twice would leave two taps fighting over the same hardware mute.
    }

    /// Called once, after the application has finished launching.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        AppLog.write("AppModel.start()")

        engine.processor.wet = Float(wet)
        engine.processor.gainDecibels = Float(gainDB)
        engine.processor.isBypassed = bypassed
        engine.normalizeImpulseResponse = normalize
        engine.onStateChange = { [weak self] state in
            DispatchQueue.main.async { self?.apply(state) }
        }

        prepareLibrary()
        startHealthTimer()
    }

    // MARK: - Library

    /// Generates the built-in demo impulse responses the first time the app runs
    /// so there is something to listen to immediately.
    private func prepareLibrary() {
        let manager = FileManager.default
        refreshList()
        if !items.isEmpty {
            selectFallbackIfNeeded()
            startIfNeeded()
            return
        }
        guard !manager.fileExists(atPath: folderURL.path) || items.isEmpty else { return }

        isPreparingLibrary = true
        let target = folderURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                try IRSynthesis.writeDemoFiles(to: target)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isPreparingLibrary = false
                    self.refreshList()
                    self.selectFallbackIfNeeded()
                    self.startIfNeeded()
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isPreparingLibrary = false
                    self.errorMessage = "Could not create the demo impulse responses: \(error.localizedDescription)"
                }
            }
        }
    }

    func refreshList() {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        items = contents
            .filter { IRFile.isImpulseResponse($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { ImpulseResponseItem(url: $0) }
        refreshInfo()
    }

    private func selectFallbackIfNeeded() {
        if let selected = selectedURL {
            // A file picked from outside the folder should survive a relaunch.
            if !items.contains(where: { $0.url == selected }),
               FileManager.default.fileExists(atPath: selected.path) {
                items.append(ImpulseResponseItem(url: selected))
                items.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
            if items.contains(where: { $0.url == selected }) {
                engine.impulseResponseURL = selected
                return
            }
        }
        let preferred = items.first { $0.name == "Large Hall" } ?? items.first
        selectedURL = preferred?.url
        engine.impulseResponseURL = preferred?.url
    }

    func chooseImpulseResponseFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose an impulse response"
        panel.prompt = "Use"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowsOtherFileTypes = true
        panel.message = "Viper4Android .irs files (and any WAV/AIFF) can be used."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !items.contains(where: { $0.url == url }) {
            items.append(ImpulseResponseItem(url: url))
            items.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        selectedURL = url
        startIfNeeded()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose an impulse response folder"
        panel.prompt = "Use Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folderURL = url
        UserDefaults.standard.set(url.path, forKey: Keys.folder)
        refreshList()
        selectFallbackIfNeeded()
    }

    func revealFolder() {
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folderURL)
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Engine

    func startIfNeeded() {
        guard !isRunning else { return }
        engine.start()
    }

    func toggleRunning() {
        if isRunning { engine.stop() } else { engine.start() }
    }

    func quit() {
        engine.stop()
        NSApplication.shared.terminate(nil)
    }

    private func apply(_ state: AudioEngine.State) {
        switch state {
        case .stopped:
            status.isRunning = false
        case .starting:
            status.isRunning = false
        case .running:
            status.isRunning = true
            errorMessage = nil
        case .failed(let message):
            status.isRunning = false
            errorMessage = message
            if engine.isWaitingForPermission {
                hintMessage = "Approve IRSVerb under System Settings › Privacy & Security › "
                    + "Screen & System Audio Recording, then press Start."
            }
        }
        refreshInfo()
    }

    // MARK: - Meters and status

    /// The panel tells us when it is on screen so the 20 Hz meter timer only runs
    /// while someone can actually see the meters.
    func panelAppeared() {
        guard !panelVisible else { return }
        panelVisible = true
        // Pick up impulse responses dropped into the folder since launch.
        refreshList()
        selectFallbackIfNeeded()
        // `.common` modes keep the timer alive while a menu or the panel is
        // tracking events, which would otherwise pause default-mode timers.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.meterTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
        healthTick()
    }

    func panelDisappeared() {
        panelVisible = false
        meterTimer?.invalidate()
        meterTimer = nil
    }

    /// 1 Hz, always: the safety watchdog has to keep running even with the panel
    /// closed, because a stalled output would leave system audio muted.
    private func startHealthTimer() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.healthTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
    }

    private func meterTick() {
        let input = Double(engine.inputLevel.load())
        let output = Double(engine.outputLevel.load())
        // Peak-style decay so the meters are readable.
        meters.input = max(input, meters.input * 0.72)
        meters.output = max(output, meters.output * 0.72)
    }

    private func healthTick() {
        checkOutputWatchdog()
        guard panelVisible else { return }

        let input = engine.inputLevel.load()
        if isRunning && input < 1e-7 {
            silentCallbacks += 1
            if silentCallbacks > 5 {
                silenceHintActive = true
                if hintMessage == nil {
                    hintMessage = "No audio is being captured. Check System Settings › Privacy & Security › "
                        + "Screen & System Audio Recording, then restart IRSVerb."
                }
            }
        } else {
            silentCallbacks = 0
            if input > 1e-7, silenceHintActive {
                silenceHintActive = false
                hintMessage = nil
            }
        }
        refreshInfo()
    }

    /// The tap mutes system audio for as long as it is being read, so if the
    /// output side ever stops being pulled the machine would go silent. Restart
    /// the engine in that case, which releases the mute.
    private func checkOutputWatchdog() {
        guard isRunning else {
            lastCallbackCount = engine.renderCallbacks.load()
            lastCapturedFrames = engine.capturedFrames.load()
            stalledTicks = 0
            return
        }
        let callbacks = engine.renderCallbacks.load()
        let captured = engine.capturedFrames.load()
        // A silent Mac legitimately freezes both counters. It is only a stall if
        // audio keeps arriving from the tap but never leaves the output, because
        // then the hardware stays muted with nothing replacing it.
        if callbacks == lastCallbackCount && captured != lastCapturedFrames {
            stalledTicks += 1
            if stalledTicks > 120 {
                AppLog.write("watchdog: audio arriving but no render callbacks for ~6s; restarting")
                stalledTicks = 0
                engine.restart()
            }
        } else {
            stalledTicks = 0
        }
        lastCallbackCount = callbacks
        lastCapturedFrames = captured
    }

    private func refreshInfo() {
        guard isRunning else {
            if engine.isWaitingForPermission {
                infoLines = ["Waiting for System Audio Recording permission"]
            } else if case .starting = engine.state {
                infoLines = ["Starting…"]
            } else if case .failed = engine.state {
                infoLines = []
            } else {
                infoLines = ["Engine stopped"]
            }
            return
        }
        var lines: [String] = []
        lines.append("\(Int(engine.sampleRate)) Hz · \(engine.sourceDescription)")
        if let name = engine.impulseResponseName {
            lines.append("IR: \(name)")
        } else if let error = engine.impulseResponseError {
            lines.append("IR error: \(error)")
        } else {
            lines.append("IR: none loaded")
        }
        if !engine.outputStarted {
            lines.append("Waiting for audio to play…")
        }
        lines.append(String(format: "Added latency ≈ %.0f ms · buffer %d frames",
                            engine.totalLatencyMilliseconds, engine.ringFill))
        lines.append("Dropouts: \(engine.missingFrames) under, \(engine.droppedFrames) over"
            + " · drift trims \(engine.driftDrops)")
        infoLines = lines
    }
}
