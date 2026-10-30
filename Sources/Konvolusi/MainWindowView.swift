import AppKit
import Combine
import SwiftUI

/// The conventional window offered alongside the menu bar panel. It exists so
/// users can find Konvolusi from the Dock/Spotlight (when enabled), browse a
/// library, read diagnostics, and reach Settings without hunting for a menu bar
/// icon.
struct MainWindowView: View {
    var model: AppModel
    var meters: MeterStore
    var status: StatusStore
    var suppressWelcome = false

    @AppStorage(PreferenceKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @AppStorage("MainTab") private var tabRaw = MainTab.control.rawValue
    @State private var showWelcome = false
    @State private var isSurfaceVisible = false

    private var selectedTab: MainTab {
        MainTab(rawValue: tabRaw) ?? .control
    }

    private var tabSelection: Binding<MainTab> {
        Binding(
            get: { selectedTab },
            set: { tabRaw = $0.rawValue }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 190)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 980, minHeight: 640)
        .onAppear {
            if !isSurfaceVisible {
                isSurfaceVisible = true
                DockVisibility.showForWindow()
                model.uiAppeared()
            }
            NSApp.activate(ignoringOtherApps: true)
            if !suppressWelcome && !hasCompletedOnboarding {
                showWelcome = true
            }
        }
        .onChange(of: hasCompletedOnboarding) { _, completed in
            if completed {
                focusMainWindow()
            } else if !suppressWelcome {
                showWelcome = true
            }
        }
        .onChange(of: showWelcome) { _, showing in
            if !showing { focusMainWindow() }
        }
        .onDisappear {
            if isSurfaceVisible {
                isSurfaceVisible = false
                DockVisibility.hideAfterWindow()
                model.uiDisappeared()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard isSurfaceVisible,
                  let window = notification.object as? NSWindow,
                  window.title == "Konvolusi" else { return }
            isSurfaceVisible = false
            DockVisibility.hideAfterWindow()
            model.uiDisappeared()
        }
        .sheet(isPresented: $showWelcome) {
            OnboardingView(model: model)
        }
    }

    private var sidebar: some View {
        // Plain rows, no Section header: macOS renders sidebar sections with a
        // collapsible disclosure control, and a header would compete with the
        // window title. The title bar already identifies the app.
        List(selection: tabSelection) {
            Label("Control", systemImage: "slider.horizontal.3")
                .tag(MainTab.control)
            Label("Library", systemImage: "waveform")
                .tag(MainTab.library)
            Label("Diagnostics", systemImage: "stethoscope")
                .tag(MainTab.diagnostics)
            Label("Settings", systemImage: "gearshape")
                .tag(MainTab.settings)
            Label("About", systemImage: "info.circle")
                .tag(MainTab.about)
        }
        .listStyle(.sidebar)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func focusMainWindow() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.title == "Konvolusi" }?.makeKeyAndOrderFront(nil)
        }
    }

    @ViewBuilder private var detail: some View {
        switch selectedTab {
        case .control:
            ScrollView {
                ConvolverControls(model: model, meters: meters, status: status, compact: false)
                    .frame(maxWidth: 960, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        case .library:
            LibraryView(model: model)
        case .diagnostics:
            DiagnosticsView(model: model)
        case .settings:
            SettingsView(model: model)
                .frame(maxWidth: 720, maxHeight: .infinity)
                .padding(24)
                .frame(maxWidth: .infinity)
        case .about:
            AboutView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

enum MainTab: String, CaseIterable, Hashable {
    case control
    case library
    case diagnostics
    case settings
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
                Button {
                    model.addImpulseResponseFiles()
                } label: {
                    Label("Add IR…", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                Button {
                    model.removeSelectedImpulseResponse()
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .buttonStyle(.bordered)
                .disabled(!model.canRemoveSelected)
            }

            Text("Built-in responses are always available. Added IRs are copied into "
                + "Konvolusi's library and can be removed here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.isPreparingLibrary {
                ProgressView("Generating built-in responses…")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if model.items.isEmpty {
                ContentUnavailableView(
                    "No impulse responses",
                    systemImage: "waveform.slash",
                    description: Text("Use Add IR… to copy a .irs, WAV, AIFF, CAF, FLAC, or M4A file into the library.")
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                .accessibilityLabel("Impulse response library")
            }

            HStack {
                Toggle("Normalize impulse response", isOn: $model.normalize)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Match the loudness of responses with different lengths when you switch.")
                Spacer()
                Button("Refresh") { model.refreshLibrary() }
                    .help("Re-read the folder and pick up new .irs files.")
                    .accessibilityHint("Re-reads the folder and picks up new .irs files")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct DiagnosticsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Diagnostics")
                    .font(.title2.bold())

                Text("Konvolusi captures system audio, convolves it, and plays the result. "
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
                    Button("Show Logs in Finder") { model.revealLogs() }
                    Button("Copy Report") { model.copyDiagnosticReport() }
                        .accessibilityHint("Copies status, device, and error information without any audio")
                }

                GroupBox("Full end-to-end check") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quit Konvolusi, then run this from Terminal. It creates a real tap, "
                            + "plays a system sound, and writes a pass/fail report to the log folder.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("open /Applications/Konvolusi.app --args --diagnose 6")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Text("When running from a source build, use dist/Konvolusi.app instead.")
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
            .padding(24)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
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
            Text("Konvolusi")
                .font(.largeTitle.bold())
            Text("Rediscover the songs you love.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Version \(version) (\(build))")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Link("Repository", destination: URL(string: "https://github.com/xaepudin/Konvolusi")!)
                Link("GPL-3.0 licence", destination: URL(string: "https://github.com/xaepudin/Konvolusi/blob/main/LICENSE")!)
                Link("CC0 responses", destination: URL(string: "https://github.com/xaepudin/Konvolusi/blob/main/LICENSE-IRS")!)
            }
            .font(.callout)

            Text("Konvolusi is an independent app. “.irs” describes the impulse response "
                + "file format.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .padding(30)
        .frame(minWidth: 520, minHeight: 380)
    }
}
