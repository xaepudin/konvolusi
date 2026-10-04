import Foundation

/// Parameters for a synthetic reverberant impulse response.
public struct ReverbParameters: Sendable {
    public var duration: Double = 2.6
    public var t60: Double = 1.9
    public var predelay: Double = 0.012
    public var attack: Double = 0.004
    public var initialCutoff: Double = 9000
    public var cutoffDecay: Double = 0.9
    public var finalCutoff: Double = 2200
    public var earlyReflectionCount: Int = 22
    public var directLevel: Float = 0.6
    public var seed: UInt64 = 0x5EED_1234

    public init() {}
}

/// Synthesizes impulse responses so the app (and the tests) have believable
/// material to work with before the user drops in their own Viper4Android files.
public enum IRSynthesis {
    /// ln(1000): a 60 dB decay corresponds to an amplitude factor of 1/1000.
    private static let sixtyDecibels = 6.907755278982137

    /// Decorrelated stereo reverb: exponentially decaying, progressively darker
    /// noise plus a sparse early reflection pattern.
    public static func reverb(name: String,
                              sampleRate: Double = 44100,
                              parameters: ReverbParameters = ReverbParameters()) -> ImpulseResponse {
        let frames = max(1, Int(parameters.duration * sampleRate))
        let predelayFrames = max(0, min(Int(parameters.predelay * sampleRate), frames - 1))
        // Time for the tail to fall by 60 dB -> exponential amplitude decay rate.
        let decayConstant = sixtyDecibels / max(0.001, parameters.t60)

        var generator = SplitMix64(seed: parameters.seed)
        var channels: [[Float]] = []

        for _ in 0..<2 {
            var tail = [Float](repeating: 0, count: frames)
            for index in 0..<frames { tail[index] = generator.gaussian() }

            // One-pole low pass whose cutoff falls as the tail decays: halls lose
            // high frequencies much faster than low ones.
            var state: Float = 0
            for index in 0..<frames {
                let time = Double(index) / sampleRate
                let cutoff = parameters.finalCutoff
                    + (parameters.initialCutoff - parameters.finalCutoff) * exp(-time / parameters.cutoffDecay)
                let coefficient = Float(1 - exp(-2 * Double.pi * cutoff / sampleRate))
                state += coefficient * (tail[index] - state)
                tail[index] = state
            }

            for index in 0..<frames {
                let time = Double(index) / sampleRate
                let decay = exp(-decayConstant * time)
                let attack = min(1.0, time / max(0.0001, parameters.attack))
                tail[index] *= Float(decay * attack)
            }

            var channel = [Float](repeating: 0, count: frames)
            channel[0] += parameters.directLevel
            let usable = max(0, frames - predelayFrames)
            for index in 0..<min(tail.count, usable) {
                channel[index + predelayFrames] += tail[index]
            }

            // Early reflections: discrete echoes arriving before the diffuse tail.
            for _ in 0..<parameters.earlyReflectionCount {
                let delay = 0.006 + Double(generator.uniform() * 0.5 + 0.5) * 0.075 + parameters.predelay
                let index = Int(delay * sampleRate)
                guard index > 0, index < frames else { continue }
                let sign: Float = generator.uniform() < 0 ? -1 : 1
                let amplitude = Float(exp(-delay / 0.12)) * 0.45 * sign
                channel[index] += amplitude
            }
            channels.append(channel)
        }

        var response = ImpulseResponse(name: name, sampleRate: sampleRate, channels: channels)
        response.normalizeEnergy()
        return response
    }

    /// Impulse response of a cascade of biquads - used for speaker / radio coloration.
    public static func filterChain(name: String,
                                   chain: [Biquad],
                                   sampleRate: Double = 44100,
                                   duration: Double = 0.2) -> ImpulseResponse {
        let length = max(16, Int(duration * sampleRate))
        let samples = Biquad.impulseResponse(of: chain, length: length, sampleRate: sampleRate)
        var response = ImpulseResponse(name: name, sampleRate: sampleRate, channels: [samples])
        if response.energy > 0 { response.normalizeEnergy() }
        return response
    }

