import Accelerate
import Foundation

/// Uniform-partitioned overlap-save FFT convolution (the standard real-time
/// convolution scheme, cf. Wefers / Gardner).
///
/// The impulse response is split into `partitionCount` blocks of `blockSize`
/// samples, each transformed once into the frequency domain. Incoming audio is
/// consumed a hop at a time; every hop is transformed once and multiplied
/// against all impulse-response partitions held in a spectrum delay line.
///
/// The engine is fed and drained with equal frame counts, but input always
/// leads output within a call: `output[i]` is the convolution of `input[i]`
/// delayed by exactly `latency` samples, whatever buffer sizes the caller
/// happens to use. That determinism is what lets dry/wet mixing and offline
/// rendering line up sample for sample.
///
/// vDSP conventions verified on this machine:
///   * `vDSP_fft_zrip` round trip scales by exactly `2 * fftSize`, so a
///     transform / multiply / inverse round trip needs `1 / (4 * fftSize)`.
///   * `vDSP_zvma` is a plain `D = A*B + C` (no conjugation).
///   * The packed bin 0 holds (DC, Nyquist), so it must be multiplied
///     component-wise rather than as a complex number.
public final class PartitionedConvolver: @unchecked Sendable {
    public let blockSize: Int
    public let fftSize: Int
    public let partitionCount: Int
    /// Input-to-output delay of the block engine, in samples.
    public var latency: Int { blockSize }

    /// True when the engine is currently producing exact silence.
    public var isSilent: Bool { silentHops > partitionCount }

    private let log2N: vDSP_Length
    private let halfN: Int
    private let fftSetup: FFTSetup
    private let scale: Float

    // Impulse response spectra: partitionCount * halfN complex bins.
    private let hReal: UnsafeMutablePointer<Float>
    private let hImag: UnsafeMutablePointer<Float>
    // Spectrum delay line for the most recent hops.
    private let xReal: UnsafeMutablePointer<Float>
    private let xImag: UnsafeMutablePointer<Float>
    private var histIndex = 0

    // Scratch: sliding window, accumulator, packed real output, one hop.
    private let window: UnsafeMutablePointer<Float>
    private let accReal: UnsafeMutablePointer<Float>
    private let accImag: UnsafeMutablePointer<Float>
    private let packed: UnsafeMutablePointer<DSPComplex>
    private let hopOutput: UnsafeMutablePointer<Float>

    // Streaming state.
    private let pendingInput: UnsafeMutablePointer<Float>
    private var pendingCount = 0
    /// Consecutive hops whose input was digitally silent. Once this reaches the
    /// partition count the whole delay line is zero, so the output is provably
    /// zero and the FFT work can be skipped entirely.
    private var silentHops = 0

    /// Ring of computed output frames waiting to be emitted, capacity 4 hops.
    private let staging: UnsafeMutablePointer<Float>
    private let stagingCapacity: Int
    private let stagingMask: Int
    private var stagingRead = 0
    private var stagingWrite = 0
    private var stagingCount = 0

