#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent   ; 常驻托盘：关闭窗口 = 缩到托盘，程序继续运行（开机自启依赖此行为）

; =====================================================================
;  AirPods Buddy v1.2 - 米白简约风 AirPods 管理小助手
;  UI: HTML/CSS via WebView2 (webui/index.html)
;  Core connect/disconnect logic from ChromuSx/BluetoothDeviceConnector (MIT)
; =====================================================================
#Include lib\WebView2\WebView2.ahk

; ------------------------- Config ------------------------------------
APP_VERSION   := "1.9.7"
UPDATE_API    := "https://api.github.com/repos/lyzbcy/AirPods-Windows/releases/latest"
RELEASE_PAGE  := "https://github.com/lyzbcy/AirPods-Windows/releases/latest"
; 微软官方 Evergreen Bootstrapper 直链（约 2MB，缺失运行时时的自愈安装器）
WEBVIEW2_SETUP_URL := "https://go.microsoft.com/fwlink/p/?LinkId=2124703"

audioProfile := "a2dp-hfp"
maxRetries := 10
SEP := Chr(31)

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
LoadPriority()

; ------------------------- Device priority ---------------------------
; 用户自定义的"一键连接"优先顺序（每行一个设备名），Apple 设备默认排前。
SETTINGS_PATH := A_ScriptDir "pp_settings.ini"
PRIO_PATH := A_ScriptDir "\device_priority.txt"
priorityList := []

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
    try {
        FileDelete(PRIO_PATH)
        FileAppend(Join(priorityList, "`n") "`n", PRIO_PATH, "UTF-8")
    }
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
        if (StrLower(pn) = n)
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
    appRoot := A_Temp "\AirPodsBuddy_app"
    uiHtml := appRoot "\index_built.html"
    wvDll := appRoot "\WebView2Loader.dll"
    DirCreate(appRoot)
    ; always overwrite: prevents stale/partial extractions
    FileInstall "webui\index_built.html", appRoot "\index_built.html", 1
    FileInstall "webui\pet_built.html", appRoot "\pet_built.html", 1
    FileInstall "tools\noise_mode.ps1", appRoot "\noise_mode.ps1", 1
    FileInstall "lib\WebView2\64bit\WebView2Loader.dll", appRoot "\WebView2Loader.dll", 1
    FileInstall "assets\face_off.ico", appRoot "\face_off.ico", 1
    FileInstall "assets\face_on.ico", appRoot "\face_on.ico", 1
    FileInstall "assets\loading_0.ico", appRoot "\loading_0.ico", 1
    FileInstall "assets\loading_1.ico", appRoot "\loading_1.ico", 1
    FileInstall "assets\loading_2.ico", appRoot "\loading_2.ico", 1
    FileInstall "assets\loading_3.ico", appRoot "\loading_3.ico", 1
    FileInstall "assets\loading_4.ico", appRoot "\loading_4.ico", 1
    FileInstall "assets\loading_5.ico", appRoot "\loading_5.ico", 1
}
LogMsg("boot v" APP_VERSION " compiled=" A_IsCompiled " scriptdir=" A_ScriptDir)

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
    code := 0
    RunWait(A_ComSpec ' /c powershell -NoProfile -ExecutionPolicy Bypass -File "' ps1 '" -Mac ' addr ' -Mode ' mode,, "Hide", &code)
    if (code = 0) {
        TrayTip("AirPods 小助手", "已切换「" target.name "」→ " modeName " 🎧", 1)
        LogMsg("noise mode ok: " modeName)
    } else {
        ; 根因（子 Agent 实证）：Windows 用户态 Winsock L2CAP 不可用（bind 都
        ; 报 10050），Apple 控制通道需内核驱动（MagicPods 即此路线）。
        TrayTip("AirPods 小助手", "Windows 无法直接切降噪（需内核驱动）`n建议安装 MagicPods：magicpods.app", 3)
        LogMsg("noise mode FAILED exit=" code "（详见 noise_debug.log）", "WARN")
    }
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
    if (IsSet(petGui) && petGui != 0)
        return true
    p := A_IsCompiled ? (appRoot "\pet_built.html") : (A_ScriptDir "\webui\pet_built.html")
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
    petWv.add_WebMessageReceived(PetOnMsg)
    petWv.NavigateToString(FileRead(p, "UTF-8"))
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
    global WEBVIEW2_SETUP_URL
    if (WebView2RuntimeVersion() != "")
        return ""
    LogMsg("WebView2 runtime missing, auto-repair starting", "WARN")
    if MsgBox("系统缺少界面引擎组件 WebView2 Runtime（微软官方组件，约 2MB）。`n`n是否现在自动下载并安装？`n安装完成后程序会自动继续。", "AirPods 小助手", "YesNo Icon!") != "Yes" {
        LogMsg("user declined auto-install, trying Edge fallback", "WARN")
        return EdgeFallbackDir()
    }
    busy := Gui("+AlwaysOnTop -Caption +ToolWindow")
    busy.SetFont("s10")
    busy.BackColor := "FFFFFF"
    busy.AddText("w300 Center", "正在下载界面组件（约 2 MB）…`n来自微软官方，请稍候")
    busy.Show()
    exe := A_Temp "\AirPodsBuddy_WebView2Setup.exe"
    try {
        Download WEBVIEW2_SETUP_URL, exe
        code := RunWait('"' exe '" /silent /install')
        LogMsg("WebView2 setup exit code " code)
        if (WebView2RuntimeVersion() != "") {
            LogMsg("WebView2 runtime installed via auto-repair")
            return ""
        }
    } catch as e {
        LogMsg("WebView2 auto-repair failed: " e.Message, "WARN")
    } finally {
        try busy.Destroy()
        try FileDelete(exe)
    }
    ; 下载/安装没成功（断网、UAC 被拒、被安全软件拦截）：降级借 Edge 目录
    LogMsg("auto-repair unsuccessful, falling back to local Edge", "WARN")
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
            if MsgBox("界面引擎（WebView2）初始化失败：`n" e.Message "`n`n通常是系统缺少 WebView2 Runtime（精简版系统较常见），`n或被安全软件拦截。安装 Edge 浏览器是没有用的哦。`n`n点「是」打开官方下载页，安装完成后重新运行本程序；`n仍失败的话，请把本程序加入安全软件白名单。", "AirPods 小助手", "YesNo Icon!") = "Yes"
                Run(WEBVIEW2_SETUP_URL)
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
wv.add_WebMessageReceived(WebMessageHandler)
wv.add_NavigationCompleted((wv2, args) => LogMsg(
    "navigation " (args.IsSuccess ? "ok" : "FAILED webError=" args.WebErrorStatus),
    args.IsSuccess ? "INFO" : "ERROR"))

