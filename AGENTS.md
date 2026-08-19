# AGENTS.md · 接力开发入口（给任何 AI Agent / 新协作者）

> **你是刚接手的 Agent？只读这一页 + 按需跳转 doc/，不要盲目翻代码。**
> 本项目采用"渐进式披露"：入口 → 索引 → 按需深读，避免浪费上下文。

## 30 秒了解项目

- **是什么**：AirPods 小助手（AirPodsBuddy）——Windows/Mac 桌面小工具，
  一键连接 AirPods、常驻托盘/菜单栏、纯本地零上传
- **仓库布局**：
  - `airpods_buddy.ahk` — Windows 主程序（AHK v2 + WebView2）
  - `webui/` — 共享前端（index.html 源码 / index_built.html 构建产物）
  - `mac/AirPodsBuddyMac/` — Mac 版（Swift 菜单栏应用，**待首次编译**）
  - `doc/` — 知识库（**必读**，见下）
  - `tools/` — 构建工具（gitignore，下载方式见 doc/02 §7）
- **当前版本**：Windows v1.3.1（已部署可用）；Mac v0.1 脚手架（未编译）

## 必读文档（按角色）

| 你要做什么 | 先读 |
|---|---|
| 任何开发前的共识 | `doc/01-初心与使命.md`（为什么做、为谁做） |
| **Mac 端继续开发** | `doc/06-Mac版方案.md`（看门狗机制 + 构建风险点 + 测试清单） |
| 改 Windows 端 | `doc/02-架构与原理.md`（模块原理 + 编译部署全流程） |
| 调试任何问题 | `doc/05-已知问题与踩坑记录.md`（**先读再动手**，能省你两小时） |
| 了解进度/待办 | `doc/04-项目进度.md`（改完代码请更新它） |

## Mac 端 Agent 的第一步（当前最优先任务）

```bash
cd mac/AirPodsBuddyMac
swift build -c release        # 需要 macOS 13+ 和 Xcode CLT
.build/release/AirPodsBuddyMac
```

1. 修到编译通过（三个预判风险点在 doc/06「构建状态与坑」）
2. 按 doc/06「测试清单」真机验证（连接/左键切换/看门狗抗 iPhone 抢走/输出锁定）
3. 验证通过后：更新 doc/04 进度，参照 doc/02 §7 的精神给 Mac 补构建文档
4. Windows 的坑对 Mac 多数不适用，但 doc/05 的 B 节（验证方法论）通用

## 红线（历代 Agent 用算力换来的）

1. **错误不许弹窗到用户脸上**——Windows 走日志系统（doc/02 §5），
   Mac 走 `~/Library/Logs/AirPodsBuddyMac.log`
2. **改完必须更新** `doc/04-项目进度.md` 和 `CHANGELOG.md`
3. **在用户桌面上跑测试脚本要极其克制**（历史事故：弹窗轰炸用户）
4. 提交信息写清楚"为什么"；不确定的决策记到 doc/04 待办里问用户

## 快速事实

- Windows 构建：Ahk2Exe 必须从仓库根目录、`Start-Process` 分离启动
  （直接 bash 调用会静默失败，见 doc/05 坑 B1）
- 本机安全软件会间歇性删 .ps1/.ahk 文件——重要脚本必须进 git
- 用户设备：Windows 开发机 + MacBook（通过 E:\共享 同步此仓库）

## 双机协作规矩（Windows ↔ Mac 经共享文件夹）

- ⚠️ **不要直接运行共享文件夹里的 dist\AirPodsBuddy.exe**——dist 在
  gitignore 里，同步不保证最新（2026-08-19 事故：用户跑了共享目录里的
  v1.3.1 旧 exe，抱怨"图标不更新"，其实 v1.4.0 部署在 AppData 没被运行）。
  Windows 上正确入口 = 桌面快捷方式（指向
  `%LOCALAPPDATA%\BluetoothDeviceConnector\AirPodsBuddy.exe`）。
  判断跑的是哪个：看日志 boot 行的 scriptdir。

- 本文件夹是**含 .git 的完整仓库副本**（E:\共享\创业\BluetoothDeviceConnector）
- **在 Mac 上开工前**：`git pull --rebase origin main`（拿远端最新）
- **在 Mac 上提交后**：`git push origin main`；提醒用户回 Windows 时也 `git pull`
- 两台机器**不要同时改同一文件后各自提交**——会冲突
- Windows 侧的正主仓库在 `E:\github\BluetoothDeviceConnector`（构建/发版在这边做）
