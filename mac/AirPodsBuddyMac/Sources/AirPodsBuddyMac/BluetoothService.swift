import Foundation
import IOBluetooth

// 蓝牙服务：连接/断开/状态查询。
// 核心逻辑移植自上游 ChromuSx/BluetoothDeviceConnector 的 macos-helper
// （IOBluetoothDevice.openConnection/closeConnection，MIT），新增：
// 设备状态通知订阅与"只断开 Apple 音频设备"的辅助判断。

enum BluetoothService {
    /// 所有已配对设备（名字非空）
    static func pairedDevices() -> [IOBluetoothDevice] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
            .filter { !($0.nameOrAddress ?? "").isEmpty }
    }

    /// Apple 家族（AirPods / Beats）优先排序，其余按名字
    static func sortedAudioCandidates() -> [IOBluetoothDevice] {
        pairedDevices().sorted { a, b in
            let aa = isApple(a), ab = isApple(b)
            if aa != ab { return aa }
            return (a.nameOrAddress ?? "").localizedCaseInsensitiveCompare(b.nameOrAddress ?? "") == .orderedAscending
        }
    }

    static func isApple(_ device: IOBluetoothDevice) -> Bool {
        let n = (device.nameOrAddress ?? "").lowercased()
        return n.contains("airpods") || n.contains("beats")
    }

    static func device(named name: String) -> IOBluetoothDevice? {
        pairedDevices().first {
            ($0.nameOrAddress ?? "").localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    static func isConnected(_ name: String) -> Bool {
        device(named: name)?.isConnected() ?? false
    }

    /// 连接并等待到位（超时 8s）
    static func connect(_ name: String) -> Bool {
        guard let device = device(named: name) else {
            Log.error("device not found: \(name)")
            return false
        }
        if !device.isConnected() {
            let r = device.openConnection()
            guard r == kIOReturnSuccess else {
                Log.error("openConnection failed: \(r)")
                return false
            }
        }
        return waitFor(connected: true, device: device)
    }

    /// 断开并等待到位（超时 8s）
    static func disconnect(_ name: String) -> Bool {
        guard let device = device(named: name) else { return false }
        if device.isConnected() {
            let r = device.closeConnection()
            guard r == kIOReturnSuccess else {
                Log.error("closeConnection failed: \(r)")
                return false
            }
        }
        return waitFor(connected: false, device: device)
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

/// 简单文件日志：~/Library/Logs/AirPodsBuddyMac.log（对应 Windows 版 logs/ 的设计）
enum Log {
    private static var logURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("AirPodsBuddyMac.log")
    }

    static func info(_ msg: String) { write("INFO", msg) }
    static func error(_ msg: String) { write("ERROR", msg) }

    private static func write(_ level: String, _ msg: String) {
        let line = "\(timestamp()) [\(level)] \(msg)\n"
        if let data = line.data(using: .utf8) {
            if let fh = try? FileHandle(forWritingTo: logURL) {
                fh.seekToEndOfFile()
                fh.write(data)
                try? fh.close()
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}

enum AppInfo {
    static let version = "0.1.0"
}
