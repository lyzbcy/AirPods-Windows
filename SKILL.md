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
连接/断开进度最新安装候选（2026-09-27，15:49 已部署）：后端已按真实操作阶段提供 `progress`，前端已加入小宠物/圆形主按钮持续动画、阶段说明、第 N / M 步、已等待时间和当前阶段观察窗口（非整体完成倒计时或百分比），终态结果持留、连接中取消、断开中防重复点击及减少动态效果。完整离线 `OFFLINE_PASS assertions=364 suites=20`，460×600 连接/断开截图已检查。此前用户反馈只适用于 15:11 的旧候选，不是这次进度 UI 的真机验收；新安装 exe SHA256 `59F859CA5A4A9A27E18245FE3785919072A3848BDFA33383E816F7FC99202D3A`、本地 ZIP SHA256 `4E6AC4F14E7ADC8C95248FB4B9FAE2EEEC68974EB70421A24B9E4684EC009AC9`，15:49 正常启动与 navigation/list RPC 已读回。用户在新安装版一次真实连接后明确确认 Windows 默认输出从 AirPods 听到声音，Windows CI `36304899963` 已通过；历史五轮失败仍按已知问题披露。版本号维持 v1.9.20，发布资产以最终哈希回执和 GitHub Release 为准。实现见 `doc/02-架构与原理.md`，进度与证据见 `doc/04-项目进度.md`、`verification/2026-09-27-progress-frontend/`、`verification/2026-09-27-progress-backend/`。

P0 音频真相（2026-09-27，优先于下方旧候选记录）：用户在此前旧安装版默认输出清晰提示音时确认「完全没听到」，Windows 原生「测试」答复「完全没听到／系统报错」；即使链路已连、目标 render ACTIVE、三个默认输出角色指向耳机，也不能宣称可播放。独立 Core Audio 探针的目标端点 `IsFormatSupported(shared, mix)=0x88890008`，Realtek 对照为 `0x00000000`；根因未定。**候选工作树已实现**对精确目标 render 的无声格式支持与共享模式初始化预检，阴性不切默认、不标 `ready`/`audiook`、不补 KS；阳性只证明该预检通过，**不等于用户听音**。该候选离线 `OFFLINE_PASS assertions=337 suites=20`、AHK build-only 编译通过，已于 15:11 部署、15:12 经 explorer 正常启动（PID 47240；boot v1.9.20/navigation ok/list RPC），但尚无新候选耳机听音确认。Windows 版本号仍为 v1.9.20 候选，正式 Release 仍是草稿；当前 main/tag 与 GitHub 草稿资产仍属旧候选；新安装 exe SHA256 `080C6A1CA39D91D18BA444B3F363C8F3F4F4E7CB7306439B87F7719651725BEB`，本地新 ZIP SHA256 `024D1AE1709C3C497CB9A190DDFB223E85BDBCDDBAB395B7BE03C1AD83C0AFA3` 且内 exe 匹配。仍须更新远端资产、复验与用户实际听音，不沿用下方旧哈希或历史有声记录放行。证据见 `verification/2026-09-27-coreaudio-readonly/RESULT.txt`、`verification/2026-09-27-p0-audio-truth/VERIFICATION.txt` 与 `verification/2026-09-27-formal-release/`。

2026-09-27 发布政策更新：用户明确要求正式 Release 并写明偶发连接/无声已知问题；这不改变下述五轮失败事实。发布前需另行完成最终源码/ZIP/已安装 exe 一致性、真实默认输出听音与问题反馈入口、远端 CI，以及显式已知问题验收回执。若走 `scripts/release-precheck.py` 的已知问题接受路径，必须同时保留历史失败证据，不得伪造五轮通过。AirPods 5 只有口头反馈，尚无该型号真机验收；Classic 已配对设备仅扩大名称候选，LE-only 不在当前实现范围。首页页脚主反馈应附日志，轻意见仍在「关于捞鱼」。

Windows 源码 v1.9.20，分支 `fix/audit-20260926`，版本字段在 `airpods_buddy.ahk` 的 `APP_VERSION`。本机完整离线 `OFFLINE_PASS assertions=301 suites=20` 且 build-only 编译通过；最终安装版、远端 CI、ZIP 和正式 Release 状态按 `verification/2026-09-27-formal-release/` 的最新证据核对，不以旧候选哈希代替。严格真机五轮仍失败：`verification/2026-09-27-single5/` 的第 1 轮断开约 39.48 秒后 link=1、exit5，没有进入重连；之前的标准策略第 3 轮也曾 `audio_failed`。用户明确同意披露此问题后发正式版，但不能把该失败改写为通过。用户曾手动关开电脑蓝牙恢复 Windows 原生连接，应用未自动重置全局无线电。现有 AirPods 5 报告仅为口头转述，无准确设备名、日志或真机听音；本次仅扩大已配对 Classic 名称候选，不覆盖 LE-only。反馈页脚优先附日志，取消勾选时摘要和附件均不发送，轻意见仍在「关于捞鱼」。发布流程、手工恢复与已知问题回执见 `doc/08-更新与后台任务.md`、`RELEASE_NOTES_v1.9.20.md`；排障见 `doc/09-Windows连接方案选型.md`、`doc/07-审计修复清单.md`。Mac CI 5 项单测与 release build 通过，真机另记。

## 红线
错误不弹窗；不要用测试脚本打扰用户桌面；GitHub Release 必须先获用户明确同意。完整协作与构建注意事项见 `AGENTS.md`。
