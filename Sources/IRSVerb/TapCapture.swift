import Accelerate
import CoreAudio
import Foundation
import IRSKit

/// Reads the tapped audio on Core Audio's IO thread and pushes it into the ring
/// buffer that the output unit drains.
///
/// Nothing here allocates, locks or logs: this runs on the real-time IO thread.
final class TapCapture: @unchecked Sendable {
    let deviceID: AudioObjectID
    let format: AudioStreamBasicDescription

    private let ring: AudioRingBuffer
    private let level: AtomicLevel
    private let frameCounter: AtomicLevel
    private let maxCallbackFrames: AtomicLevel
    private var ioProcID: AudioDeviceIOProcID?

    private let scratchCapacity = 16_384
    private let scratchLeft: UnsafeMutablePointer<Float>
    private let scratchRight: UnsafeMutablePointer<Float>

    private let isFloat: Bool
    private let isInterleaved: Bool
    private let isSignedInteger: Bool
    private let isBigEndian: Bool
    private let bytesPerSample: Int
    private let channels: Int

    init(deviceID: AudioObjectID, format: AudioStreamBasicDescription, ring: AudioRingBuffer,
         level: AtomicLevel, frameCounter: AtomicLevel, maxCallbackFrames: AtomicLevel) {
        self.deviceID = deviceID
        self.format = format
        self.ring = ring
        self.level = level
        self.frameCounter = frameCounter
        self.maxCallbackFrames = maxCallbackFrames
        self.isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        self.isInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        self.isSignedInteger = format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0
        self.isBigEndian = format.mFormatFlags & kAudioFormatFlagIsBigEndian != 0
        self.bytesPerSample = max(1, Int(format.mBitsPerChannel) / 8)
        self.channels = max(1, Int(format.mChannelsPerFrame))
        scratchLeft = UnsafeMutablePointer<Float>.allocate(capacity: scratchCapacity)
        scratchRight = UnsafeMutablePointer<Float>.allocate(capacity: scratchCapacity)
        scratchLeft.initialize(repeating: 0, count: scratchCapacity)
        scratchRight.initialize(repeating: 0, count: scratchCapacity)
    }

    deinit {
        stop()
        scratchLeft.deallocate()
        scratchRight.deallocate()
    }

    func start() throws {
        guard ioProcID == nil else { return }
        var created: AudioDeviceIOProcID?
        // The IO block has no client-data parameter, so pass the reference
        // through a raw pointer to keep ARC traffic off the IO thread.
        let reference = Unmanaged.passUnretained(self).toOpaque()
        let status = AudioDeviceCreateIOProcIDWithBlock(&created, deviceID, nil) { _, inputData, _, _, _ in
            let capture = Unmanaged<TapCapture>.fromOpaque(reference).takeUnretainedValue()
            capture.receive(inputData)
        }
        guard status == noErr, let created else {
            throw AudioTapError.aggregateCreation(status)
        }
        ioProcID = created
        let startStatus = AudioDeviceStart(deviceID, created)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(deviceID, created)
            ioProcID = nil
            throw AudioTapError.aggregateCreation(startStatus)
        }
    }

    func stop() {
        guard let ioProcID else { return }
        AudioDeviceStop(deviceID, ioProcID)
        AudioDeviceDestroyIOProcID(deviceID, ioProcID)
        self.ioProcID = nil
    }

    // MARK: - IO thread

    private func receive(_ inputData: UnsafePointer<AudioBufferList>) {
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        guard list.count > 0 else { return }
        let bytesPerFrame = Int(format.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return }
        let frames = min(Int(list[0].mDataByteSize) / bytesPerFrame, scratchCapacity)
        guard frames > 0 else { return }

        var sourceLeft: UnsafePointer<Float>
        var sourceRight: UnsafePointer<Float>

        if isFloat && !isInterleaved && bytesPerSample == 4 {
            // The common case: planar float, one buffer per channel.
            guard let left = list[0].mData?.assumingMemoryBound(to: Float.self) else { return }
            sourceLeft = UnsafePointer(left)
            if list.count > 1, let right = list[1].mData?.assumingMemoryBound(to: Float.self) {
                sourceRight = UnsafePointer(right)
            } else {
                sourceRight = sourceLeft
            }
        } else {
            guard deinterleave(list, frames: frames) else { return }
            sourceLeft = UnsafePointer(scratchLeft)
            sourceRight = UnsafePointer(scratchRight)
        }

        ring.write(left: sourceLeft, right: sourceRight, count: frames)
        frameCounter.store(frameCounter.load() + Float(frames))
        maxCallbackFrames.storeMaximum(Float(frames))

        var rms: Float = 0
        vDSP_rmsqv(sourceLeft, 1, &rms, vDSP_Length(frames))
        level.store(rms)
    }

    /// Converts any other layout (interleaved float, double, integer) into the
    /// planar float scratch buffers. Tap streams are normally planar float32, so
    /// this is a safety net rather than the hot path.
    private func deinterleave(_ list: UnsafeMutableAudioBufferListPointer, frames: Int) -> Bool {
        if isInterleaved {
            guard let raw = list[0].mData else { return false }
            for frame in 0..<frames {
                let base = frame * channels
                scratchLeft[frame] = sample(raw, index: base)
                scratchRight[frame] = channels > 1 ? sample(raw, index: base + 1) : scratchLeft[frame]
            }
        } else {
            for channel in 0..<min(list.count, 2) {
                guard let raw = list[channel].mData else { continue }
                let destination = channel == 0 ? scratchLeft : scratchRight
                for frame in 0..<frames { destination[frame] = sample(raw, index: frame) }
            }
            if list.count == 1 {
                memcpy(scratchRight, scratchLeft, frames * MemoryLayout<Float>.size)
            }
        }
        return true
    }

    @inline(__always)
    private func sample(_ raw: UnsafeMutableRawPointer, index: Int) -> Float {
        if isFloat {
            if bytesPerSample == 4 {
                return raw.assumingMemoryBound(to: Float.self)[index]
            } else if bytesPerSample == 8 {
                return Float(raw.assumingMemoryBound(to: Double.self)[index])
            }
            return 0
        }
        if bytesPerSample == 2 {
            let value = raw.assumingMemoryBound(to: Int16.self)[index]
            let normalized = isBigEndian ? Int16(bigEndian: value) : value
            return isSignedInteger ? Float(normalized) / 32_768 : Float(UInt16(bitPattern: normalized)) / 32_768
        }
        if bytesPerSample == 4 {
            let value = raw.assumingMemoryBound(to: Int32.self)[index]
            let normalized = isBigEndian ? Int32(bigEndian: value) : value
            return isSignedInteger ? Float(normalized) / 2_147_483_648 : Float(UInt32(bitPattern: normalized)) / 2_147_483_648
        }
        return 0
    }
}