    public init(impulseResponse: [Float], blockSize: Int = 256) {
        precondition(blockSize >= 8 && blockSize & (blockSize - 1) == 0, "blockSize must be a power of two >= 8")
        self.blockSize = blockSize
        self.fftSize = blockSize * 2
        self.halfN = blockSize
        // vDSP wants log2 of the real-transform length (== fftSize).
        self.log2N = vDSP_Length(fftSize.trailingZeroBitCount)
        self.partitionCount = max(1, (impulseResponse.count + blockSize - 1) / blockSize)
        self.stagingCapacity = blockSize * 4
        self.stagingMask = stagingCapacity - 1
        // vDSP's real FFT scales the forward transform by 2, so a transform /
        // multiply / inverse round trip comes out `4 * fftSize` too large
        // (measured, not assumed).
        self.scale = 1 / Float(4 * fftSize)
        self.fftSetup = vDSP_create_fftsetup(log2N, FFTRadix(kFFTRadix2))!

        let n = halfN
        let k = partitionCount
        hReal = UnsafeMutablePointer<Float>.allocate(capacity: k * n)
        hImag = UnsafeMutablePointer<Float>.allocate(capacity: k * n)
        xReal = UnsafeMutablePointer<Float>.allocate(capacity: k * n)
        xImag = UnsafeMutablePointer<Float>.allocate(capacity: k * n)
        window = UnsafeMutablePointer<Float>.allocate(capacity: fftSize)
        accReal = UnsafeMutablePointer<Float>.allocate(capacity: n)
        accImag = UnsafeMutablePointer<Float>.allocate(capacity: n)
        packed = UnsafeMutablePointer<DSPComplex>.allocate(capacity: n)
        hopOutput = UnsafeMutablePointer<Float>.allocate(capacity: blockSize)
        pendingInput = UnsafeMutablePointer<Float>.allocate(capacity: blockSize)
        staging = UnsafeMutablePointer<Float>.allocate(capacity: stagingCapacity)

        hReal.initialize(repeating: 0, count: k * n)
        hImag.initialize(repeating: 0, count: k * n)
        xReal.initialize(repeating: 0, count: k * n)
        xImag.initialize(repeating: 0, count: k * n)
        window.initialize(repeating: 0, count: fftSize)
        accReal.initialize(repeating: 0, count: n)
        accImag.initialize(repeating: 0, count: n)
        hopOutput.initialize(repeating: 0, count: blockSize)
        pendingInput.initialize(repeating: 0, count: blockSize)
        staging.initialize(repeating: 0, count: stagingCapacity)

        // Transform every partition of the impulse response once.
        let scratch = UnsafeMutablePointer<Float>.allocate(capacity: fftSize)
        defer { scratch.deallocate() }
        for partition in 0..<k {
            scratch.update(repeating: 0, count: fftSize)
            let start = partition * blockSize
            let count = max(0, min(blockSize, impulseResponse.count - start))
            if count > 0 {
                impulseResponse.withUnsafeBufferPointer { source in
                    scratch.update(from: source.baseAddress! + start, count: count)
                }
            }
            var spectrum = DSPSplitComplex(realp: hReal + partition * n, imagp: hImag + partition * n)
            scratch.withMemoryRebound(to: DSPComplex.self, capacity: n) { complex in
                vDSP_ctoz(complex, 2, &spectrum, 1, vDSP_Length(n))
            }
            vDSP_fft_zrip(fftSetup, &spectrum, 1, log2N, FFTDirection(FFT_FORWARD))
        }

        reset()
    }