    /// The built-in demo set, ordered from largest space to smallest.
    public static func demoResponses(sampleRate: Double = 44100) -> [ImpulseResponse] {
        var cathedral = ReverbParameters()
        cathedral.duration = 4.4
        cathedral.t60 = 3.4
        cathedral.predelay = 0.028
        cathedral.initialCutoff = 6000
        cathedral.finalCutoff = 1400
        cathedral.cutoffDecay = 1.6
        cathedral.earlyReflectionCount = 14
        cathedral.directLevel = 0.4
        cathedral.seed = 0xCA7ED_1A1

        var hall = ReverbParameters()
        hall.duration = 2.6
        hall.t60 = 1.9
        hall.predelay = 0.014
        hall.initialCutoff = 9000
        hall.finalCutoff = 2200
        hall.cutoffDecay = 0.9
        hall.earlyReflectionCount = 22
        hall.directLevel = 0.62
        hall.seed = 0x5EED_1234

        var room = ReverbParameters()
        room.duration = 0.7
        room.t60 = 0.45
        room.predelay = 0.004
        room.initialCutoff = 12000
        room.finalCutoff = 3500
        room.cutoffDecay = 0.28
        room.earlyReflectionCount = 12
        room.directLevel = 0.8
        room.seed = 0x5107_2B0C

        let radio = filterChain(name: "Old Radio Speaker",
                                chain: [
                                    Biquad.highPass(frequency: 330, sampleRate: sampleRate, q: 0.6),
                                    Biquad.highPass(frequency: 200, sampleRate: sampleRate, q: 0.9),
                                    Biquad.peaking(frequency: 900, sampleRate: sampleRate, q: 2.0, gainDB: -5),
                                    Biquad.peaking(frequency: 1250, sampleRate: sampleRate, q: 1.6, gainDB: 7),
                                    Biquad.peaking(frequency: 2600, sampleRate: sampleRate, q: 2.8, gainDB: 5),
                                    Biquad.lowPass(frequency: 4300, sampleRate: sampleRate, q: 0.8),
                                    Biquad.lowPass(frequency: 6200, sampleRate: sampleRate, q: 0.6),
                                ],
                                sampleRate: sampleRate,
                                duration: 0.18)

        let telephone = filterChain(name: "Telephone",
                                    chain: [
                                        Biquad.highPass(frequency: 420, sampleRate: sampleRate, q: 0.8),
                                        Biquad.highPass(frequency: 300, sampleRate: sampleRate, q: 1.0),
                                        Biquad.peaking(frequency: 1800, sampleRate: sampleRate, q: 1.4, gainDB: 8),
                                        Biquad.peaking(frequency: 3100, sampleRate: sampleRate, q: 1.2, gainDB: 6),
                                        Biquad.lowPass(frequency: 3400, sampleRate: sampleRate, q: 0.9),
                                        Biquad.lowPass(frequency: 3800, sampleRate: sampleRate, q: 0.7),
                                    ],
                                    sampleRate: sampleRate,
                                    duration: 0.12)

        return [
            reverb(name: "Cathedral", sampleRate: sampleRate, parameters: cathedral),
            reverb(name: "Large Hall", sampleRate: sampleRate, parameters: hall),
            reverb(name: "Small Room", sampleRate: sampleRate, parameters: room),
            radio,
            telephone,
        ]
    }

    /// Generates the demo set on disk (16-bit PCM `44.1 kHz` WAV files with an
    /// `.irs` extension, matching what Viper4Android ships).
    @discardableResult
    public static func writeDemoFiles(to directory: URL, sampleRate: Double = 44100) throws -> [URL] {
        var urls: [URL] = []
        for response in demoResponses(sampleRate: sampleRate) {
            let url = directory.appendingPathComponent("\(response.name).irs")
            try IRFile.write(response, to: url)
            urls.append(url)
        }
        return urls
    }
}
