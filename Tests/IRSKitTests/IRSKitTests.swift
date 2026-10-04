import XCTest
import Accelerate
@testable import IRSKit

/// Naive direct convolution used as the reference for the FFT engine.
private func directConvolution(signal: [Float], impulse: [Float]) -> [Float] {
    var output = [Float](repeating: 0, count: signal.count)
    for n in 0..<signal.count {
        var sum: Float = 0
        let upper = min(impulse.count - 1, n)
        if upper >= 0 {
            for k in 0...upper { sum += signal[n - k] * impulse[k] }
        }
        output[n] = sum
    }
    return output
}

private func maxDifference(_ a: [Float], _ b: [Float], count: Int) -> Float {
    var worst: Float = 0
    for index in 0..<count { worst = max(worst, abs(a[index] - b[index])) }
    return worst
}

private func peak(_ values: [Float]) -> Float {
    var maximum: Float = 0
    for value in values { maximum = max(maximum, abs(value)) }
    return maximum
}

final class ConvolutionTests: XCTestCase {

    func testMatchesDirectConvolution() {
        let blockSize = 256
        let irLength = 1000
        let signalLength = 4096
        var generator = SplitMix64(seed: 0xA11CE)

        let signal = (0..<signalLength).map { _ in generator.gaussian() }
        let impulse = (0..<irLength).map { index in
            generator.gaussian() * exp(-Float(index) / 300)
        }

        let convolver = PartitionedConvolver(impulseResponse: impulse, blockSize: blockSize)
        XCTAssertEqual(convolver.partitionCount, (irLength + blockSize - 1) / blockSize)

        var output = [Float](repeating: 0, count: signalLength)
        signal.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                convolver.process(input: source.baseAddress!,
                                  output: destination.baseAddress!,
                                  frameCount: signalLength)
            }
        }

        let reference = directConvolution(signal: signal, impulse: impulse)
        // Output lags the input by exactly `blockSize` samples.
        let compared = signalLength - blockSize
        var worst: Float = 0
        for index in 0..<compared {
            worst = max(worst, abs(output[index + blockSize] - reference[index]))
        }
        let referencePeak = peak(reference)
        XCTAssertGreaterThan(referencePeak, 1)
        XCTAssertLessThan(worst, referencePeak * 1e-4,
                          "FFT convolution deviates from direct convolution (worst \(worst), peak \(referencePeak))")
    }

    func testDeltaImpulseIsPureDelay() {
        let blockSize = 128
        let length = 1000
        var generator = SplitMix64(seed: 7)
        let signal = (0..<length).map { _ in generator.gaussian() }

        let convolver = PartitionedConvolver(impulseResponse: [1], blockSize: blockSize)
        var output = [Float](repeating: 0, count: length)
        signal.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                convolver.process(input: source.baseAddress!, output: destination.baseAddress!, frameCount: length)
            }
        }
        for index in 0..<(length - blockSize) {
            XCTAssertEqual(output[index + blockSize], signal[index], accuracy: 1e-5)
        }
        for index in 0..<blockSize { XCTAssertEqual(output[index], 0, accuracy: 1e-6) }
    }

    func testLongImpulseResponseMatchesDirectConvolution() {
        // Exercises many partitions, including a length that is not a multiple
        // of the block size.
        let blockSize = 64
        let irLength = 517
        let signalLength = 1500
        var generator = SplitMix64(seed: 0xBEEF)
        let signal = (0..<signalLength).map { _ in generator.uniform() }
        let impulse = (0..<irLength).map { _ in generator.uniform() * 0.5 }

        let convolver = PartitionedConvolver(impulseResponse: impulse, blockSize: blockSize)
        XCTAssertEqual(convolver.partitionCount, 9)

        var output = [Float](repeating: 0, count: signalLength)
        signal.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                convolver.process(input: source.baseAddress!, output: destination.baseAddress!, frameCount: signalLength)
            }
        }
        let reference = directConvolution(signal: signal, impulse: impulse)
        let compared = signalLength - blockSize
        let worst = maxDifference(Array(output[blockSize..<(blockSize + compared)]), reference, count: compared)
        XCTAssertLessThan(worst, peak(reference) * 1e-4)
    }

    func testChunkedProcessingMatchesSingleCall() {
        let blockSize = 256
        let length = 5000
        var generator = SplitMix64(seed: 99)
        let signal = (0..<length).map { _ in generator.gaussian() }
        let impulse = (0..<800).map { _ in generator.gaussian() * 0.4 }
        let reference = directConvolution(signal: signal, impulse: impulse)

        // Feed the same signal through oddly sized buffers.
        let convolver = PartitionedConvolver(impulseResponse: impulse, blockSize: blockSize)
        var output = [Float](repeating: 0, count: length)
        var position = 0
        var chunkSizes: [Int] = []
        var sizeGenerator = SplitMix64(seed: 5)
        while position < length {
            let size = min(1 + Int(sizeGenerator.next() % 700), length - position)
            chunkSizes.append(size)
            signal.withUnsafeBufferPointer { source in
                output.withUnsafeMutableBufferPointer { destination in
                    convolver.process(input: source.baseAddress! + position,
                                      output: destination.baseAddress! + position,
                                      frameCount: size)
                }
            }
            position += size
        }
        XCTAssertGreaterThan(chunkSizes.count, 5)
        let compared = length - blockSize
        let worst = maxDifference(Array(output[blockSize..<(blockSize + compared)]), reference, count: compared)
        XCTAssertLessThan(worst, peak(reference) * 1e-4)
    }

    func testResetClearsHistory() {
        let convolver = PartitionedConvolver(impulseResponse: [0.5, 0.25], blockSize: 64)
        var input = [Float](repeating: 0, count: 128)
        var output = [Float](repeating: 0, count: 128)
        input[0] = 1
        input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                convolver.process(input: source.baseAddress!, output: destination.baseAddress!, frameCount: 128)
            }
        }
        convolver.reset()
        var second = [Float](repeating: 0, count: 128)
        input.withUnsafeBufferPointer { source in
            second.withUnsafeMutableBufferPointer { destination in
                convolver.process(input: source.baseAddress!, output: destination.baseAddress!, frameCount: 128)
            }
        }
        XCTAssertEqual(maxDifference(output, second, count: 128), 0, accuracy: 1e-6)
    }
}

