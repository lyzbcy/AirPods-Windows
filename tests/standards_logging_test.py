"""Execute production AHK functions with isolated settings/logs; never start Bluetooth/UI."""
from pathlib import Path
import subprocess, tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'airpods_buddy.ahk').read_text('utf-8-sig')
def function(name):
    start=source.index('\n'+name+'(')+1
    return source[start:source.index('\n}',start)+2]+'\n'

with tempfile.TemporaryDirectory(prefix='airpods-standards-') as directory:
    work=Path(directory)
    body='''#Requires AutoHotkey v2.0
#SingleInstance Off
OnError((e, mode) => (FileAppend(e.Message " line=" e.Line "`n", "*"), ExitApp(2)))
LOG_DIR := A_ScriptDir "\\logs"
SETTINGS_PATH := A_ScriptDir "\\settings.ini"
LOG_QUEUE := [], LOG_VERBOSE := false, LOG_MAX_BYTES := 1024, LOG_FLUSHING := false
APP_VERSION := "1.9.26", updateCheckBusy := false, requests := 0
DiagnosticSanitize(value) {
    return RegExReplace(value, "token=\\S+", "token=[hidden]")
}
JsonStr(value) {
    return value
}
PushEvent(*) {
}
StartBackgroundJob(*) {
    global requests
    requests += 1
    return true
}
Assert(value, name) {
    if !value
        throw Error(name)
    FileAppend("PASS " name "`n", "*")
}
LogMsg("hidden", "DEBUG")
Assert(LOG_QUEUE.Length=0, "debug-default-off")
LogMsg("token=secret")
Assert(!DirExist(LOG_DIR), "producer-does-not-write")
FlushLogs()
path := LOG_DIR "\\app-" FormatTime(, "yyyy-MM-dd") ".log"
Assert(!InStr(FileRead(path), "secret"), "redaction-before-queue")
Loop 40 {
    LogMsg("rotation-fixture-abcdefghijklmnopqrstuvwxyz")
    FlushLogs()
}
Assert(FileExist(path ".1") && FileGetSize(path)<LOG_MAX_BYTES, "size-rotation")
Assert(ShouldCheckUpdate(false,"2026-10-24"), "first-attempt")
Assert(!ShouldCheckUpdate(false,"2026-10-24"), "same-day-throttled")
Assert(ShouldCheckUpdate(true,"2026-10-24"), "manual-retry")
Assert(ShouldCheckUpdate(false,"2026-10-25"), "next-day")
CheckUpdate(true)
CheckUpdate(true)
Assert(requests=1, "checks-single-flight")
OnUpdateCheck(Map("status","current"),true)
Assert(IniRead(SETTINGS_PATH,"Updates","lastSuccess","")!="", "success-date-only-after-result")
A_TrayMenu.Add("详细排障日志", (*) => 0)
ToggleDiagnosticLogging()
Assert(LOG_VERBOSE && IniRead(SETTINGS_PATH,"Diagnostics","detailed","")="1", "tray-setting-persists")
ExitApp(0)
'''
    for name in ['LogMsg','FlushLogs','ShouldCheckUpdate','CheckUpdate','OnUpdateCheck','ToggleDiagnosticLogging']:
        body+=function(name)
    script=work/'test.ahk';script.write_text(body,encoding='utf-8-sig')
    result=subprocess.run([str(ROOT/'tools/ahk_v2_portable/AutoHotkey64.exe'),'/ErrorStdOut=UTF-8',str(script)],capture_output=True,timeout=30)
    print((result.stdout+result.stderr).decode('utf-8-sig',errors='replace'))
    raise SystemExit(result.returncode)
