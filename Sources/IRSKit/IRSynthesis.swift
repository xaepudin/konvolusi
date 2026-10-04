import Foundation

/// A train of discrete echoes on top of the diffuse tail - stairwells, tunnels,
/// parallel walls, car glass.
public struct FlutterEcho: Sendable {
    public var spacing: Double        // seconds between echoes
    public var count: Int
    public var decay: Double          // seconds to -60 dB across the train
    public var amplitude: Float
    public var alternatingPolarity: Bool

    public init(spacing: Double, count: Int, decay: Double,
                amplitude: Float = 0.4, alternatingPolarity: Bool = true) {
        self.spacing = spacing
        self.count = count
        self.decay = decay
        self.amplitude = amplitude
        self.alternatingPolarity = alternatingPolarity
    }
}

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
    public var flutter: FlutterEcho?

    public init() {}
}

/// One damped resonance of a struck or excited object.
public struct ResonantMode: Sendable {
    public var frequency: Double
    public var t60: Double
    public var amplitude: Float
    public var phase: Double          // in turns, 0..1

    public init(frequency: Double, t60: Double, amplitude: Float, phase: Double = 0) {
        self.frequency = frequency
        self.t60 = t60
        self.amplitude = amplitude
        self.phase = phase
    }
}

/// Synthesizes impulse responses, so the library needs no downloads and can
/// contain things that do not exist as recordings: perceptual compensation
/// curves, device feels and physical models.
public enum IRSynthesis {
    /// ln(1000): a 60 dB decay corresponds to an amplitude factor of 1/1000.
    private static let sixtyDecibels = 6.907755278982137

    // MARK: - Generators

    /// Decorrelated stereo reverb: exponentially decaying, progressively darker
    /// noise plus a sparse early reflection pattern and optional flutter echoes.
    public static func reverb(name: String,
                              sampleRate: Double = 44100,
                              parameters: ReverbParameters = ReverbParameters()) -> ImpulseResponse {
        let frames = max(1, Int(parameters.duration * sampleRate))
        let predelayFrames = max(0, min(Int(parameters.predelay * sampleRate), frames - 1))
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

            // Flutter: a regular train of echoes from parallel surfaces.
            if let flutter = parameters.flutter, flutter.count > 0 {
                for step in 1...flutter.count {
                    let delay = flutter.spacing * Double(step)
                    let index = Int((delay + parameters.predelay) * sampleRate)
                    guard index > 0, index < frames else { break }
                    let envelope = exp(-delay / max(0.0005, flutter.decay))
                    let sign: Float = flutter.alternatingPolarity && step % 2 == 1 ? -1 : 1
                    channel[index] += flutter.amplitude * Float(envelope) * sign
                }
            }
            channels.append(channel)
        }