final class IRFileTests: XCTestCase {

    func testDemoLibraryWritesAndReloads() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("irs-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let written = try IRSynthesis.writeDemoFiles(to: directory)
        XCTAssertEqual(written.count, 15)

        for url in written {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            let response = try IRFile.load(url: url)
            // The Identity control is deliberately a single sample.
            XCTAssertGreaterThan(response.frameCount, response.name.hasPrefix("Identity") ? 0 : 100)
            XCTAssertEqual(response.sampleRate, 44100, accuracy: 0.5)
            XCTAssertLessThanOrEqual(response.duration, IRFile.maximumDuration)
            // 16-bit PCM with unit energy normalization.
            XCTAssertEqual(Double(response.energy), 1.0, accuracy: 1e-3)
            XCTAssertLessThanOrEqual(response.peak, 1.0)
        }

        let hall = try IRFile.load(url: directory.appendingPathComponent("Large Hall.irs"))
        XCTAssertEqual(hall.channelCount, 2)
        XCTAssertGreaterThan(hall.duration, 1.0)
        XCTAssertLessThan(hall.duration, 3.0)

        let radio = try IRFile.load(url: directory.appendingPathComponent("Old Radio Speaker.irs"))
        XCTAssertEqual(radio.channelCount, 1)
        XCTAssertLessThan(radio.duration, 0.3)
    }

    func testLoadResamplesToRequestedRate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("irs-rate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let source = IRSynthesis.reverb(name: "Hall", sampleRate: 44100)
        let url = directory.appendingPathComponent("Hall.irs")
        try IRFile.write(source, to: url)

        let converted = try IRFile.load(url: url, targetSampleRate: 48000)
        XCTAssertEqual(converted.sampleRate, 48000, accuracy: 0.5)
        let ratio = Double(converted.frameCount) / Double(source.frameCount)
        XCTAssertEqual(ratio, 48000.0 / 44100.0, accuracy: 0.01)
    }

