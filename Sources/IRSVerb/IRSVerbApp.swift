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
            PanelView(model: model, meters: model.meters, status: model.status)
        } label: {
            MenuBarLabel(status: model.status)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Isolated so that meter updates cannot invalidate the `MenuBarExtra` scene.
private struct MenuBarLabel: View {
    @ObservedObject var status: StatusStore

    var body: some View {
        Image(systemName: status.isRunning ? "waveform.circle.fill" : "waveform.circle")
    }
}

/// Guards against a second launch notification starting a second engine.
private var launchHandled = false