        var response = ImpulseResponse(name: name, sampleRate: sampleRate, channels: channels)
        response.normalizeEnergy()
        return response
    }

    /// Impulse response of a cascade of biquads - speaker, tape and perception
    /// colouration.
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

    /// Runs an existing response through a filter chain. Filtering and convolution
    /// are both linear, so shaping the response is the same as shaping the result.
    public static func filtered(_ response: ImpulseResponse, chain: [Biquad]) -> ImpulseResponse {
        var states = [[Biquad.State]](repeating: [Biquad.State](repeating: Biquad.State(), count: chain.count),
                                      count: response.channelCount)
        var output = response
        for channel in output.channels.indices {
            for index in output.channels[channel].indices {
                var value = output.channels[channel][index]
                for stage in chain.indices {
                    value = states[channel][stage].process(value, chain[stage])
                }
                output.channels[channel][index] = value
            }
        }
        if output.energy > 0 { output.normalizeEnergy() }
        return output
    }

    /// A bank of damped resonances: the impulse response of a physical object
    /// (a can, a cabinet, a tube) rather than a space.
    public static func modal(name: String,
                             sampleRate: Double = 44100,
                             modes: [ResonantMode],
                             duration: Double,
                             noiseTail: (level: Float, decay: Double, cutoff: Double)? = nil) -> ImpulseResponse {
        let frames = max(1, Int(duration * sampleRate))
        var samples = [Float](repeating: 0, count: frames)

        for mode in modes {
            let decayRate = sixtyDecibels / max(0.0005, mode.t60)
            let phase = mode.phase * 2 * Double.pi
            let angular = 2 * Double.pi * mode.frequency
            for index in 0..<frames {
                let time = Double(index) / sampleRate
                let envelope = exp(-decayRate * time)
                if envelope < 1e-7 { break }
                samples[index] += mode.amplitude * Float(envelope * sin(angular * time + phase))
            }
        }

        if let noiseTail {
            var generator = SplitMix64(seed: 0x7111_C0FFEE)
            var state: Float = 0
            let coefficient = Float(1 - exp(-2 * Double.pi * noiseTail.cutoff / sampleRate))
            let decayRate = sixtyDecibels / max(0.0005, noiseTail.decay)
            for index in 0..<frames {
                let time = Double(index) / sampleRate
                state += coefficient * (generator.gaussian() - state)
                samples[index] += state * noiseTail.level * Float(exp(-decayRate * time))
            }
        }

        var response = ImpulseResponse(name: name, sampleRate: sampleRate, channels: [samples])
        if response.energy > 0 { response.normalizeEnergy() }
        return response
    }

    /// The control case: convolving with this changes nothing, which makes it the
    /// way to prove the effect is off (or to check the engine while debugging).
    public static func identity(sampleRate: Double = 44100) -> ImpulseResponse {
        ImpulseResponse(name: "Identity (control)", sampleRate: sampleRate, channels: [[1]])
    }

    // MARK: - The built-in library

    /// A deliberately small, purpose-chosen set rather than a pile of downloads.
    ///
    /// Grouped by what they are for: a control, two perceptual compensations that
    /// do not exist as recordings, three everyday spaces, the Viper4Android style
    /// character pieces, big spaces, and one physical model for fun.
    public static func builtInLibrary(sampleRate: Double = 44100) -> [ImpulseResponse] {
        var library: [ImpulseResponse] = []

        // --- Control -------------------------------------------------------
        library.append(identity(sampleRate: sampleRate))

        // --- Perceptual compensation (impossible to download) --------------
        // Clarity for speech on laptop speakers: kill the rumble and the boxy
        // low-mid, lift the consonant band.
        library.append(filterChain(name: "Speech Lift", chain: [
            Biquad.highPass(frequency: 110, sampleRate: sampleRate, q: 0.7),
            Biquad.highPass(frequency: 80, sampleRate: sampleRate, q: 0.8),
            Biquad.peaking(frequency: 260, sampleRate: sampleRate, q: 1.4, gainDB: -3.5),
            Biquad.peaking(frequency: 3000, sampleRate: sampleRate, q: 1.1, gainDB: 5),
            Biquad.peaking(frequency: 5500, sampleRate: sampleRate, q: 1.5, gainDB: 2.5),
            Biquad.lowPass(frequency: 13000, sampleRate: sampleRate, q: 0.7),
        ], sampleRate: sampleRate, duration: 0.16))

        // Equal-loudness compensation: at low volume the ear loses bass and
        // treble first, so put them back and clear a little space in the middle.
        library.append(filterChain(name: "Night Mode", chain: [
            Biquad.lowShelf(frequency: 120, sampleRate: sampleRate, gainDB: 7),
            Biquad.peaking(frequency: 2600, sampleRate: sampleRate, q: 1.0, gainDB: -2),
            Biquad.highShelf(frequency: 7000, sampleRate: sampleRate, gainDB: 4),
            Biquad.lowPass(frequency: 16000, sampleRate: sampleRate, q: 0.7),
        ], sampleRate: sampleRate, duration: 0.16))

        // --- Everyday spaces (subtle, for daily listening) -----------------
        var studio = ReverbParameters()
        studio.duration = 0.42
        studio.t60 = 0.34
        studio.predelay = 0.003
        studio.initialCutoff = 11000
        studio.finalCutoff = 3000
        studio.cutoffDecay = 0.16
        studio.earlyReflectionCount = 16
        studio.directLevel = 0.5
        studio.seed = 0x5D10_0001
        library.append(reverb(name: "Studio Room", sampleRate: sampleRate, parameters: studio))

        var desk = ReverbParameters()
        desk.duration = 0.24
        desk.t60 = 0.16
        desk.predelay = 0.002
        desk.initialCutoff = 6000
        desk.finalCutoff = 1200
        desk.cutoffDecay = 0.1
        desk.earlyReflectionCount = 10
        desk.directLevel = 0.72
        desk.seed = 0x5D10_0002
        library.append(reverb(name: "Warm Desk", sampleRate: sampleRate, parameters: desk))

        // A plate: no discrete early reflections, dense and bright from the first
        // millisecond, and it stays bright as it decays.
        var plate = ReverbParameters()
        plate.duration = 1.35
        plate.t60 = 1.1
        plate.predelay = 0.0005
        plate.attack = 0.001
        plate.initialCutoff = 14000
        plate.finalCutoff = 7500
        plate.cutoffDecay = 1.5
        plate.earlyReflectionCount = 0
        plate.directLevel = 0.06
        plate.seed = 0x5D10_0003
        library.append(reverb(name: "Plate", sampleRate: sampleRate, parameters: plate))

        // --- Character pieces ---------------------------------------------
        library.append(filterChain(name: "Old Radio Speaker", chain: [
            Biquad.highPass(frequency: 330, sampleRate: sampleRate, q: 0.6),
            Biquad.highPass(frequency: 200, sampleRate: sampleRate, q: 0.9),
            Biquad.peaking(frequency: 900, sampleRate: sampleRate, q: 2.0, gainDB: -5),
            Biquad.peaking(frequency: 1250, sampleRate: sampleRate, q: 1.6, gainDB: 7),
            Biquad.peaking(frequency: 2600, sampleRate: sampleRate, q: 2.8, gainDB: 5),
            Biquad.lowPass(frequency: 4300, sampleRate: sampleRate, q: 0.8),
            Biquad.lowPass(frequency: 6200, sampleRate: sampleRate, q: 0.6),
        ], sampleRate: sampleRate, duration: 0.18))

        library.append(filterChain(name: "Telephone", chain: [
            Biquad.highPass(frequency: 420, sampleRate: sampleRate, q: 0.8),
            Biquad.highPass(frequency: 300, sampleRate: sampleRate, q: 1.0),
            Biquad.peaking(frequency: 1800, sampleRate: sampleRate, q: 1.4, gainDB: 8),
            Biquad.peaking(frequency: 3100, sampleRate: sampleRate, q: 1.2, gainDB: 6),
            Biquad.lowPass(frequency: 3400, sampleRate: sampleRate, q: 0.9),
            Biquad.lowPass(frequency: 3800, sampleRate: sampleRate, q: 0.7),
        ], sampleRate: sampleRate, duration: 0.12))

        // Tape: head bump in the bass, a dull top end, a little midrange push.
        library.append(filterChain(name: "Cassette Tape", chain: [
            Biquad.highPass(frequency: 35, sampleRate: sampleRate, q: 0.7),
            Biquad.lowShelf(frequency: 90, sampleRate: sampleRate, gainDB: 4),
            Biquad.peaking(frequency: 350, sampleRate: sampleRate, q: 1.0, gainDB: -2.5),
            Biquad.peaking(frequency: 2500, sampleRate: sampleRate, q: 1.2, gainDB: 2),
            Biquad.lowPass(frequency: 7500, sampleRate: sampleRate, q: 0.7),
            Biquad.lowPass(frequency: 10000, sampleRate: sampleRate, q: 0.6),
        ], sampleRate: sampleRate, duration: 0.12))

        // Car cabin: strong comb colouration from the glass plus a low-mid boom.
        var cabin = ReverbParameters()
        cabin.duration = 0.22
        cabin.t60 = 0.15
        cabin.predelay = 0.0015
        cabin.initialCutoff = 7000
        cabin.finalCutoff = 1800
        cabin.cutoffDecay = 0.08
        cabin.earlyReflectionCount = 8
        cabin.directLevel = 0.7
        cabin.seed = 0x5D10_0004
        cabin.flutter = FlutterEcho(spacing: 0.0014, count: 14, decay: 0.006,
                                   amplitude: 0.5, alternatingPolarity: true)
        library.append(filtered(reverb(name: "Car Cabin", sampleRate: sampleRate, parameters: cabin), chain: [
            Biquad.lowShelf(frequency: 120, sampleRate: sampleRate, gainDB: 4),
            Biquad.peaking(frequency: 250, sampleRate: sampleRate, q: 1.2, gainDB: -3),
        ]))

        // Stairwell: a long train of discrete echoes that gives the metallic
        // flutter every hard-surfaced stairwell has.
        var stairwell = ReverbParameters()
        stairwell.duration = 1.7
        stairwell.t60 = 1.35
        stairwell.predelay = 0.012
        stairwell.initialCutoff = 8000
        stairwell.finalCutoff = 2600
        stairwell.cutoffDecay = 0.5
        stairwell.earlyReflectionCount = 6
        stairwell.directLevel = 0.5
        stairwell.seed = 0x5D10_0005
        stairwell.flutter = FlutterEcho(spacing: 0.045, count: 26, decay: 0.5,
                                        amplitude: 0.4, alternatingPolarity: true)
        library.append(filtered(reverb(name: "Stairwell", sampleRate: sampleRate, parameters: stairwell), chain: [
            Biquad.peaking(frequency: 420, sampleRate: sampleRate, q: 1.1, gainDB: 3),
            Biquad.peaking(frequency: 1400, sampleRate: sampleRate, q: 1.4, gainDB: 2),
        ]))

        // --- Big spaces (impressive, use sparingly) ------------------------
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
        library.append(reverb(name: "Small Room", sampleRate: sampleRate, parameters: room))

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
        library.append(reverb(name: "Large Hall", sampleRate: sampleRate, parameters: hall))

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
        library.append(reverb(name: "Cathedral", sampleRate: sampleRate, parameters: cathedral))

        // --- Physical model (the odd one out) ------------------------------
        // Inharmonic modes of a thin metal shell plus a short bright rattle.
        library.append(modal(name: "Tin Can", sampleRate: sampleRate, modes: [
            ResonantMode(frequency: 384, t60: 0.16, amplitude: 1.0, phase: 0.0),
            ResonantMode(frequency: 831, t60: 0.12, amplitude: 0.72, phase: 0.21),
            ResonantMode(frequency: 1247, t60: 0.09, amplitude: 0.55, phase: 0.44),
            ResonantMode(frequency: 1893, t60: 0.07, amplitude: 0.4, phase: 0.13),
            ResonantMode(frequency: 2477, t60: 0.055, amplitude: 0.3, phase: 0.67),
            ResonantMode(frequency: 3313, t60: 0.04, amplitude: 0.22, phase: 0.32),
            ResonantMode(frequency: 4192, t60: 0.03, amplitude: 0.16, phase: 0.81),
        ], duration: 0.3, noiseTail: (level: 0.06, decay: 0.03, cutoff: 9000)))

        return library
    }

    /// Generates the built-in library on disk (16-bit PCM WAV files with an
    /// `.irs` extension, matching what Viper4Android ships).
    @discardableResult
    public static func writeDemoFiles(to directory: URL, sampleRate: Double = 44100) throws -> [URL] {
        var urls: [URL] = []
        for response in builtInLibrary(sampleRate: sampleRate) {
            let url = directory.appendingPathComponent("\(response.name).irs")
            try IRFile.write(response, to: url)
            urls.append(url)
        }
        return urls
    }
}
