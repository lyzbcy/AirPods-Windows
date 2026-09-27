---
name: airpods-buddy-dev
description: AirPods 小助手接力开发入口
---

# AirPods 小助手开发入口

AirPods 小助手是 Windows 托盘与 Mac 菜单栏应用。Windows 用 AutoHotkey v2 + WebView2，Mac 用 Swift；本仓库是两端唯一开发仓库。

## 先看哪里

- `AGENTS.md`：协作红线与本机部署约定；`doc/README.md`：按任务选择文档，不要一次读完整个 `doc/`。
- `airpods_buddy.ahk`：Windows 主程序，`APP_VERSION` 是源码版本字段；`webui/`：页面及小精灵；`mac/`：Mac 端；`tools/`：本机构建工具。
- `doc/04-项目进度.md` **顶部最新条目**：当前进度与待办的项目内唯一入口；下方按时间排列的“候选／草稿／阻断”均是当时快照，不代表现状。模块实现与排障再按 `doc/README.md` 跳转。原始测试和发布回执保存在 `verification/`，不要把历史哈希抄成当前资产。

## 当前版本

工作树 `APP_VERSION = 1.9.21`；v1.9.21 已于 2026-09-27 正式发布为 [GitHub Latest Release](https://github.com/lyzbcy/AirPods-Windows/releases/tag/v1.9.21)，[产品页](https://lyzbcy.github.io/airpods-buddy.html)也已同步。偶发连接／无声与严格五轮失败仍按已知问题披露，不得改写为通过。当前资产、验收边界与官网部署以 `verification/2026-09-27-v1921-release/` 及 `doc/04-项目进度.md` 顶部记录核对；后续开发不自动等于已部署或已发布。

## 修改与发布

开发前按 `doc/README.md` 读对应模块。Windows 页面改动先运行 `webui/build_ui.ps1`，编译步骤见 `doc/02-架构与原理.md`；按改动层级验证，不以离线测试代替真机听音。改代码后同步 `doc/04-项目进度.md`、`CHANGELOG.md` 与版本字段/发布说明的适用状态，避免候选与正式版混写。

**GitHub Release 必须先得到用户对该版本的明确同意。**发版门槛、已知问题接受路径与回执见 `doc/08-更新与后台任务.md`。正式 Release 后还须同步公开产品页 https://lyzbcy.github.io/airpods-buddy.html，其源码位于独立网站仓库 `lyzbcy/lyzbcy.github.io` 的 `main/airpods-buddy.html`：更新版本/日期、两处下载地址、日志及已知问题，递增 `PAGE_VER`；等待 `pages-deploy.yml` 发布，再从公网页面无缓存读回并核对 Release 资产 SHA256。把部署 run、公网页面和资产核对记入发布证据；公网未更新则发版未闭环。

## 用户反馈取证

优先读用户常驻目录 `C:\Users\24676\Desktop\AirPodsBuddy\logs\app-YYYY-MM-DD.log`。本机企业微信反馈按 `E:\共享\工作\微盛\.agents\skills\lyzbcy-daily-note-summarizer\SKILL.md` 的缓存方法：运行 `scripts/wecom_chat_export.py --date YYYY-M-D --root E:\共享\工作\微盛`，再只读 `E:\共享\工作\微盛\每日笔记\wecom-cache\YYYY.M.DD.md` 的「软件反馈群」相关消息。导出命令可能打印密钥，不复制到报告；文件传输占位不是日志正文。用原始应用日志交叉核对。

## 红线

错误不弹窗；不要用测试脚本打扰用户桌面；不自动重置整机蓝牙。完整协作与本机启动注意事项见 `AGENTS.md`。
