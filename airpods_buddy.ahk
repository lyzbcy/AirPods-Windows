#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent   ; 常驻托盘：关闭窗口 = 缩到托盘，程序继续运行（开机自启依赖此行为）

; =====================================================================
;  AirPods Buddy v1.2 - 米白简约风 AirPods 管理小助手
;  UI: HTML/CSS via WebView2 (webui/index.html)
;  Core connect/disconnect logic from ChromuSx/BluetoothDeviceConnector (MIT)
; =====================================================================
#Include lib\WebView2\WebView2.ahk
#Include lib\AudioRouting.ahk
#Include lib\BackgroundJobs.ahk

; ------------------------- Config ------------------------------------
APP_VERSION   := "1.9.19"
UPDATE_API    := "https://api.github.com/repos/lyzbcy/AirPods-Windows/releases/latest"
RELEASE_PAGE  := "https://github.com/lyzbcy/AirPods-Windows/releases/latest"
; 微软官方 Evergreen Bootstrapper 直链（约 2MB，缺失运行时时的自愈安装器）
WEBVIEW2_SETUP_URL := "https://go.microsoft.com/fwlink/p/?LinkId=2124703"

deviceOps := Map()   ; per-device generations: bulk disconnects do not cancel each other
operationSerial := 0
routeOwner := 0       ; only the latest connect request may change system defaults
connectCount := 0
RUN_KEY   := "Software\Microsoft\Windows\CurrentVersion\Run"
RUN_NAME  := "AirPodsBuddy"
backgroundJobs := []
OnExit(StopBackgroundJobs)
updateBusy := false
feedbackBusy := false
audioProfile := "a2dp-hfp"
maxRetries := 10
SEP := Chr(31)
; 链路连续失败计数与蓝牙自救状态（v1.9.11）：栈卡死时 API 全 ok 但链路
; 永远起不来，重启 App 无效、重启无线电/电脑才有效（2026-09-21 反馈实测）

; ------------------------- Logging system ----------------------------
; 日志统一写入 <脚本目录>\logs\app-YYYYMMDD.log，保留 7 天。
; 日志写入本身永不抛错（全部 try 保护），避免"为了记日志反而弹窗"。
LOG_DIR := A_ScriptDir "\logs"

LogMsg(msg, level := "INFO") {
    global LOG_DIR
    line := Format("[{}] [{}] {}`r`n", FormatTime(, "yyyy-MM-dd HH:mm:ss"), level, msg)
    path := LOG_DIR "\app-" FormatTime(, "yyyy-MM-dd") ".log"
    ; 三级回退：本机安全软件可能间歇性拦截文件写入（0x800704C7），
    ; 日志系统绝不允许自己把程序搞挂。
    try {
        DirCreate(LOG_DIR)
        FileAppend(line, path, "UTF-8")
        return
    }
    try FileAppend(line, path)                       ; CP0 兜底
    catch
        DllCall("OutputDebugString", "str", "AirPodsBuddy " line)   ; 最后手段，永不失败
}

; 全局错误拦截：任何未捕获错误写入日志而不是弹出 AHK 报错对话框。
; 返回 -1 = 静默结束当前线程（不再弹窗）。
OnErrorHandler(err, mode) {
    try LogMsg(Type(err) " @ " (err.HasOwnProp("File") ? err.File : "?") ":" err.Line (err.What ? " in " err.What : "") " : " err.Message, "ERROR")
    return -1
}
OnError(OnErrorHandler)

CleanOldLogs() {
    global LOG_DIR
    try {
        cutoff := DateAdd(A_Now, -7, "days")
        loop files, LOG_DIR "\app-*.log"
        {
            if (A_LoopFileTimeModified < cutoff)
                FileDelete(A_LoopFileFullPath)
        }
    }
}
CleanOldLogs()
CleanManagedTemp()

; ------------------------- Device priority ---------------------------
; 用户自定义的"一键连接"优先顺序（每行一个设备名），Apple 设备默认排前。
SETTINGS_PATH := A_ScriptDir "\app_settings.ini"
PRIO_PATH := A_ScriptDir "\device_priority.txt"
priorityList := []
LoadPriority()

LoadPriority() {
    global PRIO_PATH, priorityList
    priorityList := []
    try {
        if FileExist(PRIO_PATH) {
            txt := FileRead(PRIO_PATH, "UTF-8")
            for line in StrSplit(StrReplace(txt, "`r`n", "`n"), "`n") {
                if (Trim(line) != "")
                    priorityList.Push(line)
            }
        }
    }
}

SavePriority() {
    global PRIO_PATH, priorityList
    return AtomicWriteText(PRIO_PATH, Join(priorityList, "`n") "`n")
}


Join(arr, sep) {
    out := ""
    for i, v in arr {
        if (i > 1)
            out .= sep
        out .= v
    }
    return out
}

IsAppleDevice(name) {
    n := StrLower(name)
    return InStr(n, "airpods") || InStr(n, "beats")
}

; 排序键：用户优先级序号（未设置=999）→ Apple 家族优先 → 名称
DeviceSortKey(dev) {
    global priorityList
    n := StrLower(dev.name)
    for i, pn in priorityList {
        if (StrLower(pn) = StrLower(DeviceKey(dev)) || StrLower(pn) = n)
            return i
    }
    return 999
}

DevLess(a, b) {
    ka := DeviceSortKey(a), kb := DeviceSortKey(b)
    if (ka != kb)
        return ka < kb
    aa := IsAppleDevice(a.name), ab := IsAppleDevice(b.name)
    if (aa != ab)
        return aa
    return StrCompare(StrLower(a.name), StrLower(b.name)) < 0
}

SortDevices() {
    global devices
    n := devices.Length
    if (n < 2)
        return
    loop n - 1 {
        i := A_Index + 1
        key := devices[i]
        j := i - 1
        while (j >= 1 && DevLess(key, devices[j])) {
            devices[j + 1] := devices[j]
            j--
        }
        devices[j + 1] := key
    }
}

; ------------------------- Resources ---------------------------------
; compiled: extract the self-contained web UI + loader dll to temp
appRoot := A_ScriptDir
uiHtml := A_ScriptDir "\webui\index_built.html"
wvDll := A_ScriptDir "\lib\WebView2\64bit\WebView2Loader.dll"
if A_IsCompiled {
    appRoot := A_Temp "\AirPodsBuddy_app\" APP_VERSION "-" DllCall("GetCurrentProcessId")
    uiHtml := appRoot "\index_built.html"
    wvDll := appRoot "\WebView2Loader.dll"
    EnsureResources()
}

EnsureResources() {
    global appRoot
    if !A_IsCompiled
        return true
    try {
        DirCreate(appRoot)
        if !FileExist(appRoot "\index_built.html")
            FileInstall "webui\index_built.html", appRoot "\index_built.html", 1
        if !FileExist(appRoot "\pet_built.html")
            FileInstall "webui\pet_built.html", appRoot "\pet_built.html", 1
        if !FileExist(appRoot "\noise_mode.ps1")
            FileInstall "tools\noise_mode.ps1", appRoot "\noise_mode.ps1", 1
        if !FileExist(appRoot "\WebView2Loader.dll")
            FileInstall "lib\WebView2\64bit\WebView2Loader.dll", appRoot "\WebView2Loader.dll", 1
        if !FileExist(appRoot "\face_off.ico")
            FileInstall "assets\face_off.ico", appRoot "\face_off.ico", 1
        if !FileExist(appRoot "\face_on.ico")
            FileInstall "assets\face_on.ico", appRoot "\face_on.ico", 1
        if !FileExist(appRoot "\loading_0.ico")
            FileInstall "assets\loading_0.ico", appRoot "\loading_0.ico", 1
        if !FileExist(appRoot "\loading_1.ico")
            FileInstall "assets\loading_1.ico", appRoot "\loading_1.ico", 1
        if !FileExist(appRoot "\loading_2.ico")
            FileInstall "assets\loading_2.ico", appRoot "\loading_2.ico", 1
        if !FileExist(appRoot "\loading_3.ico")
            FileInstall "assets\loading_3.ico", appRoot "\loading_3.ico", 1
        if !FileExist(appRoot "\loading_4.ico")
            FileInstall "assets\loading_4.ico", appRoot "\loading_4.ico", 1
        if !FileExist(appRoot "\loading_5.ico")
            FileInstall "assets\loading_5.ico", appRoot "\loading_5.ico", 1
        if !FileExist(appRoot "\background-worker.ps1")
            FileInstall "scripts\background-worker.ps1", appRoot "\background-worker.ps1", 1
        if !FileExist(appRoot "\UpdateCore.psm1")
            FileInstall "scripts\UpdateCore.psm1", appRoot "\UpdateCore.psm1", 1
        if !FileExist(appRoot "\update-swap.ps1")
            FileInstall "scripts\update-swap.ps1", appRoot "\update-swap.ps1", 1
        return true
    } catch as e {
        LogMsg("resource recovery failed: " e.Message, "ERROR")
        return false
    }
}

