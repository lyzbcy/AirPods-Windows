import Foundation
import IOBluetooth

// All calls into IOBluetooth are made by Watchdog's serial worker, never its timer.
enum BluetoothService {
    static func pairedDevices() -> [IOBluetoothDevice] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter {
            guard let address = $0.addressString else { return false }
            return !address.isEmpty && isAudio($0)
        }
    }

    // Bluetooth Class of Device: major class 0x04 is Audio/Video.
    static func isAudio(_ device: IOBluetoothDevice) -> Bool {
        Int(device.deviceClassMajor) == kBluetoothDeviceClassMajorAudio
            || device.isHandsFreeDevice || isApple(device)
    }

    static func sortedAudioCandidates() -> [IOBluetoothDevice] {
        pairedDevices().sorted { a, b in
            let aa = isApple(a), ab = isApple(b)
            if aa != ab { return aa }
            let comparison = (a.nameOrAddress ?? "").localizedCaseInsensitiveCompare(b.nameOrAddress ?? "")
            return comparison == .orderedSame
                ? (a.addressString ?? "") < (b.addressString ?? "")
                : comparison == .orderedAscending
        }
    }

    static func isApple(_ device: IOBluetoothDevice) -> Bool {
        let name = (device.nameOrAddress ?? "").lowercased()
        return name.contains("airpods") || name.contains("beats")
    }

    static func device(address: String) -> IOBluetoothDevice? {
        let matches = pairedDevices().filter {
            ($0.addressString ?? "").caseInsensitiveCompare(address) == .orderedSame
        }
        return matches.count == 1 ? matches[0] : nil
    }

    static func isConnected(address: String) -> Bool {
        device(address: address)?.isConnected() ?? false
    }

    static func connect(address: String) -> Bool {
        guard let device = device(address: address) else {
            Log.error("audio device not found for address \(address)")
            return false
        }
        if !device.isConnected() {
            let result = device.openConnection()
            guard result == kIOReturnSuccess else {
                Log.error("openConnection failed: \(result)")
                return false
            }
        }
        return waitFor(connected: true, device: device)
    }

    static func disconnect(address: String) -> Bool {
        guard let device = device(address: address) else {
            Log.error("disconnect target not found: \(address)")
            return false
        }
        if device.isConnected() {
            let result = device.closeConnection()
            guard result == kIOReturnSuccess else {
                Log.error("closeConnection failed: \(result)")
                return false
            }
        }
        let disconnected = waitFor(connected: false, device: device)
        if !disconnected { Log.error("disconnect not verified: \(address)") }
        return disconnected
    }

    private static func waitFor(connected: Bool, device: IOBluetoothDevice,
                                timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if device.isConnected() == connected { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return device.isConnected() == connected
    }
}

enum Log {
    private static let queue = DispatchQueue(label: "AirPodsBuddyMac.log")
    private static var logURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("AirPodsBuddyMac.log")
    }
    static func info(_ message: String) { write("INFO", message) }
    static func error(_ message: String) { write("ERROR", message) }
    private static func write(_ level: String, _ message: String) {
        queue.async {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let line = "\(formatter.string(from: Date())) [\(level)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}

enum AppInfo { static let version = "0.2.0" }
