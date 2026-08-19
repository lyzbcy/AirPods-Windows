import AppKit

// AirPodsBuddyMac — 菜单栏常驻小工具（Mac 版 AirPods 小助手）
// 设计原则对应 doc/01-初心与使命.md：一键连接、绝不自己跳走、少一步是一步。
// 这是 LSUIElement 应用：不占 Dock，只活在菜单栏。

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("boot v\(AppInfo.version)")
        statusBar = StatusBarController()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // LSUIElement：无 Dock 图标
app.run()
