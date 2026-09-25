#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon

key := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
name := "AirPodsBuddy"
exe := "C:\Users\24676\Desktop\AirPodsBuddy\AirPodsBuddy.exe"
logPath := A_ScriptDir "\live_startup_probe.log"
expected := '"' exe '"'
result := "fail"
try {
    before := RegRead(key, name)
    FileAppend("before=" before "`n", logPath, "UTF-8")
    RegDelete(key, name)
    missing := false
    try {
        RegRead(key, name)
    } catch {
        missing := true
    }
    FileAppend("deleted=" (missing ? 1 : 0) "`n", logPath, "UTF-8")
    if !missing
        throw Error("Run value still present after delete")
    Run('"' exe '"')
    Sleep(5000)
    after := ""
    try after := RegRead(key, name)
    FileAppend("after=" after "`n", logPath, "UTF-8")
    FileAppend("process=" (ProcessExist("AirPodsBuddy.exe") ? 1 : 0) "`n", logPath, "UTF-8")
    if (after = expected && ProcessExist("AirPodsBuddy.exe"))
        result := "pass"
} catch as e {
    FileAppend("error=" e.Message "`n", logPath, "UTF-8")
}
if (result != "pass") {
    try RegWrite(expected, "REG_SZ", key, name)
}
FileAppend("result=" result "`n", logPath, "UTF-8")
ExitApp(result = "pass" ? 0 : 1)
