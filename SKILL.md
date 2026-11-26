---
name: airpods-buddy-dev
description: AirPods 小助手的开发技能。当用户要开发、修改、排障、更新这款 Windows 蓝牙耳机管理软件，或准备发版、接入捞鱼软件中心时使用。
---

# AirPods 小助手 开发 Skill

## 项目一句话
AirPods 小助手帮助 Windows 用户从托盘一键连接已配对的蓝牙耳机，并如实区分「请求已提交 / 蓝牙链路 / 播放端点 / 默认输出 / 实际听音」五层证据；给不想装驱动、不想折腾系统设置的普通用户用。Mac 菜单栏实验端独立维护，不随 Windows 发版。

## 技术栈
- 宿主：AutoHotkey v2（x64，`tools/ahk_v2_portable`）→ Ahk2Exe 1.1.36.02f（`tools/ahk2exe_stable`）→ 单文件 exe。
- 界面：WebView2（系统 Evergreen）+ 原生 HTML/CSS/JS，无框架；`webui/build_ui.ps1` 内联图片生成四个 `*_built.html`，`FileInstall` 内嵌，虚拟主机映射加载。
- 蓝牙/音频：PowerShell 5.1 子进程里运行时编译 C#（`scripts/KsBluetooth.cs`：MMDevice 拓扑 + KS `KSPROPERTY_ONESHOT_RECONNECT/DISCONNECT`）+ Core Audio（`lib/AudioRouting.ahk`）。不装驱动、不要管理员。
- 更新：`scripts/UpdateCore.psm1`（Release 元数据、SHA-256、原子替换、健康检查、回滚）。
- 测试：Python 驱动的离线套件 `tests/run_suite.py`（.py / .ps1 / .ahk / .cjs）。
- 独立实验室：`beta/`（.NET 8 WinForms，自包含）。Mac：Swift（`mac/`）。

## 目录地图
- `airpods_buddy.ahk`：Windows 主程序——托盘、窗口、RPC、每设备状态机、设置；`APP_VERSION` 是版本唯一字段。
- `lib/`：`AudioRouting.ahk`（默认设备路由）、`Diagnostics.ahk`（脱敏日志、设备发现、导出）、`BackgroundJobs.ahk`（子进程作业）、`AgentHelp.ahk`（Agent 并排窗口）、`TrayPopup.ahk`（托盘快捷弹层）、`WebView2/`、`Promise.ahk`、`ComVar.ahk`。
- `scripts/`：`KsBluetooth.cs/.psm1`（KS 后端）、`background-worker.ps1`（阻塞调用子进程）、`UpdateCore.psm1` + `update-swap.ps1`（更新事务）、`RepairCore.psm1`（端点只读诊断与显式修复）、`build-deploy.ps1`（构建 / 事务部署）、`ui_fixture_shots.py`（无头截图核对排版）、`package-windows-release.py`（发布打包校验）、`release-precheck.py` / `strict_gate.py`（发版门禁）、`release_downloads.py`（下载趋势）。
- `webui/`：`index.html`（整窗开盒 UI）、`pet.html`（右下角小精灵）、`tray.html`（托盘弹层）、`agent.html`（Agent 窗口）、`assets/`。
- `assets/`：`airpods-brand.png/.ico`（程序、窗口、托盘同源图标）、`brand-tray-*.ico`、`make_brand_tray_icons.py`、`align_pet_sheets.py`。
- `tests/`：离线套件。`verification/`：本机原始验收证据，不提交，只上传脱敏回执。
- `docs/`：知识库，先读 `docs/agent.md`。`reference/`：深度资料（`history/`、`maintenance/`、`design/`、`verification/`）。
- `beta/`：独立 AAP 控制实验室。`mac/`：Mac 实验端。`streamdeck-plugin/`：继承自上游，不随主程序验收。
- `tools/`：本机构建工具（不入库）。`dist/`：临时构建，只保留最新两个 `build-*` 与正式版归档，不入库。
- 根文件：`AGENTS.md`（协作入口）、`AI_NATIVE.md`、`CHANGELOG.md`、`HANDOFF.md`、`README.md`、`launcher-adapter.json`（软件中心适配描述）、`THIRD_PARTY_NOTICES.md`、`RELEASE_NOTES_*.md`、`AirPods小助手.bat` / `诊断模式.bat`（从源码启动）、`修复耳机无声.bat`（定点修复工具）。

## docs 索引
[docs/agent.md](docs/agent.md) 是唯一导航入口，列出每份文档的主题和「什么情况下该读它」。开发任何功能前先查对应模块文档；模块文档头部三行摘要是现状、负责人、最后更新时间。