LogMsg("boot v" APP_VERSION " compiled=" A_IsCompiled " scriptdir=" A_ScriptDir)
wv2Fallback := ""   ; 提前初始化：/testpet 模式在 EnsureWebView2Runtime 之前就会进 PetEnsure

; /testpet：宠物弹窗演示模式（QA/截图验证用）
if (A_Args.Length = 1 && A_Args[1] = "/testpet") {
    if PetEnsure() {
        for i, s in ["connecting", "ok", "disconnecting", "off", "fail"] {
            (i = 1) ? PetShow(s) : PetUpdate(s)
            Sleep(1700)
        }
        PetFade()
        Sleep(700)
    }
    ExitApp(0)
}

; /testnoise：降噪切换自测（结果看日志与气泡）
if (A_Args.Length = 1 && A_Args[1] = "/testnoise") {
    RunNoiseMode("trans")
    ExitApp(0)
}
if !A_IsCompiled && FileExist(A_ScriptDir "\assets\star_pudding.ico")
    TraySetIcon(A_ScriptDir "\assets\star_pudding.ico")

devices := []
busy := false
myGui := 0
wv := 0

AnyConnected() {
    global devices
    for dev in devices {
        if dev.connected
            return true
    }
    return false
}

; ------------------------- Tray icon state machine --------------------
; 三态（学习 Mac 版）：未连接=可爱脸 / 已连接=心动脸+绿环 /
; 连接中=加油脸+旋转弧动画（防用户在慢连接期间重复操作）
TrayIconDir() {
    global appRoot
    EnsureResources()
    return A_IsCompiled ? appRoot : A_ScriptDir "\assets"
}

trayLoading := false
trayLoadFrame := 0
lastTrayOn := -1

UpdateTrayIcon(force := false) {
    global lastTrayOn, trayLoading
    if trayLoading
        return
    on := AnyConnected()
    if (!force && on = lastTrayOn)
        return
    lastTrayOn := on
    p := TrayIconDir() . (on ? "\face_on.ico" : "\face_off.ico")
    if FileExist(p)
        TraySetIcon(p)
    A_IconTip := on ? "AirPods 小助手 · 已连接（左键断开）" : "AirPods 小助手 · 未连接（左键连接）"
}

SetTrayLoading(on) {
    global trayLoading, trayLoadFrame
    if (on && !trayLoading) {
        trayLoading := true
        trayLoadFrame := 0
        SetTimer(TrayLoadingTick, 130)
        TrayLoadingTick()
    } else if (!on && trayLoading) {
        trayLoading := false
        SetTimer(TrayLoadingTick, 0)
        UpdateTrayIcon(true)
    }
}

TrayLoadingTick() {
    global trayLoadFrame
    p := TrayIconDir() "\loading_" trayLoadFrame ".ico"
    if FileExist(p)
        TraySetIcon(p)
    A_IconTip := "AirPods 小助手 · 连接中…"
    trayLoadFrame := Mod(trayLoadFrame + 1, 6)
}

; 独立看门：不依赖前端 statuspoll（窗口隐藏时 WebView2 会节流定时器，
; 曾导致托盘图标不更新）。每 2 秒自己枚举设备并刷新图标。
WatchTrayState() {
    global trayLoading
    if trayLoading
        return
    FindAllAudioDevices()
    SortDevices()
    UpdateTrayIcon()
    WatchFlap()
}

; 连接来回跳检测（v1.9.8，用户 2026-09-06）：手机/电脑抢耳机或链路不稳时
; 连接状态反复翻转。120 秒窗口内翻转 ≥3 次 = 横跳，提示用户（5 分钟冷却）。
; 只提示不自动动作：自动重连会跟手机抢得更凶，决策权交给用户（doc/04 待办调研）。
flapLog := Map()      ; name -> "|"-连接的时间戳串（必须 Map：Object 无 Has/__Item，见日志 8389 错误教训）
flapPrev := Map()     ; name -> 上次连接状态(1/0)
flapAdvised := Map()  ; name -> 上次提示时刻

WatchFlap() {
    global devices, flapLog, flapPrev, flapAdvised
    for dev in devices {
        key := dev.name
        now := dev.connected ? 1 : 0
        if !flapPrev.Has(key) {
            flapPrev[key] := now
            continue
        }
        if (flapPrev[key] = now)
            continue
        flapPrev[key] := now
        stamps := flapLog.Has(key) ? flapLog[key] : ""
        stamps .= (stamps = "" ? "" : "|") A_Now
        fresh := ""
        for _, t in StrSplit(stamps, "|")
            if DateDiff(A_Now, t, "Seconds") <= 120
                fresh .= (fresh = "" ? "" : "|") t
        flapLog[key] := fresh
        cnt := StrLen(fresh) ? StrSplit(fresh, "|").Length : 0
        if (cnt < 3)
            continue
        last := flapAdvised.Has(key) ? flapAdvised[key] : ""
        if (last != "" && DateDiff(A_Now, last, "Seconds") <= 300)
            continue   ; 5 分钟冷却（对审计 #1：DateDiff(…,0,…)=ValueError，哨兵必须为空串）
        flapAdvised[key] := A_Now
        flapLog[key] := ""
        LogMsg("flap detected: '" key "' x" cnt "/120s", "WARN")
        TrayTip("AirPods 小助手", "检测到 «" key "» 连接来回跳（手机和电脑在抢耳机）`n建议：暂停手机蓝牙或退出手机上的音乐，再点一次连接锁定", 4)
        PushEvent("flapping", JsonStr(key))
    }
}

; 降噪/通透模式：通过 Apple 私有 L2CAP 服务（74ec2172-...）发送 0x0D 指令。
; 协议事实来自 librepods 的逆向文档（见 README 致谢）；实现为本项目独立编写的
; PowerShell + Winsock（tools/noise_mode.ps1，编译时内嵌）。
DevAddrString(info) {
    addr := NumGet(info, 8, "uint64")
    parts := []
    loop 6
        parts.Push(Format("{:02X}", (addr >> ((A_Index - 1) * 8)) & 0xFF))
    return Join(parts, ":")
}

NoiseTarget() {
    global devices
    FindAllAudioDevices()
    SortDevices()
    for dev in devices {
        if (dev.connected && IsAppleDevice(dev.name))
            return dev
    }
    for dev in devices {
        if dev.connected
            return dev
    }
    return 0
}

RunNoiseMode(mode) {
    modes := Map("off", "关闭", "anc", "降噪", "trans", "通透", "adapt", "自适应")
    modeName := modes[mode]
    target := NoiseTarget()
    if !target {
        TrayTip("AirPods 小助手", "没有连接中的耳机，先连接再切模式", 3)
        return
    }
    addr := DevAddrString(target.info)
    ps1 := A_IsCompiled ? (appRoot "\noise_mode.ps1") : (A_ScriptDir "\tools\noise_mode.ps1")
    LogMsg("noise mode " mode " -> " target.name " (" addr ")")
    payload := '{"address":' JsonStr(addr) ',"mode":' JsonStr(mode) '}'
    StartBackgroundJob("noise", payload, (result, job) => PushEvent("toast", JsonStr(result["status"] = "ok" ? "降噪切换命令已完成" : "降噪切换未完成，请查看日志")), 20000)

}

; 左键单击托盘图标 = 在"连接首选设备 / 断开全部"之间切换
ToggleQuickAction() {
    if AnyConnected()
        TrayQuickAction("disconnect")
    else
        TrayQuickAction("connect")
}

; ------------------------- Pet popup ----------------------------------
; 托盘操作的萌系反馈：点一下，星星布丁从右下角弹出来陪你等连接。
; 素材来自 ~/.codex/pets/xingxing-pudding（hatch-pet 8x11 atlas 规范，
; 裁全宽 8 列 x 6 行(1536x1248)为 webui/assets/xingxing_pet.webp，~290KB）。
petGui := 0
petWvc := 0
petWv := 0
petVisible := false
petReady := false
petPending := ""

PetOnMsg(core, args) {
    global petReady, petPending
    if (args.Source != "https://app.airpods.local/pet_built.html" || core.Source != "https://app.airpods.local/pet_built.html")
        return
    try {
        m := args.TryGetWebMessageAsString()
        if (m = "petready") {
            petReady := true
            ; IsSet 守卫：/testpet 在 auto-exec 前段就调用 Pet 系列，
            ; 此时顶层 pet* 全局初始化(见下方)还没执行到，直接读会 UnsetError
            if (IsSet(petPending) && petPending != "") {
                PetApply(petPending)
                petPending := ""
            }
        }
    }
}

PetApply(state) {
    global petWv, petReady, petPending
    if (!IsSet(petReady) || !petReady) {
        petPending := state   ; 页面还没就绪：先存起来，petready 后补播
        return
    }
    try petWv.ExecuteScriptAsync('showPopup();setState("' state '")')
}

