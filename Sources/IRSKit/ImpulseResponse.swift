import Foundation

/// A loaded impulse response.
///
/// `.irs` files are ordinary WAV files holding either a single (mono) response
/// that is applied to both channels, or a two channel response.
public struct ImpulseResponse: Sendable {
    public var name: String
    public var sampleRate: Double
    /// One channel (mono) or two channels (independent left/right responses).
    public var channels: [[Float]]
    public var sourceURL: URL?

    public init(name: String, sampleRate: Double, channels: [[Float]], sourceURL: URL? = nil) {
        self.name = name
        self.sampleRate = sampleRate
        self.channels = channels
        self.sourceURL = sourceURL
    }

    public var channelCount: Int { channels.count }
    public var frameCount: Int { channels.first?.count ?? 0 }
    public var duration: Double { sampleRate > 0 ? Double(frameCount) / sampleRate : 0 }
    public var isStereo: Bool { channels.count > 1 }

    /// Combined L2 energy across all channels.
    public var energy: Double {
        var total = 0.0
        for channel in channels {
            for sample in channel { total += Double(sample) * Double(sample) }
        }
        return total
    }

    public var peak: Float {
        var maximum: Float = 0
        for channel in channels {
            for sample in channel { maximum = max(maximum, abs(sample)) }
        }
        return maximum
    }

    public mutating func scale(by gain: Float) {
        guard gain != 1 else { return }
        for index in channels.indices {
            for sample in channels[index].indices { channels[index][sample] *= gain }
        }
    }

    /// Scales the response so that convolving a signal with it preserves that
    /// signal's energy. This keeps perceived loudness roughly constant when
    /// switching between impulse responses of very different lengths.
    @discardableResult
    public mutating func normalizeEnergy() -> Float {
        let energy = self.energy
        guard energy > 0 else { return 1 }
        let gain = Float(1.0 / energy.squareRoot())
        scale(by: gain)
        return gain
    }

    /// Truncates the response to `seconds`.
    public mutating func truncate(toSeconds seconds: Double) {
        let limit = max(1, Int(seconds * sampleRate))
        for index in channels.indices where channels[index].count > limit {
            channels[index].removeLast(channels[index].count - limit)
        }
    }
}

// MARK: - Lightweight biquad (used for synthesis and offline analysis)

public struct Biquad: Sendable {
    public var b0: Float, b1: Float, b2: Float, a1: Float, a2: Float

    public init(b0: Float, b1: Float, b2: Float, a1: Float, a2: Float) {
        self.b0 = b0; self.b1 = b1; self.b2 = b2; self.a1 = a1; self.a2 = a2
    }

    public struct State: Sendable {
        public var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
        public init() {}
        public mutating func process(_ x: Float, _ c: Biquad) -> Float {
            let y = c.b0 * x + c.b1 * x1 + c.b2 * x2 - c.a1 * y1 - c.a2 * y2
            x2 = x1; x1 = x
            y2 = y1; y1 = y
            return y
        }
    }

    private static func normalized(_ b0: Float, _ b1: Float, _ b2: Float,
                                   _ a0: Float, _ a1: Float, _ a2: Float) -> Biquad {
        Biquad(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    public static func lowPass(frequency: Double, sampleRate: Double, q: Double = 0.7071) -> Biquad {
        let w0 = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w0) / (2 * q)
        let cosw0 = cos(w0)
        return normalized(Float((1 - cosw0) / 2), Float(1 - cosw0), Float((1 - cosw0) / 2),
                          Float(1 + alpha), Float(-2 * cosw0), Float(1 - alpha))
    }

    public static func highPass(frequency: Double, sampleRate: Double, q: Double = 0.7071) -> Biquad {
        let w0 = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w0) / (2 * q)
        let cosw0 = cos(w0)
        return normalized(Float((1 + cosw0) / 2), Float(-(1 + cosw0)), Float((1 + cosw0) / 2),
                          Float(1 + alpha), Float(-2 * cosw0), Float(1 - alpha))
    }

    public static func peaking(frequency: Double, sampleRate: Double, q: Double, gainDB: Double) -> Biquad {
        let A = pow(10, gainDB / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w0) / (2 * q)
        let cosw0 = cos(w0)
        return normalized(Float(1 + alpha * A), Float(-2 * cosw0), Float(1 - alpha * A),
                          Float(1 + alpha / A), Float(-2 * cosw0), Float(1 - alpha / A))
    }

    /// Low shelf (RBJ cookbook), `slope` of 1 is the gentlest useful setting.
    public static func lowShelf(frequency: Double, sampleRate: Double, gainDB: Double, slope: Double = 1) -> Biquad {
        let A = pow(10, gainDB / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let cosw0 = cos(w0)
        let alpha = sin(w0) / 2 * ((A + 1 / A) * (1 / slope - 1) + 2).squareRoot()
        let twoSqrtAAlpha = 2 * A.squareRoot() * alpha
        return normalized(Float(A * ((A + 1) - (A - 1) * cosw0 + twoSqrtAAlpha)),
                          Float(2 * A * ((A - 1) - (A + 1) * cosw0)),
                          Float(A * ((A + 1) - (A - 1) * cosw0 - twoSqrtAAlpha)),
                          Float((A + 1) + (A - 1) * cosw0 + twoSqrtAAlpha),
                          Float(-2 * ((A - 1) + (A + 1) * cosw0)),
                          Float((A + 1) + (A - 1) * cosw0 - twoSqrtAAlpha))
    }

    /// High shelf (RBJ cookbook).
    public static func highShelf(frequency: Double, sampleRate: Double, gainDB: Double, slope: Double = 1) -> Biquad {
        let A = pow(10, gainDB / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let cosw0 = cos(w0)
        let alpha = sin(w0) / 2 * ((A + 1 / A) * (1 / slope - 1) + 2).squareRoot()
        let twoSqrtAAlpha = 2 * A.squareRoot() * alpha
        return normalized(Float(A * ((A + 1) + (A - 1) * cosw0 + twoSqrtAAlpha)),
                          Float(-2 * A * ((A - 1) + (A + 1) * cosw0)),
                          Float(A * ((A + 1) + (A - 1) * cosw0 - twoSqrtAAlpha)),
                          Float((A + 1) - (A - 1) * cosw0 + twoSqrtAAlpha),
                          Float(2 * ((A - 1) - (A + 1) * cosw0)),
                          Float((A + 1) - (A - 1) * cosw0 - twoSqrtAAlpha))
    }

    /// Impulse response of a cascade of biquads, computed by feeding a unit impulse.
    public static func impulseResponse(of chain: [Biquad], length: Int, sampleRate: Double) -> [Float] {
        var states = [State](repeating: State(), count: chain.count)
        var output = [Float](repeating: 0, count: length)
        for index in 0..<length {
            var value: Float = index == 0 ? 1 : 0
            for stage in chain.indices {
                value = states[stage].process(value, chain[stage])
            }
            output[index] = value
        }
        _ = sampleRate
        return output
    }
}

// MARK: - Deterministic noise

/// Small deterministic PRNG so synthesized impulse responses are reproducible.
public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [-1, 1).
    public mutating func uniform() -> Float {
        Float(Double(next() >> 11) / Double(1 << 53)) * 2 - 1
    }

    /// Approximately gaussian via the central limit theorem.
    public mutating func gaussian() -> Float {
        var sum: Float = 0
        for _ in 0..<6 { sum += uniform() }
        return sum / 6 * 1.7320508
    }
}
