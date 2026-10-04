import CoreAudio
import Foundation

// Small helpers over the Core Audio HAL property API.

func caAddress(_ selector: AudioObjectPropertySelector,
               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
               element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

func caGet<T>(_ objectID: AudioObjectID,
              _ selector: AudioObjectPropertySelector,
              scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
              element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> T? {
    var address = caAddress(selector, scope: scope, element: element)
    var size = UInt32(MemoryLayout<T>.size)
    let buffer = UnsafeMutablePointer<T>.allocate(capacity: 1)
    defer { buffer.deallocate() }
    guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, buffer) == noErr else { return nil }
    return buffer.pointee
}

@discardableResult
func caSet<T>(_ objectID: AudioObjectID,
              _ selector: AudioObjectPropertySelector,
              scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
              element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
              value: T) -> Bool {
    var address = caAddress(selector, scope: scope, element: element)
    var mutable = value
    return withUnsafePointer(to: &mutable) { pointer in
        AudioObjectSetPropertyData(objectID, &address, 0, nil, UInt32(MemoryLayout<T>.size), pointer) == noErr
    }
}

func caGetString(_ objectID: AudioObjectID,
                 _ selector: AudioObjectPropertySelector,
                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                 element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> String? {
    var address = caAddress(selector, scope: scope, element: element)
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var value: Unmanaged<CFString>?
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, $0)
    }
    guard status == noErr, let string = value else { return nil }
    return string.takeRetainedValue() as String
}

func caGetArray<T>(_ objectID: AudioObjectID,
                   _ selector: AudioObjectPropertySelector,
                   scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                   element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> [T] {
    var address = caAddress(selector, scope: scope, element: element)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
    let count = Int(size) / MemoryLayout<T>.size
    guard count > 0 else { return [] }
    let buffer = UnsafeMutablePointer<T>.allocate(capacity: count)
    defer { buffer.deallocate() }
    guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, buffer) == noErr else { return [] }
    return Array(UnsafeBufferPointer(start: buffer, count: Int(size) / MemoryLayout<T>.size))
}

enum CoreAudio {
    // Note: kAudioObjectSystemObject imports as Int32 while AudioObjectID is
    // UInt32, hence the explicit conversion.
    static var systemObject: AudioObjectID { AudioObjectID(truncatingIfNeeded: kAudioObjectSystemObject) }

    static func defaultOutputDevice() -> AudioObjectID {
        let device: AudioObjectID? = caGet(systemObject, kAudioHardwarePropertyDefaultOutputDevice)
        return device ?? kAudioObjectUnknown
    }

    static func deviceName(_ deviceID: AudioObjectID) -> String {
        caGetString(deviceID, kAudioObjectPropertyName) ?? "Unknown device"
    }

    static func deviceUID(_ deviceID: AudioObjectID) -> String {
        caGetString(deviceID, kAudioDevicePropertyDeviceUID) ?? ""
    }

    static func bufferFrameSize(_ deviceID: AudioObjectID) -> Int? {
        let size: UInt32? = caGet(deviceID, kAudioDevicePropertyBufferFrameSize)
        return size.map { Int($0) }
    }

    /// Format of a device's input (or output) side, preferring the stream
    /// objects and falling back to the device level property.
    static func streamFormat(of deviceID: AudioObjectID, scope: AudioObjectPropertyScope) -> AudioStreamBasicDescription? {
        let streams: [AudioObjectID] = caGetArray(deviceID, kAudioDevicePropertyStreams, scope: scope)
        for stream in streams {
            if let format: AudioStreamBasicDescription = caGet(stream, kAudioStreamPropertyVirtualFormat),
               format.mSampleRate > 0, format.mChannelsPerFrame > 0 {
                return format
            }
        }
        if let format: AudioStreamBasicDescription = caGet(deviceID, kAudioDevicePropertyStreamFormat, scope: scope),
           format.mSampleRate > 0, format.mChannelsPerFrame > 0 {
            return format
        }
        return nil
    }

    static func describe(_ format: AudioStreamBasicDescription) -> String {
        let flags = format.mFormatFlags
        let isFloat = flags & kAudioFormatFlagIsFloat != 0
        let interleaved = flags & kAudioFormatFlagIsNonInterleaved == 0
        return "\(Int(format.mSampleRate)) Hz, \(format.mChannelsPerFrame)ch, "
            + "\(format.mBitsPerChannel)-bit \(isFloat ? "float" : "int"), "
            + (interleaved ? "interleaved" : "planar")
    }
}