PetEnsure() {
    global petGui, petWvc, petWv, wvDll, appRoot, wv2Fallback
    EnsureResources()
    if (IsSet(petGui) && petGui != 0)
        return true
    p := A_IsCompiled ? (appRoot "\pet_built.html") : (A_ScriptDir "\webui\pet_built.html")
    if (A_IsCompiled && !FileExist(p)) {
        try {
            DirCreate(appRoot)
            FileInstall "webui\pet_built.html", p, 1
            LogMsg("pet html restored: " p)
        } catch as e {
            LogMsg("pet html restore failed: " e.Message, "WARN")
        }
    }
    if !FileExist(p) {
        LogMsg("pet html missing: " p, "WARN")
        return false
    }
    petGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000", "AirPodsPet")
    petGui.MarginX := 0, petGui.MarginY := 0
    petGui.BackColor := "000000"   ; Gui 底色黑 = 颜色键色；webview 透明处露出黑再被挖穿
    petGui.Show("w200 h260 Hide")
    ; 透明方案：webview 用 DefaultBackgroundColor=真透明（旧版日志回读 00000000，
    ; 用户看到的"白"是 Gui 自身白底+白卡）；Gui 自身黑底再用颜色键挖穿。
    ; 注意 LWA_COLORKEY 只作用于顶层 GDI 表面，所以键色放在 Gui 底色而不是页面里。
    WinSetTransColor("000000", petGui)
    ex := DllCall("user32\GetWindowLongW", "ptr", petGui.Hwnd, "int", -20, "int")
    LogMsg("pet transcolor 000000 hwnd=" petGui.Hwnd " exstyle=" Format("0x{:X}", ex))
    try {
        petWvc := WebView2.create(petGui.Hwnd,, 0, EnvGet("LOCALAPPDATA") "\AirPodsBuddy_webview", wv2Fallback, 0, wvDll)
    } catch as e {
        LogMsg("pet webview create failed: " e.Message, "WARN")
        try petGui.Destroy()
        petGui := 0
        return false
    }
    petWv := petWvc.CoreWebView2
    try {
        petWvc.DefaultBackgroundColor := 0x00000000   ; webview 真透明（有效，旧版验证过）
        LogMsg("pet bg readback=" Format("{:08X}", petWvc.DefaultBackgroundColor))
    }
    try {
        petWv.Settings.AreDevToolsEnabled := false
        petWv.Settings.AreDefaultContextMenusEnabled := false
    }
    petWv.add_NavigationStarting((core, args) => (args.Cancel := args.Uri != "https://app.airpods.local/pet_built.html"))
    petWv.add_NewWindowRequested((core, args) => (args.Handled := true))
    petWv.add_WebMessageReceived(PetOnMsg)
    petWv.SetVirtualHostNameToFolderMapping("app.airpods.local", A_IsCompiled ? appRoot : A_ScriptDir "\webui", 0)
    petWv.Navigate("https://app.airpods.local/pet_built.html")
    petGui.OnEvent("Close", (*) => petGui.Hide())
    return true
}

PetShow(state) {
    global petGui, petVisible
    if !PetEnsure()
        return
    ; DPI 陷阱：A_ScreenWidth 是物理像素，Gui.Show 的 x/y 是逻辑坐标（会被
    ; 系统再缩放），直接相减会把窗口摆出屏幕。这里全部走物理坐标链：
    ; 工作区(SPI) -> 窗口实际矩形 -> SetWindowPos 原生定位。
    petGui.Show("w200 h260 NoActivate")
    wa := Buffer(16), rc := Buffer(16)
    DllCall("user32\SystemParametersInfoW", "uint", 0x0030, "uint", 0, "ptr", wa, "uint", 0)
    DllCall("user32\GetWindowRect", "ptr", petGui.Hwnd, "ptr", rc)
    w := NumGet(rc, 8, "int") - NumGet(rc, 0, "int")
    h := NumGet(rc, 12, "int") - NumGet(rc, 4, "int")
    px := NumGet(wa, 8, "int") - w - 16
    py := NumGet(wa, 12, "int") - h - 12
    DllCall("user32\SetWindowPos", "ptr", petGui.Hwnd, "ptr", 0, "int", px, "int", py, "int", 0, "int", 0, "uint", 0x0005)
    ; 主窗口同款坑：隐窗创建的 WebView2 控制器 IsVisible=false 会挂起渲染（白屏）
    petWvc.Fill()
    petWvc.IsVisible := true
    petVisible := true
    PetApply(state)
    SetTimer(PetFade, -9000)
}

PetUpdate(state) {
    global petVisible
    if (!IsSet(petVisible) || !petVisible)
        return
    global petWv, petReady
    if (!IsSet(petReady) || !petReady)
        return   ; 首帧还没播就到了终态：直接走 PetFinish 的定时即可
    try petWv.ExecuteScriptAsync('setState("' state '")')
}

PetFinish(state) {
    PetUpdate(state)
    SetTimer(PetFade, -1400)
}

PetFade() {
    global petVisible, petWv
    if (!IsSet(petVisible) || !petVisible)
        return
    SetTimer(PetFade, 0)
    try petWv.ExecuteScriptAsync('hidePopup()')
    SetTimer(PetHideNow, -400)
}

PetHideNow() {
    global petGui, petVisible
    petGui.Hide()
    petVisible := false
}

; ------------------------- Window ------------------------------------
WinW := 460, WinH := 600

; 手动拖动循环：WebView2 子窗口持有鼠标捕获，WM_NCLBUTTONDOWN 桥无效，
; 直接按全局光标位移移动窗口（GetCursorPos 不受捕获影响）。
StartWindowDrag() {
    global myGui
    pt := Buffer(8), rc := Buffer(16)
    DllCall("user32\GetCursorPos", "ptr", pt)
    DllCall("user32\GetWindowRect", "ptr", myGui.Hwnd, "ptr", rc)
    dx := NumGet(pt, 0, "int") - NumGet(rc, 0, "int")
    dy := NumGet(pt, 4, "int") - NumGet(rc, 4, "int")
    while (DllCall("user32\GetAsyncKeyState", "int", 0x01) & 0x8000) {
        DllCall("user32\GetCursorPos", "ptr", pt)
        DllCall("user32\SetWindowPos", "ptr", myGui.Hwnd, "ptr", 0,
            "int", NumGet(pt, 0, "int") - dx, "int", NumGet(pt, 4, "int") - dy,
            "int", 0, "int", 0, "uint", 0x0005)   ; NOSIZE|NOZORDER
        Sleep(10)
    }
}
myGui := Gui("-Caption +MinSize" WinW, "AirPods 小助手")
myGui.MarginX := 0, myGui.MarginY := 0
myGui.Show("w" WinW " h" WinH " Hide")

; Win11 rounded corners for the borderless window
DllCall("dwmapi\DwmSetWindowAttribute", "ptr", myGui.Hwnd, "int", 33, "int*", 2, "int", 4)

; ------------------------- WebView2 ----------------------------------
; WebView2 控件不会复用用户已装的 Edge 浏览器，只认 WebView2 Runtime
; （或 Edge Beta/Dev/Canary 通道）。精简系统/服务器镜像/被"优化工具"
; 清理过的机器上常常没有 → 0x80070002"找不到文件"，重试救不了。
; 自愈流程：探测 → 缺失则引导自动下载官方安装器静默装上 → 断网时
; 降级直接借用本机 Edge 目录 → 全失败才提示手动处理。
wv2Fallback := ""   ; 降级 Edge 目录（空=系统运行时可用），PetEnsure 也要用

; 用官方加载器 API 探测可用运行时版本，找不到返回 ''
WebView2RuntimeVersion() {
    global wvDll
    info := 0   ; 输出参数必须传 VarRef(&info)：传值会静默不回填，
    try {       ; 导致有运行时也误报缺失（本机实测 hr=0 但指针为空）
        hr := DllCall(wvDll "\GetAvailableCoreWebView2BrowserVersionString", "wstr", "", "ptr*", &info, "int")
        if (hr >= 0 && info) {
            ver := StrGet(info)
            DllCall("ole32\CoTaskMemFree", "ptr", info)
            return ver
        }
    } catch as e {
        LogMsg("WebView2 runtime probe failed: " e.Message, "WARN")
    }
    return ""
}

; 断网降级：借本机 Edge 浏览器目录当运行时（同一套内核，官方默认不
; 用它而已），返回最高版本目录，找不到返回 ''
EdgeFallbackDir() {
    best := "", ver := "0.0.0.0"
    for root in [EnvGet("ProgramFiles(x86)"), EnvGet("ProgramFiles"), EnvGet("LOCALAPPDATA")]
        loop files root "\Microsoft\Edge\Application\*", "D"
            if FileExist(A_LoopFileFullPath "\msedge.exe")
                && RegExMatch(A_LoopFilePath, "\\([\d.]+)$", &m) && VerCompare(m[1], ver) > 0
                best := A_LoopFileFullPath, ver := m[1]
    return best
}

; 自愈入口。返回值作为 WebView2.create 的 edgeRuntime 参数：
; '' = 系统运行时可用/已装好（走加载器默认查找）；非空 = 降级 Edge 目录
EnsureWebView2Runtime() {
    if (WebView2RuntimeVersion() != "")
        return ""
    LogMsg("WebView2 Runtime missing; using existing Edge fallback. Install via tray help if needed.", "WARN")
    return EdgeFallbackDir()
}


