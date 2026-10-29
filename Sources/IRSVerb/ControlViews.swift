import SwiftUI

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

    private var color: Color {
        if normalized > 0.9 { return .red }
        if normalized > 0.72 { return .yellow }
        return .green
    }

    private var valueDescription: String {
        guard level > 0 else { return "silent" }
        let decibels = 20 * log10(level)
        return String(format: "%.0f decibels", max(-120, decibels))
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: max(0, geometry.size.width * normalized))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) level")
        .accessibilityValue(valueDescription)
    }
}

struct StatusHeader: View {
    @ObservedObject var model: AppModel
    @ObservedObject var status: StatusStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: status.isRunning ? "waveform.circle.fill" : "waveform.circle")
                .font(.title2)
                .foregroundStyle(status.isRunning ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("IRSVerb")
                    .font(.headline)
                Text(status.isRunning ? "Running" : "Stopped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(status.isRunning ? "Stop" : "Start") {
                model.toggleRunning()
            }
            .controlSize(.small)
            .accessibilityHint(status.isRunning
                ? "Stops processing and restores normal system audio"
                : "Starts processing system audio")
        }
    }
}

struct ImpulseResponseSection: View {
    @ObservedObject var model: AppModel
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Impulse response")
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.isPreparingLibrary {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating demo impulse responses…")
                        .font(.caption)
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
                .accessibilityLabel("Impulse response")
                .accessibilityValue(model.selectedURL?.deletingPathExtension().lastPathComponent ?? "None")
                if !compact {
                    Text("The picker lists every supported audio file in the current folder.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                Button("Choose .irs…") { model.chooseImpulseResponseFile() }
                    .accessibilityHint("Choose a single impulse response file from anywhere on disk")
                Button("Folder…") { model.chooseFolder() }
                    .accessibilityHint("Use a different folder as the impulse response library")
                Button("Reveal") { model.revealFolder() }
                    .accessibilityHint("Show the current impulse response folder in Finder")
            }
            .controlSize(.small)

            if !compact {
                Text("Folder: \(model.folderURL.path)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
        }
    }
}

struct MixControls: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Mix").font(.caption)
                    Spacer()
                    Text("\(Int((model.wet * 100).rounded()))% wet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Slider(value: $model.wet, in: 0...1)
                    .accessibilityLabel("Mix")
                    .accessibilityValue("\(Int((model.wet * 100).rounded())) percent wet")
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Output gain").font(.caption)
                    Spacer()
                    Text(String(format: "%+.1f dB", model.gainDB))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Slider(value: $model.gainDB, in: -24...24)
                    .accessibilityLabel("Output gain")
                    .accessibilityValue(String(format: "%+.1f decibels", model.gainDB))
            }

            Toggle("Bypass", isOn: $model.bypassed)
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityHint("Passes audio through without convolution and without added latency")

            Toggle("Normalize impulse response", isOn: $model.normalize)
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityHint("Matches the loudness of responses with different lengths")
        }
    }
}

struct MetersSection: View {
    @ObservedObject var meters: MeterStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LevelMeter(label: "Input", level: meters.input)
            LevelMeter(label: "Output", level: meters.output)
        }
    }
}

struct StatusMessages: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let hint = model.hintMessage {
            VStack(alignment: .leading, spacing: 6) {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Privacy Settings…") { model.openPrivacySettings() }
                    .controlSize(.small)
            }
        }
        if let error = model.errorMessage {
            VStack(alignment: .leading, spacing: 6) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Privacy Settings…") { model.openPrivacySettings() }
                    .controlSize(.small)
            }
        }
    }
}

struct InfoFooter: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.infoLines, id: \.self) { line in
                Text(line)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
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
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            StatusHeader(model: model, status: status)
            Divider()
            ImpulseResponseSection(model: model, compact: compact)
            Divider()
            MixControls(model: model)
            Divider()
            MetersSection(meters: meters)
            StatusMessages(model: model)
            Divider()
            InfoFooter(model: model)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
