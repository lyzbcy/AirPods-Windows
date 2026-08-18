#Requires AutoHotkey v2.0
#SingleInstance Force

; =====================================================================
;  AirPods Buddy - 米白简约风 AirPods 管理小助手
;  Fork feature: GUI front-end for pairing management + one-click connect.
;  Core connect/disconnect logic reused from bluetooth_device_connector.ahk
;  by ChromuSx (MIT). Device enumeration via Bthprops.cpl Win32 API.
; =====================================================================

; ------------------------- Theme (globals) ---------------------------
C_BG     := "FAF7F2"   ; 米白背景
C_TEXT   := "3F3A35"   ; 主文字
C_SUB    := "8C8478"   ; 次级文字
C_LINE   := "E8E2D8"   ; 分隔线
C_ACCENT := "A08668"   ; 暖棕强调色
C_OK     := "6E9B5F"   ; 已连接
C_ERR    := "B85C50"   ; 错误
FONT     := "Microsoft YaHei UI"

audioProfile := "a2dp-hfp"
maxRetries := 10

; ------------------------- Update ------------------------------------
APP_VERSION   := "1.0.1"
UPDATE_API    := "https://api.github.com/repos/lyzbcy/BluetoothDeviceConnector/releases/latest"
RELEASE_PAGE  := "https://github.com/lyzbcy/BluetoothDeviceConnector/releases/latest"

; ------------------------- Resources ---------------------------------
; Flat resource paths, valid in both compiled and uncompiled modes.
gPicMain := A_ScriptDir "\assets\star_kawaii.png"
gQrQQ := A_ScriptDir "\assets\qr\qq-group.jpg"
gQrReward := A_ScriptDir "\assets\qr\reward-qr.jpg"
gQrSticker := A_ScriptDir "\assets\qr\sticker-qr.png"
if A_IsCompiled {
    dir := A_Temp "\AirPodsBuddy_assets"
    if !DirExist(dir) {
        DirCreate(dir)
        FileInstall "assets\star_kawaii.png", dir "\star_kawaii.png", 1
        FileInstall "assets\qr\qq-group.jpg", dir "\qq-group.jpg", 1
        FileInstall "assets\qr\reward-qr.jpg", dir "\reward-qr.jpg", 1
        FileInstall "assets\qr\sticker-qr.png", dir "\sticker-qr.png", 1
    }
    gPicMain := dir "\star_kawaii.png"
    gQrQQ := dir "\qq-group.jpg"
    gQrReward := dir "\reward-qr.jpg"
    gQrSticker := dir "\sticker-qr.png"
}

if !A_IsCompiled && FileExist(A_ScriptDir "\assets\star_pudding.ico")
    TraySetIcon(A_ScriptDir "\assets\star_pudding.ico")

devices := []       ; [{name, info(Buffer), connected}]
rowCtrls := []      ; dynamic row controls
statusText := 0
busy := false
myGui := 0

DllCall("LoadLibrary", "str", "Bthprops.cpl", "ptr")

; ------------------------- Main GUI ----------------------------------
BuildMainGui() {
    global myGui, gPicMain, C_BG, C_TEXT, C_SUB, FONT
    myGui := Gui("+MinSize540", "AirPods 小助手")
    myGui.BackColor := C_BG
    myGui.SetFont("s9 c" C_TEXT, FONT)

    myGui.Add("Picture", "x24 y20 w64 h64 Background" C_BG, gPicMain)
    myGui.SetFont("s16 bold")
    myGui.Add("Text", "x104 y26 w380 BackgroundTrans", "AirPods 小助手")
    myGui.SetFont("s9 norm c" C_SUB)
    myGui.Add("Text", "x104 y60 w380 BackgroundTrans", "大道至简 · 一键连接 · 星星布丁保驾护航")

    myGui.Add("Text", "x24 y100 w492 0x10 BackgroundTrans")   ; SS_ETCHEDHORZ divider

    myGui.SetFont("s10 bold c" C_TEXT)
    myGui.Add("Text", "x24 y112 w300 BackgroundTrans", "已配对的耳机")
    myGui.SetFont("s9 norm")
    btnRefresh := myGui.Add("Button", "x448 y108 w68 h26", "↻ 刷新")
    btnRefresh.OnEvent("Click", (*) => RefreshDeviceList())

    myGui.OnEvent("Close", (*) => myGui.Hide())   ; close = hide to tray
    myGui.Show("w540")
    A_IconTip := "AirPods 小助手 v" APP_VERSION "（双击图标打开界面）"

    ; tray menu: reopen / check update / exit
    A_TrayMenu.Delete()
    A_TrayMenu.Add("打开界面", (*) => myGui.Show())
    A_TrayMenu.Add("检查更新", (*) => CheckUpdate(true))
    A_TrayMenu.Add()
    A_TrayMenu.Add("退出", (*) => ExitApp())
    A_TrayMenu.Default := "打开界面"
    A_TrayMenu.Click := 1   ; single click opens

    RefreshDeviceList()
    SetTimer(UpdateStatus, 4000)
    SetTimer(CheckUpdate, -2500)   ; silent update check on first launch
}

