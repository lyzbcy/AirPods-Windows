# 🎧 AirPods 小助手 AirPodsBuddy

<div align="center">
  <img src="logo.png" alt="AirPodsBuddy" width="200">
</div>

<div align="center">
  <img src="https://img.shields.io/badge/Platform-Windows-blue?style=for-the-badge" alt="Platform">
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="MIT License">
  <img src="https://img.shields.io/badge/Version-1.3.0-brightgreen?style=for-the-badge" alt="Version">
  <img src="https://img.shields.io/badge/%E5%8D%95%E6%96%87%E4%BB%B6-2.6MB-orange?style=for-the-badge" alt="Single exe 2.6MB">
</div>

<p align="center">
<strong>给 Windows 的一口甜：点一下，AirPods 就连上。</strong><br>
米白简约风 · 常驻托盘 · 优先级连接 · 纯本地零上传<br>
<sub>Mac 版开发中（核心：防自动跳走看门狗）→ <a href="mac/README.md">mac/README.md</a></sub>
</p>

---

## 🤔 为什么需要它？（和系统设置比一比）

在 iPhone 上连 AirPods：开盖，弹窗，点一下。
在 Windows 上连 AirPods：**没有弹窗**——Windows 不支持 Apple 的私有协议，
每次都要：

| | Windows 原生 | AirPods 小助手 |
|---|---|---|
| 连接步骤 | 设置 → 蓝牙和其他设备 → 找到设备 → 点连接（4~5 步） | **双击托盘图标 / 点一下大圆钮（1 步）** |
| 耳机好几个 | 每次都要自己找哪个是哪个 | **按你的优先级自动挑**（支持 ▲▼ 排序） |
| 断开 | 再进设置点断开 | 右键托盘 → 一键断开全部 |
| 音质 | 容易连成低音质通话模式（HFP） | 默认 A2DP+HFP 完整模式 |
| 常驻 | 无 | 托盘常驻 + 开机自启，不占任务栏 |

> 类似需求的知名开源项目还有
> [AirPodsDesktop](https://github.com/SpriteOvO/AirPodsDesktop)、
> [PodBridge](https://github.com/bhemsen/PodBridge)、
> [MagicPods](https://apps.microsoft.com/detail/9p6skkfkshkm)——
> 它们证明了一件事：**Windows 用户苦"连 AirPods 繁琐"久矣**。
> 我们的差异点：**2.6MB 单文件、零依赖零后台服务、纯本地零遥测、优先级连接、界面是和星星布丁一起调出来的米白可爱风** 💕

## ✨ 功能

- 🚀 **一键连接/断开**：大圆形立体按钮；**左键单击托盘图标即切换连接状态**（右键才弹菜单）
- 🥇 **设备优先级**：列表 ▲▼ 调整顺序，"一键连接"永远先连你最想要的那个；
  苹果设备（AirPods / Beats）默认排前面，其他耳机标"其他"不捣乱
- 🔵 **托盘状态图标**：未连接=原版布丁，已连接=绿圈布丁，一眼看出状态
- 🖱️ **无边框窗口可拖动**：按住顶栏/标题区即可移动
- 🖥️ **托盘常驻**：关窗=缩托盘，开机自启，随时唤出
- 🎨 **米白简约 UI**：WebView2 渲染，圆角卡片、呼吸状态灯、手绘设备图形
- 🔒 **纯本地**：不联网上传任何数据（唯一网络行为=检查 GitHub 新版本）
- 🔄 **自动更新**：有新版弹窗一键升级
- 📋 **日志排查**：出错不弹窗吓人，全记在本地日志里

## 📥 下载使用（三步）

1. 到 [Releases](https://github.com/lyzbcy/BluetoothDeviceConnector/releases/latest) 下载 `AirPodsBuddy-Windows.zip`
2. 解压，双击 `AirPodsBuddy.exe`（无需安装；建议放到固定位置）
3. 耳机先在 Windows 蓝牙设置里配对过一次，之后就只用点它了

> ⚠️ 个别安全软件可能误报/拦截 AHK 编译的程序（毕竟它会操作蓝牙），
> 请加入信任列表。程序纯本地运行，可自行审计源码。

## 🛠 开发者

- 技术栈：AutoHotkey v2 + WebView2（系统自带 Edge 内核），编译为单文件 exe
- 完整文档在 [`doc/`](doc/README.md)（渐进式披露：初心 / 原理 / 技术方案 / 进度 / 踩坑记录）
- 构建：改 `webui/index.html` → `webui/build_ui.ps1` → Ahk2Exe 编译（详见 doc/02）

## 🙏 致谢

- 蓝牙核心逻辑复用自 [ChromuSx/BluetoothDeviceConnector](https://github.com/ChromuSx/BluetoothDeviceConnector)（MIT）
- WebView2 承载使用 [thqby 的 WebView2-AHK 库](https://github.com/thqby/ahk2_lib)
- 用爱发电 · 捞鱼 & 星星布丁 💕

## 📄 License

MIT
