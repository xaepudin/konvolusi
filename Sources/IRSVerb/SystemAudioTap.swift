import CoreAudio
import Foundation

enum AudioTapError: LocalizedError {
    case processObjectUnavailable
    case tapCreation(OSStatus)
    case missingTapUID
    case aggregateCreation(OSStatus)
    case formatUnavailable

    var errorDescription: String? {
        switch self {
        case .processObjectUnavailable:
            return "Could not find this application's audio process object."
        case .tapCreation(let status):
            return "Could not tap system audio (OSStatus \(status)). IRSVerb needs permission in "
                + "System Settings › Privacy & Security › Screen & System Audio Recording."
        case .missingTapUID:
            return "The system audio tap did not report a UID."
        case .aggregateCreation(let status):
            return "Could not create the capture device (OSStatus \(status))."
        case .formatUnavailable:
            return "The capture device did not report a usable audio format."
        }
    }
}

/// A Core Audio process tap, plus the private aggregate device that makes it
/// readable.
///
/// This is the macOS 14.2+ kext-free way to capture every *other* process'
/// audio, and with
/// `muteBehavior = .mutedWhenTapped` it is muted at the hardware for exactly as
/// long as this process is reading the tap. IRSVerb then plays the convolved
/// result back out, so the system hears only the processed signal.
final class SystemAudioTap {
    private(set) var tapID: AudioObjectID = kAudioObjectUnknown
    private(set) var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private(set) var tapUID: String = ""
    private(set) var streamFormat = AudioStreamBasicDescription()

    let displayName: String

    var sampleRate: Double { streamFormat.mSampleRate }
    var channelCount: Int { Int(streamFormat.mChannelsPerFrame) }

    init(displayName: String = "IRSVerb") throws {
        self.displayName = displayName

        let processObject = try Self.currentProcessObject()
        // NS_REFINED_FOR_SWIFT gives the Swift overlay an [AudioObjectID] array.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [processObject])
        description.name = displayName
        description.isPrivate = true
        // The tapped audio is muted at the hardware while we read it, which is
        // what lets us replace the system output with the convolved signal.
        description.muteBehavior = CATapMuteBehavior.mutedWhenTapped

        var createdTap: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(description, &createdTap)
        guard tapStatus == noErr else { throw AudioTapError.tapCreation(tapStatus) }
        tapID = createdTap

        guard let uid = caGetString(tapID, kAudioTapPropertyUID) else {
            destroy()
            throw AudioTapError.missingTapUID
        }
        tapUID = uid

        let dictionary: [String: Any] = [
            kAudioAggregateDeviceUIDKey: "io.github.xaepudin.IRSVerb.capture.\(UUID().uuidString)",
            kAudioAggregateDeviceNameKey: "\(displayName) Capture",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: uid,
                    // A single tap needs no drift compensation against itself.
                    kAudioSubTapDriftCompensationKey: false,
                ]
            ],
        ]

        var aggregate: AudioObjectID = kAudioObjectUnknown
        let aggregateStatus = AudioHardwareCreateAggregateDevice(dictionary as CFDictionary, &aggregate)
        guard aggregateStatus == noErr else {
            destroy()
            throw AudioTapError.aggregateCreation(aggregateStatus)
        }
        aggregateDeviceID = aggregate

        // Ask for a small capture buffer to keep the added latency low; failure
        // is fine, the device then uses its default size.
        caSet(aggregate, kAudioDevicePropertyBufferFrameSize, scope: kAudioObjectPropertyScopeInput, value: UInt32(256))

        guard let format = CoreAudio.streamFormat(of: aggregate, scope: kAudioObjectPropertyScopeInput) else {
            destroy()
            throw AudioTapError.formatUnavailable
        }
        streamFormat = format
    }

    /// The AudioObjectID representing this process, needed so that IRSVerb's own
    /// output is not captured (which would feed the effect back into itself).
    private static func currentProcessObject() throws -> AudioObjectID {
        var pid = getpid()
        var address = caAddress(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var objectID: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(CoreAudio.systemObject, &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &objectID)
        guard status == noErr, objectID != kAudioObjectUnknown else { throw AudioTapError.processObjectUnavailable }
        return objectID
    }

    func destroy() {
        // Order matters: the aggregate device must go away before the tap it
        // references, and any IOProc on it must already be gone.
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    deinit {
        destroy()
    }
}