SetStatus(msg, color) {
    global statusText
    if !IsObject(statusText)
        return
    statusText.SetFont("c" color)
    statusText.Text := msg
}

; ------------------------- Device logic ------------------------------
; Enumerate paired Bluetooth audio devices (major class Audio/Video = 0x04).
FindAllAudioDevices() {
    global devices
    devices := []
    searchParams := Buffer(40, 0)
    NumPut("uint", 40, searchParams, 0)
    NumPut("uint", 1, searchParams, 4)     ; fReturnAuthenticated

    deviceInfo := Buffer(560, 0)
    NumPut("uint", 560, deviceInfo, 0)

    searchHandle := DllCall("Bthprops.cpl\BluetoothFindFirstDevice", "ptr", searchParams, "ptr", deviceInfo, "ptr")
    if !searchHandle
        return

    loop {
        cod := NumGet(deviceInfo, 16, "uint")
        if ((cod >> 8) & 0x1F) = 4 {      ; Audio/Video major device class
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

; (Re)build device rows + footer. Layout is fully dynamic.
RefreshDeviceList() {
    global rowCtrls, myGui, statusText, devices, C_TEXT, C_SUB, C_LINE, C_ACCENT, C_OK, FONT
    for c in rowCtrls
        try c.Destroy()
    rowCtrls := []

    FindAllAudioDevices()

    y := 146
    if devices.Length = 0 {
        myGui.SetFont("s9 c" C_SUB)
        rowCtrls.Push(myGui.Add("Text", "x24 y" y + 16 " w492 h40 Center BackgroundTrans",
            "还没有已配对的耳机`n点下方「添加新耳机」，跟着指引两分钟搞定"))
        y += 76
    } else {
        for dev in devices {
            myGui.SetFont("s10 bold c" C_TEXT)
            rowCtrls.Push(myGui.Add("Text", "x24 y" y " w300 BackgroundTrans", dev.name))
            myGui.SetFont("s9 bold c" (dev.connected ? C_OK : C_SUB))
            st := myGui.Add("Text", "x24 y" y + 24 " w240 BackgroundTrans",
                (dev.connected ? "● 已连接" : "○ 未连接"))
            st.isStatus := true
            rowCtrls.Push(st)

            myGui.SetFont("s9 norm c" C_TEXT)
            b1 := myGui.Add("Button", "x330 y" y - 2 " w58 h26", "连接")
            b1.OnEvent("Click", (*) => DoAction(dev.name, "connect"))
            rowCtrls.Push(b1)
            b2 := myGui.Add("Button", "x394 y" y - 2 " w58 h26", "断开")
            b2.OnEvent("Click", (*) => DoAction(dev.name, "disconnect"))
            rowCtrls.Push(b2)
            b3 := myGui.Add("Button", "x458 y" y - 2 " w58 h26", "删除")
            b3.OnEvent("Click", (*) => RemoveDevice(dev.name))
            rowCtrls.Push(b3)

            y += 56
            if A_Index < devices.Length {
                ln := myGui.Add("Text", "x24 y" y - 8 " w492 h1 Background" C_LINE)
                rowCtrls.Push(ln)
            }
        }
    }

    y += 6
    myGui.SetFont("s10 bold c" C_ACCENT)
    btnAdd := myGui.Add("Button", "x24 y" y " w492 h40 Default", "＋  添加新耳机（打开系统蓝牙设置，附指引）")
    btnAdd.OnEvent("Click", (*) => AddDeviceFlow())
    rowCtrls.Push(btnAdd)

    y += 52
    ln2 := myGui.Add("Text", "x24 y" y " w492 0x10 BackgroundTrans")
    rowCtrls.Push(ln2)
    y += 10

    myGui.SetFont("s8 c" C_SUB)
    statusText := myGui.Add("Text", "x24 y" y " w360 BackgroundTrans", "v" APP_VERSION " · 检测到 " devices.Length " 台已配对耳机")
    rowCtrls.Push(statusText)

    myGui.SetFont("s8 c" C_ACCENT " underline")
    aboutLink := myGui.Add("Text", "x400 y" y " w116 Right BackgroundTrans", "关于捞鱼 🐟")
    aboutLink.OnEvent("Click", (*) => ShowAbout())
    rowCtrls.Push(aboutLink)

    myGui.Move(, , , y + 30)
    SetStatus("v" APP_VERSION " · 检测到 " devices.Length " 台已配对耳机", C_SUB)
}

; Silent status poll: refresh fConnected, update status labels only.
UpdateStatus() {
    global rowCtrls, devices, busy, C_OK, C_SUB
    if busy
        return
    n := 0
    for c in rowCtrls {
        if IsObject(c) && c.HasProp("isStatus")
            n++
    }
    if (n != devices.Length)
        return
    for dev in devices {
        DllCall("Bthprops.cpl\BluetoothGetDeviceInfo", "ptr", 0, "ptr", dev.info, "uint")
        dev.connected := NumGet(dev.info, 20, "uint") = 1
    }
    i := 0
    for c in rowCtrls {
        if c.HasProp("isStatus") {
            i++
            dev := devices[i]
            c.SetFont("c" (dev.connected ? C_OK : C_SUB))
            c.Text := dev.connected ? "● 已连接" : "○ 未连接"
        }
    }
}

DoAction(name, action) {
    global busy, devices, audioProfile, maxRetries, C_ACCENT, C_OK, C_ERR
    if busy {
        SetStatus("上一个操作还在进行中…", C_ERR)
        return
    }
    dev := FindDevByName(name)
    if !dev
        return
    busy := true
    SetStatus((action = "connect") ? "正在连接 «" name "» …" : "正在断开 «" name "» …", C_ACCENT)

    if (action = "connect") {
        hfOn := (audioProfile = "a2dp-hfp") ? 1 : 0
        hf := ToggleBluetoothService(dev.info, "{0000111e-0000-1000-8000-00805f9b34fb}", hfOn, maxRetries)
        a2 := ToggleBluetoothService(dev.info, "{0000110b-0000-1000-8000-00805f9b34fb}", 1, maxRetries)
    } else {
        hf := ToggleBluetoothService(dev.info, "{0000111e-0000-1000-8000-00805f9b34fb}", 0, maxRetries)
        a2 := ToggleBluetoothService(dev.info, "{0000110b-0000-1000-8000-00805f9b34fb}", 0, maxRetries)
    }

    if (IsSuccessfulOperation(action, audioProfile, hf, a2)) {
        SetStatus((action = "connect" ? "已连接 💕  " : "已断开 💤  ") "«" name "»", C_OK)
    } else {
        SetStatus("操作失败 «" name "» (HF: " hf "  A2DP: " a2 ")", C_ERR)
    }
    busy := false
    RefreshDeviceList()
}

FindDevByName(name) {
    global devices
    for dev in devices
        if (dev.name = name)
            return dev
    return 0
}

RemoveDevice(name) {
    global devices, myGui, C_OK, C_ERR
    dev := FindDevByName(name)
    if !dev
        return
    if (MsgBox("确定要删除 «" name "» 吗？`n删除后需要重新配对才能再次连接。", "删除设备",
            "YesNo Icon! Owner" myGui.Hwnd) != "Yes")
        return
    addr := Buffer(8)
    NumPut("uint64", NumGet(dev.info, 8, "uint64"), addr, 0)
    hr := DllCall("Bthprops.cpl\BluetoothRemoveDevice", "ptr", addr, "uint")
    if (hr = 0) {
        SetStatus("已删除 «" name "» ✅", C_OK)
    } else {
        SetStatus("删除失败 (0x" Format("{:08X}", hr) ")", C_ERR)
    }
    RefreshDeviceList()
}

AddDeviceFlow() {
    Run("ms-settings:bluetooth")
    ShowAddHelp()
}

; ------------------------- Help window -------------------------------
ShowAddHelp() {
    global gPicMain, gQrQQ, gQrReward, gQrSticker, myGui, C_BG, C_TEXT, C_SUB, FONT
    hGui := Gui("+AlwaysOnTop Owner" myGui.Hwnd, "🎧 添加指引")
    hGui.BackColor := C_BG
    hGui.SetFont("s9 c" C_TEXT, FONT)

    hGui.Add("Picture", "x20 y20 w56 h56 Background" C_BG, gPicMain)
    hGui.SetFont("s12 bold")
    hGui.Add("Text", "x92 y28 w360 BackgroundTrans", "跟着做，两分钟搞定")
    hGui.SetFont("s9 norm c" C_SUB)
    hGui.Add("Text", "x92 y56 w360 BackgroundTrans", "已为你打开系统蓝牙设置页面")

    hGui.Add("Text", "x20 y92 w440 0x10 BackgroundTrans")

    hGui.SetFont("s9 c" C_TEXT)
    hGui.Add("Text", "x20 y106 w440 BackgroundTrans",
        "①  📴 先断开旧连接`n     把之前连着这副 AirPods 的设备（iPhone / iPad / Mac）`n     的蓝牙关掉，让耳机处于待连接状态。")
    hGui.Add("Text", "x20 y172 w440 BackgroundTrans",
        "②  💡 让耳机进入「待连接模式」（白灯闪烁）`n     • AirPods 1 / 2 / 3 代、Pro 系列：开盖 → 长按充电盒`n       背面小按钮，直到白灯闪烁`n     • AirPods 4 代：开盖 → 敲击两下充电盒，白灯闪烁`n     • AirPods Max：按住顶部降噪按钮，直到白灯闪烁")
    hGui.Add("Text", "x20 y272 w440 BackgroundTrans",
        "③  ➕ 在系统设置里点「添加设备」，选择你的 AirPods`n     等待出现「已连接」即配对成功。")
    hGui.Add("Text", "x20 y322 w440 BackgroundTrans",
        "④  🏠 配对完成后，回到小助手点「刷新」就能看到它啦")

    btnDone := hGui.Add("Button", "x160 y376 w160 h34 Default", "我配对好了，去刷新 ✨")
    btnDone.OnEvent("Click", (*) => (hGui.Destroy(), RefreshDeviceList()))
    hGui.Show("w480")
}

; ------------------------- About window ------------------------------
ShowAbout() {
    global gPicMain, gQrQQ, gQrReward, gQrSticker, myGui, C_BG, C_TEXT, C_SUB, FONT
    aGui := Gui("+Owner" myGui.Hwnd, "关于捞鱼 🐟")
    aGui.BackColor := C_BG
    aGui.SetFont("s9 c" C_TEXT, FONT)

    aGui.Add("Picture", "x20 y20 w56 h56 Background" C_BG, gPicMain)
    aGui.SetFont("s12 bold")
    aGui.Add("Text", "x92 y26 w400 BackgroundTrans", "捞鱼 lyzbcy")
    aGui.SetFont("s9 norm c" C_SUB)
    aGui.Add("Text", "x92 y54 w400 BackgroundTrans", "和星星布丁一起做的开源小工具 · 用爱发电")

    aGui.Add("Text", "x20 y92 w560 0x10 BackgroundTrans")

    aGui.SetFont("s10 bold c" C_TEXT)
    aGui.Add("Text", "x60 y104 w140 Center BackgroundTrans", "粉丝群")
    aGui.Add("Text", "x240 y104 w140 Center BackgroundTrans", "赞赏码")
    aGui.Add("Text", "x420 y104 w140 Center BackgroundTrans", "星星布丁表情包")
    aGui.Add("Picture", "x60 y130 w140 h140", gQrQQ)
    aGui.Add("Picture", "x240 y130 w140 h140", gQrReward)
    aGui.Add("Picture", "x420 y130 w140 h140", gQrSticker)
    aGui.SetFont("s8 norm c" C_SUB)
    aGui.Add("Text", "x60 y276 w140 Center BackgroundTrans", "一起摸鱼聊技术")
    aGui.Add("Text", "x240 y276 w140 Center BackgroundTrans", "帮到了你就请我喝杯奶茶")
    aGui.Add("Text", "x420 y276 w140 Center BackgroundTrans", "超可爱的表情包，快扫码收藏")

    aGui.Show("w620")
}

; ------------------------- Update system ------------------------------
; Check GitHub latest release vs APP_VERSION.
; manual=true shows a toast even when up-to-date (tray menu entry).
CheckUpdate(manual := false) {
    global APP_VERSION, UPDATE_API, RELEASE_PAGE
    json := ""
    try {
        jsonPath := A_Temp "\AirPodsBuddy_release.json"
        Download(UPDATE_API, jsonPath)
        json := FileRead(jsonPath, "UTF-8")
    } catch {
        if manual
            SetStatus("检查更新失败：无法访问网络", C_ERR)
        return
    }
    remoteTag := ExtractJsonString(json, "tag_name")
    if (remoteTag = "") {
        if manual
            SetStatus("检查更新失败：解析版本信息出错", C_ERR)
        return
    }
    remoteVer := StrReplace(remoteTag, "v")
    if (CompareVersions(APP_VERSION, remoteVer) >= 0) {
        if manual
            SetStatus("v" APP_VERSION " 已是最新版本 ✅", C_OK)
        return
    }
    ; find the zip asset download url (GitHub API JSON is compact: no space after colon)
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
            SetStatus("发现新版本 v" remoteVer "，但未找到下载包", C_ERR)
        return
    }
    ShowUpdateGui(remoteVer, dlUrl)
}

; Minimal JSON string-field extractor for compact API JSON: "key":"value"
ExtractJsonString(json, key) {
    needle := '"' key '":"'
    pos := InStr(json, needle)
    if !pos
        return ""
    start := pos + StrLen(needle)
    end := InStr(json, '"', true, start)
    return SubStr(json, start, end - start)
}

; Semantic version compare: -1 (a<b), 0 (equal), 1 (a>b)
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

; Cream-white update dialog: one-click update / release page / later.
ShowUpdateGui(remoteVer, dlUrl) {
    global myGui, gPicMain, APP_VERSION, RELEASE_PAGE, C_BG, C_TEXT, C_SUB, C_ACCENT, C_ERR, FONT
    uGui := Gui("+AlwaysOnTop Owner" myGui.Hwnd, "发现新版本 ✨")
    uGui.BackColor := C_BG
    uGui.SetFont("s9 c" C_TEXT, FONT)

    uGui.Add("Picture", "x24 y22 w56 h56 Background" C_BG, gPicMain)
    uGui.SetFont("s13 bold")
    uGui.Add("Text", "x96 y24 w380 BackgroundTrans", "发现新版本 v" remoteVer)
    uGui.SetFont("s9 norm c" C_SUB)
    uGui.Add("Text", "x96 y54 w380 BackgroundTrans", "当前版本 v" APP_VERSION " · 建议更新以获得最新功能与修复")

    uGui.Add("Text", "x24 y94 w440 0x10 BackgroundTrans")

    st := uGui.Add("Text", "x24 y106 w440 c" C_SUB " BackgroundTrans", "更新内容请见发布页。点「一键更新」自动完成下载与安装。")

    btnGo := uGui.Add("Button", "x24 y142 w200 h38 Default", "🚀 一键更新")
    btnPage := uGui.Add("Button", "x234 y142 w120 h38", "🌐 发布页")
    btnLater := uGui.Add("Button", "x364 y142 w100 h38", "下次再说")
    btnGo.OnEvent("Click", (*) => DoUpdate(dlUrl, st, uGui))
    btnPage.OnEvent("Click", (*) => Run(RELEASE_PAGE))
    btnLater.OnEvent("Click", (*) => uGui.Destroy())
    uGui.Show("w488")
}

; One-click self update: download zip -> extract -> swap exe -> restart.
DoUpdate(dlUrl, stCtrl, uGui) {
    global C_OK, C_ERR, C_ACCENT
    zipPath := A_Temp "\AirPodsBuddy_update.zip"
    extDir := A_Temp "\AirPodsBuddy_update"
    exeDir := A_ScriptDir

    ; 1. download
    stCtrl.SetFont("c" C_ACCENT)
    stCtrl.Text := "⬇ 正在下载更新包…（约 2 MB）"
    try
        Download(dlUrl, zipPath)
    catch {
        stCtrl.SetFont("c" C_ERR)
        stCtrl.Text := "下载失败，请检查网络后重试，或到发布页手动下载。"
        return
    }

    ; 2. extract (Windows 10+ ships tar.exe which handles zip)
    stCtrl.Text := "📦 正在解压…"
    DirDelete(extDir, true)
    DirCreate(extDir)
    RunWait(A_ComSpec ' /c tar -xf "' zipPath '" -C "' extDir '"',, "Hide")
    newExe := extDir "\AirPodsBuddy.exe"
    if !FileExist(newExe) {
        stCtrl.SetFont("c" C_ERR)
        stCtrl.Text := "解压失败：未找到新版程序，请到发布页手动下载。"
        return
    }

    ; 3. stage new exe next to the running one
    try
        FileCopy(newExe, exeDir "\AirPodsBuddy_new.exe", true)
    catch {
        stCtrl.SetFont("c" C_ERR)
        stCtrl.Text := "无法写入程序目录（权限不足），请到发布页手动更新。"
        return
    }

    ; 4. hand off to a tiny PowerShell swapper: wait for us to exit, replace, restart
    stCtrl.SetFont("c" C_OK)
    stCtrl.Text := "✅ 下载完成，正在重启到新版本…"
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
    ExitApp()
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

BuildMainGui()
