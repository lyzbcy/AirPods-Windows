; Each operation gets private files and an owned process handle. The UI never
; waits on network downloads, PowerShell, or Bluetooth service-state calls.
StartBackgroundJob(kind, payload, callback, timeoutMs := 45000) {
    global backgroundJobs, appRoot
    static serial := 0
    dir := A_Temp "\AirPodsBuddy_jobs\" DllCall("GetCurrentProcessId") "-" A_TickCount "-" (++serial)
    job := {dir: dir, handle: 0, started: A_TickCount, timeout: timeoutMs, callback: callback, keep: false}
    try {
        DirCreate(dir)
        request := dir "\request.json"
        job.result := dir "\result.txt"
        FileAppend('{"kind":' JsonStr(kind) ',"result":' JsonStr(job.result) ',"args":' payload '}', request, "UTF-8-RAW")
        worker := A_IsCompiled ? appRoot "\background-worker.ps1" : A_ScriptDir "\scripts\background-worker.ps1"
        EnsureResources()
        command := '"' A_WinDir '\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' worker '" -Request "' request '"'
        pid := 0
        Run(command,, "Hide", &pid)
        job.handle := DllCall("OpenProcess", "uint", 0x101001, "int", 0, "uint", pid, "ptr")
        if !job.handle {
            try ProcessClose(pid)
            throw Error("worker handle unavailable")
        }
        backgroundJobs.Push(job)
        SetTimer(() => PollBackgroundJob(job), -100)
        return true
    } catch as e {
        LogMsg("worker start failed: " kind " " e.Message, "ERROR")
        CleanupBackgroundJob(job)
        return false
    }
}

PollBackgroundJob(job) {
    done := DllCall("WaitForSingleObject", "ptr", job.handle, "uint", 0, "uint") = 0
    timedOut := A_TickCount - job.started > job.timeout
    if (!done && !timedOut) {
        SetTimer(() => PollBackgroundJob(job), -100)
        return
    }
    result := Map("status", "fail", "error", timedOut ? "worker timeout" : "worker result missing")
    if timedOut {
        DllCall("TerminateProcess", "ptr", job.handle, "uint", 124)
        DllCall("WaitForSingleObject", "ptr", job.handle, "uint", 1000)
    } else {
        try {
            for line in StrSplit(FileRead(job.result, "UTF-8"), "`n", "`r") {
                pos := InStr(line, "=")
                if pos
                    result[SubStr(line, 1, pos-1)] := SubStr(line, pos+1)
            }
        }
    }
    try job.callback.Call(result, job)
    catch as e
        LogMsg("worker callback failed: " e.Message, "ERROR")
    finally CleanupBackgroundJob(job)
}

CleanupBackgroundJob(job) {
    global backgroundJobs
    if job.handle {
        DllCall("CloseHandle", "ptr", job.handle)
        job.handle := 0
    }
    for i, item in backgroundJobs {
        if item = job {
            backgroundJobs.RemoveAt(i)
            break
        }
    }
    if !job.keep {
        ; dir is generated internally and never supplied by WebView content.
        try DirDelete(job.dir, true)
    }
}

StopBackgroundJobs(*) {
    global backgroundJobs
    for job in backgroundJobs.Clone() {
        if job.handle {
            DllCall("TerminateProcess", "ptr", job.handle, "uint", 125)
            DllCall("WaitForSingleObject", "ptr", job.handle, "uint", 1000)
        }
        CleanupBackgroundJob(job)
    }
}
