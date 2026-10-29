import AppKit
import SwiftUI

extension View {
    /// A subtle raised surface used by the main window's cards. The menu bar
    /// panel deliberately stays flat and compact.
    func cardSurface(padding: CGFloat = 0, cornerRadius: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

struct PanelCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 16)
    }
}

/// A horizontal level meter with a text label and an accessibility value.
///
/// The colored bar is decorative; the value is exposed as a single accessible
/// element so VoiceOver hears "Input level, -24 decibels" instead of an
/// unlabelled geometry view.
struct LevelMeter: View {
    let label: String
    let level: Double

    private var normalized: Double {
        guard level > 0 else { return 0 }
        let decibels = 20 * log10(level)
        return min(1, max(0, (decibels + 60) / 60))
    }

    private var valueDescription: String {
        guard level > 0 else { return "silent" }
        let decibels = 20 * log10(level)
        return String(format: "%.0f decibels", max(-120, decibels))
    }

    private var valueText: String {
        guard level > 0 else { return "Silent" }
        return String(format: "%.0f dB", max(-120, 20 * log10(level)))
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.green, .yellow, .orange, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geometry.size.width * normalized))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
            Text(valueText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) level")
        .accessibilityValue(valueDescription)
        .help("\(label) level. “Silent” means no audio is being captured right now.")
    }
}

struct StatusHeader: View {
    @ObservedObject var model: AppModel
    @ObservedObject var status: StatusStore
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(status.isRunning ? Color.green.opacity(0.14) : Color.secondary.opacity(0.10))
                    .frame(width: 42, height: 42)
                Image(systemName: status.isRunning ? "waveform.circle.fill" : "waveform.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(status.isRunning ? Color.green : Color.secondary)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("IRSVerb")
                    .font(.headline)
                if !compact {
                    Text("System-wide impulse response convolver")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Text(status.isRunning ? "Running" : "Stopped")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .foregroundStyle(status.isRunning ? Color.green : Color.secondary)
                .background(
                    status.isRunning ? Color.green.opacity(0.13) : Color.secondary.opacity(0.11),
                    in: Capsule()
                )
                .accessibilityLabel("Status")
                .accessibilityValue(status.isRunning ? "Running" : "Stopped")

            Button(status.isRunning ? "Stop" : "Start") {
                model.toggleRunning()
            }
            .controlSize(.regular)
            .buttonStyle(.bordered)
            .tint(status.isRunning ? .red : .accentColor)
            .help(status.isRunning
                ? "Stop processing and restore normal system audio"
                : "Start processing system audio")
            .accessibilityHint(status.isRunning
                ? "Stops processing and restores normal system audio"
                : "Starts processing system audio")
        }
    }
}

struct ImpulseResponseSection: View {
    @ObservedObject var model: AppModel
    var compact: Bool
    var showsHeading: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            if showsHeading {
                Text("Impulse response")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.isPreparingLibrary {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating demo impulse responses…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else if model.items.isEmpty {
                Text("No .irs files in this folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Impulse response", selection: $model.selectedURL) {
                    ForEach(model.items) { item in
                        Text(item.name).tag(Optional(item.url))
                    }
                }
                .labelsHidden()
                .controlSize(compact ? .regular : .large)
                .frame(maxWidth: .infinity)
                .help("Choose the impulse response applied to all system audio. "
                    + "Use Folder… to point IRSVerb at your own collection.")
                .accessibilityLabel("Impulse response")
                .accessibilityValue(model.selectedURL?.deletingPathExtension().lastPathComponent ?? "None")
            }

            if compact {
                HStack(spacing: 6) {
                    actionButtons
                }
                .controlSize(.small)
            } else {
                ControlGroup {
                    actionButtons
                }
                .controlSize(.regular)
            }

            if !compact {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "folder")
                        .font(.caption2)
                        .accessibilityHidden(true)
                    Text(model.folderURL.path)
                        .font(.caption)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(model.folderURL.path)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var actionButtons: some View {
        Button("Choose .irs…") { model.chooseImpulseResponseFile() }
            .help("Add a single .irs, WAV, AIFF, CAF, FLAC, or M4A file from anywhere on disk.")
            .accessibilityHint("Choose a single impulse response file from anywhere on disk")
        Button("Folder…") { model.chooseFolder() }
            .help("Use a folder on this Mac as the impulse response library.")
            .accessibilityHint("Use a different folder as the impulse response library")
        Button("Show in Finder") { model.revealFolder() }
            .help("Show the current impulse response folder in Finder.")
            .accessibilityHint("Show the current impulse response folder in Finder")
    }
}

struct MixControls: View {
    @ObservedObject var model: AppModel
    var compact: Bool = true

    private var labelFont: Font {
        compact ? .caption.weight(.medium) : .subheadline.weight(.medium)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            controlRow(
                title: "Mix",
                value: "\(Int((model.wet * 100).rounded()))% wet"
            ) {
                Slider(value: $model.wet, in: 0...1)
                    .help("Wet/dry blend. 100% is fully convolved; lower values mix the "
                        + "unprocessed signal back in.")
                    .accessibilityLabel("Mix")
                    .accessibilityValue("\(Int((model.wet * 100).rounded())) percent wet")
            }

            controlRow(
                title: "Output gain",
                value: String(format: "%+.1f dB", model.gainDB)
            ) {
                Slider(value: $model.gainDB, in: -24...24)
                    .help("Make-up gain applied after convolution, from -24 dB to +24 dB.")
                    .accessibilityLabel("Output gain")
                    .accessibilityValue(String(format: "%+.1f decibels", model.gainDB))
            }

            if compact {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Bypass", isOn: $model.bypassed)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.caption)
                        .help("Pass audio through without convolution, with no added latency. "
                            + "Use it for an instant A/B comparison.")
                        .accessibilityHint("Passes audio through without convolution and without added latency")
                    Toggle("Normalize impulse response", isOn: $model.normalize)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.caption)
                        .help("Match the loudness of responses with different lengths when you switch.")
                        .accessibilityHint("Matches the loudness of responses with different lengths")
                }
            } else {
                Divider()
                HStack(spacing: 24) {
                    Toggle("Bypass", isOn: $model.bypassed)
                        .toggleStyle(.switch)
                        .help("Pass audio through without convolution, with no added latency. "
                            + "Use it for an instant A/B comparison.")
                        .accessibilityHint("Passes audio through without convolution and without added latency")
                    Toggle("Normalize impulse response", isOn: $model.normalize)
                        .toggleStyle(.switch)
                        .help("Match the loudness of responses with different lengths when you switch.")
                        .accessibilityHint("Matches the loudness of responses with different lengths")
                    Spacer()
                }
            }
        }
    }

    private func controlRow<Content: View>(
        title: String,
        value: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(labelFont)
                Spacer()
                Text(value)
                    .font(compact ? .caption.monospacedDigit() : .subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            content()
        }
    }
}

