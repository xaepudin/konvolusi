import AppKit
import SwiftUI

enum PreferenceKey {
    static let hasCompletedOnboarding = "HasCompletedOnboarding"
    static let showInDock = "ShowInDock"
}

/// Optional Dock presence. The app is an agent by default (`LSUIElement`), which
/// is right for a background audio utility; users who prefer the Dock can opt in.
enum DockVisibility {
    static let key = PreferenceKey.showInDock

    static func apply() {
        set(UserDefaults.standard.bool(forKey: key), activate: false)
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

    @AppStorage(DockVisibility.key) private var showInDock = false
    @AppStorage(PreferenceKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section("General") {
                Toggle("Show IRSVerb in the Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { _, newValue in
                        DockVisibility.set(newValue)
                    }
                Text("When off, IRSVerb stays in the menu bar only. Turning this on adds "
                    + "the app to the Dock and to ⌘-Tab, which makes it easier to find.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Setup") {
                Button("Open System Audio Recording settings…") {
                    model.openPrivacySettings()
                }
                Button("Show the welcome screen again") {
                    hasCompletedOnboarding = false
                    openWindow(id: "onboarding")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Text("The welcome screen explains the menu bar icon and the audio permission. "
                    + "It opens now and will also appear the next time IRSVerb starts.")
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
