#Requires AutoHotkey v2.0
#SingleInstance Off
#Include ..\lib\BackgroundJobs.ahk
FileEncoding("UTF-8-RAW")
OnError((e, mode) => (FileAppend("ERROR " e.Message "`n", "*"), ExitApp(2)))
backgroundJobs := [], appRoot := "", resultStatus := "", callbackCount := 0
dir := A_Temp "\AirPodsBuddy_jobs\" DllCall("GetCurrentProcessId") "-" A_TickCount "-9999"
DirCreate(dir)
pid := 0
Run('"' A_WinDir '\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -Command "Start-Sleep -Seconds 30"',, "Hide", &pid)
handle := DllCall("OpenProcess", "uint", 0x101001, "int", 0, "uint", pid, "ptr")
job := {dir:dir, handle:handle, result:dir "\result.txt", started:A_TickCount-500, timeout:10, callback:Finished,keep:false}
backgroundJobs.Push(job)
PollBackgroundJob(job)
if (resultStatus != "fail" || callbackCount != 1 || job.handle != 0 || backgroundJobs.Length || DirExist(dir) || ProcessExist(pid)) {
    FileAppend("FAIL worker_timeout_cleanup`n", "*")
    ExitApp(1)
}
FileAppend("PASS worker_timeout_terminates_owned_process`nPASS callback_runs_once`nPASS private_files_and_handle_cleaned`nRESULT failures=0`n", "*")
ExitApp(0)
Finished(result, job) {
    global resultStatus, callbackCount
    resultStatus := result["status"]
    callbackCount++
}
LogMsg(*) {
}
EnsureResources() {
}
JsonStr(s) {
    return '"' s '"'
}
