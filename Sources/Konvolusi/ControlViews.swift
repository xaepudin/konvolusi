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

struct InfoContent {
    let title: String
    let message: String
}

/// A visible ⓘ affordance. Clicking opens a popover; hovering also shows the
/// short title as a standard tooltip. The old `.help`-only approach depended on
/// the user discovering hover, which was too easy to miss.
struct InfoButton: View {
    let title: String
    let message: String

    @State private var isShowing = false
    @State private var isHovering = false

    var body: some View {
        Button {
            isShowing.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isHovering ? Color.primary : Color.secondary)
                .frame(width: 22, height: 22)
                .background(
                    Color.primary.opacity(isHovering ? 0.12 : 0.06),
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("About \(title)")
        .accessibilityLabel("About \(title)")
        .accessibilityHint(message)
        .popover(isPresented: $isShowing, arrowEdge: .leading) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 300, alignment: .leading)
        }
    }
}

struct PanelCard<Content: View>: View {
    let title: String
    let systemImage: String
    var info: InfoContent? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let info {
                    InfoButton(title: info.title, message: info.message)
                }
                Spacer(minLength: 0)
            }
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
        guard level > 0 else { return "" }
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
        .help("\(label) level. A blank value means no audio is being captured right now.")
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
                Image(nsImage: KonvolusiMark.image(running: status.isRunning, size: 24))
                    .renderingMode(.template)
                    .interpolation(.high)
                    .foregroundStyle(status.isRunning ? Color.green : Color.secondary)
                    .frame(width: 24, height: 24)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Konvolusi")
                    .font(.headline)
                if !compact {
                    Text("Rediscover the songs you love.")
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
                    Text("Generating built-in responses…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else if model.items.isEmpty {
                Text("No impulse responses available")
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
                .accessibilityLabel("Impulse response")
                .accessibilityValue(model.selectedURL?.deletingPathExtension().lastPathComponent ?? "None")
            }

            if compact {
                HStack(spacing: 6) {
                    actionButtons
                }
                .controlSize(.small)
            } else {
                HStack(spacing: 8) {
                    actionButtons
                    Spacer(minLength: 0)
                }
                .controlSize(.regular)
            }

            if !compact {
                Text("Built-in responses are always available. Added IRs are copied into "
                    + "Konvolusi's library.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var actionButtons: some View {
        Button {
            model.addImpulseResponseFiles()
        } label: {
            Label("Add IR…", systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Choose one or more impulse response files. They are copied into Konvolusi's library.")

        Button {
            model.removeSelectedImpulseResponse()
        } label: {
            Label("Remove", systemImage: "minus")
        }
        .buttonStyle(.bordered)
        .disabled(!model.canRemoveSelected)
        .accessibilityHint("Remove the selected added impulse response. Built-in responses cannot be removed.")
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
                value: "\(Int((model.wet * 100).rounded()))% wet",
                info: InfoContent(
                    title: "Mix",
                    message: "Blends the processed signal with the original audio. 100% wet is "
                        + "fully convolved; lower values let more of the unprocessed signal through."
                )
            ) {
                Slider(value: $model.wet, in: 0...1)
                    .help("Wet/dry blend. 100% is fully convolved; lower values mix the "
                        + "unprocessed signal back in.")
                    .accessibilityLabel("Mix")
                    .accessibilityValue("\(Int((model.wet * 100).rounded())) percent wet")
            }

            controlRow(
                title: "Output gain",
                value: String(format: "%+.1f dB", model.gainDB),
                info: InfoContent(
                    title: "Output gain",
                    message: "Make-up volume applied after convolution, from -24 dB to +24 dB. "
                        + "Use it to compensate for a quiet or loud impulse response."
                )
            ) {
                Slider(value: $model.gainDB, in: -24...24)
                    .help("Make-up gain applied after convolution, from -24 dB to +24 dB.")
                    .accessibilityLabel("Output gain")
                    .accessibilityValue(String(format: "%+.1f decibels", model.gainDB))
            }

            if compact {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Toggle("Bypass", isOn: $model.bypassed)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .font(.caption)
                            .help("Pass audio through without convolution, with no added latency. "
                                + "Use it for an instant A/B comparison.")
                            .accessibilityHint("Passes audio through without convolution and without added latency")
                        InfoButton(
                            title: "Bypass",
                            message: "Pass audio through without convolution, with no added latency. "
                                + "Use it for an instant A/B comparison."
                        )
                    }
                    HStack(spacing: 6) {
                        Toggle("Normalize impulse response", isOn: $model.normalize)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .font(.caption)
                            .help("Match the loudness of responses with different lengths when you switch.")
                            .accessibilityHint("Matches the loudness of responses with different lengths")
                        InfoButton(
                            title: "Normalize impulse response",
                            message: "Scales each response so responses of different lengths play at a "
                                + "similar loudness when you switch between them."
                        )
                    }
                }
            } else {
                Divider()
                HStack(spacing: 24) {
                    HStack(spacing: 6) {
                        Toggle("Bypass", isOn: $model.bypassed)
                            .toggleStyle(.switch)
                            .help("Pass audio through without convolution, with no added latency. "
                                + "Use it for an instant A/B comparison.")
                            .accessibilityHint("Passes audio through without convolution and without added latency")
                        InfoButton(
                            title: "Bypass",
                            message: "Pass audio through without convolution, with no added latency. "
                                + "Use it for an instant A/B comparison."
                        )
                    }
                    HStack(spacing: 6) {
                        Toggle("Normalize impulse response", isOn: $model.normalize)
                            .toggleStyle(.switch)
                            .help("Match the loudness of responses with different lengths when you switch.")
                            .accessibilityHint("Matches the loudness of responses with different lengths")
                        InfoButton(
                            title: "Normalize impulse response",
                            message: "Scales each response so responses of different lengths play at a "
                                + "similar loudness when you switch between them."
                        )
                    }
                    Spacer()
                }
            }
        }
    }

    private func controlRow<Content: View>(
        title: String,
        value: String,
        info: InfoContent,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(labelFont)
                InfoButton(title: info.title, message: info.message)
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
    var showsHeading = false

    private let info = InfoContent(
        title: "Levels",
        message: "Input is the audio captured from other apps. Output is the convolved "
            + "signal sent to your speakers. A blank value means no audio is being "
            + "captured right now."
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsHeading {
                HStack(spacing: 6) {
                    Text("Levels")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    InfoButton(title: info.title, message: info.message)
                }
            }
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
    var meters: MeterStore
    var status: StatusStore
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
            MetersSection(meters: meters, showsHeading: true)
            StatusMessages(model: model, compact: true)
            Divider()
            Text("Status")
                .font(.caption)
                .foregroundStyle(.secondary)
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

            PanelCard(
                title: "Levels",
                systemImage: "waveform.path.ecg",
                info: InfoContent(
                    title: "Levels",
                    message: "Input is the audio captured from other apps. Output is the "
                        + "convolved signal sent to your speakers. A blank value means no audio "
                        + "is being captured right now."
                )
            ) {
                MetersSection(meters: meters)
            }

            StatusMessages(model: model, compact: false)

            PanelCard(title: "Status", systemImage: "info.circle") {
                InfoFooter(model: model, compact: false)
            }
        }
    }
}
