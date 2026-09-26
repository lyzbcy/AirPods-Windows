import AppKit
import IOBluetooth

final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var isBusy = false
    private var isCancelling = false
    private var busyTimer: Timer?
    private var busyFrame = 0
    private let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(onStatusClick(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        Watchdog.shared.onStateChange = { [weak self] in self?.refreshIcon() }
        Watchdog.shared.restorePreference()
        refreshIcon()
    }

    private func refreshIcon() {
        guard !isBusy else { return }
        // Armed expresses intent, never actual connectivity.
        let connected = Watchdog.shared.actualConnected
        statusItem.button?.image = EmojiIcon.image(for: connected
            ? Preferences.connectedEmoji : Preferences.disconnectedEmoji)
        statusItem.button?.toolTip = connected
            ? "AirPods 小助手 · 已连接（左键断开）"
            : "AirPods 小助手 · 未连接（左键连接）"
    }

    @objc private func onStatusClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp { popUpMenu() }
        else { toggle() }
    }

    private func toggle() {
        if isBusy {
            guard !isCancelling else { return }
            isCancelling = true
            Watchdog.shared.disconnect { [weak self] ok in
                Log.info("user cancelled pending connect; disconnect verified=\(ok)")
                self?.isCancelling = false
                self?.finishBusy()
            }
            return
        }
        isBusy = true
        startBusyAnimation()
        if Watchdog.shared.actualConnected {
            Watchdog.shared.disconnect { [weak self] ok in
                Log.info("user disconnect verified=\(ok)")
                self?.finishBusy()
            }
        } else {
            let address = Watchdog.shared.targetAddress
            Watchdog.shared.connect(address: address) { [weak self] ok in
                Log.info("user connect and output verified=\(ok)")
                self?.finishBusy()
            }
        }
    }

    private func startBusyAnimation() {
        statusItem.button?.toolTip = "AirPods 小助手 · 操作中…"
        busyFrame = 0
        busyTimer?.invalidate()
        busyTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.busyFrame = (self.busyFrame + 1) % self.spinnerFrames.count
            self.statusItem.button?.image = EmojiIcon.image(for: self.spinnerFrames[self.busyFrame])
        }
    }

    private func finishBusy() {
        busyTimer?.invalidate()
        busyTimer = nil
        isBusy = false
        isCancelling = false
        refreshIcon()
    }

    private func popUpMenu() {
        Watchdog.shared.refreshCandidates()
        let menu = NSMenu()
        let title = NSMenuItem(title: "AirPods 小助手 v\(AppInfo.version)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        let toggleItem = NSMenuItem(title: Watchdog.shared.actualConnected ? "断开耳机" : "连接耳机",
            action: #selector(menuToggle), keyEquivalent: "t")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        let deviceMenu = NSMenuItem(title: "选择耳机", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for device in Watchdog.shared.candidates {
            let address = device.address
            let item = NSMenuItem(title: device.name,
                action: #selector(pickDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = address
            item.state = address.caseInsensitiveCompare(Watchdog.shared.targetAddress) == .orderedSame
                ? .on : .off
            sub.addItem(item)
        }
        menu.setSubmenu(sub, for: deviceMenu)
        menu.addItem(deviceMenu)
        let watchdogItem = NSMenuItem(title: "防止自动切走（看门狗）",
            action: #selector(toggleWatchdog), keyEquivalent: "w")
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
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    @objc private func menuToggle() { toggle() }

    @objc private func pickDevice(_ sender: NSMenuItem) {
        guard !isBusy, let address = sender.representedObject as? String else { return }
        isBusy = true
        startBusyAnimation()
        Watchdog.shared.connect(address: address) { [weak self] ok in
            Log.info("selected address connect/output verified=\(ok)")
            self?.finishBusy()
        }
    }

    @objc private func toggleWatchdog() {
        Preferences.watchdogEnabled.toggle()
        Watchdog.shared.setWatchdogEnabled(Preferences.watchdogEnabled)
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

enum EmojiIcon {
    static func image(for emoji: String) -> NSImage? {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuBarFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = (emoji as NSString).size(withAttributes: attributes)
        let image = NSImage(size: NSSize(width: max(size.width, 18), height: 18))
        image.lockFocus()
        (emoji as NSString).draw(at: NSPoint(x: max(0, (max(size.width, 18) - size.width) / 2),
            y: (18 - size.height) / 2), withAttributes: attributes)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