struct MetersSection: View {
    @ObservedObject var meters: MeterStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LevelMeter(label: "Input", level: meters.input)
            LevelMeter(label: "Output", level: meters.output)
        }
    }
}

struct StatusMessages: View {
    @ObservedObject var model: AppModel
    var compact: Bool = true

    var body: some View {
        if let hint = model.hintMessage {
            message(
                icon: "exclamationmark.triangle.fill",
                tint: .orange,
                text: hint
            )
        }
        if let error = model.errorMessage {
            message(
                icon: "xmark.octagon.fill",
                tint: .red,
                text: error
            )
        }
    }

    @ViewBuilder private func message(icon: String, tint: Color, text: String) -> some View {
        let content = VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(text)
                    .font(compact ? .caption : .callout)
                    .foregroundStyle(compact ? tint : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            Button("Open Privacy Settings…") { model.openPrivacySettings() }
                .controlSize(.small)
                .accessibilityHint("Opens the System Audio Recording privacy pane")
        }

        if compact {
            content
        } else {
            content.cardSurface(padding: 14)
        }
    }
}

struct InfoFooter: View {
    @ObservedObject var model: AppModel
    var compact: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            ForEach(model.infoLines, id: \.self) { line in
                Text(line)
                    .font(compact ? .caption2 : .caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The shared control surface used by both the menu bar panel and the main
/// window. Keeping one implementation means the two entry points cannot drift
/// apart in behaviour or accessibility.
struct ConvolverControls: View {
    @ObservedObject var model: AppModel
    @ObservedObject var meters: MeterStore
    @ObservedObject var status: StatusStore
    var compact: Bool = true

    var body: some View {
        Group {
            if compact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatusHeader(model: model, status: status, compact: true)
            Divider()
            ImpulseResponseSection(model: model, compact: true)
            Divider()
            MixControls(model: model, compact: true)
            Divider()
            MetersSection(meters: meters)
            StatusMessages(model: model, compact: true)
            Divider()
            InfoFooter(model: model, compact: true)
        }
    }

    private var regularLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            StatusHeader(model: model, status: status, compact: false)
                .cardSurface(padding: 16)

            PanelCard(title: "Impulse response", systemImage: "waveform") {
                ImpulseResponseSection(model: model, compact: false, showsHeading: false)
            }

            PanelCard(title: "Mix & output", systemImage: "slider.horizontal.3") {
                MixControls(model: model, compact: false)
            }

            PanelCard(title: "Levels", systemImage: "waveform.path.ecg") {
                MetersSection(meters: meters)
            }

            StatusMessages(model: model, compact: false)

            PanelCard(title: "Status", systemImage: "info.circle") {
                InfoFooter(model: model, compact: false)
            }
        }
    }
}
