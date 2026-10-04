import AppKit
import SwiftUI

@main
struct IRSVerbApp: App {
    @StateObject private var model: AppModel

    init() {
        // `--diagnose` exercises the live audio path and exits; it must run
        // before the menu bar UI (and the engine it starts) exists.
        Diagnostics.runIfRequested()

        let model = AppModel()
        _model = StateObject(wrappedValue: model)

        // Starting the engine during App.init is too early: Core Audio IO
        // created before the application finishes launching never gets its
        // callbacks. Wait for the launch notification instead, exactly once.
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification,
                                              object: nil,
                                              queue: .main) { _ in
            guard !launchHandled else { return }
            launchHandled = true
            // The notification is delivered on the main queue.
            MainActor.assumeIsolated { model.start() }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            Image(systemName: model.isRunning ? "waveform.circle.fill" : "waveform.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Guards against a second launch notification starting a second engine.
private var launchHandled = false