htmlText := FileRead(uiHtml, "UTF-8")
LogMsg("loading UI html chars=" StrLen(htmlText))
wv.NavigateToString(htmlText)

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
            TrayTip("AirPods 小助手", "「" devices[1].name "」已经连着啦 ✅", 1)
            return
        }
        PetShow("connecting")
        SetTrayLoading(true)
        r := DoAction(target.name, "connect")
        SetTrayLoading(false)
        if (r = "ok") {
            ; 真实链路由 LinkVerifyTick 异步核实，完成后修正宠物与提示
            TrayTip("AirPods 小助手", "正在连接 «" target.name "» …", 2)
        } else {
            PetFinish("fail")
            TrayTip("AirPods 小助手", "连接失败 «" target.name "»", 3)
        }
    } else {
        any := false
        first := true
        for dev in devices {
            if dev.connected {
                any := true
                if (first) {
                    PetShow("disconnecting")
                    first := false
                }
                SetTrayLoading(true)
                DoAction(dev.name, "disconnect")
                SetTrayLoading(false)
            }
        }
        if any {
            PetFinish("off")
            TrayTip("AirPods 小助手", "已断开全部耳机 💤", 1)
        }
        else
            TrayTip("AirPods 小助手", "当前没有连接中的耳机", 2)
    }
}

SetTimer(CheckUpdate, -3000)
SetTimer(CheckUpdateReceipt, -3500)   ; v1.9.2：核对上次自动更新回执，如实告知