    deinit {
        hReal.deallocate(); hImag.deallocate()
        xReal.deallocate(); xImag.deallocate()
        window.deallocate()
        accReal.deallocate(); accImag.deallocate()
        packed.deallocate(); hopOutput.deallocate()
        pendingInput.deallocate(); staging.deallocate()
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Clears all history so the convolver can be reused for a fresh stream.
    public func reset() {
        let n = halfN * partitionCount
        xReal.update(repeating: 0, count: n)
        xImag.update(repeating: 0, count: n)
        window.update(repeating: 0, count: fftSize)
        pendingInput.update(repeating: 0, count: blockSize)
        staging.update(repeating: 0, count: stagingCapacity)
        histIndex = 0
        pendingCount = 0
        silentHops = 0
        // Prime the output with one hop of silence: this is what makes the
        // input-to-output delay exactly `latency`.
        stagingRead = 0
        stagingWrite = blockSize
        stagingCount = blockSize
    }

    /// Streaming convolution. `output` receives the fully convolved signal,
    /// delayed by exactly `latency` samples.
    public func process(input: UnsafePointer<Float>,
                        output: UnsafeMutablePointer<Float>,
                        frameCount: Int) {
        guard frameCount > 0 else { return }
        var inIndex = 0
        var outIndex = 0
        let subChunk = blockSize * 2

        while outIndex < frameCount {
            let count = min(subChunk, frameCount - outIndex)

            // Phase 1: consume this sub-chunk, running every hop it completes.
            // Consuming ahead of emitting is what keeps the delay fixed even
            // when the caller feeds buffers that are not hop aligned.
            var remainingInput = count
            while remainingInput > 0 {
                let space = blockSize - pendingCount
                let take = min(space, remainingInput)
                pendingInput.advanced(by: pendingCount).update(from: input.advanced(by: inIndex), count: take)
                pendingCount += take
                inIndex += take
                remainingInput -= take
                if pendingCount == blockSize {
                    processHop()
                    pendingCount = 0
                }
            }

            // Phase 2: emit the same number of frames.
            var remainingOutput = count
            while remainingOutput > 0 {
                let take = min(stagingCount, remainingOutput)
                if take == 0 {
                    // Not reachable while the priming hop is in place, but keep
                    // the output defined if the engine is driven oddly.
                    output.advanced(by: outIndex).update(repeating: 0, count: remainingOutput)
                    outIndex += remainingOutput
                    break
                }
                for index in 0..<take {
                    output[outIndex + index] = staging[stagingRead]
                    stagingRead = (stagingRead + 1) & stagingMask
                }
                stagingCount -= take
                remainingOutput -= take
                outIndex += take
            }
        }
    }

    private func stage(_ source: UnsafePointer<Float>, count: Int) {
        for index in 0..<count {
            staging[stagingWrite] = source[index]
            stagingWrite = (stagingWrite + 1) & stagingMask
        }
        stagingCount += count
    }

    /// Transforms one hop and stages one hop of output.
    private func processHop() {
        let n = halfN
        let slot = histIndex

        // Slide the window: [previous hop | current hop]. This happens on every
        // hop, silent or not, because the window is what gets transformed.
        memmove(window, window + blockSize, blockSize * MemoryLayout<Float>.size)
        window.advanced(by: blockSize).update(from: pendingInput, count: blockSize)

        if windowIsSilent() {
            // The spectrum of an all-zero window is exactly zero, so the forward
            // FFT can be skipped. The slot must still be cleared, because the
            // accumulate below reads the whole delay line.
            silentHops += 1
            vDSP_vclr(xReal + slot * n, 1, vDSP_Length(n))
            vDSP_vclr(xImag + slot * n, 1, vDSP_Length(n))
            if silentHops > partitionCount {
                // Every slot in the delay line has been cleared by now, so the
                // output is provably zero: skip the accumulate and inverse FFT.
                hopOutput.update(repeating: 0, count: blockSize)
                stage(hopOutput, count: blockSize)
                advanceHistory()
                return
            }
        } else {
            silentHops = 0
            // Forward transform of the current window into the delay line.
            var spectrum = DSPSplitComplex(realp: xReal + slot * n, imagp: xImag + slot * n)
            window.withMemoryRebound(to: DSPComplex.self, capacity: n) { complex in
                vDSP_ctoz(complex, 2, &spectrum, 1, vDSP_Length(n))
            }
            vDSP_fft_zrip(fftSetup, &spectrum, 1, log2N, FFTDirection(FFT_FORWARD))
        }

        // Accumulate X[t-k] * H[k] over the partition delay line.
        accReal.update(repeating: 0, count: n)
        accImag.update(repeating: 0, count: n)
        var accumulator = DSPSplitComplex(realp: accReal, imagp: accImag)
        var accumulatorTail = DSPSplitComplex(realp: accReal + 1, imagp: accImag + 1)

        for partition in 0..<partitionCount {
            var index = slot - partition
            if index < 0 { index += partitionCount }
            let x = DSPSplitComplex(realp: xReal + index * n, imagp: xImag + index * n)
            let h = DSPSplitComplex(realp: hReal + partition * n, imagp: hImag + partition * n)

            if n > 1 {
                var xTail = DSPSplitComplex(realp: x.realp + 1, imagp: x.imagp + 1)
                var hTail = DSPSplitComplex(realp: h.realp + 1, imagp: h.imagp + 1)
                vDSP_zvma(&xTail, 1, &hTail, 1, &accumulatorTail, 1, &accumulatorTail, 1, vDSP_Length(n - 1))
            }
            // Bin 0 packs (DC, Nyquist): two independent real products.
            accReal[0] += x.realp[0] * h.realp[0]
            accImag[0] += x.imagp[0] * h.imagp[0]
        }

        // Inverse transform; the second half of the result is the valid hop.
        vDSP_fft_zrip(fftSetup, &accumulator, 1, log2N, FFTDirection(FFT_INVERSE))
        vDSP_ztoc(&accumulator, 1, packed, 2, vDSP_Length(n))
        packed.withMemoryRebound(to: Float.self, capacity: fftSize) { time in
            for index in 0..<blockSize {
                hopOutput[index] = time[blockSize + index] * scale
            }
        }
        stage(hopOutput, count: blockSize)
        advanceHistory()
    }

    private func advanceHistory() {
        histIndex += 1
        if histIndex == partitionCount { histIndex = 0 }
    }

    /// Cheap O(fftSize) test that stands in for O(partitions * blockSize) of
    /// frequency-domain multiply-accumulate work when nothing is playing.
    @inline(__always)
    private func windowIsSilent() -> Bool {
        var maximum: Float = 0
        vDSP_maxmgv(window, 1, &maximum, vDSP_Length(fftSize))
        return maximum == 0
    }
}
