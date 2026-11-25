---
name: airpods-buddy-dev
description: AirPods 小助手持续开发、排障与发布交接入口。
---

# AirPods 小助手开发 Skill

AirPods 小助手帮助 Windows 用户从托盘管理已配对耳机，区分真实蓝牙链路与播放路由；Mac 菜单栏实验端独立维护。Windows 使用 AutoHotkey v2、WebView2、PowerShell/C# KS 后端与 Core Audio；Mac 使用 Swift。开发版及真实安装见 [doc/04-项目进度.md](doc/04-项目进度.md)，公开版本以 GitHub 正式 Release 为准。本次源码候选 **1.9.35**，公开 **1.9.24**；不把连接不稳定的真实失败改写为通过。

## 目录地图

- `airpods_buddy.ahk`：Windows 应用与 RPC、`APP_VERSION` 版本唯一字段。
- `lib/`：音频路由、隐私日志、后台作业、Agent 反馈窗口、WebView2。
- `scripts/`：KS 后端、事务构建/安装、更新与回滚；`tools/`：本机构建工具。
- `webui/`：页面和宠物，`build_ui.ps1` 内联图片并根据 APP_VERSION 生成三个 `*_built.html`。
- `assets/`：原创品牌图标及托盘三态；`assets/make_brand_tray_icons.py` 生成 16–256px 多尺寸 ICO。
- `tests/`：离线生产函数、UI、隐私及故障注入；`verification/`：验收证据（只上传脱敏回执）。`dist/`：临时构建，不提交仓库。
- `mac/`、`beta/`：平台与实验方案，不随 Windows 候选自动发布。
- `doc/README.md`：唯一文档导航；开发任何功能前先查对应模块文档。

## 开发、版本与部署

1. 读取 `AGENTS.md` 和 [doc/README.md](doc/README.md)，核对当前工作树、既有改动、实际进程和正式版；使用独立分支和明确提交范围，不覆盖其他平台或用户已有改动。
2. 修改完成后同步源码、受影响模块文档、版本字段、`CHANGELOG.md`、README；没有业务改动不虚增版本。页面构建先运行 `powershell -NoProfile -ExecutionPolicy Bypass -File webui/build_ui.ps1`。
3. 运行 `python tests/run_suite.py --output <私有临时结果目录>`。它不连接真机、不部署软件；`scripts/build-deploy.ps1` 可编译，`-Deploy -Destination <实际安装目录>` 在本机事务替换并校验健康回执。保留设置及旧 exe 回退。不要从共享目录 `dist` 推断用户当前版本；Windows 用 `Get-Process AirPodsBuddy` 获取实际 `Path`，从相邻 `logs/app-YYYY-MM-DD.log` 及安装 manifest 核对版本和哈希。
4. 更新相关改动先读 [doc/08-更新与后台任务.md](doc/08-更新与后台任务.md)：点击时绕过旧缓存重新查新、绑定同一平台版本制品并校验、失败留当前版、重启回读实际路径/version。每日节流不能替代点击查新。未公开开发版不能写入公网下载清单。
5. 正式 GitHub Release 先取得用户对该版本的明确授权；参见 doc/08。正式后同步独立产品页及两处下载、PAGE_VER、公开资产哈希。只发布 ZIP 不算闭环。品牌同步给软件中心及介绍页时，仅引用已经核实的正式版本；开发版单独标识并本机验收。

## 连接排障与日志

- 先区分 KS 请求回执、Classic 链路状态、播放端点状态、默认输出与实际听音。`HRESULT=0` 仅表示提交被接受。链路 1/0/-1；精确端点 0=不存在、1=ACTIVE、2=DISABLED、4=NOTPRESENT、8=UNPLUGGED、-1=未知。
- 同目标一次有界重试；链路重试期间链接已恢复不重复发送，音频端点未就绪仍可有界重试。新操作、取消或忙状态不能留下无限进度。用户可主动「重试播放连接」而不先断开；不自动抢占用户后来手选的输出。
- Windows 原生对照优先；若两条路线均失败，不能仅凭请求回执断定应用或驱动根因。不自动整机重置、清配对、改其他蓝牙设备；整机蓝牙关开仅限用户明确授权的一次性人工排障，绝不放入产品自动逻辑。
- 失败连接终态不能被轮询无条件覆盖；外部原生链接恢复后转换为音频待确认，而非宣告可播放或自动切换输出。反馈附日志时，后台可查询近24小时 BTHUSB Event ID 3 的至多20条计数和最近相对分钟，原始事件正文/设备标识不采集；无事件与访问失败分开，标明非根因。
- 日志统一 `LogMsg`：脱敏后进有界队列，批写、大小轮转、七天保留，错误不弹窗。设备地址、端点/容器、名字、路径、令牌均不写公开资料；反馈的日志选择必须尊重用户，未勾选不采。见 [doc/10](doc/10-诊断日志与隐私.md)。
- User feedback：仅在任务需要时读已授权本地缓存，先确认当前企业/数据范围；只摘取软件反馈群症状、阶段和安全错误码。原始缓存/联系方式/附件均不进 Git；文件传输占位不当日志正文。反馈通道由运行时 `feedback_webhook` 本地设置或 `AIRPODS_FEEDBACK_WEBHOOK` 环境变量提供，禁止在源码/构建资源中硬编码真实密钥；未配置则不读日志、不发送，用户可主动走 GitHub/复制反馈。

## 视觉与资源

暖黄米白玻璃设计，静态模糊，短合成动画，隐藏宠物停止计时。`headphones-49.webp` 、`headphones-fail-49.webp`、`headphones-wait-49.webp`、`headphones-idle-49.webp` 为独立 7×7 精灵表，128px 格、20fps：连接戴上、断开逆序摘下、失败检查耳机，等待和佩戴后待机循环，不可见时停止合成；终态由后端证据决定。对齐脚底 y119–120，中心 x63.04–64.62（128px 格）。整窗开盖采用根窗口透明色键、WebView2 透明背景与 CSS 后转轴视角；先验收批准的三态设计，再实机核对透明轮廓、设备列表、实际链接 LED、详情与反馈。无实际链接不能亮绿灯。图标与托盘、软件中心及介绍页同源；16/32px 检查；原始素材和来源登记由所有者本地维护，不上传私有路径。

## 当前验收入口

- Windows 连接与听音： [doc/09](doc/09-Windows连接方案选型.md)、[doc/11](doc/11-通话音频与麦克风.md)，一次人工实听成功；最新获准冷重连两次 KS 请求均接受但链路未建立，Windows 原生随后恢复。修复终态被轮询覆盖及外部恢复后播放重试缺失，预检实机通过；严格五轮尚未通过。
- 本机升级、反馈分析、UI/素材、隐私审计：[2026-11-25 维护记录](doc/maintenance-20261125.md)。
- 用户侧 Agent 指引：[AI_NATIVE.md](AI_NATIVE.md)；Agent 文本不代表已采集日志或获得 PR/系统操作授权。
- Mac 与独立 AAP 实验： [doc/06](doc/06-Mac版方案.md)，本地实验分支按自身 `doc/13-AAP实验版.md` 维护，不以 Windows 结果代替真机验收。