    func testResamplePreservesASineWave() throws {
        let sourceRate = 44100.0
        let targetRate = 48000.0
        let frequency = 1000.0
        let frames = 4410
        var sine = [Float](repeating: 0, count: frames)
        for index in 0..<frames {
            sine[index] = Float(sin(2 * Double.pi * frequency * Double(index) / sourceRate))
        }
        let converted = try IRFile.resample([sine], from: sourceRate, to: targetRate)
        XCTAssertEqual(converted.count, 1)
        let output = converted[0]
        XCTAssertEqual(Double(output.count) / Double(frames), targetRate / sourceRate, accuracy: 0.01)

        // Compare against the same sine generated at the target rate.
        let skip = 200
        var worst: Float = 0
        for index in skip..<(output.count - skip) {
            let expected = Float(sin(2 * Double.pi * frequency * Double(index) / targetRate))
            worst = max(worst, abs(output[index] - expected))
        }
        XCTAssertLessThan(worst, 0.02, "resampled sine deviates (worst \(worst))")
    }

    func testEnergyNormalization() {
        var response = ImpulseResponse(name: "test", sampleRate: 48000, channels: [[3, 4], [0, 0]])
        response.normalizeEnergy()
        XCTAssertEqual(Double(response.energy), 1.0, accuracy: 1e-6)
        XCTAssertEqual(response.channels[0][0], 0.6, accuracy: 1e-6)
        XCTAssertEqual(response.channels[0][1], 0.8, accuracy: 1e-6)
    }

    func testRejectsSilentFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("irs-bad-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let silentURL = directory.appendingPathComponent("Silent.irs")
        try IRFile.write(ImpulseResponse(name: "Silent", sampleRate: 44100, channels: [[0, 0, 0, 0]]), to: silentURL)
        XCTAssertThrowsError(try IRFile.load(url: silentURL)) { error in
            guard case IRFileError.silent = error else { return XCTFail("expected .silent, got \(error)") }
        }
    }

    func testRejectsOverlongFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("irs-long-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let longURL = directory.appendingPathComponent("Long.irs")
        // 12 seconds at 44.1 kHz; note that Core Audio clamps unusual sample
        // rates (a 1 kHz WAV is stored as 8 kHz), so use a realistic one.
        let long = ImpulseResponse(name: "Long", sampleRate: 44100,
                                   channels: [[Float](repeating: 0.1, count: 44100 * 12)])
        try IRFile.write(long, to: longURL)
        XCTAssertThrowsError(try IRFile.load(url: longURL)) { error in
            guard case IRFileError.tooLong = error else { return XCTFail("expected .tooLong, got \(error)") }
        }
    }

    func testBiquadLowPassPassesDC() {
        let sampleRate = 48000.0
        let chain = [
            Biquad.highPass(frequency: 300, sampleRate: sampleRate),
            Biquad.lowPass(frequency: 4000, sampleRate: sampleRate),
        ]
        let impulse = Biquad.impulseResponse(of: chain, length: 8192, sampleRate: sampleRate)
        let sum = impulse.reduce(0) { $0 + Double($1) }
        // A 300 Hz high pass removes DC, so the response must sum to ~0.
        XCTAssertEqual(sum, 0, accuracy: 1e-3)
        XCTAssertGreaterThan(peak(impulse), 0.1)
    }
}

final class ProcessorTests: XCTestCase {

