from pathlib import Path

root = Path(__file__).resolve().parents[2]
src = (root / "airpods_buddy.ahk").read_text(encoding="utf-8-sig")
anchor = 'wv2Fallback := ""   ; 提前初始化：/testpet 模式在 EnsureWebView2Runtime 之前就会进 PetEnsure'
assert src.count(anchor) == 1
hook = r'''

; Temporary, headless regression harness; never shipped in the app source.
if (A_Args.Length = 1 && (A_Args[1] = "/regressionprobe" || A_Args[1] = "/regressiondisconnect" || A_Args[1] = "/regressionaudio" || A_Args[1] = "/regressionaudiohfp")) {
    LOG_DIR := A_ScriptDir "\live_logs"
    mode := A_Args[1]
    if (mode = "/regressionprobe") {
        p := appRoot "\pet_built.html"
        try FileDelete(p)
        petOk := PetEnsure()
        existsAfter := FileExist(p) ? 1 : 0
        LogMsg("REGRESSION petrestore ok=" (petOk ? 1 : 0) " exists=" existsAfter)
        RUN_KEY := "Software\APBRegression_20260925"
        RUN_NAME := "AirPodsBuddyProbe"
        SETTINGS_PATH := A_Temp "\APB_regression_settings.ini"
        SettingWrite("autostart", "1")
        try RegDelete("HKCU\" RUN_KEY, RUN_NAME)
        AutostartRepair()
        regValue := ""
        try regValue := RegRead("HKCU\" RUN_KEY, RUN_NAME)
        LogMsg("REGRESSION autostart restored=" (regValue != "" ? 1 : 0))
        RegWrite('"C:\stale.exe"', "REG_SZ", "HKCU\" RUN_KEY, RUN_NAME)
        AutostartRepair()
        repairedValue := RegRead("HKCU\" RUN_KEY, RUN_NAME)
        staleFixed := (repairedValue = '"' A_ScriptFullPath '"')
        LogMsg("REGRESSION autostart stale_path_fixed=" (staleFixed ? 1 : 0) " state=" AutostartEnabled())
        try RegDelete("HKCU\" RUN_KEY, RUN_NAME)
        try FileDelete(SETTINGS_PATH)
        devices := []
        FindAllAudioDevices()
        for dev in devices
            LogMsg("REGRESSION device name=" dev.name " connected=" (dev.connected ? 1 : 0))
        ExitApp(petOk && existsAfter && regValue != "" && staleFixed ? 0 : 1)
    }
    devices := []
    busy := false
    trayLoading := false
    trayLoadFrame := 0
    lastTrayOn := -1
    audioVerifyGen := 0
    SETTINGS_PATH := "C:\Users\24676\Desktop\AirPodsBuddy\app_settings.ini"
    if (mode = "/regressionaudiohfp") {
        SETTINGS_PATH := A_Temp "\APB_audiohfp_test.ini"
        try FileDelete(SETTINGS_PATH)
        FileAppend("auto_mic_switch=1`n", SETTINGS_PATH, "UTF-8")
    }
    FindAllAudioDevices()
    target := ""
    alreadyConnected := false
    for dev in devices {
        LogMsg("REGRESSION device name=" dev.name " connected=" (dev.connected ? 1 : 0))
        if (InStr(StrLower(dev.name), "airpods")) {
            target := dev.name
            alreadyConnected := dev.connected
        }
    }
    if (target = "") {
        LogMsg("REGRESSION disconnect skipped: AirPods not paired", "WARN")
        ExitApp(3)
    }
    if (mode = "/regressionaudio" || mode = "/regressionaudiohfp") {
        connectResult := DoAction(target, "connect")
        LogMsg("REGRESSION audio connect target=" target " result=" connectResult)
        Sleep(19000)
        render := 0, capture := 0
        try {
            wmi := ComObject("WbemScripting.SWbemLocator").ConnectServer(".", "root\cimv2")
            for ep in wmi.ExecQuery("SELECT Name, PNPDeviceID, ConfigManagerErrorCode FROM Win32_PnPEntity WHERE PnPClass='AudioEndpoint'") {
                if (InStr(ep.Name, target) && ep.ConfigManagerErrorCode = 0) {
                    if InStr(ep.PNPDeviceID, "{0.0.0.")
                        render++
                    if InStr(ep.PNPDeviceID, "{0.0.1.")
                        capture++
                }
            }
        } catch as e {
            LogMsg("REGRESSION audio endpoint query error=" e.Message, "ERROR")
        }
        LogMsg("REGRESSION audio final link=" (IsLinkUp(target) ? 1 : 0) " render=" render " capture=" capture)
        if (mode = "/regressionaudiohfp")
            try FileDelete(SETTINGS_PATH)
        ExitApp(render > 0 ? 0 : 4)
    }
    if (!alreadyConnected) {
        connectResult := DoAction(target, "connect")
        LogMsg("REGRESSION connect target=" target " result=" connectResult)
        Sleep(14000)
        FindAllAudioDevices()
        linked := FindDevByName(target)
        if (!linked || !linked.connected) {
            LogMsg("REGRESSION disconnect skipped: AirPods link did not come up", "WARN")
            ExitApp(3)
        }
    }
    result := DoAction(target, "disconnect")
    LogMsg("REGRESSION disconnect target=" target " result=" result)
    Sleep(15000)
    ExitApp(result = "ok" ? 0 : 1)
}
'''
out = root / "REGRESSION_20260925.ahk"
out.write_text(src.replace(anchor, anchor + hook), encoding="utf-8", newline="\r\n")
print(out)
