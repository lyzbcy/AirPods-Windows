import Foundation
import CoreAudio

// 音频路由：把系统默认输出锁定到目标耳机。
// 这是 Mac 版"防跳走"的第二条腿——蓝牙连着但输出被系统切走时，
// 看门狗会把默认输出设备改回来。

enum AudioRouter {
    // MARK: - 默认输出设备

    static func defaultOutputDeviceID() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        guard status == noErr else {
            Log.error("defaultOutputDeviceID failed: \(status)")
            return nil
        }
        return id
    }

    static func setDefaultOutputDevice(_ id: AudioDeviceID) -> Bool {
        var mutableID = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &mutableID)
        guard status == noErr else {
            Log.error("setDefaultOutputDevice failed: \(status)")
            return false
        }
        return true
    }

    // MARK: - 设备列表 / 匹配

    static func outputDevices() -> [(id: AudioDeviceID, name: String)] {
        var propertySize = UInt32(0)
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &devicesAddress, 0, nil, &propertySize) == noErr,
              propertySize > 0 else { return [] }

        let count = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &devicesAddress, 0, nil, &propertySize, &ids) == noErr
        else { return [] }

        // 只保留有输出流的设备（排除纯输入）
        return ids.compactMap { id -> (AudioDeviceID, String)? in
            guard hasOutputStreams(id) else { return nil }
            return (id, deviceName(id))
        }
    }

    private static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var size = UInt32(0)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func deviceName(_ id: AudioDeviceID) -> String {
        var name = CFString("")
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr else {
            return "unknown"
        }
        return name as String
    }

    /// 按耳机名匹配输出设备（AirPods 在 CoreAudio 里通常叫 "<名字>" 或带后缀）
    static func findOutputDevice(matchingDeviceName: String) -> AudioDeviceID? {
        let target = matchingDeviceName.lowercased()
        // 1) 精确
        if let exact = outputDevices().first(where: { $0.name.lowercased() == target }) {
            return exact.id
        }
        // 2) 包含（"XX的AirPods Pro" → CoreAudio 可能显示 "XX的AirPods Pro" 或 "AirPods Pro"）
        if let fuzzy = outputDevices().first(where: {
            let n = $0.name.lowercased()
            return n.contains(target) || target.contains(n) || n.contains("airpods")
        }) {
            return fuzzy.id
        }
        return nil
    }
}