wv2Fallback := EnsureWebView2Runtime()
if (wv2Fallback != "")
    LogMsg("using Edge fallback dir: " wv2Fallback, "WARN")
; 创建失败（如被安全软件瞬时拦截 0x800704C7）时自动重试
wvc := 0
loop 3 {
    try {
        wvc := WebView2.create(myGui.Hwnd,, 0, EnvGet("LOCALAPPDATA") "\AirPodsBuddy_webview", wv2Fallback, 0, wvDll)
        break
    } catch as e {
        LogMsg("WebView2 init attempt " A_Index " failed: " e.Message, "WARN")
        if (A_Index = 3) {
            LogMsg("WebView2 init failed permanently", "ERROR")
            TrayTip("界面组件暂未就绪。请从托盘打开微软 WebView2 安装页面；详细原因已写入日志。", "AirPods 小助手", 2)
            ExitApp(1)
        }
        Sleep(1200)
    }
}
wv := wvc.CoreWebView2
wvc.Fill()   ; explicit: ensure bounds match client area even when created hidden
try {
    wv.Settings.AreDevToolsEnabled := false
    wv.Settings.AreDefaultContextMenusEnabled := false
}
wv.add_NavigationStarting((core, args) => (args.Cancel := args.Uri != "https://app.airpods.local/index_built.html"))
wv.add_NewWindowRequested((core, args) => (args.Handled := true))
wv.add_WebMessageReceived(WebMessageHandler)
wv.add_NavigationCompleted(MarkUpdateHealthy)
wv.add_NavigationCompleted((wv2, args) => LogMsg(
    "navigation " (args.IsSuccess ? "ok" : "FAILED webError=" args.WebErrorStatus),
    args.IsSuccess ? "INFO" : "ERROR"))

htmlText := FileRead(uiHtml, "UTF-8")
LogMsg("loading UI html chars=" StrLen(htmlText))
wv.SetVirtualHostNameToFolderMapping("app.airpods.local", A_IsCompiled ? appRoot : A_ScriptDir "\webui", 0)
wv.Navigate("https://app.airpods.local/index_built.html")

myGui.OnEvent("Close", (*) => myGui.Hide())
myGui.OnEvent("Size", SyncWebView)

; ---------------------------------------------------------------------
; 白屏修复（根因）：窗口先以 Hide 方式创建、再创建 WebView2 控制器时，
; 控制器的 IsVisible 初始为 false，WebView2 会挂起渲染 —— 页面 JS 照常
; 运行（轮询、rpc 都正常）但屏幕上永远是一片空白。
; 因此每次窗口显示/尺寸变化后都要 Fill 边界并强制 IsVisible := true。
; ---------------------------------------------------------------------
SyncWebView(*) {
    global wvc, myGui
    if WinExist(myGui.Hwnd) && !DllCall("IsIconic", "ptr", myGui.Hwnd) {
        wvc.Fill()
        wvc.IsVisible := true
    }
}

myGui.Show()
SyncWebView()
LogMsg("window shown, controller IsVisible=" wvc.IsVisible)
A_IconTip := "AirPods 小助手 v" APP_VERSION

trayToggleName := "⇄ 切换连接"
A_TrayMenu.Delete()
A_TrayMenu.Add(trayToggleName, (*) => ToggleQuickAction())
noiseMenu := Menu()
noiseMenu.Add("🔴 关闭", (*) => RunNoiseMode("off"))
noiseMenu.Add("🎧 降噪", (*) => RunNoiseMode("anc"))
noiseMenu.Add("🔊 通透", (*) => RunNoiseMode("trans"))
noiseMenu.Add("✨ 自适应", (*) => RunNoiseMode("adapt"))
A_TrayMenu.Add("🎧 降噪/通透模式", noiseMenu)
A_TrayMenu.Add("打开界面", (*) => (myGui.Show(), SyncWebView()))
A_TrayMenu.Add()
A_TrayMenu.Add("🎧 一键连接", (*) => TrayQuickAction("connect"))
A_TrayMenu.Add("🚫 一键断开", (*) => TrayQuickAction("disconnect"))
A_TrayMenu.Add()
A_TrayMenu.Add("检查更新", (*) => CheckUpdate(true))
A_TrayMenu.Add("退出", (*) => ExitApp())
try {
    A_TrayMenu.Default := trayToggleName   ; 单击左键即触发，右键才弹菜单
    A_TrayMenu.ClickCount := 1   ; v2 属性名是 ClickCount；v1 的 Click 会被当普通属性静默赋值（左键单击失效根因，v1.8.1 修复）
} catch as e {
    LogMsg("tray default set failed: " e.Message, "ERROR")
}
lastTrayOn := -1
UpdateTrayIcon(true)
SetTimer(WatchTrayState, 2000)   ; 独立看门：托盘状态不依赖前端轮询

; tray quick action follows the device priority order:
;   connect    -> connect the FIRST non-connected device in sorted order
;   disconnect -> disconnect every connected device (top priority first)
TrayQuickAction(action) {
    global devices, busy
    FindAllAudioDevices()
    SortDevices()
    if (devices.Length = 0) {
        TrayTip("AirPods 小助手", "没有已配对的耳机，请先打开界面添加。", 3)
        return
    }
    if (busy) {
        TrayTip("AirPods 小助手", "上一个操作还在进行中…", 2)
        return
    }
    if (action = "connect") {
        target := 0
        for dev in devices {
            if !dev.connected {
                target := dev
                break
            }
        }
        if !target {
            StartAudioVerify(DeviceKey(devices[1]))
            return
        }
        PetShow("connecting")
        SetTrayLoading(true)
        r := DoAction(DeviceKey(target), "connect")
        SetTrayLoading(false)
        if (r = "ok") {
            ; 真实链路由 LinkVerifyTick 异步核实，完成后修正宠物与提示
            TrayTip("AirPods 小助手", "正在连接 «" target.name "» …", 2)
        } else {
            PetFinish("fail")
            TrayTip("AirPods 小助手", "连接失败 «" target.name "»", 3)
        }
    } else {
        queue := []
        for dev in devices
            if dev.connected
                queue.Push(DeviceKey(dev))
        if queue.Length {
            PetShow("disconnecting")
            DisconnectQueue(queue)
        } else
            TrayTip("当前没有连接中的耳机", "AirPods 小助手", 1)

    }
}

SetTimer(CheckUpdate, -3000)
SetTimer(CheckUpdateReceipt, -3500)   ; v1.9.2：核对上次自动更新回执，如实告知

; v1.9.2：上次更新置换的回执（swapper 写入 update_result.txt）。
; ok → 确认 toast；fail → 多半被 360 等安全软件拦截，如实提醒用户。
; ------------------------- 意见反馈（v1.9.6） -------------------------
; 通道：企业微信群机器人 webhook（免注册免跳转，直发用户手里）。
; 主通道：前端 WebView2(Edge 引擎) 内 fetch 直发（v1.9.8）——实测 360 主动防御
; 会拦截应用派生子进程（curl/powershell）的联网，但不拦浏览器引擎。
; 本函数仅作兜底通道（第二族传输，不同失败域）。
; webhook 存 app_settings.ini 的 feedback_webhook，可随时换 key 不用重编译。
FbWebhook() {
    webhook := SettingRead("feedback_webhook", "")
    if (webhook = "")
        webhook := "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=93bbfb6e-6d93-437e-a8ab-605062cc5db5"
    return webhook
}




; 最近 50 条日志：今天优先，不足补昨天（横跳/闪断可能跨零点）
GatherLogTail() {
    dir := A_ScriptDir "\logs"
    today := dir "\app-" FormatTime(A_Now, "yyyy-MM-dd") ".log"
    yest := dir "\app-" FormatTime(DateAdd(A_Now, -1, "days"), "yyyy-MM-dd") ".log"
    lines := []
    for _, f in [today, yest] {
        if !FileExist(f)
            continue
        try {
            for line in StrSplit(FileRead(f, "UTF-8"), "`n", "`r")
                lines.Push(line)
        } catch {
            continue
        }
    }
    start := Max(1, lines.Length - 49)
    out := "=== AirPodsBuddy 日志（最近 " (lines.Length - start + 1) " 行 · " A_Now "） ===`r`n"
    Loop lines.Length - start + 1
        out .= lines[start + A_Index - 1] "`r`n"
    return out
}

; 日志随反馈上传：企微机器人先 upload_media（multipart，HttpClient）拿 media_id，
; 再发 file 消息。50 行日志对一个文件，开发者可直接下载 grep，比贴文本好定位。
B64Utf16(str) {
    chars := StrLen(str)
    bytes := chars * 2
    buf := Buffer(bytes + 2, 0)
    StrPut(str, buf, "UTF-16")
    size := 0
    DllCall("crypt32\CryptBinaryToStringW", "ptr", buf, "uint", bytes, "uint", 0x40000001, "ptr", 0, "uint*", &size)
    out := Buffer(size * 2, 0)
    DllCall("crypt32\CryptBinaryToStringW", "ptr", buf, "uint", bytes, "uint", 0x40000001, "ptr", out, "uint*", &size)
    return StrGet(out, size)   ; base64（无换行），-EncodedCommand 直接可用
}

