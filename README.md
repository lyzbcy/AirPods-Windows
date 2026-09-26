# 🎧 AirPods 小助手 AirPodsBuddy

<div align="center">
  <img src="logo.png" alt="AirPodsBuddy" width="200">
</div>

<div align="center">
  <img src="https://img.shields.io/badge/Platform-Windows-blue?style=for-the-badge" alt="Platform">
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="MIT License">
  <img src="https://img.shields.io/badge/Version-1.9.20-brightgreen?style=for-the-badge" alt="Version">
  <img src="https://img.shields.io/badge/%E5%8D%95%E6%96%87%E4%BB%B6-3.4MB-orange?style=for-the-badge" alt="Single exe 3.4MB">
</div>

<p align="center">
<strong>给 Windows 的一口甜：点一下，AirPods 就连上。</strong><br>
<sub>🏠 <a href=https://lyzbcy.github.io/airpods-buddy.html>产品介绍页</a> · 📦 <a href=https://github.com/lyzbcy/AirPods-Windows/releases/latest>下载</a></sub><br>
奶油黄白 Apple 风 · 常驻托盘 · 优先级连接 · 无遥测 · 主动反馈可附日志<br>
<sub>Mac 版开发中（核心：防自动跳走看门狗）→ <a href="mac/AirPodsBuddyMac/README.md">mac/AirPodsBuddyMac/README.md</a></sub>
</p>

---

> 当前源码为 v1.9.20 开发候选，公开下载仍以 Release 页面为准。KS 后端与验收进度见 [开发清单](doc/07-审计修复清单.md)。

## 🤔 为什么需要它？（和系统设置比一比）

在 iPhone 上连 AirPods：开盖，弹窗，点一下。
在 Windows 上连 AirPods：**没有弹窗**——Windows 不支持 Apple 的私有协议，
每次都要：

| | Windows 原生 | AirPods 小助手 |
|---|---|---|
| 连接步骤 | 设置 → 蓝牙和其他设备 → 找到设备 → 点连接（4~5 步） | **单击托盘图标 / 点一下大圆钮（1 步）** |
| 耳机好几个 | 每次都要自己找哪个是哪个 | **按你的优先级自动挑**（支持 ▲▼ 排序） |
| 断开 | 再进设置点断开 | 右键托盘 → 一键断开全部 |
| 音质 | 容易连成低音质通话模式（HFP） | 默认 A2DP+HFP 完整模式 |
| 常驻 | 无 | 托盘常驻 + 开机自启，不占任务栏 |

