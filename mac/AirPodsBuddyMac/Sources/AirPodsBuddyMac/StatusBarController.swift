import AppKit
import IOBluetooth

// 菜单栏交互 —— 用户的核心要求：
//   1) 左键单击 = 连接/断开 切换（能少一步就少一步）
//   2) 右键 = 完整菜单（设备选择/看门狗开关/退出）
//   3) 图标随状态变化（🎧 已连接 / 💤 未连接，可自定义表情）

final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!

    override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(onStatusClick(_:))
        // 左键和右键都路由到 action，在 handler 里区分
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        refreshIcon()
        Watchdog.shared.tick()   // 启动时对齐一次状态

        // 开机即恢复上次的锁定（如果上次是连接态）
        if Preferences.watchdogEnabled,
           let name = Preferences.targetDeviceName,
           BluetoothService.isConnected(name) {
            Watchdog.shared.arm(deviceName: name)
        }
    }

    // MARK: - 状态图标

    private func refreshIcon() {
        // 图标以"耳机实际连着"为准，而不是看门狗 armed——否则看门狗关掉后
        // 已连接也永远显示 💤（真机日志抓到的坑）
        let connected = Watchdog.shared.armed
            || (!Watchdog.shared.targetDeviceName.isEmpty
                && BluetoothService.isConnected(Watchdog.shared.targetDeviceName))
        let emoji = connected ? Preferences.connectedEmoji : Preferences.disconnectedEmoji
        statusItem.button?.image = EmojiIcon.image(for: emoji)
        statusItem.button?.toolTip = connected
            ? "AirPods 小助手 · 已连接（左键断开）"
            : "AirPods 小助手 · 未连接（左键连接）"
    }

    // MARK: - 点击

    @objc private func onStatusClick(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            popUpMenu()
        } else {
            toggle()
        }
    }

    /// 左键单击：连接态→断开；断开态→连接（并启动防跳看门狗）
    /// 状态以"耳机实际是否连着"为准（armed 或 isConnected 任一为真都算连着），
    /// 否则看门狗关闭时左键永远走"连接"分支、无法断开（真机日志抓到的坑）
    private func toggle() {
        let name = Watchdog.shared.targetDeviceName
        let connected = Watchdog.shared.armed || BluetoothService.isConnected(name)
        if connected {
            Watchdog.shared.disarm()
            _ = BluetoothService.disconnect(name)
            Log.info("toggle → disconnected '\(name)'")
        } else {
            if BluetoothService.connect(name) {
                if Preferences.watchdogEnabled {
                    Watchdog.shared.arm(deviceName: name)
                } else {
                    Log.info("watchdog OFF (pref), connected without arm")
                }
                Log.info("toggle → connected '\(name)'")
            } else {
                Log.error("toggle connect failed for '\(name)'")
            }
        }
        refreshIcon()
    }

    // MARK: - 右键菜单

    private func popUpMenu() {
        let menu = NSMenu()

        let title = NSMenuItem(title: "AirPods 小助手 v\(AppInfo.version)",
                               action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let toggleItem = NSMenuItem(title: Watchdog.shared.armed ? "断开耳机" : "连接耳机",
                                    action: #selector(menuToggle),
                                    keyEquivalent: "t")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let deviceMenu = NSMenuItem(title: "选择耳机", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for device in BluetoothService.sortedAudioCandidates() {
            guard let name = device.nameOrAddress else { continue }
            let item = NSMenuItem(title: name, action: #selector(pickDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.state = (name == Watchdog.shared.targetDeviceName) ? .on : .off
            sub.addItem(item)
        }
        menu.setSubmenu(sub, for: deviceMenu)
        menu.addItem(deviceMenu)

        let watchdogItem = NSMenuItem(title: "防止自动切走（看门狗）",
                                      action: #selector(toggleWatchdog),
                                      keyEquivalent: "w")
        watchdogItem.target = self
        watchdogItem.state = Preferences.watchdogEnabled ? .on : .off
        menu.addItem(watchdogItem)

        menu.addItem(.separator())
        let logItem = NSMenuItem(title: "打开日志", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu                    // 临时挂上以弹出
        statusItem.button?.performClick(nil)      // 触发系统弹出
        // 弹出结束后必须摘掉 menu，否则左键 action 会失效
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    @objc private func menuToggle() { toggle() }

    @objc private func pickDevice(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        Preferences.targetDeviceName = name
        Watchdog.shared.disarm()
        Watchdog.shared.arm(deviceName: name)   // 选择即切换目标并尝试连接
        if BluetoothService.connect(name) {
            Log.info("picked & connected '\(name)'")
        }
        refreshIcon()
    }

    @objc private func toggleWatchdog() {
        Preferences.watchdogEnabled.toggle()
        if Preferences.watchdogEnabled, !Watchdog.shared.armed {
            Watchdog.shared.arm(deviceName: Watchdog.shared.targetDeviceName)
        } else if !Preferences.watchdogEnabled {
            Watchdog.shared.disarm()
        }
        refreshIcon()
    }

    @objc private func openLog() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/AirPodsBuddyMac.log")
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        Log.info("quit")
        NSApp.terminate(nil)
    }
}

// 表情 → 菜单栏 NSImage（模板渲染会丢颜色，必须 template=false）
enum EmojiIcon {
    static func image(for emoji: String) -> NSImage? {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuBarFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = (emoji as NSString).size(withAttributes: attributes)
        let image = NSImage(size: NSSize(width: max(size.width, 18), height: 18))
        image.lockFocus()
        (emoji as NSString).draw(
            at: NSPoint(x: max(0, (max(size.width, 18) - size.width) / 2),
                        y: (18 - size.height) / 2),
            withAttributes: attributes)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
