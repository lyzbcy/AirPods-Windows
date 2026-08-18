#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; =====================================================================
;  Bluetooth Tray Connector - taskbar-resident variant
;  Fork feature: sits in the tray, right-click menu with one-click
;  connect / disconnect for a paired Bluetooth audio device.
;  Core logic reused from bluetooth_device_connector.ahk (Bthprops.cpl).
; =====================================================================

; ------------------------- Configuration ----------------------------
deviceName := "AirPods Pro"
audioProfile := "a2dp-hfp"   ; "a2dp" = stereo only, "a2dp-hfp" = stereo + mic
maxRetries := 10

iconPath := A_ScriptDir "\assets\star_pudding.ico"
fallbackIcon := "C:\WINDOWS\system32\netshell.dll"

; ------------------------- Tray setup --------------------------------
appTitle := "星星布丁连接器"
A_IconTip := appTitle " - " deviceName
if FileExist(iconPath)
    TraySetIcon(iconPath)
else
    TraySetIcon(fallbackIcon, 104)

busy := false

trayMenu := A_TrayMenu
trayMenu.Delete()
trayMenu.Add("一键连接", (*) => DoAction("connect"))
trayMenu.Add("一键断开", (*) => DoAction("disconnect"))
trayMenu.Add()
trayMenu.Add("退出", (*) => ExitApp())
trayMenu.Default := "一键连接"   ; double-click the tray icon = connect

; Load the Windows Bluetooth Control Panel API.
DllCall("LoadLibrary", "str", "Bthprops.cpl", "ptr")

; ------------------------- Actions -----------------------------------
DoAction(action) {
    global busy, deviceName, audioProfile, maxRetries, appTitle
    if busy {
        TrayTip(appTitle, "上一个操作还在进行中，请稍候…", 2)
        return
    }
    busy := true

    verb := (action = "connect") ? "正在连接" : "正在断开"
    TrayTip(appTitle, verb " «" deviceName "» …", 2)

    device := FindDeviceByName(deviceName)
    if (!device) {
        TrayTip(appTitle, "找不到已配对设备 «" deviceName "» " Chr(10) "请先在 Windows 蓝牙设置中配对。", 3)
        busy := false
        return
    }
    deviceNameActual := StrGet(device.Ptr + 64, "UTF-16")

    if (action = "connect") {
        hfToggleOn := (audioProfile = "a2dp-hfp") ? 1 : 0
        hfStatus := ToggleBluetoothService(device, "{0000111e-0000-1000-8000-00805f9b34fb}", hfToggleOn, maxRetries)
        asStatus := ToggleBluetoothService(device, "{0000110b-0000-1000-8000-00805f9b34fb}", 1, maxRetries)
    } else {
        hfStatus := ToggleBluetoothService(device, "{0000111e-0000-1000-8000-00805f9b34fb}", 0, maxRetries)
        asStatus := ToggleBluetoothService(device, "{0000110b-0000-1000-8000-00805f9b34fb}", 0, maxRetries)
    }

    if (IsSuccessfulOperation(action, audioProfile, hfStatus, asStatus)) {
        done := (action = "connect") ? "已连接 💕" : "已断开 💤"
        profile := (action = "connect") ? Chr(10) "模式: " AudioProfileLabel(audioProfile) : ""
        TrayTip(appTitle, "«" deviceNameActual "» " done profile, 1)
    } else {
        TrayTip(appTitle, "操作失败: «" deviceNameActual "»" Chr(10)
                "Hands-Free: " hfStatus "  AudioSink: " asStatus, 3)
    }
    busy := false
}

; ------------------------- Helpers (from upstream) -------------------
AudioProfileLabel(audioProfile) {
    return (audioProfile = "a2dp") ? "立体声 (A2DP)" : "立体声+麦克风 (A2DP+HFP)"
}

MakeSearchParams() {
    structSize := 24 + A_PtrSize * 2
    searchParams := Buffer(structSize, 0)
    NumPut("uint", structSize, searchParams, 0)
    NumPut("uint", 1, searchParams, 4)
    return searchParams
}

; Return the first paired device whose name contains targetName, or 0.
FindDeviceByName(targetName) {
    searchParams := MakeSearchParams()
    deviceInfo := Buffer(560, 0)
    NumPut("uint", 560, deviceInfo, 0)

    searchHandle := DllCall("Bthprops.cpl\BluetoothFindFirstDevice", "ptr", searchParams, "ptr", deviceInfo, "ptr")
    if !searchHandle
        return 0

    match := 0
    loop
    {
        if (InStr(StrGet(deviceInfo.Ptr + 64, "UTF-16"), targetName))
        {
            match := deviceInfo
            break
        }
        if !DllCall("Bthprops.cpl\BluetoothFindNextDevice", "ptr", searchHandle, "ptr", deviceInfo)
            break
    }

    DllCall("Bthprops.cpl\BluetoothFindDeviceClose", "ptr", searchHandle)
    return match
}

; Stereo-only success requires A2DP. Combined connects and disconnects require
; every exposed service to reach the requested state, while allowing devices
; that legitimately lack either Hands-Free or AudioSink.
IsSuccessfulOperation(action, audioProfile, hfStatus, asStatus) {
    if (action = "connect" && audioProfile = "a2dp")
        return (asStatus = "ok" && (hfStatus = "ok" || hfStatus = "absent"))

    allExposedSucceeded := (hfStatus = "ok" || hfStatus = "absent")
        && (asStatus = "ok" || asStatus = "absent")
    atLeastOneProfileExists := (hfStatus = "ok" || asStatus = "ok")
    return (allExposedSucceeded && atLeastOneProfileExists)
}

; Toggle one Bluetooth audio service to the desired state.
; Returns "ok", "absent", or "fail:0x...".
ToggleBluetoothService(deviceInfo, serviceGuidStr, toggleOn, maxRetries) {
    serviceGuid := Buffer(16)
    DllCall("ole32\CLSIDFromString", "wstr", serviceGuidStr, "ptr", serviceGuid)

    toggle := toggleOn
    retryCount := 0
    lastHR := 0
    loop
    {
        hr := DllCall("Bthprops.cpl\BluetoothSetServiceState", "ptr", 0, "ptr", deviceInfo, "ptr", serviceGuid, "int", toggle, "uint")
        lastHR := hr

        if (hr = 0)
        {
            if (toggle = toggleOn)
                return "ok"
            toggle := !toggle
        }
        else if (hr = 87 || hr = 0x80070057)
        {
            if (toggle = toggleOn && toggleOn = 0)
                return "ok"
            toggle := !toggle
        }
        else if (hr = 1060)
            return "absent"
        else if (hr = 1168 && toggleOn = 0 && StrLower(serviceGuidStr) = "{0000111e-0000-1000-8000-00805f9b34fb}")
            return "absent"

        retryCount++
        if (retryCount >= maxRetries)
            return "fail:0x" . Format("{:08X}", lastHR)
    }
}