    func testWetAndDryAlignInTime() {
        let blockSize = 64
        let length = 512
        var generator = SplitMix64(seed: 3)
        let left = (0..<length).map { _ in generator.gaussian() }
        let right = (0..<length).map { _ in generator.gaussian() }

        for wet in [Float(1), 0.5, 0] {
            let processor = IRSProcessor(maxBlockSize: blockSize)
            processor.wet = wet
            processor.load(ImpulseResponse(name: "delta", sampleRate: 48000, channels: [[1]]))

            var outLeft = [Float](repeating: 0, count: length)
            var outRight = [Float](repeating: 0, count: length)
            left.withUnsafeBufferPointer { sourceLeft in
                right.withUnsafeBufferPointer { sourceRight in
                    outLeft.withUnsafeMutableBufferPointer { destinationLeft in
                        outRight.withUnsafeMutableBufferPointer { destinationRight in
                            processor.process(inputLeft: sourceLeft.baseAddress!,
                                              inputRight: sourceRight.baseAddress!,
                                              outputLeft: destinationLeft.baseAddress!,
                                              outputRight: destinationRight.baseAddress!,
                                              frameCount: length)
                        }
                    }
                }
            }
            // With a unit impulse response the output is the input, delayed by
            // exactly one block, whatever the wet/dry setting.
            let worst = maxDifference(Array(outLeft[blockSize...]), left, count: length - blockSize)
            XCTAssertLessThan(worst, 1e-4, "wet=\(wet) misaligned")
        }
    }

    func testBypassIsLatencyFreePassThrough() {
        let processor = IRSProcessor(maxBlockSize: 64)
        processor.gain = 0.5
        processor.isBypassed = true
        processor.load(ImpulseResponse(name: "delta", sampleRate: 48000, channels: [[1]]))
        var input = [Float](repeating: 1, count: 32)
        var output = [Float](repeating: 0, count: 32)
        input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                processor.process(inputLeft: source.baseAddress!, inputRight: source.baseAddress!,
                                  outputLeft: destination.baseAddress!, outputRight: destination.baseAddress!,
                                  frameCount: 32)
            }
        }
        for value in output { XCTAssertEqual(value, 0.5, accuracy: 1e-6) }
    }

    func testUnloadRestoresTransparency() {
        let processor = IRSProcessor(maxBlockSize: 64)
        processor.load(ImpulseResponse(name: "hall", sampleRate: 48000,
                                       channels: [[Float](repeating: 0.1, count: 5000)]))
        processor.unload()
        XCTAssertEqual(processor.latency, 0)
        var input = [Float](repeating: 0.25, count: 16)
        var output = [Float](repeating: 0, count: 16)
        input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                processor.process(inputLeft: source.baseAddress!, inputRight: source.baseAddress!,
                                  outputLeft: destination.baseAddress!, outputRight: destination.baseAddress!,
                                  frameCount: 16)
            }
        }
        for value in output { XCTAssertEqual(value, 0.25, accuracy: 1e-6) }
    }

    func testGainDecibelsRoundTrip() {
        let processor = IRSProcessor(maxBlockSize: 64)
        processor.gainDecibels = -6
        XCTAssertEqual(processor.gain, 0.5011872, accuracy: 1e-4)
        XCTAssertEqual(processor.gainDecibels, -6, accuracy: 1e-3)
    }
}

final class RingBufferTests: XCTestCase {

    func testWriteReadRoundTripAndWrapAround() {
        let ring = AudioRingBuffer(capacity: 256)
        var generator = SplitMix64(seed: 11)
        var expectedLeft: [Float] = []
        var expectedRight: [Float] = []
        var produced: [Float] = []
        var producedRight: [Float] = []

        for _ in 0..<40 {
            let count = 1 + Int(generator.next() % 100)
            let left = (0..<count).map { _ in generator.gaussian() }
            let right = (0..<count).map { _ in generator.gaussian() }
            let written = left.withUnsafeBufferPointer { sourceLeft in
                right.withUnsafeBufferPointer { sourceRight in
                    ring.write(left: sourceLeft.baseAddress!, right: sourceRight.baseAddress!, count: count)
                }
            }
            XCTAssertGreaterThan(written, 0)
            // Only the samples the ring actually accepted can come back out.
            expectedLeft.append(contentsOf: left.prefix(written))
            expectedRight.append(contentsOf: right.prefix(written))

            let toRead = min(written, Int(generator.next() % 120))
            if toRead > 0 {
                var outLeft = [Float](repeating: 0, count: toRead)
                var outRight = [Float](repeating: 0, count: toRead)
                let read = outLeft.withUnsafeMutableBufferPointer { destinationLeft in
                    outRight.withUnsafeMutableBufferPointer { destinationRight in
                        ring.read(into: destinationLeft.baseAddress!, destinationRight.baseAddress!, count: toRead)
                    }
                }
                XCTAssertEqual(read, toRead)
                produced.append(contentsOf: outLeft)
                producedRight.append(contentsOf: outRight)
            }
        }
        XCTAssertGreaterThan(produced.count, 100)
        XCTAssertLessThanOrEqual(produced.count, expectedLeft.count)
        for index in produced.indices {
            XCTAssertEqual(produced[index], expectedLeft[index], accuracy: 1e-6)
            XCTAssertEqual(producedRight[index], expectedRight[index], accuracy: 1e-6)
        }
    }

