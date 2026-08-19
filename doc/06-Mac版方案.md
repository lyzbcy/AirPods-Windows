# 06 · Mac 版方案

> 读这份文档的时机：要开发/构建/调试 Mac 版时。Windows 版不用读。

## 背景

用户原话：Mac 上"明明选择了 AirPods、手机没在放音频、电脑还在播放，
结果音频直接切换走了"。这是 Apple 多设备自动切换（AAP）+ macOS 输出
设备漂移的典型症状。Mac 版的核心使命 = **连接后不许自己跳走**。

## 架构决策（已定）

**一个仓库 + 共享 Web UI + 两个原生轻宿主**（README 的"为什么"表格）。
- Windows：AHK v2 + WebView2（现有，2.6MB）
- Mac：Swift AppKit 菜单栏应用（`mac/AirPodsBuddyMac/`），复用上游
  `macos-helper` 的 IOBluetooth 核心，**不依赖 blueutil/brew**
- Phase 2 才做 Mac 端 Web UI（WKWebView + host.js 桥适配层）

## 防跳走看门狗（核心机制）

```
用户左键"连接" → openConnection + arm 看门狗
每 2s：
  耳机没连？→ 自动重连（对抗 iPhone 抢走）
  连着但 CoreAudio 默认输出不是耳机？→ 改回去（对抗输出漂移）
用户左键"断开" → disarm 看门狗 + closeConnection（此后不再拉回）
```
- 关键文件：`Watchdog.swift`（重连+锁输出）、`AudioRouter.swift`
  （CoreAudio 默认输出 get/set/按名匹配）、`BluetoothService.swift`
  （IOBluetooth 连接，移植自上游 main.swift + 文件日志）
- 偏好：UserDefaults（目标耳机、🎧/💤 表情、看门狗开关）

## 交互（对应用户要求）

- 左键单击 = 切换连接/断开；右键 = 菜单（选耳机/看门狗开关/日志/退出）
- 状态表情图标（🎧/💤，EmojiIcon.swift 渲染成 NSImage，template=false）

## 构建状态与坑（重要）

- ⚠️ **未编译验证**：开发机是 Windows，没有 macOS/Xcode。
  上 Mac 后：`cd mac/AirPodsBuddyMac && swift build -c release`
- 已知风险点（若编译报错先查这里）：
  1. `AudioRouter.swift` 的 CoreAudio 属性调用（kAudioObjectPropertyElementMain
     需要 macOS 12+；老系统用 kAudioObjectPropertyElementMaster）
  2. `popUpMenu()` 的 `performClick` 弹菜单 hack——如左键失灵，改用
     `menu.popUp(positioning:at:in:)` 直弹
  3. IOBluetooth 无沙盒要求，但 macOS 可能把 app 识别为无签名，
     首次连接可能要求蓝牙权限确认
- 测试清单：连接/断开/切换目标/看门狗抗抢（连上后拿 iPhone 靠近播放）/
  输出锁定（连着时手动把输出切到扬声器，2s 内应被改回）

## Windows 侧未做（Mac 教训反哺的候选项）

- Windows 输出设备锁定（对应 AudioRouter）：等用户确认 Windows 也需要
- AHK 侧"看门狗"等价物：轮询 + BluetoothSetServiceState 重连
