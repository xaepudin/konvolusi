import AppKit
import Foundation
import IRSKit

/// `IRSVerb --diagnose [seconds]` drives the live routing and reports what it
/// finds, so the system-wide audio path can be verified without listening.
///
/// It also plays a system sound so the tap has something to capture. Output goes
/// to stdout *and* to `~/Library/Logs/IRSVerb/diagnostic.log`, because an app
/// launched through LaunchServices (the way macOS wants to attribute the
/// system-audio permission) has nowhere useful to print.
enum Diagnostics {
    private static let logURL: URL = {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        let directory = base.appendingPathComponent("Logs/IRSVerb")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("diagnostic.log")
    }()

    private static func log(_ message: String = "") {
        print(message)
        let data = Data((message + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logURL)
        }
    }

    static func runIfRequested() {
        guard CommandLine.arguments.contains("--diagnose") else { return }
        try? FileManager.default.removeItem(at: logURL)
        run()
    }

    private static func run() -> Never {
        let arguments = CommandLine.arguments
        var seconds = 5.0
        if let index = arguments.firstIndex(of: "--diagnose"),
           index + 1 < arguments.count,
           let value = Double(arguments[index + 1]) {
            seconds = max(1, min(value, 60))
        }

        log("IRSVerb diagnostics — \(Date())")
        log("  macOS            : \(ProcessInfo.processInfo.operatingSystemVersionString)")
        log("  bundle           : \(Bundle.main.bundlePath)")
        log("  bundle id        : \(Bundle.main.bundleIdentifier ?? "(none — running unbundled)")")
        log("  log file         : \(logURL.path)")

        // Two taps reading the same audio fight over the hardware mute.
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.asep.irsverb")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !running.isEmpty {
            log("")
            log("NOTE: IRSVerb is already running (pid \(running.map { String($0.processIdentifier) }.joined(separator: ", "))).")
            log("      Quit it first, otherwise both instances will compete for the audio.")
            log("")
        }

        var temporary: URL?
        var impulseResponseURL = locateImpulseResponse()
        if impulseResponseURL == nil {
            let responses = IRSynthesis.demoResponses()
            let generated = responses.first { $0.name == "Large Hall" } ?? responses[0]
            let target = FileManager.default.temporaryDirectory
                .appendingPathComponent("irsverb-diagnostic-\(UUID().uuidString).irs")
            try? IRFile.write(generated, to: target)
            temporary = target
            impulseResponseURL = target
        }
        defer { if let temporary { try? FileManager.default.removeItem(at: temporary) } }
        log("  impulse response : \(impulseResponseURL?.path ?? "(none)")")
        log("  output device    : \(CoreAudio.deviceName(CoreAudio.defaultOutputDevice()))")
        log("")

        let engine = AudioEngine()
        engine.impulseResponseURL = impulseResponseURL

        log("Creating the system audio tap (system audio is muted and replaced while this runs)…")
        log("  note: if macOS is showing a permission prompt, answer it now.")
        engine.start()

        // Setup runs off the main thread because creating a tap blocks inside
        // Core Audio while the system-audio permission prompt is on screen.
        var setupTicks = 0
        while case .starting = engine.state, setupTicks < 1500 {   // ~15 s
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            setupTicks += 1
        }

        log("  state            : \(engine.state)")
        if case .failed(let message) = engine.state {
            log("  error            : \(message)")
            log("")
            log("RESULT: FAIL — the tap could not be created.")
            log("        Grant IRSVerb access in System Settings › Privacy & Security ›")
            log("        Screen & System Audio Recording, then run this again.")
            finish(2)
        }
        if case .starting = engine.state {
            log("")
            log("RESULT: FAIL — Core Audio did not finish setting up within 15s.")
            log("        That usually means a permission prompt is still waiting to be")
            log("        answered, or coreaudiod is busy.")
            finish(5)
        }
        log("  tap format       : \(engine.captureFormatDescription)")
        log("  sample rate      : \(Int(engine.sampleRate)) Hz")

        let sound = "/System/Library/Sounds/Submarine.aiff"
        log("")
        log("Playing \(sound) so the tap has something to capture…")
        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = [sound]
        try? player.run()

        var peakInput: Float = 0
        var peakOutput: Float = 0
        var minimumFill = Int.max
        var maximumFill = 0
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            peakInput = max(peakInput, engine.inputLevel.load())
            peakOutput = max(peakOutput, engine.outputLevel.load())
            minimumFill = min(minimumFill, engine.ringFill)
            maximumFill = max(maximumFill, engine.ringFill)
        }
        if player.isRunning { player.terminate() }

        log("")
        log("Results after \(Int(seconds))s:")
        log(String(format: "  peak input level : %.6f", peakInput))
        log(String(format: "  peak output level: %.6f", peakOutput))
        log("  ring fill range  : \(minimumFill == Int.max ? 0 : minimumFill)…\(maximumFill) frames")
        log("  dropouts         : \(engine.missingFrames) under, \(engine.droppedFrames) over")
        log("  drift trims      : \(engine.driftDrops)")
        log("  buffers          : tap \(Int(engine.maxTapFrames.load())) frames, "
            + "output \(Int(engine.maxRenderFrames.load())) frames")
        log("  impulse response : \(engine.impulseResponseName ?? "(none)")")
        if let error = engine.impulseResponseError { log("  IR error         : \(error)") }
        log("  added latency    : \(Int(engine.totalLatencyMilliseconds)) ms")
        engine.stop()
        log("  state after stop : \(engine.state)")
        log("")

        if peakInput > 1e-4 {
            log("RESULT: PASS — system audio was captured and convolved.")
            if peakOutput <= 1e-6 {
                log("        warning: nothing came out of the output unit.")
                finish(4)
            }
            finish(0)
        } else {
            log("RESULT: FAIL — the tap delivered silence.")
            log("        Check System Settings › Privacy & Security › Screen & System Audio Recording,")
            log("        and make sure something is actually playing audio.")
            finish(3)
        }
    }

    private static func finish(_ code: Int32) -> Never {
        log("exit \(code)")
        exit(code)
    }

    private static func locateImpulseResponse() -> URL? {
        let candidates = [
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("IRSVerb/Impulse Responses"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Impulse Responses"),
        ].compactMap { $0 }

        for directory in candidates {
            let contents = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                        includingPropertiesForKeys: nil)) ?? []
            if let match = contents
                .filter({ IRFile.isImpulseResponse($0) })
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                .first {
                return match
            }
        }
        return nil
    }
}