## 开发约定
1. 开工顺序：`AGENTS.md` → 本 Skill → `docs/agent.md` → `docs/roadmap.md` → 对应模块文档。
2. 核对现状：`git status` 看既有改动；用 `Get-Process AirPodsBuddy` 取实际 `Path`，再从同目录 `build-manifest.json`、exe 哈希和 `logs/app-YYYY-MM-DD.log` 确认运行版本。不要预设某台机器的安装路径，不要从 `dist` 推断用户当前版本。
3. 多会话协作：同一工作树可能有另一个 Agent 会话在同时改（2026-11-25 实际发生过）。动手前看最近修改时间，不覆盖别人的改动；Windows 与 Mac 不要同时改同一文件。
4. 分支与提交：开发在 `dev/*`；`main` 只随正式 Release 前进；`release/vX.Y.Z` 分支和 tag 对应正式版精确源码，不用当前工作树重打旧正式资产。提交信息用 `feat:` / `fix:` / `docs:` / `release:` 前缀并带 `[skip ci]`——发版优先本机构建，不走 Action。
5. 日志：统一走 `LogMsg`——脱敏后进有界队列，批写、大小轮转、七天保留，错误只写日志不弹窗；默认只记操作摘要，排障模式才记详细；链路变化日志中的 lastLocalAction/Phase 只表示该进程最后已知操作上下文，不是回连来源。操作状态切换统一走 SetOpState；已核实断开后的再次连接观察只提示、不自动干预。用户侧用小精灵和进度面板说明程序在干什么（第 N / M 步，不编造百分比）。
6. 测试与构建：`python tests/run_suite.py --output <私有临时结果目录>`，串行、低负载、不连真机。页面改动后先跑 `powershell -NoProfile -ExecutionPolicy Bypass -File webui/build_ui.ps1`，再用 `python scripts/ui_fixture_shots.py --output <仓库外目录> --poster` 无头截图看排版（离线测试只管逻辑，不管布局；`--poster` 额外导出降噪说明的分享长图），然后 `scripts/build-deploy.ps1`；加 `-Deploy -Destination <实际安装目录>` 才替换本机安装（事务替换 + 健康回执 + 保留回退）。夜间不默认替换用户正在运行的安装。bat 文件保持 CRLF 与纯 ASCII。
7. 文档同生命周期：改设计必须同步模块文档、`CHANGELOG.md`、`docs/roadmap.md`；单份文档超过 300 行就拆；进度和待办只写在 `docs/roadmap.md`。
8. 隐私：设备地址、端点/容器、名字、路径、令牌、密钥都不进公开资料和远端；原始日志、聊天缓存、用户截图留在受控本机。仓库是公开的：`AGENTS.md` 在远端只是一份简短的英文协作指南，工作区里的完整版含所有者的内部工作说明，提交前运行 `python scripts/stage_public_agents.py`，不要让 `git add -A` 把工作区版本带上去。

## 版本号规则
- 唯一版本字段是 `airpods_buddy.ahk` 的 `APP_VERSION := "x.y.z"`。独立实验室版本在 `beta/AirPodsBuddy.Beta/*.csproj`，Mac 在 `mac/`，互不联动。
- 开发完成 = 代码 + 文档 + 版本号三者同步；有业务行为改动才递增 patch，只改文档不抬版本、不构建、不替换安装。
- `build_ui.ps1` 把版本烙进页面，`build-manifest.json` 记录全部输入哈希与 exe 哈希；打包脚本拒绝与当前源码不一致的构建。
- 版本号变化和 Git 推送本身不会让客户端发现新版。正式发版需要 Release 资产和更新元数据，流程见 [docs/08](docs/08-更新与后台任务.md)。

## 红线
1. GitHub Release 必须先取得用户对该版本的明确同意；某版的同意不延续到下一版。已知问题接受路径要保留失败事实，绝不把严格五轮写成通过。
2. 不自动重置整机蓝牙、不清配对、不切换其他设备；不安装内核驱动、不接管适配器、不降低系统保护。
3. 更新器（`UpdateCore.psm1`、`update-swap.ps1`）是红线级改动：必须单独补 `tests/update_health_test.ps1` 的隔离夹具测试并记录回滚证据。
4. 反馈通道由运行时本机设置 `feedback_webhook` 或环境变量 `AIRPODS_FEEDBACK_WEBHOOK` 提供；禁止在源码或构建资源里硬编码真实密钥，未配置就不读日志、不发送。
5. 不把 GPL 实现（AirPodsDesktop、AirPodsWindows、NTPods、WPods、SoundStage、LibrePods）并入 MIT 主程序，只依据公开协议事实独立实现。
6. 用户机桌面测试要克制：工作日 9:00–18:30 优先离线 / 无头，不用自动化脚本反复弹窗打扰；真机断开重连、录音会话都要先取得当次授权。
7. Release 之后必须同步独立产品页、软件中心和介绍页并从公网回读，只上线 ZIP 不算闭环。