    func testOverrunDropsAndCounts() {
        let ring = AudioRingBuffer(capacity: 64)
        let samples = [Float](repeating: 1, count: 100)
        let written = samples.withUnsafeBufferPointer { pointer in
            ring.write(left: pointer.baseAddress!, right: pointer.baseAddress!, count: 100)
        }
        XCTAssertEqual(written, 64)
        XCTAssertEqual(ring.droppedFrames.load(), 36)
        XCTAssertEqual(ring.fill, 64)
    }

    func testUnderrunReportsMissingFrames() {
        let ring = AudioRingBuffer(capacity: 64)
        var outLeft = [Float](repeating: 0, count: 10)
        var outRight = [Float](repeating: 0, count: 10)
        let read = outLeft.withUnsafeMutableBufferPointer { destinationLeft in
            outRight.withUnsafeMutableBufferPointer { destinationRight in
                ring.read(into: destinationLeft.baseAddress!, destinationRight.baseAddress!, count: 10)
            }
        }
        XCTAssertEqual(read, 0)
        XCTAssertEqual(ring.missingFrames.load(), 10)
    }
}


/// Tests for the energy optimisations: the silence fast path and the adaptive
/// partition size.
final class OptimizationTests: XCTestCase {

    private func process(_ convolver: PartitionedConvolver,
                         _ input: [Float],
                         into output: inout [Float],
                         offset: Int) {
        input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                convolver.process(input: source.baseAddress!,
                                  output: destination.baseAddress! + offset,
                                  frameCount: input.count)
            }
        }
    }

    func testSilenceFastPathIsExact() {
        let blockSize = 64
        var generator = SplitMix64(seed: 4242)
        let impulse = (0..<200).map { index in generator.gaussian() * exp(-Float(index) / 80) }
        let convolver = PartitionedConvolver(impulseResponse: impulse, blockSize: blockSize)
        let partitions = convolver.partitionCount
        XCTAssertGreaterThan(partitions, 1)

        let head = (0..<512).map { _ in generator.gaussian() }
        // Long enough to drain the impulse response completely.
        let silence = [Float](repeating: 0, count: (partitions + 2) * blockSize)
        let tail = (0..<512).map { _ in generator.gaussian() }
        let signal = head + silence + tail

        var output = [Float](repeating: 0, count: signal.count)
        process(convolver, head, into: &output, offset: 0)
        XCTAssertFalse(convolver.isSilent, "must not report silence while signal is playing")
        process(convolver, silence, into: &output, offset: head.count)
        XCTAssertTrue(convolver.isSilent, "fast path should have engaged after a full tail of silence")
        process(convolver, tail, into: &output, offset: head.count + silence.count)
        XCTAssertFalse(convolver.isSilent, "must leave the fast path as soon as signal returns")

        // The whole point: skipping the FFTs must not change a single sample.
        let reference = directConvolution(signal: signal, impulse: impulse)
        let compared = signal.count - blockSize
        let worst = maxDifference(Array(output[blockSize..<(blockSize + compared)]), reference, count: compared)
        XCTAssertLessThan(worst, peak(reference) * 1e-4,
                          "silence fast path changed the result (worst \(worst))")
    }

    func testSilenceFastPathRecognisesDigitalSilenceOnly() {
        // A tiny non-zero value must keep the engine on the exact path.
        let convolver = PartitionedConvolver(impulseResponse: [0.5, 0.25], blockSize: 64)
        var output = [Float](repeating: 0, count: 128)
        var quiet = [Float](repeating: 0, count: 128)
        quiet[3] = 1e-30
        process(convolver, quiet, into: &output, offset: 0)
        XCTAssertFalse(convolver.isSilent)
    }

    func testAdaptiveBlockSizeSelection() {
        // Thresholds are by duration: <=0.55 s -> 256, <=1.7 s -> 512, else 1024.
        func block(seconds: Double, maximum: Int = 1024) -> Int {
            IRSProcessor.preferredBlockSize(forFrameCount: Int(seconds * 48000),
                                            sampleRate: 48000,
                                            maximum: maximum)
        }
        XCTAssertEqual(block(seconds: 0.1), 256)
        XCTAssertEqual(block(seconds: 0.55), 256)
        XCTAssertEqual(block(seconds: 0.6), 512)
        XCTAssertEqual(block(seconds: 1.7), 512)
        XCTAssertEqual(block(seconds: 1.8), 1024)
        XCTAssertEqual(block(seconds: 4.0), 1024)
        // Never exceeds the caller's ceiling.
        XCTAssertEqual(block(seconds: 4.0, maximum: 256), 256)
        XCTAssertEqual(block(seconds: 4.0, maximum: 512), 512)
    }

    func testLongImpulseResponseKeepsDryWetAligned() {
        // A 1.8 s response selects the 1024-sample block, which changes the dry
        // delay line length; getting that wrong would smear the mix.
        let blockSize = 1024
        let processor = IRSProcessor(maxBlockSize: blockSize)
        processor.wet = 0.5
        var impulse = [Float](repeating: 0, count: 86_400)
        impulse[0] = 1
        processor.load(ImpulseResponse(name: "long delta", sampleRate: 48000, channels: [impulse]))
        XCTAssertEqual(processor.latency, blockSize)

        var generator = SplitMix64(seed: 77)
        let length = 4096
        let left = (0..<length).map { _ in generator.gaussian() }
        let right = (0..<length).map { _ in generator.gaussian() }
        var outLeft = [Float](repeating: 0, count: length)
        var outRight = [Float](repeating: 0, count: length)
        left.withUnsafeBufferPointer { sourceLeft in
            right.withUnsafeBufferPointer { sourceRight in
                outLeft.withUnsafeMutableBufferPointer { destinationLeft in
                    outRight.withUnsafeMutableBufferPointer { destinationRight in
                        processor.process(inputLeft: sourceLeft.baseAddress!,
                                          inputRight: sourceRight.baseAddress!,
                                          outputLeft: destinationLeft.baseAddress!,
                                          outputRight: destinationRight.baseAddress!,
                                          frameCount: length)
                    }
                }
            }
        }
        let worst = maxDifference(Array(outLeft[blockSize...]), left, count: length - blockSize)
        XCTAssertLessThan(worst, 1e-4, "dry/wet lost alignment at block size \(blockSize)")
    }
}


