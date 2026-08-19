import Foundation

// 防跳走看门狗 —— Mac 版核心差异点。
// 用户点"连接"后 armed=true，之后每 2 秒：
//   1) 耳机被抢走（iPhone 自动切换等）→ 立即重连
//   2) 耳机连着但系统默认输出被切走 → 改回耳机
// 只有用户点"断开"才 disarm，耳机从此不再被我们拉回。

final class Watchdog {
    static let shared = Watchdog()

    private var timer: Timer?
    private(set) var armed = false

    private(set) var targetDeviceName: String

    private init() {
        targetDeviceName = Preferences.targetDeviceName
            ?? BluetoothService.sortedAudioCandidates().first.map { $0.nameOrAddress ?? "" }
            ?? ""
        if targetDeviceName.isEmpty {
            Log.error("no paired device found for watchdog")
        }
    }

    func arm(deviceName: String) {
        targetDeviceName = deviceName
        Preferences.targetDeviceName = deviceName
        armed = true
        start()
        Log.info("watchdog armed for '\(deviceName)'")
    }

    func disarm() {
        armed = false
        timer?.invalidate()
        timer = nil
        Log.info("watchdog disarmed")
    }

    private func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    func tick() {
        guard armed, !targetDeviceName.isEmpty else { return }

        // 1) 连接被抢走 → 重连
        if !BluetoothService.isConnected(targetDeviceName) {
            Log.info("watchdog: '\(targetDeviceName)' dropped, reconnecting…")
            let ok = BluetoothService.connect(targetDeviceName)
            Log.info("watchdog reconnect result: \(ok)")
            if ok {
                _ = lockOutputToDevice()
            }
            return
        }

        // 2) 连着但输出不是它 → 改回
        lockOutputToDevice()
    }

    @discardableResult
    func lockOutputToDevice() -> Bool {
        guard let target = AudioRouter.findOutputDevice(matchingDeviceName: targetDeviceName) else {
            return false
        }
        if AudioRouter.defaultOutputDeviceID() == target { return true }
        let ok = AudioRouter.setDefaultOutputDevice(target)
        if ok { Log.info("output locked to '\(targetDeviceName)'") }
        return ok
    }
}
