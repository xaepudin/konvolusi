import Foundation
import IRSKit

// =====================================================================================
// irsconv - offline impulse response tooling for the IRSVerb project.
//
//   irsconv render <input...> --irs <file.irs> [--out <dir|file.wav>] [--wet 1.0]
//                            [--gain-db 0] [--bits 24] [--rate 48000]
//   irsconv make-ir [--out <dir>] [--rate 44100]
//   irsconv info <file...>
//   irsconv selftest
// =====================================================================================

struct ArgumentParser {
    private(set) var values: [String: String] = [:]
    private(set) var flags: Set<String> = []
    private(set) var positional: [String] = []

    init(_ raw: [String], booleanFlags: Set<String> = []) {
        var index = 0
        while index < raw.count {
            let argument = raw[index]
            defer { index += 1 }
            guard argument.hasPrefix("--") else {
                positional.append(argument)
                continue
            }
            let body = String(argument.dropFirst(2))
            if let equals = body.firstIndex(of: "=") {
                values[String(body[body.startIndex..<equals])] = String(body[body.index(after: equals)...])
            } else if booleanFlags.contains(body) {
                flags.insert(body)
            } else if index + 1 < raw.count, !raw[index + 1].hasPrefix("--") {
                values[body] = raw[index + 1]
                index += 1
            } else {
                flags.insert(body)
            }
        }
    }

