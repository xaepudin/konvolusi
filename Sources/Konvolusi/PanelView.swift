import AppKit
import SwiftUI

/// The menu bar quick panel. It uses the same `ConvolverControls` as the main
/// window, plus explicit entry points to the conventional window and Settings.
struct PanelView: View {
    var model: AppModel
    var meters: MeterStore
    var status: StatusStore

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ConvolverControls(model: model, meters: meters, status: status)

            Divider()

            HStack(spacing: 6) {
                Button("Open Konvolusi…") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .help("Open the full Konvolusi window.")
                .accessibilityHint("Opens the full Konvolusi window")

                Button("Settings…") {
                    UserDefaults.standard.set(MainTab.settings.rawValue, forKey: "MainTab")
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .help("Open Konvolusi settings.")
                .accessibilityHint("Opens Konvolusi settings")

                Spacer()

                Button("Quit Konvolusi") { model.quit() }
                    .help("Stop processing, restore normal audio, and quit Konvolusi.")
                    .accessibilityHint("Stops processing, restores normal audio, and quits Konvolusi")
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
