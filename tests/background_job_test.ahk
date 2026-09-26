#Requires AutoHotkey v2.0
#SingleInstance Off
#Include ..\lib\BackgroundJobs.ahk
FileEncoding("UTF-8-RAW")
OnError((e, mode) => (FileAppend("ERROR " e.Message "`n", "*"), ExitApp(2)))
backgroundJobs := [], appRoot := "", resultStatus := "", resultError := false, callbackCount := 0
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
FileAppend("PASS worker_timeout_terminates_owned_process`nPASS callback_runs_once`nPASS private_files_and_handle_cleaned`n", "*")

; A signaled Win32 event models a worker that has already exited. Delayed
; polling must read its result even though the deadline has passed.
doneDir := A_Temp "\AirPodsBuddy_jobs\" DllCall("GetCurrentProcessId") "-" A_TickCount "-9998"
DirCreate(doneDir)
FileAppend("status=ok`n", doneDir "\result.txt", "UTF-8-RAW")
doneHandle := DllCall("CreateEventW", "ptr", 0, "int", 1, "int", 1, "ptr", 0, "ptr")
if !doneHandle {
    FileAppend("FAIL completed_late_poll_handle`n", "*")
    ExitApp(2)
}
resultStatus := "", resultError := false, callbackCount := 0
doneJob := {dir:doneDir, handle:doneHandle, result:doneDir "\result.txt",
    started:A_TickCount-2000, timeout:1000, callback:Finished, keep:false}
backgroundJobs.Push(doneJob)
PollBackgroundJob(doneJob)
if (resultStatus != "ok" || resultError || callbackCount != 1 || doneJob.handle != 0 || backgroundJobs.Length || DirExist(doneDir)) {
    FileAppend("FAIL completed_late_poll_keeps_result`n", "*")
    ExitApp(1)
}
FileAppend("PASS completed_late_poll_keeps_result`nPASS successful_result_has_no_synthetic_error`nRESULT failures=0`n", "*")
ExitApp(0)

Finished(result, job) {
    global resultStatus, resultError, callbackCount
    resultStatus := result["status"]
    resultError := result.Has("error")
    callbackCount++
}
LogMsg(*) {
}
EnsureResources() {
}
JsonStr(s) {
    return '"' s '"'
}