> 类似需求的知名开源项目还有
> [AirPodsDesktop](https://github.com/SpriteOvO/AirPodsDesktop)、
> [PodBridge](https://github.com/bhemsen/PodBridge)、
> [MagicPods](https://apps.microsoft.com/detail/9p6skkfkshkm)——
> 它们证明了一件事：**Windows 用户苦"连 AirPods 繁琐"久矣**。
> 我们的差异点：**3.4MB 单文件、零依赖零后台服务、纯本地零遥测、优先级连接、界面是和星星布丁一起调出来的米白可爱风** 💕

## ✨ 功能

- 🚀 **一键连接/断开**：大圆钮一点即连；**左键单击托盘图标直接切换**（右键才弹菜单）
- 🧚 **星星布丁小宠物**：点托盘后她从右下角弹出来陪你等连接——等待张望→
  连上开心跳跃撒💕→断开挥手拜拜，全帧动画+桌面级透明（素材取自
  Codex 版星星布丁宠物精灵图）
- 🥇 **设备优先级**：列表 ▲▼ 调整顺序，"一键连接"永远先连你最想要的那个；
  苹果设备（AirPods / Beats）默认排前面，其他耳机标"其他"不捣乱
- 🔵 **三态托盘图标**：未连接=可爱脸 / 已连接=心动脸+绿环 / 连接中=加油脸+旋转弧
- 🎨 **Apple 风界面**：奶油黄白底+蜂蜜金主按钮，macOS 级克制质感，长名字优雅截断
- 🖱️ **无边框窗口可拖动**：按住顶栏/标题区即可移动
- ℹ️ 降噪/通透：Windows 用户态无法访问 Apple 控制通道（需内核驱动，见
  [MagicPods](https://github.com/steam3d/MagicPods-Windows) 路线），菜单内已
  诚实说明并指路；Mac 版不存在此限制
- 🖥️ **托盘常驻**：关窗=缩托盘，开机自启，随时唤出
- 🔒 **纯本地**：连接诊断主要在本地完成；网络仅用于更新及用户主动提交的反馈（可勾选日志）
- 🔄 **自动更新**：有新版弹窗一键升级
- 📋 **日志排查**：出错不弹窗吓人，全记在本地日志里

## 📥 下载使用（三步）

1. 到 [Releases](https://github.com/lyzbcy/AirPods-Windows/releases/latest) 下载 `AirPodsBuddy-Windows.zip`
2. 解压，双击 `AirPodsBuddy.exe`（无需安装；建议放到固定位置）
3. 耳机先在 Windows 蓝牙设置里配对过一次，之后就只用点它了

> ⚠️ 个别安全软件可能误报/拦截 AHK 编译的程序（毕竟它会操作蓝牙），
> 请加入信任列表。程序纯本地运行，可自行审计源码。
>
> 💡 极少数精简版系统缺少微软 WebView2 组件（首次运行会自动引导安装，
> 约 2MB 官方包；断网时也会自动借用本机 Edge 内核，无需手动处理）。
> 注意：**单独安装 Edge 浏览器解决不了这个问题**——程序用的是独立的
> WebView2 Runtime。

## ❓ 常见问题

**新耳机（AirPods 5 / AirPods Pro 3 等）连不上或连上没声音？**

新款 AirPods 支持「LE 音频」新协议，Windows 与它的协商路径和老款不同
（微软 2026 年 6 月的系统更新专门改善了这块的稳定性）。可以按顺序试：

1. **Windows 设置 → 蓝牙和其他设备 → 点开耳机详情**：如有「LE 音频」
   开关，先关掉再连接（走传统蓝牙路径，兼容性最好）
2. **更新 Windows 到最新**（2026-06 之后的更新包含蓝牙/LE 音频修复）
3. 重新配对：删除设备后按耳机说明重新配对一次
4. 都不行的话，在程序里点「🐞 问题反馈」选「🆕 新耳机连不上」，
   附上系统版本说明一下——日志会自动带上，我拿到就能定位

## 🛠 开发者

- 技术栈：AutoHotkey v2 + WebView2（系统自带 Edge 内核），编译为单文件 exe
- 完整文档在 [`doc/`](doc/README.md)（渐进式披露：初心 / 原理 / 技术方案 / 进度 / 踩坑记录）
- 构建：改 `webui/index.html` → `webui/build_ui.ps1` → Ahk2Exe 编译（详见 doc/02）

## 🙏 致谢

- 蓝牙核心逻辑复用自 [ChromuSx/BluetoothDeviceConnector](https://github.com/ChromuSx/BluetoothDeviceConnector)（MIT）
- WebView2 承载使用 [thqby 的 WebView2-AHK 库](https://github.com/thqby/ahk2_lib)
- 降噪/通透切换基于 [librepods](https://github.com/librepods-org/librepods) 项目逆向发现的
  Apple AAP 协议规范（L2CAP 服务 `74ec2172-...` + 0x0D 监听模式指令）独立实现，
  感谢他们的开创性逆向工作 🙏（协议规范以事实引用，实现为本项目独立编写）
- 用爱发电 · 捞鱼 & 星星布丁 💕

## 📄 License

MIT

## 维护与验收

当前开发版 v1.9.19，尚未发布 GitHub Release；公开下载页仍按其已发布版本提供安装包。开发入口 [SKILL.md](SKILL.md)，审计清单 [doc/07-审计修复清单.md](doc/07-审计修复清单.md)。Windows 与 Mac 应用各有独立 CI，不把 Stream Deck helper 的构建当主应用验收。
