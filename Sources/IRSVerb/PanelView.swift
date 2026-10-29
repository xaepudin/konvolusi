import AppKit
import SwiftUI

/// The menu bar quick panel. It uses the same `ConvolverControls` as the main
/// window, plus explicit entry points to the conventional window and Settings.
struct PanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var meters: MeterStore
    @ObservedObject var status: StatusStore

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ConvolverControls(model: model, meters: meters, status: status)

            Divider()

            HStack(spacing: 6) {
                Button("Open IRSVerb…") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .help("Open the full IRSVerb window.")
                .accessibilityHint("Opens the full IRSVerb window")

                Button("Settings…") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
                .help("Open IRSVerb settings.")
                .accessibilityHint("Opens IRSVerb settings")

                Spacer()

                Button("Quit IRSVerb") { model.quit() }
                    .help("Stop processing, restore normal audio, and quit IRSVerb.")
                    .accessibilityHint("Stops processing, restores normal audio, and quits IRSVerb")
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 420)
        // The 20 Hz meter timer only runs while a surface is actually on screen.
        .onAppear { model.panelAppeared() }
        .onDisappear { model.panelDisappeared() }
    }
}