    func value(_ key: String) -> String? { values[key] }
    func flag(_ key: String) -> Bool { flags.contains(key) }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func printUsage() {
    print("""
    irsconv - apply Viper4Android .irs impulse responses offline

    USAGE
      irsconv render <input...> --irs <file.irs> [options]
      irsconv make-ir [--out <dir>] [--rate <hz>]
      irsconv info <file...>
      irsconv selftest

    RENDER OPTIONS
      --irs <file>      impulse response to apply (required)
      --out <path>      output directory, or a .wav file for a single input
      --wet <0..1>      wet/dry mix, default 1.0 (fully convolved)
      --gain-db <db>    output gain in dB, default 0
      --bits <16|24|32> output bit depth, default 24
      --rate <hz>       render sample rate, default: the input file's rate
      --normalize       re-normalize the impulse response energy (on by default)
      --no-normalize    keep the impulse response's original level
    """)
}

// MARK: - render

func renderCommand(_ parser: ArgumentParser) throws {
    guard let irPath = parser.value("irs") else { fail("render requires --irs <file.irs>") }
    guard !parser.positional.isEmpty else { fail("render requires at least one input file") }

    let wet = parser.value("wet").flatMap(Float.init) ?? 1
    guard (0...1).contains(wet) else { fail("--wet must be between 0 and 1") }
    let gainDB = parser.value("gain-db").flatMap(Float.init) ?? 0
    let bits = parser.value("bits").flatMap(Int.init) ?? 24
    guard [16, 24, 32].contains(bits) else { fail("--bits must be 16, 24 or 32") }
    let requestedRate = parser.value("rate").flatMap(Double.init)
    let normalize = !parser.flag("no-normalize")

    let irURL = URL(fileURLWithPath: irPath)
    let impulse = try IRFile.load(url: irURL, normalize: normalize)
    print("impulse response: \(irURL.lastPathComponent)  "
        + "\(impulse.frameCount) taps  \(impulse.channelCount)ch  "
        + String(format: "%.2fs  %.0f Hz", impulse.duration, impulse.sampleRate))

    for inputPath in parser.positional {
        let inputURL = URL(fileURLWithPath: inputPath)
        let source = try IRFile.readAudio(url: inputURL)
        let rate = requestedRate ?? source.sampleRate

        var input = source
        if abs(source.sampleRate - rate) > 0.5 {
            let channels = try IRFile.resample(source.channels, from: source.sampleRate, to: rate, url: inputURL)
            input = ImpulseResponse(name: source.name, sampleRate: rate, channels: channels, sourceURL: inputURL)
        }
        var response = impulse
        if abs(impulse.sampleRate - rate) > 0.5 {
            let channels = try IRFile.resample(impulse.channels, from: impulse.sampleRate, to: rate, url: irURL)
            response = ImpulseResponse(name: impulse.name, sampleRate: rate, channels: channels)
        }
        if normalize { response.normalizeEnergy() }

        let outputURL = try resolveOutputURL(explicit: parser.value("out"), input: inputURL, impulseName: response.name)
        let rendered = try render(input: input, impulse: response, wet: wet, gainDB: gainDB)
        try IRFile.write(rendered.response, to: outputURL, bitDepth: bits)

        let partitions = (response.frameCount + rendered.blockSizeUsed - 1) / rendered.blockSizeUsed
        let inputLevel = level(of: input.channels)
        let outputLevel = level(of: rendered.response.channels)
        print("""
          \(inputURL.lastPathComponent): \(input.frameCount) frames @ \(Int(rate)) Hz
            in  peak \(format(inputLevel.peak))  rms \(format(inputLevel.rms)) dBFS
            out peak \(format(outputLevel.peak))  rms \(format(outputLevel.rms)) dBFS  \
        (delta \(format(outputLevel.rms - inputLevel.rms)) dB)
            -> \(outputURL.path)
               \(rendered.response.frameCount) frames, \(partitions) partitions, \
        block \(rendered.blockSizeUsed) (\(String(format: "%.1f", Double(rendered.blockSizeUsed) / rate * 1000)) ms) latency
        """)
    }
}

private func format(_ decibels: Double) -> String {
    decibels <= -120 ? "-inf" : String(format: "%+.2f", decibels)
}

private func level(of channels: [[Float]]) -> (peak: Double, rms: Double) {
    var peak = 0.0
    var sum = 0.0
    var count = 0
    for channel in channels {
        for sample in channel {
            let magnitude = abs(Double(sample))
            peak = max(peak, magnitude)
            sum += Double(sample) * Double(sample)
            count += 1
        }
    }
    let rms = count > 0 ? (sum / Double(count)).squareRoot() : 0
    return (peak, rms > 0 ? 20 * log10(rms) : -200)
}

private struct Rendered {
    var response: ImpulseResponse
    var blockSizeUsed: Int
}

private func resolveOutputURL(explicit: String?, input: URL, impulseName: String) throws -> URL {
    let manager = FileManager.default
    let defaultName = "\(input.deletingPathExtension().lastPathComponent) - \(impulseName).wav"
    guard let explicit else {
        return input.deletingLastPathComponent().appendingPathComponent(defaultName)
    }
    let url = URL(fileURLWithPath: explicit)
    var isDirectory: ObjCBool = false
    let exists = manager.fileExists(atPath: url.path, isDirectory: &isDirectory)
    if exists && isDirectory.boolValue {
        return url.appendingPathComponent(defaultName)
    }
    // A path with no extension is treated as a directory so that rendering
    // several files at once does not silently overwrite one output.
    if explicit.hasSuffix("/") || (url.pathExtension.isEmpty && !exists) {
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
        return url.appendingPathComponent(defaultName)
    }
    return url
}

private func render(input: ImpulseResponse,
                    impulse: ImpulseResponse,
                    wet: Float,
                    gainDB: Float) throws -> Rendered {
    let blockSize = 256
    let processor = IRSProcessor(blockSize: blockSize)
    processor.wet = wet
    processor.gainDecibels = gainDB
    processor.load(impulse)

    let frames = input.frameCount
    let irFrames = impulse.frameCount
    // Feed the input plus enough silence to flush the block engine and the tail.
    let totalFrames = frames + irFrames - 1 + blockSize
    let channelCount = input.channelCount

    var left = input.channels[0]
    var right = channelCount > 1 ? input.channels[1] : input.channels[0]

    var outputLeft = [Float](repeating: 0, count: totalFrames)
    var outputRight = [Float](repeating: 0, count: totalFrames)

    let chunk = 4096
    var scratchLeft = [Float](repeating: 0, count: chunk)
    var scratchRight = [Float](repeating: 0, count: chunk)
    var chunkOutLeft = [Float](repeating: 0, count: chunk)
    var chunkOutRight = [Float](repeating: 0, count: chunk)

    var position = 0
    while position < totalFrames {
        let count = min(chunk, totalFrames - position)
        for index in 0..<count {
            let source = position + index
            if source < frames {
                scratchLeft[index] = left[source]
                scratchRight[index] = right[source]
            } else {
                scratchLeft[index] = 0
                scratchRight[index] = 0
            }
        }
        scratchLeft.withUnsafeBufferPointer { sourceLeft in
            scratchRight.withUnsafeBufferPointer { sourceRight in
                chunkOutLeft.withUnsafeMutableBufferPointer { destinationLeft in
                    chunkOutRight.withUnsafeMutableBufferPointer { destinationRight in
                        processor.process(inputLeft: sourceLeft.baseAddress!,
                                          inputRight: sourceRight.baseAddress!,
                                          outputLeft: destinationLeft.baseAddress!,
                                          outputRight: destinationRight.baseAddress!,
                                          frameCount: count)
                    }
                }
            }
        }
        for index in 0..<count {
            outputLeft[position + index] = chunkOutLeft[index]
            outputRight[position + index] = chunkOutRight[index]
        }
        position += count
    }
    left.removeAll(); right.removeAll()

    // Drop the block-engine latency so the render lines up with the input, then
    // keep exactly the length of the true convolution.
    let trimmedLength = frames + irFrames - 1
    var resultLeft = Array(outputLeft[blockSize..<(blockSize + trimmedLength)])
    var resultRight = Array(outputRight[blockSize..<(blockSize + trimmedLength)])

    let outputChannels: [[Float]]
    if channelCount > 1 {
        outputChannels = [resultLeft, resultRight]
    } else {
        outputChannels = [resultLeft]
    }
    resultLeft.removeAll(); resultRight.removeAll()

    var response = ImpulseResponse(name: "\(input.name) - \(impulse.name)",
                                   sampleRate: input.sampleRate,
                                   channels: outputChannels)
    response.sourceURL = nil
    return Rendered(response: response, blockSizeUsed: blockSize)
}

// MARK: - make-ir

func makeIRCommand(_ parser: ArgumentParser) throws {
    let directory = URL(fileURLWithPath: parser.value("out") ?? "./Impulse Responses")
    let rate = parser.value("rate").flatMap(Double.init) ?? 44100
    let urls = try IRSynthesis.writeDemoFiles(to: directory, sampleRate: rate)
    print("wrote \(urls.count) impulse responses to \(directory.path):")
    for url in urls { print("  \(url.lastPathComponent)") }
}

// MARK: - info

func infoCommand(_ parser: ArgumentParser) throws {
    guard !parser.positional.isEmpty else { fail("info requires at least one file") }
    for path in parser.positional {
        let url = URL(fileURLWithPath: path)
        let response = try IRFile.load(url: url, normalize: false)
        let partitions = (response.frameCount + 255) / 256
        print("""
        \(url.lastPathComponent)
          channels     : \(response.channelCount)\(response.isStereo ? " (stereo)" : " (mono)")
          sample rate  : \(Int(response.sampleRate)) Hz
          length       : \(response.frameCount) taps / \(String(format: "%.3f", response.duration)) s
          peak         : \(String(format: "%.4f", response.peak))
          energy       : \(String(format: "%.4f", response.energy))
          partitions   : \(partitions) @ block 256
        """)
    }
}

// MARK: - selftest

func selfTestCommand() -> Never {
    var failures: [String] = []

    func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            print("  PASS  \(name)")
        } else {
            print("  FAIL  \(name) \(detail)")
            failures.append(name)
        }
    }

    var generator = SplitMix64(seed: 0xDEC0DE)

    // 1. A unit impulse response must be a pure delay of one block.
    do {
        let block = 128
        let signal = (0..<1000).map { _ in generator.gaussian() }
        let convolver = PartitionedConvolver(impulseResponse: [1], blockSize: block)
        var output = [Float](repeating: 0, count: signal.count)
        signal.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                convolver.process(input: source.baseAddress!, output: destination.baseAddress!, frameCount: signal.count)
            }
        }
        var worst: Float = 0
        for index in 0..<(signal.count - block) {
            worst = max(worst, abs(output[index + block] - signal[index]))
        }
        check("unit impulse is a pure delay", worst < 1e-5, "worst \(worst)")
    }

    // 2. FFT convolution must agree with direct convolution.
    do {
        let block = 128
        let signal = (0..<3000).map { _ in generator.gaussian() }
        let impulse = (0..<777).map { index in generator.gaussian() * exp(-Float(index) / 200) }
        let convolver = PartitionedConvolver(impulseResponse: impulse, blockSize: block)
        var output = [Float](repeating: 0, count: signal.count)
        signal.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                convolver.process(input: source.baseAddress!, output: destination.baseAddress!, frameCount: signal.count)
            }
        }
        var worst: Float = 0
        var referencePeak: Float = 0
        for n in 0..<(signal.count - block) {
            var sum: Float = 0
            let upper = min(impulse.count - 1, n)
            for k in 0...upper { sum += signal[n - k] * impulse[k] }
            referencePeak = max(referencePeak, abs(sum))
            worst = max(worst, abs(output[n + block] - sum))
        }
        check("FFT convolution matches direct convolution", worst < referencePeak * 1e-4,
              "worst \(worst) vs peak \(referencePeak)")
    }

    // 3. Ring buffer must preserve samples across wrap-around.
    do {
        let ring = AudioRingBuffer(capacity: 128)
        var expected: [Float] = []
        var actual: [Float] = []
        for _ in 0..<30 {
            let count = 1 + Int(generator.next() % 40)
            let block = (0..<count).map { _ in generator.gaussian() }
            expected.append(contentsOf: block)
            let written = block.withUnsafeBufferPointer {
                ring.write(left: $0.baseAddress!, right: $0.baseAddress!, count: count)
            }
            var out = [Float](repeating: 0, count: written)
            let read = out.withUnsafeMutableBufferPointer {
                ring.read(into: $0.baseAddress!, $0.baseAddress!, count: written)
            }
            actual.append(contentsOf: out.prefix(read))
        }
        var worst: Float = 0
        for index in actual.indices where index < expected.count {
            worst = max(worst, abs(actual[index] - expected[index]))
        }
        check("ring buffer round trip", actual.count == expected.count && worst < 1e-6, "worst \(worst)")
    }

    // 4. Synthesis + file round trip.
    do {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("irsconv-selftest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try IRSynthesis.writeDemoFiles(to: directory)
        var allGood = urls.count == 5
        for url in urls {
            let response = try IRFile.load(url: url)
            if response.frameCount < 100 || abs(response.energy - 1) > 1e-3 { allGood = false }
        }
        check("demo impulse responses write and reload (16-bit .irs)", allGood)
    } catch {
        check("demo impulse responses write and reload (16-bit .irs)", false, "\(error)")
    }

    print("")
    if failures.isEmpty {
        print("selftest: all checks passed")
        exit(0)
    } else {
        print("selftest: \(failures.count) check(s) failed: \(failures.joined(separator: ", "))")
        exit(1)
    }
}

// MARK: - entry point

let rawArguments = Array(CommandLine.arguments.dropFirst())
guard let command = rawArguments.first else {
    printUsage()
    exit(1)
}
let parser = ArgumentParser(Array(rawArguments.dropFirst()),
                            booleanFlags: ["normalize", "no-normalize", "help"])

do {
    switch command {
    case "render":
        try renderCommand(parser)
    case "make-ir":
        try makeIRCommand(parser)
    case "info":
        try infoCommand(parser)
    case "selftest":
        selfTestCommand()
    case "-h", "--help", "help":
        printUsage()
    default:
        fail("unknown command '\(command)' (try: render, make-ir, info, selftest)")
    }
} catch {
    fail("\(error.localizedDescription)")
}