## 视觉与设计
规范和改版自查在 [docs/16](docs/16-视觉与设计规范.md)。新设计先用生图模型出稿，所有者批准后再还原；静态分享图导出须显式关闭入场动画并核对五站卡片可见；页面改完用 `scripts/ui_fixture_shots.py` 和 `scripts/ui_geometry_check.py`（后者需要 Playwright） 无头截图自检，离线测试只管逻辑。主窗口 560×580 整窗开盒；合盒右侧仅品牌 Logo 与居中连接按钮，无滚动，状态详情只在开盒出现；盒盖拖动、右下手柄等比缩放，小精灵是四张 7×7 精灵表并按脚底对齐，托盘右键默认原生快速菜单，美化菜单按需打开，1.9.46 为原生主题 GUI（避免第二 WebView 参数异常），图标同源并在 16/32px 检查。真实桌面截图不进仓库。
进行中的设计任务放在 `reference/design/`，每项带一份接手简报。已还原、待真机核对：降噪说明一图流，见 [简报](reference/design/noise-explainer-brief.md)。

## 功能现状与验收入口

| 能力 | 状态 | 代码 / 文档 | 验证 |
|---|---|---|---|
| 一键连接（KS） | 已实现；AirPods 冷连接在通用 USB 适配器上 4 次成功（独立实验 1 次 + 已安装产品 3 次），用户实听确认 1 次。1.9.41 复测两轮完整通过，第 3 轮失败；其他型号未验收 | `scripts/KsBluetooth.cs`、[docs/09](docs/09-Windows连接方案选型.md) | `tests/ks_backend_test.ps1`、`tests/ks_retry_behavior.py` |
| 通话与麦克风 | 部分实现：默认不切麦、通话中不做播放探测；10 秒真机录音会话验证 1 次。长时通话、多应用争用未验收 | `lib/AudioRouting.ahk`、[docs/11](docs/11-通话音频与麦克风.md) | `tests/call_audio_test.py` |
| 降噪 / 通透 / 自适应 | 未实现。调研确认 Windows 微软蓝牙栈的用户态打不开 AAP 的 L2CAP 通道，所有竞品都靠内核驱动；实验室只有协议与 UI 门控 | `beta/`、[docs/13](docs/13-AAP实验版.md)、[docs/14](docs/14-竞品对标与高级能力路线.md) | `dotnet run --project beta/tests -c Release`（3115 项） |
| 高音质耳机麦 | 未实现；需要内核驱动 + 虚拟麦克风 + AAC-ELD 解码 | [docs/14](docs/14-竞品对标与高级能力路线.md) | — |
| 自动更新 | 已实现：每日首次查新、点击强制查新、绑定目标、SHA-256、事务替换、健康回执、失败回退；新版确认后只留最近几份回退（1.9.39 起，尚待真实升级验收） | `scripts/UpdateCore.psm1`、[docs/08](docs/08-更新与后台任务.md) | `tests/update_health_test.ps1`（8 项） |
| 日志与排障模式 | 已实现：队列、批写、轮转、七天、脱敏、详细开关 | `lib/Diagnostics.ahk`、[docs/10](docs/10-诊断日志与隐私.md) | `tests/diagnostics_test.py`、`tests/standards_logging_test.py` |
| 反馈 | 已实现：企业微信机器人直发文本 + 日志附件，用户勾选才附日志；未配置通道时走 GitHub / 复制。「遇到问题反馈」是主窗口左栏、失败面板和托盘菜单里的一级入口 | `airpods_buddy.ahk`、`webui/index.html`、`webui/tray.html` | `tests/feedback_consent_test.py`、`tests/rpc_test.cjs`、`tests/tray_popup_test.cjs` |
| 求好评 | 已实现：第 10 次成功连接触发，之后每 50 次；关闭后 15 天内不再弹 | `airpods_buddy.ahk` | `tests/run_behavior.py`（7 项） |
| 界面 / 小精灵 / 托盘 | 已实现：整窗开盒、四套 7×7 精灵、托盘快捷弹层与悬浮卡 | `webui/`、`lib/TrayPopup.ahk` | `tests/rpc_test.cjs`、`tests/pet_popup_test.cjs`、`tests/tray_popup_test.cjs` |
| AI-Native | 已实现：Agent 并排窗口与接口说明 | `AI_NATIVE.md`、`webui/agent.html` | `tests/agent_help_test.cjs` |
| 软件中心适配 | 产品 ID `airpods-buddy`、便携 ZIP；描述文件在根目录。权威软件中心工程严格自查 36 项通过；无关联自动探测不覆盖受管便携目录；生产路径解析现有关联通过，运行版本与哈希一致 | `launcher-adapter.json` | 启动器适配 Skill 的 `check_adapter.py --strict` |
| Mac 菜单栏版 | 实验端，独立 CI | `mac/`、[docs/06](docs/06-Mac版方案.md) | 真机另验 |

未完成项：严格五轮冷连接与更多型号；长时通话稳定性；AAP 控制（等可信的已签名驱动通道）；高音质耳机麦；更新器的镜像下载线路；软件中心自动探测安装；公开发版需当次授权。

## 当前状态
- 版本：源码 **1.9.49**（已构建），本机运行 **1.9.49**，公开正式 **1.9.24**，实验室 **1.10.0-beta.3** ｜ 进度与待办详见 [docs/roadmap.md](docs/roadmap.md)，最近一轮见 [1.9.49 维护记录](reference/maintenance/maintenance-20261126-reappearance.md)。
