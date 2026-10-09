# AirPods 小助手 · 协作入口

先读项目根 SKILL.md，再由 doc/README.md 按任务进入模块文档；不要把历史候选快照当作当前部署状态。

## 30 秒定位

| 项目 | 入口 |
|---|---|
| Windows 主程序 / 页面 | airpods_buddy.ahk（AHK v2 + WebView2）/ webui/ |
| Mac 菜单栏版 | mac/AirPodsBuddyMac/；构建与真机边界见 doc/06-Mac版方案.md |
| 当前状态 / 历史 | doc/04-项目进度.md 顶部为现状，下方日期标题是当时快照 |
| Windows 架构 / 排障 | doc/02-架构与原理.md / doc/05-已知问题与踩坑记录.md |
| 连接验收 / 发布事务 | doc/09-Windows连接方案选型.md / doc/08-更新与后台任务.md |

Windows 源码版本字段是 airpods_buddy.ahk 的 APP_VERSION；工作树 v1.9.23 是未部署、未发布的隐私诊断与通话音频修复候选，v1.9.21 为已发布版且官网已同步。诊断边界见 doc/10-诊断日志与隐私.md；切麦行为与反馈验收见 doc/11-通话音频与麦克风.md。偶发连接或无声、严格五轮失败仍按已知问题披露。现状、Release 资产和证据以 SKILL.md 指向的当前入口核对。应用源码在本仓库维护；产品页源码在独立的 lyzbcy/lyzbcy.github.io 仓库。

## 开发红线

1. 错误写日志，不向用户弹窗（Windows 见 doc/02，Mac 写 ~/Library/Logs/AirPodsBuddyMac.log）；用户机桌面测试要克制，不用自动化脚本反复打扰。
2. 修改代码后同步 doc/04-项目进度.md 和 CHANGELOG.md，核对 APP_VERSION 与发布状态；源码提交、离线通过、真实安装、用户听音和公开 Release 是不同证据层级。
3. GitHub Release 先取得用户对**该版本**的明确同意。v1.9.20 的同意不自动授权后续版本；已知问题接受路径保留失败事实，绝不伪造五轮通过。
4. Release 发布后必须按 doc/08-更新与后台任务.md 同步独立产品页、递增 PAGE_VER，等待 Pages 部署并从公网核对两处下载链接、已知问题和资产 SHA256；只上线 ZIP 不算闭环。
5. 不自动重置整机蓝牙、清除用户配对或切换其他设备；更新器改动须单独记录测试与回滚证据。

## 本机与双机约定

- 唯一开发仓库是 E:\共享\创业\BluetoothDeviceConnector；E:\github\BluetoothDeviceConnector 为历史副本。Windows 与 Mac 不要同时改同一文件。Mac 开工前拉取、提交后推送并通知另一端同步。
- 用户常驻安装目录是 C:\Users\24676\Desktop\AirPodsBuddy\；不要从共享目录的 dist\AirPodsBuddy.exe 判断当前运行版本。以常驻目录 exe 哈希及启动日志 scriptdir 核对。旧 %LOCALAPPDATA%\BluetoothDeviceConnector\ 安装位置不再使用。
- Windows 构建工具与命令见 doc/02-架构与原理.md；沙箱 shell 直接启动应用可能带受限令牌，用户侧启动需经 explorer.exe <path> 或由用户启动。构建 bat 保持 CRLF 与纯 ASCII；本机安全软件可能拦写/删脚本，先核对 Git 状态。
- 用户反馈日志与企业微信缓存读取规则在根 SKILL.md；只把相关反馈和原始日志证据写入项目记录。
