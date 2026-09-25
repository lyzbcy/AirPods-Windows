# 交接 Prompt：AirPods 小助手（Windows 托盘工具）问题修复

> **历史交接（2026-09-25 22:36 更新）**：下述 v1.9.13/P0 待修描述已过期。P0 断开、宠物 Temp 恢复及自启动 Run 恢复已在 v1.9.14 修复并部署用户机；同用户上下文删除真实 Run 项后重启，日志证实自动重建。现状与验收见 `doc/04-项目进度.md` 和 `verification/2026-09-25/VERIFICATION.txt`；尚未发 GitHub Release。

> 把本文整段交给新 Agent 即可。它是自包含的：项目地图、已验证事实、问题清单、环境地雷、验收协议都在里面。

## 项目背景（30 秒了解）

「AirPods 小助手」：Windows 托盘工具（AutoHotkey v2 + WebView2，单 exe 免安装），一键连接/断开 AirPods，自带桌面宠物星星布丁、意见反馈直发企业微信群。MIT 开源，有真实存量用户。

**唯一开发仓库**：`E:\共享\创业\BluetoothDeviceConnector\`（Windows 与 Mac 共享，不要再建别的副本）
- 源码：`airpods_buddy.ahk`（主程序，1781 行，当前 v1.9.13）+ `webui\index.html`（前端，`webui\build_ui.ps1` 构建成内联版 index_built.html）
- 知识库：`doc\01-06`（**先读 doc/05 踩坑记录**，历代 Agent 用算力换来的）+ `AGENTS.md`（红线）
- 应用运行目录：`C:\Users\24676\Desktop\AirPodsBuddy\`（exe + `logs\` 日志，日志是排障第一现场）
- 编译：仓库根「编译并部署.bat」（或手动 Ahk2Exe，工具在 `tools\ahk2exe_stable\`）

## 已验证事实（2026-09-25 实测，引用自运行日志 logs\app-2026-09-25.log）

1. **运行中的 exe**：Desktop\AirPodsBuddy\AirPodsBuddy.exe（2026-09-22 编译，v1.9.13，源码约 3200+ 行）
2. **当前仓库源码只有 1781 行**——exe 编译后仓库被重构精简过，**exe 日志里的行号与当前源码不对应**，定位问题要以功能链路为准，不能按行号 grep
3. **反馈通道正常**：`issue sent: types=… file=1 ec=0 resp=ok`（文字+日志文件都直达企微群）
4. **横跳检测正常**：`flap detected: '余恩泽的AirPods Pro - Find My' x3/120s` 多次触发
5. **诚实连接正常**：`link NOT up after ~9s` / `audio endpoint NOT up` 如实报告

## 待修问题（按优先级）

### P0-1：断开链路 Unset 变量错误（功能性 bug）
日志：`rpc: disconnect 余恩泽的AirPods Pro - Find My` 之后立刻连续 5 条
`UnsetError @ *#1:3217/3218/3222/3224/3226 : This local variable has not been assigned a value.`（13:17、13:18 两次）
- 行号属于 exe 内嵌的旧源码（当前仓库只有 1781 行，对不上）
- 定位方法：错误紧跟 disconnect rpc，在当前源码的断开链路里找「一次声明/使用 5 个连续局部变量、且可能未赋值」的函数（嫌疑：disconnect 后的通知/状态更新/托盘刷新链路）；或从当前源码重新编译复现
- 修复后必须验证：断开一台已连接耳机，日志零 ERROR

### P0-2：宠物弹窗在 Temp 被清后死亡
日志：`pet html missing: C:\Users\24676\AppData\Local\Temp\AirPodsBuddy_app\pet_built.html`（多次）
- 根因：应用资源解包到 %TEMP%\AirPodsBuddy_app\ 只在启动时做一次；360/系统清理事后删掉 Temp 文件 → UI 已加载内存无恙，但宠物是按需加载 → 永久失效直到重启
- 修复：PetEnsure() 里检测 pet_built.html 缺失时**就地重新解包**（FileInstall 的资源已在 exe 内，重新触发解包逻辑即可），而非只报 WARN
- 验证：手动删 Temp 里那个文件 → 触发宠物 → 自动恢复

### P1-1：360 删除开机自启动（用户实测被删）
用户原话：「360 检查，竟然把我的开机自启动给我删了」
- 现状：应用有 StartupApproved 禁用检测（开关置灰+指路），但**没有「Run 键被整个删除」的检测**
- 修复：启动时若设置里 autostart=on 而 Run 键不存在 → 判定被外部删除 → 自动重建 + toast 告知（或先提示再自动，倾向自动+告知，用户已被骚扰够了）

### P1-2：连接抢占的用户痛点（调研+缓解，非纯代码）
用户原话（反馈原文在 09-25 日志 11:15 行，214 字）：重启、蓝牙开关都不行，最后**删除设备重新配对**才好；且重连后只回了麦克风音频、扬声器没自动切，还要手动去声音设置调。21:34 又发作：「耳机又抢不过来了」
- 已有：横跳检测（只提示）。用户需要的是**更强的恢复**：
  a) 连接成功后检测默认音频设备是否指向该耳机（含扬声器与麦克风两个端点），没指 → 界面提示一键切换（切换默认设备可用第三方 AudioDeviceCmdlets 思路或 nircmd，需调研许可与打包体积）
  b) 「修复连接」一键流程：断开→删除设备→重新枚举配对→连接→校验双端点（把用户手动做的那套自动化），入口放设备卡片长按/右键
- 先做调研笔记（doc/03），方案确认后再动代码

### P2（顺手）
- exe 内嵌源码与仓库不同步的问题：发版前必须从仓库当前源码编译（已是流程，强调）
- 弹窗标题在内部滚动时会滚出视野（打磨项）

## 环境地雷（每一条都踩过，别再踩）

1. **360 安全卫士**：主动防御 ZhuDongFangYu + 内核驱动**界面退出后仍驻留**。会：拦应用派生子进程联网（curl/powershell 全拦，浏览器引擎不拦——反馈主通道因此走 WebView2 fetch no-cors）、挂死 Ahk2Exe 编译器、删 Run 键、扫删工具目录、清 Temp。用户已把共享仓库加入信任区，但行为仍是间歇性的
2. **AI 沙箱里 AHK 解释器静默不执行**：连 FileAppend 冒烟都不出文件。运行时验证只能：编译 oracle（Ahk2Exe 退出码）+ 用户真机点一下 + 用 PS/.NET/curl 复刻同等逻辑
3. **bash heredoc 转义腐蚀源码**（doc/05 B8.5，五种形态一次全中：吞函数名首字母、\a→BEL、\v→VT、引号塌缩）。**给 AHK/PS 源码打补丁一律用 Write 工具写补丁脚本（raw string）+ 字节级断言替换**，写完必做三连：控制字符扫描（<0x20 且非 \t\r\n）+ 关键函数名/路径 grep + 编译 oracle
4. **github.com 直连间歇断**：push 失败挂后台每 90 秒重试即可，别死等
5. **红线**：任何错误不许弹窗到用户脸上（走日志）；发 GitHub Release 必须先征得用户同意；改完代码必须更新 doc/04 进度 + CHANGELOG.md

## 验收协议

1. 编译 oracle 通过（Ahk2Exe 4 秒内出包）
2. 源码控制字符扫描 = 0
3. 启动后观察运行日志（logs\app-当日.log）≥30 秒：零 ERROR
4. 每个修复项按上文「验证」条目真机走一遍
5. 更新 doc/04 + CHANGELOG，commit 信息写「为什么」