/// Magnitude of an impulse response at one frequency (a single DFT bin).
///
/// Rotates a phasor rather than calling cos/sin per sample, which matters
/// because the long responses have hundreds of thousands of samples.
func responseMagnitude(_ samples: [Float], at frequency: Double, sampleRate: Double) -> Double {
    let omega = 2 * Double.pi * frequency / sampleRate
    let stepCos = cos(omega)
    let stepSin = sin(omega)
    var cosPhase = 1.0
    var sinPhase = 0.0
    var real = 0.0
    var imaginary = 0.0
    var sinceRenormalise = 0
    for sample in samples {
        real += Double(sample) * cosPhase
        imaginary -= Double(sample) * sinPhase
        let nextCos = cosPhase * stepCos - sinPhase * stepSin
        sinPhase = sinPhase * stepCos + cosPhase * stepSin
        cosPhase = nextCos
        sinceRenormalise += 1
        if sinceRenormalise == 4096 {
            sinceRenormalise = 0
            let magnitude = (cosPhase * cosPhase + sinPhase * sinPhase).squareRoot()
            if magnitude > 0 { cosPhase /= magnitude; sinPhase /= magnitude }
        }
    }
    return (real * real + imaginary * imaginary).squareRoot()
}

final class LibraryTests: XCTestCase {

