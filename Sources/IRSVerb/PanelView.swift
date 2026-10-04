import SwiftUI

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

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
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
        }
    }
}

struct PanelView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            impulseResponseSection
            Divider()
            controls
            Divider()
            meters
            if let hint = model.hintMessage {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Privacy Settings…") { model.openPrivacySettings() }
                    .controlSize(.small)
            }
            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Privacy Settings…") { model.openPrivacySettings() }
                    .controlSize(.small)
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 380)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.isRunning ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8)
            Text("IRSVerb")
                .font(.headline)
            Spacer()
            Button(model.isRunning ? "Stop" : "Start") { model.toggleRunning() }
                .controlSize(.small)
        }
    }

    private var impulseResponseSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Impulse response")
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.isPreparingLibrary {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Generating demo impulse responses…").font(.caption)
                }
            } else if model.items.isEmpty {
                Text("No .irs files in this folder").font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Impulse response", selection: $model.selectedURL) {
                    ForEach(model.items) { item in
                        Text(item.name).tag(Optional(item.url))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            HStack(spacing: 6) {
                Button("Choose .irs…") { model.chooseImpulseResponseFile() }
                Button("Folder…") { model.chooseFolder() }
                Button("Reveal") { model.revealFolder() }
            }
            .controlSize(.small)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Mix").font(.caption)
                    Spacer()
                    Text("\(Int((model.wet * 100).rounded()))% wet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $model.wet, in: 0...1)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Output gain").font(.caption)
                    Spacer()
                    Text(String(format: "%+.1f dB", model.gainDB))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $model.gainDB, in: -24...24)
            }
            Toggle("Bypass", isOn: $model.bypassed)
                .toggleStyle(.switch)
                .controlSize(.small)
            Toggle("Normalize impulse response", isOn: $model.normalize)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private var meters: some View {
        VStack(alignment: .leading, spacing: 4) {
            LevelMeter(label: "In", level: model.inputLevel)
            LevelMeter(label: "Out", level: model.outputLevel)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.infoLines, id: \.self) { line in
                Text(line)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Quit IRSVerb") { model.quit() }
                    .controlSize(.small)
            }
            .padding(.top, 2)
        }
    }
}