; v1.9.2：上次更新置换的回执（swapper 写入 update_result.txt）。
; ok → 确认 toast；fail → 多半被 360 等安全软件拦截，如实提醒用户。
; ------------------------- 意见反馈（v1.9.6） -------------------------
; 通道：企业微信群机器人 webhook（免注册免跳转，直发用户手里）。
; webhook 存 app_settings.ini 的 feedback_webhook，可随时换 key 不用重编译。
; 未配置 → 返回 "nochan"，前端降级为打开预填好的 GitHub issue。
SendFeedback(text) {
    s := Trim(text)
    if (s = "")
        return "empty"
    if (StrLen(s) > 1000)
        s := SubStr(s, 1, 1000)
    s := RegExReplace(s, "[\xDC00-\xDFFF]$", "")   ; 截断可能切裂 emoji 代理对
    webhook := SettingRead("feedback_webhook", "")
    if (webhook = "")
        webhook := "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=93bbfb6e-6d93-437e-a8ab-605062cc5db5"
    content := "📮 **AirPods 小助手 意见反馈**`n> " s "`n`n— v" APP_VERSION " · Windows"
    payload := '{"msgtype":"markdown","markdown":{"content":' JsonStr(content) '}}'
    ; powershell.exe 直连发送（v1.9.7）：系统签名二进制，安全软件对它和浏览器
    ; 一样宽容（实测 curl.exe 会被主动防御拦截网络，curl=空 reason=net）。
    ; 脚本走 -EncodedCommand（base64 UTF-16LE，免引号/免落 ps1 文件）；
    ; payload/响应走临时文件，UTF-8-RAW 无 BOM（带 BOM 企微 API 报 40008 但 HTTP=200）。
    jsonFile := A_Temp "\AirPodsBuddy_fb.json"
    respFile := A_Temp "\AirPodsBuddy_fb_resp.txt"
    try FileDelete(jsonFile)
    try FileDelete(respFile)
    try {
        f := FileOpen(jsonFile, "w", "UTF-8-RAW")   ; "w"=覆盖语义；UTF-8-RAW=无 BOM（带 BOM 企微 API 拒收但 HTTP=200）
        f.Write(payload)
        f.Close()
    } catch {
        LogMsg("feedback: payload write failed", "WARN")
        return "net"
    }
    ps := "$ErrorActionPreference='Stop'`n"
    ps .= "try {`n"
    ps .= "  $b=[IO.File]::ReadAllBytes($args[0])`n"
    ps .= "  $r=Invoke-WebRequest -Uri $args[1] -Method Post -ContentType 'application/json' -Body $b -TimeoutSec 12 -UseBasicParsing`n"
    ps .= "  [IO.File]::WriteAllText($args[2], $r.Content)`n"
    ps .= "  exit 0`n"
    ps .= "} catch { exit 1 }"
    enc := B64Utf16(ps)
    ; RunWait 签名：Target[, WorkingDir, Options, &PID] —— 参数必须并进 Target 单串（P0 修复）
    target := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand " enc " \"" jsonFile "\" \"" webhook "\" \"" respFile "\""
    try ec := RunWait(target, , "Hide")
    catch {
        LogMsg("feedback: powershell launch failed", "WARN")
        ec := -1
    }
    r := ""
    try r := FileRead(respFile, "UTF-8")
    try FileDelete(respFile)
    try FileDelete(jsonFile)
    if (ec = 0 && InStr(r, '"errcode":0')) {
        LogMsg("feedback delivered (" StrLen(s) " chars)")
        return "ok"
    }
    ; 失败归因：ec=1 → 传输层失败（网络/拦截）；有响应体但 errcode≠0 → 服务端拒绝
    reason := "net"
    if (ec = 0) {
        pos := InStr(r, '"errcode":')
        if (pos) {
            codeTxt := SubStr(r, pos + 10)
            if RegExMatch(codeTxt, "^-?\d+", &m)
                reason := "api:" m[0]
        }
    }
    LogMsg("feedback failed: ec=" ec " reason=" reason " resp=" r, "WARN")
    return reason
}

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

