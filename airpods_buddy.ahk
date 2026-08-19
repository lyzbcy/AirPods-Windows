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
APP_VERSION   := "1.3.1"
UPDATE_API    := "https://api.github.com/repos/lyzbcy/BluetoothDeviceConnector/releases/latest"
RELEASE_PAGE  := "https://github.com/lyzbcy/BluetoothDeviceConnector/releases/latest"

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
    FileInstall "lib\WebView2\64bit\WebView2Loader.dll", appRoot "\WebView2Loader.dll", 1
    FileInstall "assets\star_pudding_on.ico", appRoot "\star_pudding_on.ico", 1
    FileInstall "assets\star_pudding.ico", appRoot "\star_pudding_off.ico", 1
}
LogMsg("boot v" APP_VERSION " compiled=" A_IsCompiled " scriptdir=" A_ScriptDir)
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

; 托盘状态图标：断开=原版布丁，连接=绿圈布丁；只在状态变化时切换防闪烁
TrayIconPath(onState) {
    global appRoot
    if A_IsCompiled
        p := appRoot (onState ? "\star_pudding_on.ico" : "\star_pudding_off.ico")
    else
        p := A_ScriptDir "\assets\" (onState ? "star_pudding_on.ico" : "star_pudding.ico")
    return FileExist(p) ? p : 0
}

UpdateTrayIcon() {
    global lastTrayOn
    on := AnyConnected()
    if (on = lastTrayOn)
        return
    lastTrayOn := on
    p := TrayIconPath(on)
    if p
        TraySetIcon(p)
    A_IconTip := on ? "AirPods 小助手 · 已连接（左键切换）" : "AirPods 小助手 · 未连接（左键切换）"
}

; 左键单击托盘图标 = 在"连接首选设备 / 断开全部"之间切换
ToggleQuickAction() {
    if AnyConnected()
        TrayQuickAction("disconnect")
    else
        TrayQuickAction("connect")
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
; 创建失败（如被安全软件瞬时拦截 0x800704C7）时自动重试
wvc := 0
loop 3 {
    try {
        wvc := WebView2.create(myGui.Hwnd,, 0, EnvGet("LOCALAPPDATA") "\AirPodsBuddy_webview",, 0, wvDll)
        break
    } catch as e {
        LogMsg("WebView2 init attempt " A_Index " failed: " e.Message, "WARN")
        if (A_Index = 3) {
            LogMsg("WebView2 init failed permanently", "ERROR")
            MsgBox("界面引擎(WebView2)初始化失败：`n" e.Message "`n`n请安装微软 Edge 或 WebView2 Runtime 后重试，`n或将本程序加入安全软件白名单。", "AirPods 小助手", "Icon!")
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

A_TrayMenu.Delete()
A_TrayMenu.Add("⇄ 切换连接（左键直达）", (*) => ToggleQuickAction())
A_TrayMenu.Add("打开界面", (*) => (myGui.Show(), SyncWebView()))
A_TrayMenu.Add()
A_TrayMenu.Add("🎧 一键连接", (*) => TrayQuickAction("connect"))
A_TrayMenu.Add("🚫 一键断开", (*) => TrayQuickAction("disconnect"))
A_TrayMenu.Add()
A_TrayMenu.Add("检查更新", (*) => CheckUpdate(true))
A_TrayMenu.Add("退出", (*) => ExitApp())
A_TrayMenu.Default := "⇄ 切换连接（左键直达）"   ; 单击左键即触发，右键才弹菜单
A_TrayMenu.Click := 1
lastTrayOn := -1
UpdateTrayIcon()

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
        r := DoAction(target.name, "connect")
        if (r = "ok")
            TrayTip("AirPods 小助手", "已连接 💕 «" target.name "»", 1)
        else
            TrayTip("AirPods 小助手", "连接失败 «" target.name "»", 3)
    } else {
        any := false
        for dev in devices {
            if dev.connected {
                any := true
                DoAction(dev.name, "disconnect")
            }
        }
        if any
            TrayTip("AirPods 小助手", "已断开全部耳机 💤", 1)
        else
            TrayTip("AirPods 小助手", "当前没有连接中的耳机", 2)
    }
}

SetTimer(CheckUpdate, -3000)

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
        LogMsg("rpc: " msg)

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
        case "windrag":           StartWindowDrag(), Reply(id, "true")
        case "setprio":
            priorityList := StrSplit(arg1, Chr(31))
            SavePriority()
            LogMsg("priority updated: " arg1)
            Reply(id, "true")
        case "doupdate":          Reply(id, JsonStr(DoUpdate(arg1)))
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
                connected: NumGet(info, 20, "uint") = 1
            })
        }
        if !DllCall("Bthprops.cpl\BluetoothFindNextDevice", "ptr", searchHandle, "ptr", deviceInfo)
            break
    }
    DllCall("Bthprops.cpl\BluetoothFindDeviceClose", "ptr", searchHandle)
}

DoAction(name, action) {
    global busy, devices, audioProfile, maxRetries
    if busy
        return "busy"
    dev := FindDevByName(name)
    if !dev
        return "notfound"
    busy := true
    if (action = "connect") {
        hfOn := (audioProfile = "a2dp-hfp") ? 1 : 0
        hf := ToggleBluetoothService(dev.info, "{0000111e-0000-1000-8000-00805f9b34fb}", hfOn, maxRetries)
        a2 := ToggleBluetoothService(dev.info, "{0000110b-0000-1000-8000-00805f9b34fb}", 1, maxRetries)
    } else {
        hf := ToggleBluetoothService(dev.info, "{0000111e-0000-1000-8000-00805f9b34fb}", 0, maxRetries)
        a2 := ToggleBluetoothService(dev.info, "{0000110b-0000-1000-8000-00805f9b34fb}", 0, maxRetries)
    }
    ok := IsSuccessfulOperation(action, audioProfile, hf, a2)
    if !ok
        LogMsg("DoAction " action " '" name "' failed: HFP=" hf " A2DP=" a2, "WARN")
    busy := false
    return ok ? "ok" : "fail"
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
    FileAppend(
        "param([int]`$OldPid, [string]`$Dir)`n" .
        "Wait-Process -Id `$OldPid -ErrorAction SilentlyContinue`n" .
        "Start-Sleep -Milliseconds 800`n" .
        "Move-Item -LiteralPath (Join-Path `$Dir 'AirPodsBuddy_new.exe') -Destination (Join-Path `$Dir 'AirPodsBuddy.exe') -Force`n" .
        "Start-Process -FilePath (Join-Path `$Dir 'AirPodsBuddy.exe')`n" .
        "Remove-Item -LiteralPath `$MyInvocation.MyCommand.Path -Force`n",
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
