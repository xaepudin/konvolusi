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
        VStack(alignment: .leading, spacing: 22) {
            header

            Divider()

            Text("IRSVerb lives in the menu bar. Click the waveform icon to pick a "
                + "response, set the mix, and see your input and output levels. The main "
                + "window appears in the Dock while it is open; closing it returns IRSVerb "
                + "to the menu bar and keeps audio running.")
                .font(.body)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 16) {
                Text("Before you start")
                    .font(.headline)

                OnboardingRow(
                    icon: "checkmark.shield.fill",
                    title: "Allow System Audio Recording",
                    detail: "When macOS asks, allow IRSVerb to capture the audio other apps "
                        + "are playing. If you miss the prompt, you can grant it later in "
                        + "System Settings."
                )

                Divider()

                OnboardingRow(
                    icon: "speaker.wave.2.fill",
                    title: "Hear the effect once",
                    detail: "IRSVerb mutes the original signal while it reads the tap, so you "
                        + "hear the convolved result — not the dry signal plus an effect."
                )

                Divider()

                OnboardingRow(
                    icon: "lock.fill",
                    title: "Stay on this Mac",
                    detail: "Audio is processed in memory. IRSVerb has no network code, no "
                        + "telemetry, and no account."
                )
            }
            .cardSurface(padding: 18)

            Text("You can change the permission later in System Settings › Privacy & "
                + "Security › Screen & System Audio Recording. If you miss the prompt, "
                + "open the panel and press Start after granting it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Open System Settings…") { model.openPrivacySettings() }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Opens the System Audio Recording privacy pane")

                Spacer()

                Button("Not now") {
                    closeAndFocusMainWindow()
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Closes this sheet. It will appear again next time IRSVerb opens the main window.")

                Button("Open IRSVerb") {
                    hasCompletedOnboarding = true
                    model.startIfNeeded()
                    closeAndFocusMainWindow()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("Closes the welcome sheet and starts IRSVerb")
            }
        }
        .padding(32)
        .frame(width: 600)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    private func closeAndFocusMainWindow() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.title == "IRSVerb" }?.makeKeyAndOrderFront(nil)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to IRSVerb")
                    .font(.largeTitle.bold())
                Text("A system-wide impulse response convolver for macOS")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct OnboardingRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(
                    Color.accentColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
