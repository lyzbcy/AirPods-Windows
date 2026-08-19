# AirPodsBuddyMac · Mac 版小助手（v0.1 脚手架）

> 状态：**代码就绪，未在本机编译验证**（开发机是 Windows，没有 Mac）。
> 在 Mac 上跑一次 `swift build` 即可验证，遇到编译错误直接丢给 AI 修。

## 为什么做 Mac 版

Mac 上 AirPods 会被 iPhone"抢走"/系统把输出切到别的设备（Apple 自动切换
导致的音频"跳走"）。Windows 版解决"连得麻烦"，Mac 版核心解决
**"连上之后不许自己跳走"**。

## 架构决策：为什么不是"一个框架打包两端"

| 方案 | 结论 |
|---|---|
| (a) Windows/Mac 各一套 | ❌ UI 和逻辑两份，维护翻倍 |
| (b) Electron/Tauri 统一框架 | ❌ 抛弃能用的 2.6MB Windows 版，换来 60MB+ 安装包和两套打包链 |
| **(b') 一个仓库 + 共享 Web UI + 两个原生轻宿主 ✅** | AHK 宿主（Windows）/ Swift 宿主（Mac），核心逻辑各自原生（蓝牙 API 本来就无法跨平台），UI 层共享 |

Mac 端复用上游 ChromuSx 的 `macos-helper` Swift 核心逻辑
（`IOBluetoothDevice.openConnection/closeConnection`，MIT，已在
`streamdeck-plugin/macos-helper/` 里躺了很久），不依赖 blueutil/brew。

## v0.1 功能（菜单栏原生）

- **左键单击 = 连接/断开切换**（右键才弹菜单，能少一步是一步）
- **状态表情图标**：🎧 已连接 / 💤 未连接（可在 Preferences.swift 改默认）
- **防跳走看门狗**（默认开）：每 2 秒
  1. 耳机被抢走 → 自动重连
  2. 连着但系统输出不是耳机 → 自动把默认输出改回去
  只有左键点"断开"才解除锁定 —— 精确对应需求"只有我点取消时它才跳走"
- 右键菜单：切换 / 选择耳机（Apple 排前）/ 看门狗开关 / 日志 / 退出
- 日志：`~/Library/Logs/AirPodsBuddyMac.log`

## 构建与运行（在你的 Mac 上）

```bash
cd mac/AirPodsBuddyMac
swift build -c release
.build/release/AirPodsBuddyMac
```

要求：macOS 13+，Xcode Command Line Tools（`xcode-select --install`）。
首次运行系统可能弹蓝牙权限确认，允许即可。

### 开机自启（v0.1 手动方式）

系统设置 → 通用 → 登录项 → 添加
`mac/AirPodsBuddyMac/.build/release/AirPodsBuddyMac`。
（正式发布时做成 .app + SMAppService 一键自启。）

## 路线图

- [ ] Mac 上首次编译验证 + 真机 AirPods 全流程测试
- [ ] 看门狗实际抗"iPhone 抢走"效果验证（连接后拿 iPhone 靠近试）
- [ ] 打包 .app + 图标（星星布丁）+ 签名/公证 + DMG 分发
- [ ] SMAppService 一键开机自启
- [ ] Phase 2：WKWebView 加载共享 `webui/index.html`（需抽一层
      `host.js` 桥适配：`chrome.webview.postMessage` vs
      `window.webkit.messageHandlers`），与 Windows 界面完全一致
- [ ] 电量显示（调研 AirPodsDesktop 的 BLE 方案）

## 与 Windows 版的对照

| | Windows | Mac |
|---|---|---|
| 宿主 | AHK v2 | Swift (AppKit) |
| 蓝牙 | Bthprops.cpl | IOBluetooth |
| 输出锁定 | （未做，Windows 少见此问题） | CoreAudio 默认输出 |
| 状态图标 | 绿圈布丁/原版布丁 .ico | 🎧/💤 表情 |
| 左键切换 | A_TrayMenu.Default+Click=1 | NSStatusItem action |
| 防跳看门狗 | 未做 | ✅ 核心 |
