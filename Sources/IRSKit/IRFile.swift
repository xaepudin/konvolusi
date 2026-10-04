import AVFoundation
import Foundation

public enum IRFileError: LocalizedError {
    case unreadable(URL, String)
    case empty(URL)
    case silent(URL)
    case tooLong(URL, Double)
    case unsupported(URL)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url, let reason):
            return "Could not read \(url.lastPathComponent): \(reason)"
        case .empty(let url):
            return "\(url.lastPathComponent) contains no audio."
        case .silent(let url):
            return "\(url.lastPathComponent) is silent (all samples are zero)."
        case .tooLong(let url, let seconds):
            return "\(url.lastPathComponent) is \(String(format: "%.1f", seconds))s long; the limit is \(Int(IRFile.maximumDuration))s."
        case .unsupported(let url):
            return "\(url.lastPathComponent) is not a supported audio file."
        }
    }
}

/// Reads and writes Viper4Android style `.irs` impulse responses.
///
/// An `.irs` file is a plain WAV file; only the extension is unusual. Reading is
/// content based so the extension does not matter, but `AVAudioFile` infers the
/// container from the extension when *writing*, so files are written as `.wav`
/// and then moved into place.
public enum IRFile {
    /// Longest impulse response accepted, in seconds.
    public static let maximumDuration: Double = 10.0

    public static let supportedExtensions: Set<String> = ["irs", "wav", "wave", "aif", "aiff", "caf", "flac", "m4a"]

    public static func isImpulseResponse(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - Loading

    public static func load(url: URL,
                            targetSampleRate: Double? = nil,
                            normalize: Bool = true) throws -> ImpulseResponse {
        var response = try readAudio(url: url, targetSampleRate: targetSampleRate)
        guard response.frameCount > 0 else { throw IRFileError.empty(url) }
        guard response.duration <= maximumDuration else { throw IRFileError.tooLong(url, response.duration) }
        if normalize {
            guard response.energy > 0 else { throw IRFileError.silent(url) }
            response.normalizeEnergy()
        }
        return response
    }

    /// Reads any audio file into float channels, optionally resampled, without
    /// the impulse-response specific length limit or normalization.
    public static func readAudio(url: URL, targetSampleRate: Double? = nil) throws -> ImpulseResponse {
        var (channels, sampleRate) = try readAll(url: url)
        guard let frames = channels.first?.count, frames > 0 else { throw IRFileError.empty(url) }
        if let target = targetSampleRate, abs(target - sampleRate) > 0.5 {
            channels = try resample(channels, from: sampleRate, to: target, url: url)
            sampleRate = target
        }
        return ImpulseResponse(name: url.deletingPathExtension().lastPathComponent,
                               sampleRate: sampleRate,
                               channels: channels,
                               sourceURL: url)
    }

    private static func readAll(url: URL) throws -> (channels: [[Float]], sampleRate: Double) {
        if let file = try? AVAudioFile(forReading: url) {
            return try extract(from: file, url: url)
        }
        // Fall back to a .wav copy for containers the reader refuses by extension.
        let manager = FileManager.default
        let temporary = manager.temporaryDirectory
            .appendingPathComponent("irs-\(UUID().uuidString).wav")
        defer { try? manager.removeItem(at: temporary) }
        do {
            try manager.copyItem(at: url, to: temporary)
        } catch {
            throw IRFileError.unreadable(url, error.localizedDescription)
        }
        guard let file = try? AVAudioFile(forReading: temporary) else {
            throw IRFileError.unreadable(url, "not a recognised audio format")
        }
        return try extract(from: file, url: url)
    }

    private static func extract(from file: AVAudioFile, url: URL) throws -> (channels: [[Float]], sampleRate: Double) {
        let format = file.processingFormat
        let frameCount = Int(file.length)
        guard frameCount > 0 else { throw IRFileError.empty(url) }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw IRFileError.unreadable(url, "could not allocate a decode buffer")
        }
        do {
            try file.read(into: buffer)
        } catch {
            throw IRFileError.unreadable(url, error.localizedDescription)
        }
        guard let data = buffer.floatChannelData else { throw IRFileError.unsupported(url) }

        let channels = Int(format.channelCount)
        let frames = Int(buffer.frameLength)
        guard channels > 0, frames > 0 else { throw IRFileError.empty(url) }

        var result: [[Float]] = []
        let keep = min(channels, 2)
        if format.isInterleaved {
            let base = data[0]
            for channel in 0..<keep {
                var samples = [Float](repeating: 0, count: frames)
                for frame in 0..<frames { samples[frame] = base[frame * channels + channel] }
                result.append(samples)
            }
        } else {
            for channel in 0..<keep {
                result.append(Array(UnsafeBufferPointer(start: data[channel], count: frames)))
            }
        }
        return (result, format.sampleRate)
    }

