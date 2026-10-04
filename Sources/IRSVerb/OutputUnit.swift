import AudioToolbox
import CoreAudio
import Foundation
import IRSKit

/// Core Audio render callback for IRSVerb's output unit. Kept as a file-scope
/// constant so it is a plain C function pointer with no captured context.
private let irsVerbRenderCallback: AURenderCallback = { refCon, _, _, _, frameCount, ioData in
    guard let ioData else { return noErr }
    let engine = Unmanaged<AudioEngine>.fromOpaque(refCon).takeUnretainedValue()
    return engine.renderOutput(frameCount: Int(frameCount), ioData: ioData)
}

/// The default output audio unit. Its client format matches the tap's, so Core
/// Audio performs any hardware sample-rate conversion for us.
final class OutputUnit {
    private(set) var audioUnit: AudioUnit?
    let sampleRate: Double

    init(engine: AudioEngine, sampleRate: Double) throws {
        self.sampleRate = sampleRate

        var description = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                                    componentSubType: kAudioUnitSubType_DefaultOutput,
                                                    componentManufacturer: kAudioUnitManufacturer_Apple,
                                                    componentFlags: 0,
                                                    componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw AudioTapError.formatUnavailable
        }
        var unit: AudioUnit?
        guard AudioComponentInstanceNew(component, &unit) == noErr, let unit else {
            throw AudioTapError.formatUnavailable
        }
        audioUnit = unit
        do {
            try configure(unit, engine: engine)
        } catch {
            AudioComponentInstanceDispose(unit)
            audioUnit = nil
            throw error
        }
    }

    deinit {
        stop()
    }

    private func configure(_ unit: AudioUnit, engine: AudioEngine) throws {
        var format = AudioStreamBasicDescription()
        format.mSampleRate = sampleRate
        format.mFormatID = kAudioFormatLinearPCM
        format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved
        format.mBytesPerPacket = 4
        format.mFramesPerPacket = 1
        format.mBytesPerFrame = 4
        format.mChannelsPerFrame = 2
        format.mBitsPerChannel = 32
        format.mReserved = 0

        // Non-interleaved stereo is what makes the render callback simple: one
        // buffer per channel.
        var mutableFormat = format
        var status = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
                                          kAudioUnitScope_Input, 0, &mutableFormat,
                                          UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard status == noErr else { throw AudioTapError.formatUnavailable }

        var callback = AURenderCallbackStruct(inputProc: irsVerbRenderCallback,
                                              inputProcRefCon: Unmanaged.passUnretained(engine).toOpaque())
        status = AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback,
                                      kAudioUnitScope_Input, 0, &callback,
                                      UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        guard status == noErr else { throw AudioTapError.formatUnavailable }

        status = AudioUnitInitialize(unit)
        guard status == noErr else { throw AudioTapError.formatUnavailable }
    }

    func start() throws {
        guard let unit = audioUnit else { throw AudioTapError.formatUnavailable }
        let status = AudioOutputUnitStart(unit)
        guard status == noErr else { throw AudioTapError.aggregateCreation(status) }
    }

    func stop() {
        guard let unit = audioUnit else { return }
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        audioUnit = nil
    }
}
