import AppKit
import SwiftUI

/// The conventional window offered alongside the menu bar panel. It exists so
/// users can find IRSVerb from the Dock/Spotlight (when enabled), browse a
/// library, read diagnostics, and reach Settings without hunting for a menu bar
/// icon.
struct MainWindowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var meters: MeterStore
    @ObservedObject var status: StatusStore

    @State private var tab: MainTab = .control

    var body: some View {
        TabView(selection: $tab) {
            ScrollView {
                ConvolverControls(model: model, meters: meters, status: status, compact: false)
                    .frame(maxWidth: 700, alignment: .leading)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .tabItem { Label("Control", systemImage: "slider.horizontal.3") }
            .tag(MainTab.control)

            LibraryView(model: model)
                .tabItem { Label("Library", systemImage: "waveform") }
                .tag(MainTab.library)

            DiagnosticsView(model: model)
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
                .tag(MainTab.diagnostics)

            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(MainTab.about)
        }
        .frame(minWidth: 680, minHeight: 540)
        .onAppear {
            model.uiAppeared()
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear { model.uiDisappeared() }
    }
}

private enum MainTab: Hashable {
    case control
    case library
    case diagnostics
    case about
}

struct LibraryView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Impulse responses")
                    .font(.title2.bold())
                Spacer()
                Button("Choose .irs…") { model.chooseImpulseResponseFile() }
                Button("Folder…") { model.chooseFolder() }
                Button("Reveal") { model.revealFolder() }
            }

            Text("Folder: \(model.folderURL.path)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)

            if model.isPreparingLibrary {
                ProgressView("Generating demo impulse responses…")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if model.items.isEmpty {
                ContentUnavailableView(
                    "No impulse responses",
                    systemImage: "waveform.slash",
                    description: Text("Choose a folder or add a .irs file to get started.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $model.selectedURL) {
                    ForEach(model.items) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "waveform")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(item.name)
                            Spacer()
                            if item.url == model.selectedURL {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                                    .accessibilityLabel("Selected")
                            }
                        }
                        .tag(Optional(item.url))
                        .accessibilityLabel(item.name)
                    }
                }
                .listStyle(.inset)
                .accessibilityLabel("Impulse response library")
            }

            HStack {
                Toggle("Normalize impulse response", isOn: $model.normalize)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                Button("Refresh") { model.refreshLibrary() }
                    .accessibilityHint("Re-reads the folder and picks up new .irs files")
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 500)
    }
}

struct DiagnosticsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Diagnostics")
                    .font(.title2.bold())

                Text("IRSVerb captures system audio, convolves it, and plays the result. "
                    + "These values update while this window is open.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox("Current status") {
                    VStack(alignment: .leading, spacing: 6) {
                        if model.infoLines.isEmpty {
                            Text("Engine is stopped.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(model.infoLines, id: \.self) { line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let error = model.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let hint = model.hintMessage {
                            Text(hint)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                HStack(spacing: 8) {
                    Button("Open Privacy Settings…") { model.openPrivacySettings() }
                    Button("Open Log") { model.openLog() }
                    Button("Reveal Logs") { model.revealLogs() }
                    Button("Copy Report") { model.copyDiagnosticReport() }
                        .accessibilityHint("Copies status, device, and error information without any audio")
                }

                GroupBox("Full end-to-end check") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quit IRSVerb, then run this from Terminal. It creates a real tap, "
                            + "plays a system sound, and writes a pass/fail report to the log folder.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("open /Applications/IRSVerb.app --args --diagnose 6")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Text("When running from a source build, use dist/IRSVerb.app instead.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Log: \(AppLog.url.path)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                Text("Audio is processed in memory. The log contains lifecycle messages, "
                    + "device names, and file paths — never audio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(minWidth: 680, minHeight: 500)
    }
}

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("IRSVerb")
                .font(.largeTitle.bold())
            Text("Version \(version) (\(build))")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("A system-wide impulse response convolver for macOS.")
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Repository", destination: URL(string: "https://github.com/xaepudin/IRSVerb")!)
                Link("MIT licence", destination: URL(string: "https://github.com/xaepudin/IRSVerb/blob/main/LICENSE")!)
                Link("CC0 responses", destination: URL(string: "https://github.com/xaepudin/IRSVerb/blob/main/LICENSE-IRS")!)
            }
            .font(.callout)

            Text("IRSVerb is not affiliated with Viper4Android or its authors. "
                + "“Viper4Android” describes the .irs file format and workflow only.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .padding(30)
        .frame(minWidth: 520, minHeight: 380)
    }
}