PsStr(v) {
    return "'" StrReplace(v, "'", "''") "'"   ; 拼进 PS 脚本本体的单引号字符串字面量
}

; ------------------------- 问题反馈（v1.9.10：类型 + 说明 + 完整日志文件） -------------------------
; 与「提意见」分工：意见 = 纯文本轻通道；问题反馈 = 类型化 + 完整日志（今天+昨天
; 合并成文件）经企微 upload_media → file 消息发到群里。前端 fetch 文本失败时，
; 文本兜底也在这里一并发。返回：ok / nofile（文本已达、文件没发出去）/ fail
BuildIssueLogFile() {
    dir := A_ScriptDir "\logs"
    today := dir "\app-" FormatTime(A_Now, "yyyy-MM-dd") ".log"
    yest := dir "\app-" FormatTime(DateAdd(A_Now, -1, "days"), "yyyy-MM-dd") ".log"
    body := "AirPodsBuddy v" APP_VERSION " 完整日志 · " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    n := 0
    for label, f in Map("今天", today, "昨天", yest) {
        if FileExist(f) {
            n++
            try body .= "`r`n`r`n========== " label " " f " ==========`r`n`r`n" FileRead(f, "UTF-8")
        }
    }
    if (n = 0)
        return ""
    p := A_Temp "\AirPodsBuddy_issue_log_" DllCall("GetCurrentProcessId") "_" A_TickCount ".txt"
    try {
        fw := FileOpen(p, "w", "UTF-8-RAW")   ; 无 BOM，群里下载后记事本直接读
        fw.Write(body)
        fw.Close()
        return p
    } catch as e {
        LogMsg("issue log file write failed: " e.Message, "WARN")
        return ""
    }
}

; 按 UTF-8 字节数从头部丢整行（与前端 fbBuildIssue 的预算逻辑同族）
TruncateUtf8(s, maxBytes) {
    if (StrPut(s, "UTF-8") - 1 <= maxBytes)
        return s
    loop {
        pos := InStr(s, "`n")
        if !pos
            break
        s := SubStr(s, pos + 1)
        if (StrPut(s, "UTF-8") - 1 <= maxBytes)
            break
    }
    return s
}




; ------------------------- 开机自启动（v1.9.5 设置项） -------------------------
; 机制：HKCU Run 键（任务管理器→启动应用 可见可逆，免管理员）。
; 兼容旧版启动文件夹快捷方式（存在即视为已开启，切换时迁移到注册表）。
; 若被安全软件/任务管理器禁用（StartupApproved 首字节为奇数），返回
; "disabled" 让前端如实提示，而不是假装开关没生效。

