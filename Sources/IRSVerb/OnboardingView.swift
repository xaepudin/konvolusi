import AppKit
import SwiftUI

/// First-run explanation, shown as a sheet over the main window. The app is a
/// menu bar utility, but the main window keeps the welcome content visible while
/// the user reads it and after it is dismissed.
struct OnboardingView: View {
    @ObservedObject var model: AppModel

    @AppStorage(PreferenceKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @Environment(\.dismiss) private var dismiss

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
                + "response, set the mix, and see your input and output levels. It also "
                + "appears in the Dock by default; you can turn that off in Settings.")
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
                    dismiss()
                }
                .accessibilityHint("Closes this sheet. It will appear again next time IRSVerb opens the main window.")
                Button("Open IRSVerb") {
                    hasCompletedOnboarding = true
                    model.startIfNeeded()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("Closes the welcome sheet and starts IRSVerb")
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("Closes the welcome screen and opens the main IRSVerb window")
            }
        }
        .padding(28)
        .frame(width: 580)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}
