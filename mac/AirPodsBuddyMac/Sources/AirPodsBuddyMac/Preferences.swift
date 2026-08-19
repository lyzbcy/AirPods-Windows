import Foundation

// 偏好设置：UserDefaults，键名与默认值集中管理。

enum Preferences {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let targetDeviceName = "targetDeviceName"
        static let connectedEmoji = "connectedEmoji"
        static let disconnectedEmoji = "disconnectedEmoji"
        static let watchdogEnabled = "watchdogEnabled"
    }

    /// 目标耳机名（nil = 尚未选择，运行时取排序首位）
    static var targetDeviceName: String? {
        get { defaults.string(forKey: Key.targetDeviceName) }
        set { defaults.set(newValue, forKey: Key.targetDeviceName) }
    }

    /// 状态表情：连接=🎧，断开=💤（对应 Windows 版绿圈/原版布丁双图标）
    static var connectedEmoji: String {
        get { defaults.string(forKey: Key.connectedEmoji) ?? "🎧" }
        set { defaults.set(newValue, forKey: Key.connectedEmoji) }
    }

    static var disconnectedEmoji: String {
        get { defaults.string(forKey: Key.disconnectedEmoji) ?? "💤" }
        set { defaults.set(newValue, forKey: Key.disconnectedEmoji) }
    }

    /// 防跳走看门狗（默认开——这是 Mac 版存在的核心理由）
    static var watchdogEnabled: Bool {
        get { defaults.object(forKey: Key.watchdogEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.watchdogEnabled) }
    }
}
