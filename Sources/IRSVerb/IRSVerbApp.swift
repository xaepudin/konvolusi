import AppKit
import Combine
import SwiftUI

extension Notification.Name {
    /// Posted when the app is reopened (Dock click, Spotlight, Finder) with no
    /// visible windows. The menu bar label listens and opens the main window.
    static let irsVerbOpenMainWindow = Notification.Name("IRSVerbOpenMainWindow")
}

/// The app is a menu bar agent with a Dock icon by default. AppKit's default
/// "terminate after the last window closes" policy would kill it as soon as the
/// welcome sheet is dismissed, taking the menu bar item with it, so opt out.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NotificationCenter.default.post(name: .irsVerbOpenMainWindow, object: nil)
        }
        return true
    }
}

@main
struct IRSVerbApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel
    @AppStorage(PreferenceKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    private let suppressWelcomeAtLaunch = CommandLine.arguments.contains("--show-main")

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
            MainActor.assumeIsolated {
                DockVisibility.apply()
                model.start()
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model, meters: model.meters, status: model.status)
        } label: {
            MenuBarLabel(status: model.status)
        }
        .menuBarExtraStyle(.window)

        Window("IRSVerb", id: "main") {
            MainWindowView(model: model,
                           meters: model.meters,
                           status: model.status,
                           suppressWelcome: suppressWelcomeAtLaunch)
        }
        .defaultSize(width: 1120, height: 720)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.presented)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    UserDefaults.standard.set(MainTab.settings.rawValue, forKey: "MainTab")
                    NotificationCenter.default.post(name: .irsVerbOpenMainWindow, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// Isolated so that meter updates cannot invalidate the `MenuBarExtra` scene.
private struct MenuBarLabel: View {
    @ObservedObject var status: StatusStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: status.isRunning ? "waveform.circle.fill" : "waveform.circle")
            .accessibilityLabel("IRSVerb")
            .accessibilityValue(status.isRunning ? "Running" : "Stopped")
            .accessibilityHint("Opens the IRSVerb controls")
            .onReceive(NotificationCenter.default.publisher(for: .irsVerbOpenMainWindow)) { _ in
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

/// Guards against a second launch notification starting a second engine.
private var launchHandled = false
