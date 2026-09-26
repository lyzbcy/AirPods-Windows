import Foundation
import CoreAudio

struct AudioOutputCandidate {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: UInt32
}

enum AudioRouter {
    static func defaultOutputDeviceID() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &id)
        guard status == noErr, id != 0 else { return nil }
        return id
    }

    static func setDefaultOutputDevice(_ id: AudioDeviceID) -> Bool {
        var mutableID = id
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &mutableID)
        guard status == noErr, defaultOutputDeviceID() == id else {
            Log.error("default output set/readback failed: \(status)")
            return false
        }
        return true
    }

    static func outputDevices() -> [AudioOutputCandidate] {
        var size = UInt32(0)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasOutputStreams(id),
                let uid = stringProperty(id, kAudioDevicePropertyDeviceUID),
                let name = stringProperty(id, kAudioObjectPropertyName),
                let transport = transportType(id) else { return nil }
            return AudioOutputCandidate(id: id, uid: uid, name: name, transport: transport)
        }
    }

    private static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var size = UInt32(0)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func stringProperty(_ id: AudioDeviceID,
                                       _ selector: AudioObjectPropertySelector) -> String? {
        // CoreAudio's CFString properties return an owned (+1) CFObject. Keep
        // the C out-parameter as raw unmanaged storage, then transfer exactly
        // that ownership to ARC with takeRetainedValue().
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, UnsafeMutableRawPointer(pointer))
        }
        guard status == noErr, let owned = value else { return nil }
        return owned.takeRetainedValue() as String
    }

    private static func transportType(_ id: AudioDeviceID) -> UInt32? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    // Route only when CoreAudio UID embeds the selected Bluetooth address.
    // A matching display name alone cannot establish hardware identity.
    static func findOutputDevice(address: String, name: String) -> AudioDeviceID? {
        chooseOutput(outputDevices(), address: address, name: name)
    }

    static func chooseOutput(_ rows: [AudioOutputCandidate], address: String,
                             name: String) -> AudioDeviceID? {
        let candidates = rows.filter {
            $0.transport == kAudioDeviceTransportTypeBluetooth ||
            $0.transport == kAudioDeviceTransportTypeBluetoothLE
        }
        let normalizedAddress = address.filter(\.isHexDigit).lowercased()
        guard !normalizedAddress.isEmpty else { return nil }
        let byUID = candidates.filter { $0.uid.filter(\.isHexDigit).lowercased().contains(normalizedAddress) }
        if byUID.count == 1 { return byUID[0].id }
        if byUID.count > 1 {
            Log.error("ambiguous CoreAudio UID for Bluetooth address")
            return nil
        }
        Log.error("Bluetooth output UID not bound to selected address: \(name)")
        return nil
    }
}