    private let sampleRate = 48000.0
    /// Synthesised once per test run: the 4.4 s cathedral is not free.
    private static let sharedLibrary = IRSynthesis.builtInLibrary(sampleRate: 48000)
    private var library: [ImpulseResponse] { Self.sharedLibrary }

    private func response(_ name: String) -> ImpulseResponse {
        guard let match = library.first(where: { $0.name == name }) else {
            XCTFail("library is missing \(name)")
            return ImpulseResponse(name: name, sampleRate: sampleRate, channels: [[0]])
        }
        return match
    }

    private func level(_ name: String, _ frequency: Double) -> Double {
        responseMagnitude(response(name).channels[0], at: frequency, sampleRate: sampleRate)
    }

    /// How ragged the magnitude response is across a band. Diffuse reverberation
    /// sits around 0.5; a sparse modal response is far higher.
    private func ripple(_ name: String, from: Double = 300, to: Double = 3000, step: Double = 7) -> Double {
        let samples = response(name).channels[0]
        var values: [Double] = []
        var frequency = from
        while frequency <= to {
            values.append(responseMagnitude(samples, at: frequency, sampleRate: sampleRate))
            frequency += step
        }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return 0 }
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot() / mean
    }

    func testLibraryContentsAreSane() {
        XCTAssertEqual(library.count, 15, "the built-in library should stay small and curated")
        var names = Set<String>()
        for item in library {
            XCTAssertTrue(names.insert(item.name).inserted, "duplicate name \(item.name)")
            XCTAssertGreaterThan(item.frameCount, 0, "\(item.name) is empty")
            XCTAssertLessThanOrEqual(item.duration, IRFile.maximumDuration, "\(item.name) is too long")
            XCTAssertLessThanOrEqual(item.peak, 1.0001, "\(item.name) clips")
            XCTAssertEqual(Double(item.energy), 1.0, accuracy: 1e-3, "\(item.name) is not energy normalised")
            // One assertion for the whole response: per-sample XCTAssert calls
            // dominated the test runtime.
            for channel in item.channels {
                XCTAssertTrue(channel.allSatisfy { $0.isFinite }, "\(item.name) has a non-finite sample")
            }
        }
    }

    func testIdentityIsATransparentControl() {
        let identity = response("Identity (control)")
        XCTAssertEqual(identity.frameCount, 1)
        XCTAssertEqual(identity.channels[0][0], 1)
        // Flat across the spectrum, which is what makes it a usable A/B control.
        for frequency in [60.0, 1000, 12000] {
            XCTAssertEqual(level("Identity (control)", frequency), 1, accuracy: 1e-6)
        }
    }

    func testSpeechLiftRemovesRumbleAndLiftsPresence() {
        // Measured: 60 Hz ~0.16, 3 kHz ~1.94.
        XCTAssertLessThan(level("Speech Lift", 60), level("Speech Lift", 3000) * 0.25)
        XCTAssertGreaterThan(level("Speech Lift", 3000), level("Speech Lift", 1000))
    }

    func testNightModeLiftsBothExtremes() {
        // Equal-loudness compensation: bass and treble up, middle untouched.
        let middle = level("Night Mode", 1000)
        XCTAssertGreaterThan(level("Night Mode", 60), middle * 1.5)
        XCTAssertGreaterThan(level("Night Mode", 12000), middle * 1.25)
        XCTAssertLessThan(level("Night Mode", 2600), middle)
    }

    func testRadioAndTelephoneAreBandLimited() {
        // Measured: radio 60 Hz ~0.005 / 12 kHz ~0.026; telephone ~0.001 / ~0.004.
        XCTAssertLessThan(level("Old Radio Speaker", 60), level("Old Radio Speaker", 2600) * 0.1)
        XCTAssertLessThan(level("Old Radio Speaker", 12000), level("Old Radio Speaker", 2600) * 0.1)
        XCTAssertLessThan(level("Telephone", 60), level("Telephone", 2600) * 0.05)
        XCTAssertLessThan(level("Telephone", 12000), level("Telephone", 2600) * 0.05)
    }

    func testCassetteTapeHasHeadBumpAndSoftTop() {
        XCTAssertGreaterThan(level("Cassette Tape", 60), level("Cassette Tape", 1000) * 1.2)
        XCTAssertLessThan(level("Cassette Tape", 12000), level("Cassette Tape", 2600) * 0.3)
    }

    /// The flutter train is what makes a stairwell sound like a stairwell, so it
    /// is tested directly: same parameters, with and without the echoes.
    func testFlutterEchoesChangeTheResponse() {
        var plain = ReverbParameters()
        plain.duration = 0.5
        plain.t60 = 0.35
        plain.predelay = 0.004
        plain.earlyReflectionCount = 8
        plain.seed = 0x1234_5678

        var flutter = plain
        flutter.flutter = FlutterEcho(spacing: 0.045, count: 12, decay: 0.4,
                                      amplitude: 0.45, alternatingPolarity: true)

        let plainResponse = IRSynthesis.reverb(name: "plain", sampleRate: sampleRate, parameters: plain)
        let flutterResponse = IRSynthesis.reverb(name: "flutter", sampleRate: sampleRate, parameters: flutter)

        // Both responses are energy normalised, so an absolute comparison would
        // be dominated by that gain difference. Peak normalise first.
        let plainScale = 1 / Double(plainResponse.peak)
        let flutterScale = 1 / Double(flutterResponse.peak)
        var worst = 0.0
        for index in 0..<min(plainResponse.frameCount, flutterResponse.frameCount) {
            let a = Double(plainResponse.channels[0][index]) * plainScale
            let b = Double(flutterResponse.channels[0][index]) * flutterScale
            worst = max(worst, abs(a - b))
        }
        XCTAssertGreaterThan(worst, 0.1, "the flutter train had no measurable effect (worst \(worst))")
    }

    func testStairwellUsesFlutterAndCarCabinIsLowHeavy() {
        // The stairwell's echoes should be visible as distinct peaks well after
        // the direct sound.
        let stairwell = response("Stairwell").channels[0]
        let spacing = Int(0.045 * sampleRate)
        var echoEnergy: Float = 0
        var betweenEnergy: Float = 0
        for step in 1...8 {
            let index = spacing * step
            guard index + 2 < stairwell.count else { break }
            for offset in 0..<3 { echoEnergy += abs(stairwell[index + offset]) }
            for offset in 0..<3 { betweenEnergy += abs(stairwell[index + spacing / 2 + offset]) }
        }
        XCTAssertGreaterThan(echoEnergy, betweenEnergy * 1.5,
                             "stairwell echoes are not standing out from the tail")

        // Car cabin: the glass comb plus the low shelf make it strongly bass
        // heavy compared with its midrange.
        XCTAssertGreaterThan(level("Car Cabin", 60), level("Car Cabin", 1000) * 1.8)
    }

    func testTinCanIsModalNotDiffuse() {
        // A physical model of a shell: sparse resonances, so far more ragged than
        // any of the reverberant responses.
        XCTAssertGreaterThan(ripple("Tin Can"), 1.0)
        XCTAssertGreaterThan(ripple("Tin Can"), ripple("Large Hall") * 2)
        XCTAssertGreaterThan(ripple("Tin Can"), ripple("Cathedral") * 2)
        // Its modelled fundamental dominates its neighbours.
        XCTAssertGreaterThan(level("Tin Can", 384), level("Tin Can", 620) * 5)
    }

    func testFilterColourationsAreSmootherThanSpaces() {
        // Perception and tape curves are filters, not rooms: no comb structure.
        XCTAssertLessThan(ripple("Night Mode"), 0.2)
        XCTAssertLessThan(ripple("Cassette Tape"), 0.2)
        XCTAssertLessThan(ripple("Speech Lift"), 0.35)
    }
}