AutostartEnabled() {
    global RUN_KEY, RUN_NAME
    lnkOn := FileExist(A_Startup "\AirPods小助手.lnk") ? true : false
    regOn := false
    try {
        v := RegRead("HKCU\" RUN_KEY, RUN_NAME)
        regOn := (v != "")
    } catch {
        regOn := false
    }
    if (regOn) {
        try {
            bin := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run", RUN_NAME)
            ; RegRead(REG_BINARY) returns hexadecimal text, not a Buffer.
            if (StrLen(bin) >= 2 && InStr("13579BDF", StrUpper(SubStr(bin, 2, 1))))
                return "disabled"   ; Run 键还在但被禁用（安全软件/任务管理器所为）
        } catch {
        }
        return "on"
    }
    return lnkOn ? "on" : "off"
}

AutostartSet(on) {
    global RUN_KEY, RUN_NAME
    oldPreference := SettingRead("autostart", "")
    oldRun := "", hadRun := false
    try {
        oldRun := RegRead("HKCU\" RUN_KEY, RUN_NAME)
        hadRun := true
    }
    if !SettingWrite("autostart", on ? "1" : "0")
        return "fail"
    try {
        if on {
            RegWrite('"' A_ScriptFullPath '"', "REG_SZ", "HKCU\" RUN_KEY, RUN_NAME)
            ; Preserve StartupApproved: an OS-disabled entry stays visibly disabled.
        } else if hadRun {
            RegDelete("HKCU\" RUN_KEY, RUN_NAME)
        }
        lnk := A_Startup "\AirPods小助手.lnk"
        if FileExist(lnk)
            FileDelete(lnk)
        state := AutostartEnabled()
        if (on && state != "on") || (!on && state != "off")
            throw Error("autostart readback: " state)
        return "ok"
    } catch as e {
        try {
            if hadRun
                RegWrite(oldRun, "REG_SZ", "HKCU\" RUN_KEY, RUN_NAME)
            else
                RegDelete("HKCU\" RUN_KEY, RUN_NAME)
        }
        SettingWrite("autostart", oldPreference)
        LogMsg("autostart change rolled back: " e.Message, "ERROR")
        return "fail"
    }
}


AutostartRepair() {
    global RUN_KEY, RUN_NAME
    ; Only restore an explicit user choice; do not silently enable startup for old installs.
    preference := SettingRead("autostart", "")
    LogMsg("autostart repair check: preference=" (preference = "" ? "unset" : preference))
    if (preference = "") {
        ; Migrate an existing active entry while it still exists, never infer from a missing entry.
        if (AutostartEnabled() = "on")
            SettingWrite("autostart", "1")
        return
    }
    if (preference != "1")
        return
    exe := '"' A_ScriptFullPath '"'
    try {
        observed := RegRead("HKCU\" RUN_KEY, RUN_NAME)
        LogMsg("autostart Run observed: " observed)
        if (observed = exe)
            return
    } catch as e {
        LogMsg("autostart Run absent/read failed: " e.Message)
    }
    try {
        RegWrite(exe, "REG_SZ", "HKCU\" RUN_KEY, RUN_NAME)
        state := AutostartEnabled()
        if (state = "on") {
            LogMsg("autostart Run entry restored: " exe)
            SetTimer((*) => PushEvent("toast", JsonStr("开机自启动项已恢复")), -1500)
        } else {
            LogMsg("autostart Run entry rewritten but state=" state, "WARN")
            SetTimer((*) => PushEvent("toast", JsonStr("开机自启动项已重建，但仍被系统禁用；请在启动应用中启用")), -1500)
        }
    } catch as e {
        LogMsg("autostart repair failed: " e.Message, "WARN")
    }
}
AutostartRepair()   ; startup must check before a network-bound update timer can block

CheckUpdateReceipt(left := 50) {
    p := A_ScriptDir "\update_result.txt"   ; 与 DoUpdate 的 exeDir(A_ScriptDir) 一致
    if !FileExist(p) {
        if left > 1
            SetTimer(() => CheckUpdateReceipt(left - 1), -1000)
        return
    }
    r := Trim(StrReplace(FileRead(p, "UTF-8"), Chr(0xFEFF), ""))   ; 去 BOM（PS5.1 UTF8 写入带 BOM）
    try FileDelete(p)
    if (r = "ok") {
        LogMsg("update swap receipt: ok")
        PushEvent("toast", JsonStr("已成功更新到 v" APP_VERSION " ✅"))
    } else {
        LogMsg("update swap receipt: " r, "WARN")
        PushEvent("toast", JsonStr("上次自动更新未完成，已保留或恢复旧程序；具体原因见日志。"))
    }
}


; ============ 求好评组件（组件库规范：不打扰用户） ============
SettingRead(key, default) {
    global SETTINGS_PATH
    try {
        if FileExist(SETTINGS_PATH) {
            loop read SETTINGS_PATH {
                line := Trim(A_LoopReadLine)
                p := InStr(line, "=")
                if (p && SubStr(line, 1, p - 1) = key)
                    return SubStr(line, p + 1)
            }
        }
    }
    return default
}

SettingWrite(key, value) {
    global SETTINGS_PATH
    wasCritical := A_IsCritical
    Critical("On")
    try {
    lines := []
    try {
        if FileExist(SETTINGS_PATH) {
            loop read SETTINGS_PATH {
                line := Trim(A_LoopReadLine)
                p := InStr(line, "=")
                if (p && SubStr(line, 1, p - 1) = key)
                    continue
                if (line != "")
                    lines.Push(line)
            }
        }
    }
    lines.Push(key "=" value)
    return AtomicWriteText(SETTINGS_PATH, Join(lines, "`n") "`n")
    } finally Critical(wasCritical)
}



; Per-device tasks retain cancellation across link/audio/microphone phases.
BeginDeviceOp(name, action) {
    global deviceOps, operationSerial, routeOwner
    gen := ++operationSerial
    deviceOps[name] := {gen: gen, state: action, started: A_TickCount, escalated: false}
    if (action = "connect")
        routeOwner := gen
    return gen
}

OpCurrent(name, gen) {
    global deviceOps
    return deviceOps.Has(name) && deviceOps[name].gen = gen
}

CanRoute(name, gen) {
    global routeOwner
    return OpCurrent(name, gen) && routeOwner = gen
}

SetOpState(name, gen, state) {
    global deviceOps
    if OpCurrent(name, gen)
        deviceOps[name].state := state
}

StartAudioVerify(name) {
    gen := BeginDeviceOp(name, "connect")
    AudioVerifyTick(name, 9, gen)
}

AudioVerifyTick(name, left, gen) {
    if !CanRoute(name, gen)
        return
    if !IsLinkUp(name) {
        SetOpState(name, gen, "link_failed")
        PushEvent("linkfail", JsonStr(name))
        return
    }
    if (AudioEndpointAlive(DeviceLabel(name)) && RenderSwitchTo(DeviceLabel(name))) {
        SetOpState(name, gen, "ready")
        LogMsg("audio route verified (render, roles 0/1/2): '" name "'")
        OnConnectSuccess()
        PetUpdate("ok")
        PushEvent("audiook", JsonStr(name))
        MicSwitchTo(name, gen)
        return
    }
    SetOpState(name, gen, "audio_pending")
    if (left <= 1) {
        SetOpState(name, gen, "audio_failed")
        LogMsg("audio route not ready after verification window: '" name "'", "WARN")
        PetUpdate("fail")
        TrayTip("蓝牙已连接，但播放端点或默认输出尚未就绪。请查看 Windows 声音输出；原因尚未确认。", "AirPods 小助手", 2)
        PushEvent("audioheld", JsonStr(name))
        return
    }
    SetTimer(() => AudioVerifyTick(name, left - 1, gen), -1500)
}

MicSwitchTo(name, gen) {
    if (SettingRead("auto_mic_switch", "1") = "1")
        MicSwitchTick(name, 4, gen)
}

MicSwitchTick(name, left, gen) {
    if (!CanRoute(name, gen) || SettingRead("auto_mic_switch", "1") != "1" || !IsLinkUp(name))
        return
    ep := FindCaptureEndpointId(DeviceLabel(name))
    if (SetAudioDefault(ep, 1)) {
        LogMsg("mic route verified (roles 0/1/2): '" name "'")
        PushEvent("toast", JsonStr("麦克风默认设备已确认切到耳机"))
        return
    }
    if (left > 1)
        SetTimer(() => MicSwitchTick(name, left - 1, gen), -2000)
    else
        LogMsg("mic route not ready after 4 attempts: '" name "'", "WARN")
}


OnConnectSuccess() {
    global connectCount, wv
    rawCount := SettingRead("connect_count", "0")
    connectCount := RegExMatch(rawCount, "^\d{1,9}$") ? rawCount + 0 : 0
    connectCount++
    SettingWrite("connect_count", connectCount)
    if (connectCount = 10 || Mod(connectCount, 50) = 0) {
        last := SettingRead("star_ask_last", "0")
        days := DaysSince(last)
        if (last = 0 || days > 15) {
            LogMsg("star ask shown (connect #" connectCount ")")
            try wv.ExecuteScriptAsync('window.__event("starask", "true")')
        }
    }
}

StarAskShown() {
    SettingWrite("star_ask_last", A_Now)
}

; ------------------------- JS bridge ---------------------------------
; protocol: "cmd<SEP>id<SEP>arg1<SEP>arg2..."
WebMessageHandler(core, args) {
    global myGui, APP_VERSION, priorityList, RELEASE_PAGE
    if (args.Source != "https://app.airpods.local/index_built.html" || core.Source != "https://app.airpods.local/index_built.html")
        return
    msg := args.TryGetWebMessageAsString()
    if StrLen(msg) > 16000
        return
    parts := StrSplit(msg, Chr(31))
    if (parts.Length < 2 || !RegExMatch(parts[2], "^\d{1,10}$"))
        return
    cmd := parts[1]
    id := parts[2]
    arg1 := parts.Length >= 3 ? parts[3] : ""
    arg2 := parts.Length >= 4 ? parts[4] : ""
    arg3 := parts.Length >= 5 ? parts[5] : ""
    arg4 := parts.Length >= 6 ? parts[6] : ""

    if !ValidBridgeArgs(cmd, parts) {
        Reply(id, "false")
        return
    }
    ; frontend forwards window.onerror / unhandledrejection here
    if (cmd = "jserror") {
        LogMsg("[JS-ERROR] " arg1, "ERROR")
        return
    }
    if (cmd != "statuspoll")
        LogMsg((cmd = "sendfeedback" || cmd = "sendissue") ? ("rpc: " cmd " (" StrLen(arg1) " chars)") : "rpc: " msg)

    switch cmd {
        ; NOTE: Reply() injects its payload as a raw JS expression. Anything that
        ; is not already a JS literal (true/false/null/number/"quoted") must be
        ; wrapped with JsonStr(), otherwise the frontend receives bare identifiers
        ; (ReferenceError) or pre-parsed objects (JSON.parse throws "[object Object]").
        case "list", "statuspoll": Reply(id, JsonStr(BuildDevicesJson())), UpdateTrayIcon()
        case "getversion":        Reply(id, JsonStr(APP_VERSION))
        case "connect":           Reply(id, JsonStr(DoAction(arg1, "connect")))
        case "disconnect":        Reply(id, JsonStr(DoAction(arg1, "disconnect")))
        case "remove":            Reply(id, JsonStr(RemoveDevice(arg1)))
        case "add":               Run("ms-settings:bluetooth"), Reply(id, "true")
        case "winmin":            myGui.Hide(), Reply(id, "true")   ; 最小化即缩托盘：不占任务栏（初心），随时托盘唤出
        case "winclose":          myGui.Hide(), Reply(id, "true")
        case "openrelease":        Run(RELEASE_PAGE), Reply(id, "true")
        case "openrepo":           Run("https://github.com/lyzbcy/AirPods-Windows"), Reply(id, "true")
        case "stardone":           StarAskShown(), Reply(id, "true")
        case "windrag":           StartWindowDrag(), Reply(id, "true")
        case "setprio":
            nextPriority := []
            loop Max(0, parts.Length - 2)
                nextPriority.Push(parts[A_Index + 2])
            oldPriority := priorityList
            priorityList := nextPriority
            if !SavePriority() {
                priorityList := oldPriority
                Reply(id, "false")
                return
            }
            LogMsg("priority updated: " arg1)
            Reply(id, "true")
        case "doupdate":          DoUpdate(id)
        case "getautostart":      Reply(id, JsonStr(AutostartEnabled()))
        case "setautostart":      Reply(id, JsonStr(AutostartSet(arg1 = "1")))
        case "getmicswitch":      Reply(id, JsonStr(SettingRead("auto_mic_switch", "1")))
        case "setmicswitch":      Reply(id, SettingWrite("auto_mic_switch", arg1) ? "true" : "false")
        case "getrescue":         Reply(id, JsonStr("0"))
        case "setrescue":         Reply(id, "false")
        case "sendfeedback":      SendFeedbackAsync(id, arg1)
        case "sendissue":         SendIssueAsync(id, arg1, arg2, arg3, arg4)
        case "getfblogs":         Reply(id, JsonStr(GatherLogTail()))
        case "getfbwebhook":      Reply(id, "null") ; webhook stays in the host
        case "openurl":           Reply(id, OpenApprovedUrl(arg1) ? "true" : "false")
        default:                  Reply(id, "null")
    }
}

Reply(id, json) {
    global wv
    try wv.ExecuteScriptAsync('window.__rpc(' id ', ' json ')')
}
PushEvent(name, json) {
    global wv
    try wv.ExecuteScriptAsync('window.__event("' name '", ' json ')')
}

JsonStr(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    loop 32
        s := StrReplace(s, Chr(A_Index - 1), Format("\u{:04X}", A_Index - 1))
    s := StrReplace(s, Chr(0x2028), "\u2028")
    s := StrReplace(s, Chr(0x2029), "\u2029")
    return '"' s '"'
}


BuildDevicesJson() {
    FindAllAudioDevices()
    SortDevices()
    out := "["
    for i, dev in devices {
        if (i > 1)
            out .= ","
        ; 单行拼接：v2 跨行 juxtaposition 不会续行，拆行会静默丢内容（踩过）
        out .= '{"id":' JsonStr(DeviceKey(dev)) ',"name":' JsonStr(dev.name) ',"connected":' (dev.connected ? 'true' : 'false') ',"audioState":' JsonStr(DeviceAudioState(DeviceKey(dev), dev.connected)) ',"apple":' (IsAppleDevice(dev.name) ? 'true' : 'false') '}'
    }
    return out "]"
}

; ------------------------- Device logic ------------------------------
FindAllAudioDevices() {
    global devices
    devices := []
    searchParams := Buffer(40, 0)
    NumPut("uint", 40, searchParams, 0)
    NumPut("uint", 1, searchParams, 4)

    deviceInfo := Buffer(560, 0)
    NumPut("uint", 560, deviceInfo, 0)

    searchHandle := DllCall("Bthprops.cpl\BluetoothFindFirstDevice", "ptr", searchParams, "ptr", deviceInfo, "ptr")
    if !searchHandle
        return
    loop {
        cod := NumGet(deviceInfo, 16, "uint")
        if ((cod >> 8) & 0x1F) = 4 {      ; Audio/Video major class
            info := Buffer(560)
            DllCall("RtlMoveMemory", "ptr", info, "ptr", deviceInfo, "ptr", 560)
            DllCall("Bthprops.cpl\BluetoothGetDeviceInfo", "ptr", 0, "ptr", info, "uint")
            devices.Push({
                id: Format("{:012X}", NumGet(info, 8, "uint64")),
                name: StrGet(info.Ptr + 64, "UTF-16"),
                info: info,
                connected: NumGet(info, 20, "uint") != 0   ; Windows 填的是位标志(实测32)，非零即已连接
            })
        }
        if !DllCall("Bthprops.cpl\BluetoothFindNextDevice", "ptr", searchHandle, "ptr", deviceInfo)
            break
    }
    DllCall("Bthprops.cpl\BluetoothFindDeviceClose", "ptr", searchHandle)
}

DoAction(name, action) {
    global busy
    if busy
        return "busy"
    if (action != "connect" && action != "disconnect")
        return "invalid"
    FindAllAudioDevices()
    dev := FindDevByName(name)
    if !dev
        return "notfound"
    name := DeviceKey(dev)
    busy := true
    gen := BeginDeviceOp(name, action)
    try {
        SetTrayLoading(true)
        payload := '{"address":' JsonStr(Format("{:012X}", NumGet(dev.info, 8, "uint64"))) ',"action":' JsonStr(action) ',"mic":' (SettingRead("auto_mic_switch", "1") = "1" ? "true" : "false") '}'
        if !StartBackgroundJob("bluetooth", payload, (result, job) => FinishBluetoothAction(name, action, gen, result), 30000)
            throw Error("Bluetooth worker launch failed")
        return "ok"
    } catch as e {
        busy := false
        SetTrayLoading(false)
        SetOpState(name, gen, "service_failed")
        LogMsg("DoAction failed: " e.Message, "ERROR")
        return "fail"
    }
}




StartLinkVerify(name, gen) {
    LinkVerifyTick(name, 8, gen)
}

LinkVerifyTick(name, left, gen) {
    if !OpCurrent(name, gen)
        return
    if IsLinkUp(name) {
        SetOpState(name, gen, "link_up")
        LogMsg("link verified (audio still pending): '" name "'")
        PushEvent("linkok", JsonStr(name))
        AudioVerifyTick(name, 9, gen)
        return
    }
    if (left <= 1) {
        SetOpState(name, gen, "link_failed")
        LogMsg("link not verified before deadline: '" name "'", "WARN")
        PetUpdate("fail")
        PushEvent("linkfail", JsonStr(name))
        return
    }
    SetTimer(() => LinkVerifyTick(name, left - 1, gen), -1200)
}

StartDownVerify(name, gen) {
    DownVerifyTick(name, 8, gen)
}

DownVerifyTick(name, left, gen) {
    global deviceOps, busy
    if !OpCurrent(name, gen)
        return
    if !IsLinkUp(name) {
        SetOpState(name, gen, "disconnected")
        LogMsg("link down verified: '" name "'")
        PetUpdate("off")
        PushEvent("linkdown", JsonStr(name))
        return
    }
    if (left <= 1) {
        if !deviceOps[name].escalated {
            deviceOps[name].escalated := true
            busy := true
            payload := '{"address":' JsonStr(name) ',"action":"disconnect","mic":false,"escalateOnly":true}'
            if StartBackgroundJob("bluetooth", payload, (result, job) => FinishDownEscalation(name, gen, result), 15000)
                return
            busy := false
        }
        SetOpState(name, gen, "disconnect_failed")
        LogMsg("link still up after AVRCP escalation: '" name "'", "WARN")
        PushEvent("downfail", JsonStr(name))
        return
    }
    SetTimer(() => DownVerifyTick(name, left - 1, gen), -1200)
}

FinishDownEscalation(name, gen, result) {
    global busy
    busy := false
    if OpCurrent(name, gen)
        DownVerifyTick(name, 8, gen)
}

; Automatic whole-radio reset removed: endpoint absence is not evidence of a
; broken radio. No background worker, delayed reconnect, or hidden retry loop.

IsLinkUp(name) {
    searchParams := Buffer(40, 0)
    NumPut("uint", 40, searchParams, 0)
    NumPut("uint", 1, searchParams, 4)
    deviceInfo := Buffer(560, 0)
    NumPut("uint", 560, deviceInfo, 0)
    handle := DllCall("Bthprops.cpl\BluetoothFindFirstDevice", "ptr", searchParams, "ptr", deviceInfo, "ptr")
    if !handle
        return false
    up := false
    loop {
        if (Format("{:012X}", NumGet(deviceInfo, 8, "uint64")) = name || StrGet(deviceInfo.Ptr + 64, "UTF-16") = name) {
            DllCall("Bthprops.cpl\BluetoothGetDeviceInfo", "ptr", 0, "ptr", deviceInfo, "uint")
            up := NumGet(deviceInfo, 20, "uint") != 0   ; 位标志，非零即已连接
            break
        }
        if !DllCall("Bthprops.cpl\BluetoothFindNextDevice", "ptr", handle, "ptr", deviceInfo)
            break
    }
    DllCall("Bthprops.cpl\BluetoothFindDeviceClose", "ptr", handle)
    return up
}

FindDevByName(name) {
    global devices
    found := 0
    for dev in devices {
        if (DeviceKey(dev) = name || dev.name = name) {
            if found {
                LogMsg("ambiguous Bluetooth device name; action skipped", "WARN")
                return 0
            }
            found := dev
        }
    }
    return found
}


RemoveDevice(name) {
    global devices
    dev := FindDevByName(name)
    if !dev
        return "notfound"
    addr := Buffer(8)
    NumPut("uint64", NumGet(dev.info, 8, "uint64"), addr, 0)
    hr := DllCall("Bthprops.cpl\BluetoothRemoveDevice", "ptr", addr, "uint")
    return (hr = 0) ? "ok" : "fail:0x" Format("{:08X}", hr)
}

; ------------------------- Update system ------------------------------
CheckUpdate(manual := false) {
    global APP_VERSION
    StartBackgroundJob("checkupdate", '{"version":' JsonStr(APP_VERSION) '}', (result, job) => OnUpdateCheck(result, manual), 30000)
}


ExtractJsonString(json, key) {
    needle := '"' key '":"'
    pos := InStr(json, needle)
    if !pos
        return ""
    start := pos + StrLen(needle)
    end := InStr(json, '"', true, start)
    return SubStr(json, start, end - start)
}

CompareVersions(a, b) {
    pa := StrSplit(a, "."), pb := StrSplit(b, ".")
    n := Max(pa.Length, pb.Length)
    loop n {
        x := (A_Index <= pa.Length) ? pa[A_Index] + 0 : 0
        y := (A_Index <= pb.Length) ? pb[A_Index] + 0 : 0
        if (x < y)
            return -1
        if (x > y)
            return 1
    }
    return 0
}

; returns "ok" or error text; restart is deferred so JS can render the result
DoUpdate(id) {
    global updateBusy, APP_VERSION
    if updateBusy {
        Reply(id, JsonStr("更新任务正在进行"))
        return
    }
    if !A_IsCompiled {
        Reply(id, JsonStr("开发模式请使用构建部署脚本"))
        return
    }
    updateBusy := true
    if !StartBackgroundJob("stageupdate", '{"version":' JsonStr(APP_VERSION) '}', (result, job) => FinishUpdateStage(id, result, job), 120000) {
        updateBusy := false
        Reply(id, JsonStr("更新任务启动失败"))
    }
}


; ------------------------- Helpers (upstream core) -------------------
IsSuccessfulOperation(action, audioProfile, hfStatus, a2Status) {
    if (action = "connect" && audioProfile = "a2dp")
        return (a2Status = "ok" && (hfStatus = "ok" || hfStatus = "absent"))
    allExposedSucceeded := (hfStatus = "ok" || hfStatus = "absent")
        && (a2Status = "ok" || a2Status = "absent")
    if (action = "disconnect")
        return allExposedSucceeded   ; 断开：服务全 absent=本来就关着，幂等成功；链路是否真断由 StartDownVerify 核实
    atLeastOneProfileExists := (hfStatus = "ok" || a2Status = "ok")
    return (allExposedSucceeded && atLeastOneProfileExists)
}

ToggleBluetoothService(deviceInfo, serviceGuidStr, toggleOn, maxRetries) {
    serviceGuid := Buffer(16)
    DllCall("ole32\CLSIDFromString", "wstr", serviceGuidStr, "ptr", serviceGuid)
    toggle := toggleOn
    retryCount := 0
    lastHR := 0
    loop {
        hr := DllCall("Bthprops.cpl\BluetoothSetServiceState", "ptr", 0, "ptr", deviceInfo, "ptr", serviceGuid, "int", toggle, "uint")
        lastHR := hr
        if (hr = 0) {
            if (toggle = toggleOn)
                return "ok"
            toggle := !toggle
        } else if (hr = 87 || hr = 0x80070057) {
            if (toggle = toggleOn && toggleOn = 0)
                return "ok"
            toggle := !toggle
        } else if (hr = 1060)
            return "absent"
        else if (hr = 1168 && toggleOn = 0)
            return "absent"   ; 1168=服务记录已不在：关已经关了的东西，幂等视为成功（v1.9.12：不再限 HFP）
        retryCount++
        if (retryCount >= maxRetries)
            return "fail:0x" . Format("{:08X}", lastHR)
    }
}


AtomicWriteText(path, text) {
    temp := path "." DllCall("GetCurrentProcessId") "." A_TickCount ".tmp"
    try {
        file := FileOpen(temp, "w", "UTF-8-RAW")
        file.Write(text)
        file.Close()
        if !DllCall("MoveFileExW", "wstr", temp, "wstr", path, "uint", 9)
            throw OSError()
        return true
    } catch as e {
        LogMsg("atomic write failed: " e.Message, "ERROR")
        return false
    } finally {
        if FileExist(temp)
            try FileDelete(temp)
    }
}

DeviceAudioState(name, connected) {
    global deviceOps, routeOwner
    if !deviceOps.Has(name)
        return "unknown"
    if !connected {
        deviceOps[name].state := "disconnected"
        return "disconnected"
    }
    if (deviceOps[name].state = "ready" && deviceOps[name].gen != routeOwner)
        return "unknown"
    if (deviceOps[name].state = "ready" && !AudioRouteMatches(DeviceLabel(name)))
        deviceOps[name].state := "audio_lost"
    return deviceOps[name].state
}


DeviceKey(dev) {
    return dev.HasOwnProp("id") ? dev.id : dev.name
}
DeviceLabel(key) {
    global devices
    dev := FindDevByName(key)
    if !dev
        return key
    matches := 0
    for candidate in devices
        if candidate.name = dev.name
            matches++
    return matches = 1 ? dev.name : "" ; fail closed until unique endpoint identity
}

FinishBluetoothAction(name, action, gen, result) {
    global busy
    try {
        if !OpCurrent(name, gen)
            return
        if result["status"] = "ok" {
            if action = "connect"
                StartLinkVerify(name, gen)
            else
                StartDownVerify(name, gen)
        } else {
            SetOpState(name, gen, "service_failed")
            PushEvent(action = "connect" ? "linkfail" : "downfail", JsonStr(name))
        }
    } finally {
        busy := false
        SetTrayLoading(false)
    }
}
DisconnectQueue(queue) {
    global busy
    if !queue.Length
        return
    if !busy {
        name := queue.RemoveAt(1)
        if DoAction(name, "disconnect") != "ok"
            PushEvent("downfail", JsonStr(name))
    }
    if queue.Length
        SetTimer(() => DisconnectQueue(queue), -200)
}

DaysSince(stamp) {
    try {
        if RegExMatch(stamp, "^\d{14}$")
            return Max(0, DateDiff(A_Now, stamp, "days"))
    }
    return 999
}

ValidBridgeArgs(cmd, parts) {
    counts := Map("list",0,"statuspoll",0,"getversion",0,"connect",1,"disconnect",1,"remove",1,"add",0,"winmin",0,"winclose",0,"openrelease",0,"openrepo",0,"stardone",0,"windrag",0,"doupdate",0,"getautostart",0,"setautostart",1,"getmicswitch",0,"setmicswitch",1,"getrescue",0,"setrescue",1,"sendfeedback",1,"sendissue",4,"getfblogs",0,"getfbwebhook",0,"openurl",1,"jserror",1)
    argc := parts.Length - 2
    if (argc = 1 && parts[3] = "")
        argc := 0
    if cmd = "setprio" {
        if (argc > 128)
            return false
        for i, part in parts
            if (i > 2 && (StrLen(part) > 256 || RegExMatch(part, "[\x00-\x1F]")))
                return false
        return true
    }
    if (!counts.Has(cmd) || argc != counts[cmd])
        return false
    if (cmd = "setautostart" || cmd = "setmicswitch" || cmd = "setrescue")
        return parts[3] = "0" || parts[3] = "1"
    if (cmd = "connect" || cmd = "disconnect" || cmd = "remove")
        return RegExMatch(parts[3], "^[0-9A-F]{12}$") != 0
    if (cmd = "sendfeedback")
        return StrLen(parts[3]) <= 1000
    if (cmd = "sendissue")
        return StrLen(parts[3]) <= 500 && StrLen(parts[4]) <= 500 && RegExMatch(parts[5], "^0[01]$") && StrLen(parts[6]) <= 60
    return true
}

OpenApprovedUrl(url) {
    if !RegExMatch(url, "^https://github\.com/lyzbcy/AirPods-Windows(?:[/#?][^\s\x00-\x20\x22<>]*)?$")
        return false
    try {
        Run(url)
        return true
    } catch {
        return false
    }
}

OnUpdateCheck(result, manual) {
    if result["status"] = "available"
        PushEvent("update", '{"ver":' JsonStr(result["version"]) ',"url":""}')
    else if manual
        PushEvent("toast", JsonStr(result["status"] = "current" ? "当前已是最新版本" : "更新检查未完成：发布包需提供可验证摘要"))
}

FinishUpdateStage(id, result, job) {
    global updateBusy, appRoot
    try {
        if result["status"] != "ready" {
            Reply(id, JsonStr("更新校验未完成，原程序保持不变"))
            return
        }
        token := Format("{:032X}", A_TickCount * 100000 + DllCall("GetCurrentProcessId"))
        request := job.dir "\swap.json"
        payload := '{"directory":' JsonStr(A_ScriptDir) ',"oldPid":' DllCall("GetCurrentProcessId") ',"token":' JsonStr(token) ',"candidate":' JsonStr(result["candidate"]) ',"version":' JsonStr(result["version"]) ',"hash":' JsonStr(result["hash"]) '}'
        FileAppend(payload, request, "UTF-8-RAW")
        Run('"' A_WinDir '\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' appRoot '\update-swap.ps1" -Request "' request '"',, "Hide")
        job.keep := true
        Reply(id, JsonStr("ok"))
        SetTimer(() => ExitApp(), -1200)
    } catch as e {
        LogMsg("update handoff failed: " e.Message, "ERROR")
        Reply(id, JsonStr("更新交接失败，原程序保持不变"))
    } finally updateBusy := false
}

MarkUpdateHealthy(core, args) {
    global APP_VERSION
    if (!args.IsSuccess || A_Args.Length != 2 || A_Args[1] != "/update-health" || !RegExMatch(A_Args[2], "^[0-9A-Fa-f]{32}$"))
        return
    AtomicWriteText(A_ScriptDir "\update-health-" A_Args[2] ".ready", APP_VERSION)
}

SendFeedbackAsync(id, text) {
    global APP_VERSION
    content := "AirPodsBuddy v" APP_VERSION " 意见反馈`n" text
    payload := '{"webhook":' JsonStr(FbWebhook()) ',"payload":{"msgtype":"markdown","markdown":{"content":' JsonStr(content) '}}}'
    SendFeedbackJob(id, "feedback", payload)
}
SendIssueAsync(id, types, note, flags, contact) {
    global feedbackBusy
    if feedbackBusy {
        Reply(id, JsonStr("busy"))
        return
    }
    wantFile := SubStr(flags, 2, 1) = "1"
    content := "问题反馈：" types "`n" note "`n联系方式：" contact "`n" TruncateUtf8(GatherLogTail(), 2200)
    logPath := wantFile ? BuildIssueLogFile() : ""
    payload := '{"webhook":' JsonStr(FbWebhook()) ',"payload":{"msgtype":"markdown","markdown":{"content":' JsonStr(content) '}},"wantFile":' (wantFile ? 'true' : 'false') ',"logPath":' JsonStr(logPath) '}'
    SendFeedbackJob(id, "issue", payload, logPath)
}
SendFeedbackJob(id, kind, payload, logPath := "") {
    global feedbackBusy
    if feedbackBusy {
        Reply(id, JsonStr("busy"))
        return
    }
    feedbackBusy := true
    if !StartBackgroundJob(kind, payload, (result, job) => FinishFeedback(id, result, logPath), 55000) {
        feedbackBusy := false
        if logPath != ""
            try FileDelete(logPath)
        Reply(id, JsonStr("net"))
    }
}
FinishFeedback(id, result, logPath) {
    global feedbackBusy
    try Reply(id, JsonStr(result["status"]))
    finally {
        feedbackBusy := false
        if logPath != ""
            try FileDelete(logPath)
    }
}

CleanManagedTemp() {
    cutoff := DateAdd(A_Now, -7, "days")
    for kind in ["AirPodsBuddy_app", "AirPodsBuddy_jobs"] {
        root := A_Temp "\" kind "\"
        loop files root "*", "D" {
            name := A_LoopFileName
            pattern := kind = "AirPodsBuddy_app" ? "^\d+\.\d+\.\d+-(\d+)$" : "^(\d+)-\d+-\d+$"
            if (RegExMatch(name, pattern, &m) && A_LoopFileTimeModified < cutoff && !ProcessExist(m[1]+0)) {
                path := A_LoopFileFullPath
                if SubStr(path, 1, StrLen(root)) = root
                    try DirDelete(path, true)
            }
        }
    }
}
