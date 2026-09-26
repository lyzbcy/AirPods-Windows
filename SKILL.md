---
name: airpods-buddy-dev
description: AirPods 小助手接力开发入口
---

# AirPods 小助手开发入口

## 项目与技术栈
Windows 托盘工具采用 AutoHotkey v2 与 WebView2；Mac 菜单栏工具采用 Swift。

## 目录地图
`airpods_buddy.ahk` 是 Windows 主程序；`webui/` 是前端；`mac/` 是 Mac 版；`doc/` 是知识库；`tools/` 是本机构建工具。

## 文档索引
先读 `AGENTS.md`。Windows连接路线选型与“不影响用户”的验收门槛读 `doc/09-Windows连接方案选型.md`。当前审计修复读 `doc/07-审计修复清单.md`。Windows 开发读 `doc/02-架构与原理.md`；排障读 `doc/05-已知问题与踩坑记录.md`；进度读 `doc/04-项目进度.md`；技术方案读 `doc/03-技术方案.md`；Mac 开发读 `doc/06-Mac版方案.md`。

## 开发流程
只在本仓库改源码。Windows 先运行 `webui/build_ui.ps1`，再用 `tools/ahk2exe_stable/Ahk2Exe.exe` 编译。改代码后同步 `doc/04-项目进度.md` 与 `CHANGELOG.md`，核实日志与实际运行行为。

## 用户反馈取证
先看用户常驻目录 `C:\Users\24676\Desktop\AirPodsBuddy\logs\app-YYYY-MM-DD.log`。本机企业微信反馈可按 `E:\共享\工作\微盛\.agents\skills\lyzbcy-daily-note-summarizer\SKILL.md` 的缓存方法读取：先运行其 `scripts/wecom_chat_export.py --date YYYY-M-D --root E:\共享\工作\微盛`，再只看 `E:\共享\工作\微盛\每日笔记\wecom-cache\YYYY.M.DD.md` 中「软件反馈群」的相关消息。导出命令可能打印密钥，不复制到报告；缓存中的文件传输占位不是日志正文。以用户运行目录的原始日志交叉核对，不把无关群聊带入项目记录。

## 当前状态与版本
Windows 当前源码 v1.9.20（KS 后端候选）；Release 对照复测在关闭其他设备蓝牙后第2轮仍 link_failed，常驻安装版保持 v1.9.19，未发 Release；详情见 `verification/2026-09-26-release/VERIFICATION.txt`。全部审计代码项已有修改，硬件连续重连未达到验收门槛前不写“全部解决”。完整离线入口 `python tests/run_suite.py`；本轮 165 项通过。清单见 `doc/07-审计修复清单.md`，当前连接机制见 `doc/09-Windows连接方案选型.md`，更新/后台任务见 `doc/08-更新与后台任务.md`。Mac 首轮 CI 5 项单测及 release build 通过，真机另记。版本字段在 `airpods_buddy.ahk` 的 `APP_VERSION`。

## 红线
错误不弹窗；不要用测试脚本打扰用户桌面；GitHub Release 必须先获用户明确同意。完整协作与构建注意事项见 `AGENTS.md`。
