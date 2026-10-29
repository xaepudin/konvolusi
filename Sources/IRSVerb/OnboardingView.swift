import AppKit
import SwiftUI

/// First-run explanation. The app has no Dock icon by default, so without this
/// window a new user can launch it and see nothing at all.
struct OnboardingView: View {
    @ObservedObject var model: AppModel

    @AppStorage(PreferenceKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to IRSVerb")
                        .font(.largeTitle.bold())
                    Text("A system-wide impulse response convolver for macOS")
                        .foregroundStyle(.secondary)
                }
            }

            Text("IRSVerb lives in the menu bar. Click the waveform icon to pick a "
                + "response, set the mix, and see your input and output levels.")
                .fixedSize(horizontal: false, vertical: true)

            GroupBox("Before you start") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Allow System Audio Recording when macOS asks. IRSVerb needs it "
                        + "to capture the audio other apps are playing.",
                        systemImage: "checkmark.shield")
                    Label("IRSVerb mutes the original signal while it reads the tap, so you "
                        + "hear the convolved result once, not the dry signal plus an effect.",
                        systemImage: "speaker.wave.2")
                    Label("Audio is processed in memory on this Mac. IRSVerb has no network "
                        + "code, no telemetry, and no account.",
                        systemImage: "lock")
                }
                .font(.callout)
                .padding(6)
                .fixedSize(horizontal: false, vertical: true)
            }

            Text("You can change the permission later in System Settings › Privacy & "
                + "Security › Screen & System Audio Recording. If you miss the prompt, "
                + "open the panel and press Start after granting it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Open System Settings…") { model.openPrivacySettings() }
                    .accessibilityHint("Opens the System Audio Recording privacy pane")
                Spacer()
                Button("Not now") {
                    dismissWindow(id: "onboarding")
                }
                .accessibilityHint("Closes this window. It will appear again next time IRSVerb starts.")
                Button("Open IRSVerb") {
                    dismissWindow(id: "onboarding")
                    hasCompletedOnboarding = true
                    openWindow(id: "main")
                    model.startIfNeeded()
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("Closes the welcome screen and opens the main IRSVerb window")
            }
        }
        .padding(28)
        .frame(width: 580)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}
