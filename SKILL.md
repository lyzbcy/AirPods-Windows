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
2026-09-27 发布政策更新：用户明确要求正式 Release 并写明偶发连接/无声已知问题；这不改变下述五轮失败事实。发布前需另行完成最终源码/ZIP/已安装 exe 一致性、真实默认输出听音与问题反馈入口、远端 CI，以及显式已知问题验收回执。若走 `scripts/release-precheck.py` 的已知问题接受路径，必须同时保留历史失败证据，不得伪造五轮通过。AirPods 5 只有口头反馈，尚无该型号真机验收；Classic 已配对设备仅扩大名称候选，LE-only 不在当前实现范围。首页页脚主反馈应附日志，轻意见仍在「关于捞鱼」。

Windows 源码 v1.9.20，分支 `fix/audit-20260926`，版本字段在 `airpods_buddy.ahk` 的 `APP_VERSION`。本机完整离线 `OFFLINE_PASS assertions=301 suites=20` 且 build-only 编译通过；最终安装版、远端 CI、ZIP 和正式 Release 状态按 `verification/2026-09-27-formal-release/` 的最新证据核对，不以旧候选哈希代替。严格真机五轮仍失败：`verification/2026-09-27-single5/` 的第 1 轮断开约 39.48 秒后 link=1、exit5，没有进入重连；之前的标准策略第 3 轮也曾 `audio_failed`。用户明确同意披露此问题后发正式版，但不能把该失败改写为通过。用户曾手动关开电脑蓝牙恢复 Windows 原生连接，应用未自动重置全局无线电。现有 AirPods 5 报告仅为口头转述，无准确设备名、日志或真机听音；本次仅扩大已配对 Classic 名称候选，不覆盖 LE-only。反馈页脚优先附日志，取消勾选时摘要和附件均不发送，轻意见仍在「关于捞鱼」。发布流程、手工恢复与已知问题回执见 `doc/08-更新与后台任务.md`、`RELEASE_NOTES_v1.9.20.md`；排障见 `doc/09-Windows连接方案选型.md`、`doc/07-审计修复清单.md`。Mac CI 5 项单测与 release build 通过，真机另记。

## 红线
错误不弹窗；不要用测试脚本打扰用户桌面；GitHub Release 必须先获用户明确同意。完整协作与构建注意事项见 `AGENTS.md`。
