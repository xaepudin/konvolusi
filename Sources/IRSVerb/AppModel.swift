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
    /// The built-in library and every IR the user has added. Adding an IR copies
    /// it here, so the library is self-contained and there is no folder setting.
    let folderURL: URL

    private static let builtInNames: Set<String> = Set(IRSynthesis.builtInLibrary().map(\.name))

    private var healthTimer: Timer?
    private var meterTimer: Timer?
    /// Number of surfaces (menu bar panel, main window) currently on screen.
    /// Meter updates only run while at least one of them is visible.
    private var visibleSurfaces = 0
    private var silenceHintActive = false
    private var silentCallbacks = 0
    private var stalledTicks = 0
    private var lastCallbackCount: Float = 0
    private var lastCapturedFrames: Float = 0
    private var hasStarted = false
    private static var instanceCount = 0

    private enum Keys {
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
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        folderURL = base.appendingPathComponent("IRSVerb/Impulse Responses")

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
            startIfReady()
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
                    self.startIfReady()
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

    /// Start automatically only after the user has seen the welcome screen. On a
    /// first launch, starting the engine here would throw the system-audio
    /// permission dialog on top of the explanation before it can be read.
    private func startIfReady() {
        guard UserDefaults.standard.bool(forKey: PreferenceKey.hasCompletedOnboarding) else { return }
        startIfNeeded()
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

    /// Re-reads the folder and keeps a sensible selection. Used by the library
    /// window and its Refresh button.
    func refreshLibrary() {
        refreshList()
        selectFallbackIfNeeded()
    }

    private func selectFallbackIfNeeded() {
        if let selected = selectedURL,
           items.contains(where: { $0.url == selected }) {
            engine.impulseResponseURL = selected
            return
        }
        let preferred = items.first { $0.name == "Large Hall" } ?? items.first
        selectedURL = preferred?.url
        engine.impulseResponseURL = preferred?.url
    }

    /// True when the selected response was added by the user. Built-ins are
    /// always present and cannot be removed.
    var canRemoveSelected: Bool {
        guard let selectedURL,
              selectedURL.deletingLastPathComponent().standardizedFileURL == folderURL.standardizedFileURL,
              items.contains(where: { $0.url == selectedURL }) else { return false }
        return !Self.builtInNames.contains(selectedURL.deletingPathExtension().lastPathComponent)
    }

    /// Adds one or more files to the library. Files chosen from outside the
    /// library are copied in, so the library stays self-contained; a file that
    /// is already in the library is simply selected.
    func addImpulseResponseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Add impulse responses"
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowsOtherFileTypes = true
        panel.message = "Choose .irs, WAV, AIFF, CAF, FLAC, or M4A files. "
            + "They will be copied into IRSVerb's library."
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            var added: [URL] = []
            for source in panel.urls {
                if source.deletingLastPathComponent().standardizedFileURL == folderURL.standardizedFileURL {
                    added.append(source)
                } else {
                    let destination = uniqueDestination(for: source)
                    try FileManager.default.copyItem(at: source, to: destination)
                    added.append(destination)
                }
            }
            errorMessage = nil
            refreshLibrary()
            if let first = added.first {
                selectedURL = first
                startIfNeeded()
            }
        } catch {
            errorMessage = "Could not add the impulse response: \(error.localizedDescription)"
        }
    }

    func removeSelectedImpulseResponse() {
        guard canRemoveSelected, let selectedURL else { return }
        do {
            try FileManager.default.removeItem(at: selectedURL)
        } catch {
            errorMessage = "Could not remove the impulse response: \(error.localizedDescription)"
            return
        }
        self.selectedURL = nil
        errorMessage = nil
        refreshLibrary()
        selectFallbackIfNeeded()
        startIfNeeded()
    }

    private func uniqueDestination(for source: URL) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension.isEmpty ? "irs" : source.pathExtension
        var destination = folderURL.appendingPathComponent("\(base).\(ext)")
        var index = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            index += 1
            destination = folderURL.appendingPathComponent("\(base) \(index).\(ext)")
        }
        return destination
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    func revealLogs() {
        let directory = AppLog.url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([AppLog.url])
    }

    func openLog() {
        try? FileManager.default.createDirectory(at: AppLog.url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        NSWorkspace.shared.open(AppLog.url)
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// Copies a support-friendly report to the pasteboard. Audio is never
    /// included; this is lifecycle and device information only.
    func copyDiagnosticReport() {
        var lines = [
            "IRSVerb \(appVersion) (\(appBuild))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Engine running: \(isRunning ? "yes" : "no")",
            "Library: \(folderURL.path)",
        ]
        if let selectedURL {
            lines.append("Selected impulse response: \(selectedURL.lastPathComponent)")
        }
        if !infoLines.isEmpty {
            lines.append("")
            lines.append(contentsOf: infoLines)
        }
        if let errorMessage {
            lines.append("")
            lines.append("Error: \(errorMessage)")
        }
        if let hintMessage {
            lines.append("Hint: \(hintMessage)")
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
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

    /// Called by the menu bar panel and the main window. Meter updates run only
    /// while at least one surface is visible.
    func uiAppeared() {
        visibleSurfaces += 1
        guard visibleSurfaces == 1 else { return }
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

    func uiDisappeared() {
        visibleSurfaces = max(0, visibleSurfaces - 1)
        guard visibleSurfaces == 0 else { return }
        meterTimer?.invalidate()
        meterTimer = nil
    }

    /// Backwards-compatible names used by the menu bar panel.
    func panelAppeared() { uiAppeared() }
    func panelDisappeared() { uiDisappeared() }

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
        guard visibleSurfaces > 0 else { return }

        let input = engine.inputLevel.load()
        // A silent Mac with no audio playing is normal: Core Audio may not
        // deliver tap buffers at all, and the output unit has not started. Only
        // warn once output is flowing but the tap still carries silence, which
        // is the case that usually means a permission or routing problem.
        if isRunning && engine.outputStarted && input < 1e-7 {
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
            if silenceHintActive {
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