; ------------------------- 开机自启动（v1.9.5 设置项） -------------------------
; 机制：HKCU Run 键（任务管理器→启动应用 可见可逆，免管理员）。
; 兼容旧版启动文件夹快捷方式（存在即视为已开启，切换时迁移到注册表）。
; 若被安全软件/任务管理器禁用（StartupApproved 首字节为奇数），返回
; "disabled" 让前端如实提示，而不是假装开关没生效。
RUN_KEY   := "Software\Microsoft\Windows\CurrentVersion\Run"
RUN_NAME  := "AirPodsBuddy"

AutostartEnabled() {
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
            if (StrLen(bin) >= 1 && (NumGet(bin, 0, "uchar") & 1))
                return "disabled"   ; Run 键还在但被禁用（安全软件/任务管理器所为）
        } catch {
        }
        return "on"
    }
    return lnkOn ? "on" : "off"
}

AutostartSet(on) {
    lnk := A_Startup "\AirPods小助手.lnk"
    if (on) {
        exe := '"' A_ScriptFullPath '"'
        RegWrite(exe, "REG_SZ", "HKCU\" RUN_KEY, RUN_NAME)
        ; 清掉可能的禁用标记
        try RegDelete("HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run", RUN_NAME)
        ; 迁移：启动文件夹快捷方式不再需要，避免双开
        try FileDelete(lnk)
        LogMsg("autostart ON: " exe)
    } else {
        try RegDelete("HKCU\" RUN_KEY, RUN_NAME)
        try FileDelete(lnk)
        LogMsg("autostart OFF")
    }
    return "ok"
}

CheckUpdateReceipt() {
    p := A_ScriptDir "\update_result.txt"   ; 与 DoUpdate 的 exeDir(A_ScriptDir) 一致
    if !FileExist(p)
        return
    r := Trim(StrReplace(FileRead(p, "UTF-8"), Chr(0xFEFF), ""))   ; 去 BOM（PS5.1 UTF8 写入带 BOM）
    try FileDelete(p)
    if (r = "ok") {
        LogMsg("update swap receipt: ok")
        PushEvent("toast", JsonStr("已成功更新到 v" APP_VERSION " ✅"))
    } else {
        LogMsg("update swap receipt: " r, "WARN")
        PushEvent("toast", JsonStr("上次自动更新没完成（多半被安全软件拦截），仍在旧版本。把软件目录加入安全软件信任区后再更新一次即可"))
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
    try {
        FileDelete(SETTINGS_PATH)
        FileAppend(Join(lines, "`n") "`n", SETTINGS_PATH, "UTF-8")
    }
}

connectCount := 0
audioVerifyGen := 0   ; 音频抢占验证的代数号：新操作/断开时 +1，作废旧轮询

; ------------------- 音频抢占验证（v1.9.1） --------------------------
; 蓝牙层连接成功 ≠ 音频通道建立：手机正在放歌时 AirPods 不对电脑开放
; A2DP（实测：占用时该设备的 AudioEndpoint 根本不出现，空闲时 4~8s 内
; 到 OK）。连接成功后轮询端点，起来了才算真抢到，否则如实提醒用户。
; Windows 无公开 API 参与音源仲裁（Mac 的"谁播放跟谁走"做不到），
; 我们的上限 = 手机空闲时抢过来 + 抢不到时把情况说清楚。
StartAudioVerify(name) {
    global audioVerifyGen
    AudioVerifyTick(name, 7, ++audioVerifyGen)
}

AudioVerifyTick(name, left, gen) {
    global audioVerifyGen
    if (gen != audioVerifyGen)
        return   ; 已被断开/新连接取代，本轮作废
    if (AudioEndpointAlive(name)) {
        LogMsg("audio endpoint verified: '" name "'")
        PushEvent("toast", JsonStr("🎧 音频已切到电脑"))
        return
    }
    if (left <= 1) {
        LogMsg("audio endpoint NOT up after ~9s (held by phone?): '" name "'", "WARN")
        PetUpdate("fail")
        TrayTip("AirPods 小助手", "已连上 «" name "»，但声音还被手机占着`n暂停手机音乐后，再点一次连接即可抢过来", 4)
        PushEvent("audioheld", JsonStr(name))
        return
    }
    fn := (*) => AudioVerifyTick(name, left - 1, gen)
    SetTimer(fn, -1500)
}

AudioEndpointAlive(name) {
    safe := StrReplace(name, "'", "''")
    q := "SELECT ConfigManagerErrorCode FROM Win32_PnPEntity WHERE PnPClass='AudioEndpoint' AND Name LIKE '%" safe "%'"
    try {
        wmi := ComObject("WbemScripting.SWbemLocator").ConnectServer(".", "root\cimv2")
        for dev in wmi.ExecQuery(q)
            if (dev.ConfigManagerErrorCode = 0)
                return true
    } catch as e {
        LogMsg("audio endpoint WMI query failed: " e.Message, "WARN")
    }
    return false
}


OnConnectSuccess() {
    global connectCount, wv
    connectCount := SettingRead("connect_count", "0") + 0
    connectCount++
    SettingWrite("connect_count", connectCount)
    if (connectCount = 10 || Mod(connectCount, 50) = 0) {
        last := SettingRead("star_ask_last", "0") + 0
        days := (A_Now - last) / 86400
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
    global myGui, APP_VERSION
    msg := args.TryGetWebMessageAsString()
    parts := StrSplit(msg, Chr(31))
    cmd := parts[1]
    id := parts[2]
    arg1 := parts.Length >= 3 ? parts[3] : ""

    ; frontend forwards window.onerror / unhandledrejection here
    if (cmd = "jserror") {
        LogMsg("[JS-ERROR] " arg1, "ERROR")
        return
    }
    if (cmd != "statuspoll")
        LogMsg(cmd = "sendfeedback" ? "rpc: sendfeedback (" StrLen(arg1) " chars)" : "rpc: " msg)

    switch cmd {
        ; NOTE: Reply() injects its payload as a raw JS expression. Anything that
        ; is not already a JS literal (true/false/null/number/"quoted") must be
        ; wrapped with JsonStr(), otherwise the frontend receives bare identifiers
        ; (ReferenceError) or pre-parsed objects (JSON.parse throws "[object Object]").
        case "list", "statuspoll": Reply(id, JsonStr(BuildDevicesJson())), UpdateTrayIcon()
        case "getversion":        Reply(id, JsonStr(APP_VERSION))
        case "connect":           SetTrayLoading(true), Reply(id, JsonStr(DoAction(arg1, "connect"))), SetTrayLoading(false)
        case "disconnect":        SetTrayLoading(true), Reply(id, JsonStr(DoAction(arg1, "disconnect"))), SetTrayLoading(false)
        case "remove":            Reply(id, JsonStr(RemoveDevice(arg1)))
        case "add":               Run("ms-settings:bluetooth"), Reply(id, "true")
        case "winmin":            myGui.Hide(), Reply(id, "true")   ; 最小化即缩托盘：不占任务栏（初心），随时托盘唤出
        case "winclose":          myGui.Hide(), Reply(id, "true")
        case "openrelease":        Run(RELEASE_PAGE), Reply(id, "true")
        case "openrepo":           Run("https://github.com/lyzbcy/AirPods-Windows"), Reply(id, "true")
        case "stardone":           StarAskShown(), Reply(id, "true")
        case "windrag":           StartWindowDrag(), Reply(id, "true")
        case "setprio":
            priorityList := StrSplit(arg1, Chr(31))
            SavePriority()
            LogMsg("priority updated: " arg1)
            Reply(id, "true")
        case "doupdate":          Reply(id, JsonStr(DoUpdate(arg1)))
        case "getautostart":      Reply(id, JsonStr(AutostartEnabled()))
        case "setautostart":      Reply(id, JsonStr(AutostartSet(arg1 = "1")))
        case "sendfeedback":      Reply(id, JsonStr(SendFeedback(arg1)))
        case "openurl":           Run(arg1), Reply(id, "true")
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
    s := StrReplace(s, "`n", "\n")
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
        out .= '{"name":' JsonStr(dev.name) ',"connected":' (dev.connected ? 'true' : 'false') ',"apple":' (IsAppleDevice(dev.name) ? 'true' : 'false') '}'
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
    global busy, devices, audioProfile, maxRetries, audioVerifyGen
    if busy
        return "busy"
    dev := FindDevByName(name)
    if !dev
        return "notfound"
    busy := true
    SetTrayLoading(true)
    if (action = "connect") {
        ; 用户实测调优（2026-09-05）：先断后连——清掉半死链路，真实成功率显著提高
        ToggleBluetoothService(dev.info, "{0000111e-0000-1000-8000-00805f9b34fb}", 0, 3)
        ToggleBluetoothService(dev.info, "{0000110b-0000-1000-8000-00805f9b34fb}", 0, 3)
        Sleep 400
        hfOn := (audioProfile = "a2dp-hfp") ? 1 : 0
        hf := ToggleBluetoothService(dev.info, "{0000111e-0000-1000-8000-00805f9b34fb}", hfOn, maxRetries)
        a2 := ToggleBluetoothService(dev.info, "{0000110b-0000-1000-8000-00805f9b34fb}", 1, maxRetries)
    } else {
        audioVerifyGen++   ; 断开：作废进行中的音频验证
        hf := ToggleBluetoothService(dev.info, "{0000111e-0000-1000-8000-00805f9b34fb}", 0, maxRetries)
        a2 := ToggleBluetoothService(dev.info, "{0000110b-0000-1000-8000-00805f9b34fb}", 0, maxRetries)
    }
    ok := IsSuccessfulOperation(action, audioProfile, hf, a2)
    if !ok
        LogMsg("DoAction " action " '" name "' failed: HFP=" hf " A2DP=" a2, "WARN")
    busy := false
    SetTrayLoading(false)
    if (ok && action = "connect")
        StartLinkVerify(name)   ; 服务开关 ok ≠ 真连上，异步核实真实链路
    return ok ? "ok" : "fail"
}

; v1.9.4：真实链路核实。BluetoothSetServiceState 返回 ok ≠ 真连上
; （设备太远/没电时照样返回 ok，用户实测 Beats 放远处仍报成功）。
; 用 fConnected（真实链路位，实测 32=连）判定，约 9 秒内没起来就如实报失败。
StartLinkVerify(name) {
    global audioVerifyGen
    LinkVerifyTick(name, 8, ++audioVerifyGen)
}

LinkVerifyTick(name, left, gen) {
    global audioVerifyGen
    if (gen != audioVerifyGen)
        return
    if (IsLinkUp(name)) {
        LogMsg("link verified: '" name "'")
        OnConnectSuccess()
        PetUpdate("ok")
        TrayTip("AirPods 小助手", "已连接 «" name "» 💕", 1)
        PushEvent("linkok", JsonStr(name))
        AudioVerifyTick(name, 7, gen)   ; 链路真通了，继续核实音频通道
        return
    }
    if (left <= 1) {
        LogMsg("link NOT up after ~9s: '" name "'", "WARN")
        PetUpdate("fail")
        TrayTip("AirPods 小助手", "没能连上 «" name "»`n耳机可能不在附近、没电，或正被手机使用", 4)
        PushEvent("linkfail", JsonStr(name))
        return
    }
    fn := (*) => LinkVerifyTick(name, left - 1, gen)
    SetTimer(fn, -1200)
}

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
        if (StrGet(deviceInfo.Ptr + 64, "UTF-16") = name) {
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
    for dev in devices
        if (dev.name = name)
            return dev
    return 0
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
    global APP_VERSION, UPDATE_API, RELEASE_PAGE
    json := ""
    try {
        jsonPath := A_Temp "\AirPodsBuddy_release.json"
        Download(UPDATE_API, jsonPath)
        json := FileRead(jsonPath, "UTF-8")
    } catch {
        if manual
            PushEvent("toast", JsonStr("检查更新失败：无法访问网络"))
        return
    }
    remoteTag := ExtractJsonString(json, "tag_name")
    if (remoteTag = "") {
        if manual
            PushEvent("toast", JsonStr("检查更新失败：解析版本信息出错"))
        return
    }
    remoteVer := StrReplace(remoteTag, "v")
    if (CompareVersions(APP_VERSION, remoteVer) >= 0) {
        if manual
            PushEvent("toast", JsonStr("v" APP_VERSION " 已是最新版本 ✅"))
        return
    }
    LogMsg("update available: local v" APP_VERSION " -> remote v" remoteVer)
    dlUrl := ""
    needleUrl := '"browser_download_url":"'
    pos := 1
    loop {
        pos := InStr(json, needleUrl, true, pos)
        if !pos
            break
        start := pos + StrLen(needleUrl)
        end := InStr(json, '"', true, start)
        url := SubStr(json, start, end - start)
        if InStr(url, "AirPodsBuddy-Windows.zip") {
            dlUrl := url
            break
        }
        pos := end
    }
    if (dlUrl = "") {
        if manual
            PushEvent("toast", JsonStr("发现新版本 v" remoteVer "，但未找到下载包"))
        return
    }
    PushEvent("update", '{"ver":' JsonStr(remoteVer) ',"url":' JsonStr(dlUrl) '}')
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
DoUpdate(dlUrl) {
    zipPath := A_Temp "\AirPodsBuddy_update.zip"
    extDir := A_Temp "\AirPodsBuddy_update"
    exeDir := A_ScriptDir

    try
        Download(dlUrl, zipPath)
    catch
        return "下载失败，请检查网络"

    DirDelete(extDir, true)
    DirCreate(extDir)
    RunWait(A_ComSpec ' /c tar -xf "' zipPath '" -C "' extDir '"',, "Hide")
    newExe := extDir "\AirPodsBuddy.exe"
    if !FileExist(newExe)
        return "解压失败：未找到新版程序"

    try
        FileCopy(newExe, exeDir "\AirPodsBuddy_new.exe", true)
    catch
        return "无法写入程序目录（权限不足）"

    ps1 := A_Temp "\AirPodsBuddy_swapper.ps1"
    ; v1.9.2：换文件可能被安全软件（360 等）静默拦截 → 一律 -ErrorAction Stop，
    ; 成败写入 update_result.txt 回执，下次启动核对并如实告知（不再假报成功）。
    FileAppend(
        "param([int]`$OldPid, [string]`$Dir)`n" .
        "try {`n" .
        "  Wait-Process -Id `$OldPid -ErrorAction SilentlyContinue`n" .
        "  Start-Sleep -Milliseconds 800`n" .
        "  Move-Item -LiteralPath (Join-Path `$Dir 'AirPodsBuddy_new.exe') -Destination (Join-Path `$Dir 'AirPodsBuddy.exe') -Force -ErrorAction Stop`n" .
        "  Set-Content -LiteralPath (Join-Path `$Dir 'update_result.txt') -Value 'ok' -Encoding UTF8`n" .
        "} catch {`n" .
        "  Set-Content -LiteralPath (Join-Path `$Dir 'update_result.txt') -Value ('fail ' + `$_.Exception.Message) -Encoding UTF8`n" .
        "} finally {`n" .
        "  Start-Process -FilePath (Join-Path `$Dir 'AirPodsBuddy.exe')`n" .
        "  Start-Sleep -Milliseconds 500`n" .
        "  Remove-Item -LiteralPath (Join-Path `$Dir 'AirPodsBuddy_new.exe') -Force -ErrorAction SilentlyContinue`n" .
        "  Remove-Item -LiteralPath `$MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue`n" .
        "}",
        ps1, "UTF-8")
    Run('powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' ps1 '" -OldPid ' ProcessExist() ' -Dir "' exeDir '"',, "Hide")
    SetTimer((*) => ExitApp(), -1200)   ; give the page time to show the result
    return "ok"
}

; ------------------------- Helpers (upstream core) -------------------
IsSuccessfulOperation(action, audioProfile, hfStatus, a2Status) {
    if (action = "connect" && audioProfile = "a2dp")
        return (a2Status = "ok" && (hfStatus = "ok" || hfStatus = "absent"))
    allExposedSucceeded := (hfStatus = "ok" || hfStatus = "absent")
        && (a2Status = "ok" || a2Status = "absent")
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
        else if (hr = 1168 && toggleOn = 0 && StrLower(serviceGuidStr) = "{0000111e-0000-1000-8000-00805f9b34fb}")
            return "absent"
        retryCount++
        if (retryCount >= maxRetries)
            return "fail:0x" . Format("{:08X}", lastHR)
    }
}
