#Requires AutoHotkey v2.0
#SingleInstance Force

; =====================================================================
;  AirPods Buddy v1.1 - 米白简约风 AirPods 管理小助手
;  UI: HTML/CSS via WebView2 (webui/index.html)
;  Core connect/disconnect logic from ChromuSx/BluetoothDeviceConnector (MIT)
; =====================================================================
#Include lib\WebView2\WebView2.ahk

; ------------------------- Config ------------------------------------
APP_VERSION   := "1.1.0"
UPDATE_API    := "https://api.github.com/repos/lyzbcy/BluetoothDeviceConnector/releases/latest"
RELEASE_PAGE  := "https://github.com/lyzbcy/BluetoothDeviceConnector/releases/latest"

audioProfile := "a2dp-hfp"
maxRetries := 10
SEP := Chr(31)

; ------------------------- Resources ---------------------------------
; compiled: extract embedded web UI + loader dll to temp
appRoot := A_ScriptDir
wvDll := A_ScriptDir "\lib\WebView2\64bit\WebView2Loader.dll"
if A_IsCompiled {
    appRoot := A_Temp "\AirPodsBuddy_app"
    wvDll := appRoot "\WebView2Loader.dll"
    if !DirExist(appRoot) {
        DirCreate(appRoot "\assets")
        FileInstall "webui\index.html", appRoot "\index.html", 1
        FileInstall "webui\assets\face_main.png", appRoot "\assets\face_main.png", 1
        FileInstall "webui\assets\face_heart.png", appRoot "\assets\face_heart.png", 1
        FileInstall "webui\assets\face_like.png", appRoot "\assets\face_like.png", 1
        FileInstall "webui\assets\face_cheer.png", appRoot "\assets\face_cheer.png", 1
        FileInstall "assets\qr\qq-group.jpg", appRoot "\assets\qq-group.jpg", 1
        FileInstall "assets\qr\reward-qr.jpg", appRoot "\assets\reward-qr.jpg", 1
        FileInstall "assets\qr\sticker-qr.png", appRoot "\assets\sticker-qr.png", 1
        FileInstall "lib\WebView2\64bit\WebView2Loader.dll", appRoot "\WebView2Loader.dll", 1
    }
}
if !A_IsCompiled && FileExist(A_ScriptDir "\assets\star_pudding.ico")
    TraySetIcon(A_ScriptDir "\assets\star_pudding.ico")

devices := []
busy := false
myGui := 0
wv := 0

; ------------------------- Window ------------------------------------
WinW := 468, WinH := 748
myGui := Gui("-Caption +MinSize" WinW, "AirPods 小助手")
myGui.MarginX := 0, myGui.MarginY := 0
myGui.Show("w" WinW " h" WinH " Hide")

; Win11 rounded corners for the borderless window
DllCall("dwmapi\DwmSetWindowAttribute", "ptr", myGui.Hwnd, "int", 33, "int*", 2, "int", 4)

; ------------------------- WebView2 ----------------------------------
try {
    wvc := WebView2.create(myGui.Hwnd,, 0, EnvGet("LOCALAPPDATA") "\AirPodsBuddy_webview",, 0, wvDll)
} catch as e {
    MsgBox("界面引擎(WebView2)初始化失败：`n" e.Message "`n`n请安装微软 Edge 或 WebView2 Runtime 后重试。", "AirPods 小助手", "Icon!")
    ExitApp(1)
}
wv := wvc.CoreWebView2
try {
    wv.Settings.AreDevToolsEnabled := false
    wv.Settings.AreDefaultContextMenusEnabled := false
}
wv.add_WebMessageReceived(WebMessageHandler)
wv.Navigate("file:///" StrReplace(appRoot, "\", "/") "/index.html")

myGui.OnEvent("Close", (*) => myGui.Hide())
myGui.OnEvent("Size", (*) => wvc.Fill())
myGui.Show()
A_IconTip := "AirPods 小助手 v" APP_VERSION

A_TrayMenu.Delete()
A_TrayMenu.Add("打开界面", (*) => myGui.Show())
A_TrayMenu.Add("检查更新", (*) => CheckUpdate(true))
A_TrayMenu.Add()
A_TrayMenu.Add("退出", (*) => ExitApp())
A_TrayMenu.Default := "打开界面"
A_TrayMenu.Click := 1

SetTimer(CheckUpdate, -3000)

; ------------------------- JS bridge ---------------------------------
; protocol: "cmd<SEP>id<SEP>arg1<SEP>arg2..."
WebMessageHandler(core, args) {
    msg := args.TryGetWebMessageAsString()
    parts := StrSplit(msg, Chr(31))
    cmd := parts[1]
    id := parts[2]
    arg1 := parts.Length >= 3 ? parts[3] : ""

    switch cmd {
        case "list", "statuspoll": Reply(id, BuildDevicesJson())
        case "getversion":        Reply(id, JsonStr(APP_VERSION))
        case "connect":           Reply(id, DoAction(arg1, "connect"))
        case "disconnect":        Reply(id, DoAction(arg1, "disconnect"))
        case "remove":            Reply(id, RemoveDevice(arg1))
        case "add":               Run("ms-settings:bluetooth"), Reply(id, "true")
        case "winmin":            myGui.Minimize(), Reply(id, "true")
        case "winclose":          myGui.Hide(), Reply(id, "true")
        case "doupdate":          Reply(id, DoUpdate(arg1))
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
    out := "["
    for i, dev in devices {
        if (i > 1)
            out .= ","
        out .= '{"name":' JsonStr(dev.name) ',"connected":' (dev.connected ? 'true' : 'false') '}'
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