    // MARK: - Sample rate conversion

    public static func resample(_ channels: [[Float]],
                                from sourceRate: Double,
                                to targetRate: Double,
                                url: URL? = nil) throws -> [[Float]] {
        guard abs(sourceRate - targetRate) > 0.5 else { return channels }
        let channelCount = channels.count
        let frames = channels[0].count
        guard let inputFormat = AVAudioFormat(standardFormatWithSampleRate: sourceRate,
                                              channels: AVAudioChannelCount(channelCount)),
              let outputFormat = AVAudioFormat(standardFormatWithSampleRate: targetRate,
                                               channels: AVAudioChannelCount(channelCount)),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat),
              let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(frames)),
              let source = input.floatChannelData else {
            throw IRFileError.unreadable(url ?? URL(fileURLWithPath: "/"), "sample rate conversion is unavailable")
        }
        input.frameLength = AVAudioFrameCount(frames)
        for channel in 0..<channelCount {
            channels[channel].withUnsafeBufferPointer {
                source[channel].update(from: $0.baseAddress!, count: frames)
            }
        }

        var output: [[Float]] = Array(repeating: [], count: channelCount)
        var supplied = false
        let chunk = 8192
        var guardCounter = 0
        while true {
            guardCounter += 1
            if guardCounter > 100_000 { break }
            guard let destination = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                                     frameCapacity: AVAudioFrameCount(chunk)) else { break }
            var conversionError: NSError?
            let status = converter.convert(to: destination, error: &conversionError) { _, outStatus in
                if supplied {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                supplied = true
                outStatus.pointee = .haveData
                return input
            }
            if let conversionError { throw IRFileError.unreadable(url ?? URL(fileURLWithPath: "/"),
                                                                 conversionError.localizedDescription) }
            let produced = Int(destination.frameLength)
            if produced > 0, let data = destination.floatChannelData {
                for channel in 0..<channelCount {
                    output[channel].append(contentsOf: UnsafeBufferPointer(start: data[channel], count: produced))
                }
            }
            if status == .endOfStream || status == .error { break }
            if produced == 0 && status == .inputRanDry { break }
        }
        let shortest = output.map(\.count).min() ?? 0
        guard shortest > 0 else { throw IRFileError.empty(url ?? URL(fileURLWithPath: "/")) }
        for index in output.indices { output[index].removeLast(output[index].count - shortest) }
        return output
    }

    // MARK: - Writing

    public static func write(_ impulseResponse: ImpulseResponse, to url: URL, bitDepth: Int = 16) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let frames = impulseResponse.frameCount
        let channelCount = impulseResponse.channelCount
        guard frames > 0, channelCount > 0 else { throw IRFileError.empty(url) }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: impulseResponse.sampleRate,
                                         channels: AVAudioChannelCount(channelCount)),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let destination = buffer.floatChannelData else {
            throw IRFileError.unsupported(url)
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        for channel in 0..<channelCount {
            impulseResponse.channels[channel].withUnsafeBufferPointer {
                destination[channel].update(from: $0.baseAddress!, count: frames)
            }
        }

        // AVAudioFile picks the container from the extension, so write a real
        // .wav next to the target and rename it once the file is closed.
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".irs-\(UUID().uuidString).wav")
        defer { try? manager.removeItem(at: temporary) }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: impulseResponse.sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVLinearPCMBitDepthKey: bitDepth,
            AVLinearPCMIsFloatKey: bitDepth == 32,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        func writeFile() throws {
            let file = try AVAudioFile(forWriting: temporary, settings: settings)
            try file.write(from: buffer)
        }
        try writeFile()

        if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
        try manager.moveItem(at: temporary, to: url)
    }
}
