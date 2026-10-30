import AppKit
import SwiftUI

enum PreferenceKey {
    static let hasCompletedOnboarding = "HasCompletedOnboarding"
}

/// Window/Dock lifecycle. The app is a menu bar agent whenever no window is open.
/// Opening the main window temporarily makes it a regular app so it appears in
/// the Dock and ⌘-Tab; closing the window returns it to the menu bar only without
/// stopping audio. Quit remains in the menu bar panel.
enum DockVisibility {
    /// Called at launch before the main window appears.
    static func apply() {
        NSApp.setActivationPolicy(.accessory)
    }

    /// The main window is on screen.
    static func showForWindow() {
        NSApp.setActivationPolicy(.regular)
    }

    /// The main window closed: disappear from the Dock and ⌘-Tab, keep running.
    static func hideAfterWindow() {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    @AppStorage(PreferenceKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section("Background") {
                Text("Closing the main window removes IRSVerb from the Dock and ⌘-Tab, "
                    + "but it keeps running in the menu bar and audio processing continues. "
                    + "Open the main window from the menu bar, or launch IRSVerb again; the "
                    + "running app is reused. Use Quit IRSVerb in the menu bar panel to stop "
                    + "processing and exit completely.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Setup") {
                Button("Open System Audio Recording settings…") {
                    model.openPrivacySettings()
                }
                .help("Open the privacy pane where IRSVerb's System Audio Recording permission lives.")
                Button("Show the welcome screen again") {
                    hasCompletedOnboarding = false
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .help("Open the welcome sheet over the main window now.")
                Text("The welcome screen explains the menu bar icon and the audio permission. "
                    + "It appears over the main window now and again the next time IRSVerb opens it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("About") {
                LabeledContent("Version", value: "\(model.appVersion) (\(model.appBuild))")
                Text("Source code is MIT licensed. The generated impulse responses are dedicated "
                    + "to CC0. See the About section for links.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
