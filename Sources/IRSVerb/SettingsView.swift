import AppKit
import SwiftUI

enum PreferenceKey {
    static let hasCompletedOnboarding = "HasCompletedOnboarding"
    static let showInDock = "ShowInDock"
}

/// Dock presence. The app starts as a regular app so it is findable in the Dock
/// and Spotlight even when the menu bar is full; users who want a menu-bar-only
/// utility can turn this off.
enum DockVisibility {
    static let key = PreferenceKey.showInDock

    static func apply() {
        let visible = UserDefaults.standard.object(forKey: key) as? Bool ?? true
        set(visible, activate: false)
    }

    static func set(_ visible: Bool, activate: Bool = true) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
        if visible && activate {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    @AppStorage(DockVisibility.key) private var showInDock = true
    @AppStorage(PreferenceKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section("General") {
                Toggle("Show IRSVerb in the Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { _, newValue in
                        DockVisibility.set(newValue)
                    }
                    .help("Show IRSVerb in the Dock and ⌘-Tab. Turn off for a menu-bar-only utility.")
                Text("When on, IRSVerb is in the Dock and in ⌘-Tab, which makes it easy to find "
                    + "even when the menu bar is crowded or the icon is hidden. Turn it off for a "
                    + "menu-bar-only utility.")
                    .font(.caption)
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
                    + "to CC0. See the About tab for links.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 400)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}
