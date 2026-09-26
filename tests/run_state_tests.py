from pathlib import Path
import subprocess,sys
sys.stdout.reconfigure(encoding='utf-8')
ROOT=Path(__file__).resolve().parents[1]
source=(ROOT/'airpods_buddy.ahk').read_text(encoding='utf-8-sig')
names=['DoAction','BeginDeviceOp','OpCurrent','SetOpState','CanRoute','FindDevByName','IsSuccessfulOperation','AtomicWriteText','SavePriority','LoadPriority','SettingRead','SettingWrite','Join','SortDevices','DevLess','DeviceSortKey','IsAppleDevice','DeviceAudioState','DeviceKey','DeviceLabel','JsonStr','FinishBluetoothAction','DaysSince','ValidBridgeArgs']
body=r'''
#Requires AutoHotkey v2.0
#SingleInstance Off
FileEncoding("UTF-8-RAW")
OnError((e, mode) => (FileAppend("ERROR " e.Message " line=" e.Line "`n", "*"), ExitApp(2)))
SETTINGS_PATH := A_ScriptDir "\settings-test.ini"
failures := 0, busy := false, loading := false, maxRetries := 1
deviceOps := Map(), operationSerial := 0, routeOwner := 0
devices := [{name:"A",info:Buffer(560)}]
result := DoAction("A", "connect")
Check("backend_exception_returns_failure", result = "fail")
Check("backend_exception_releases_busy", !busy && !loading)
Check("failed_task_state_preserved", deviceOps["A"].state = "service_failed")
routeFresh := true
deviceOps["A"].state := "ready"
Check("ready_state_revalidated", DeviceAudioState("A", true) = "ready")
routeFresh := false
Check("changed_output_invalidates_ready", DeviceAudioState("A", true) = "audio_lost")
devices.Push({name:"A",info:Buffer(560)})
Check("duplicate_device_name_rejected", !FindDevByName("A"))
devices := [{id:"001122334455",name:"Same",info:Buffer(560)},{id:"AABBCCDDEEFF",name:"Same",info:Buffer(560)}]
Check("stable_address_selects_requested_device", FindDevByName("AABBCCDDEEFF").id = "AABBCCDDEEFF")
Check("duplicate_audio_label_fails_closed", DeviceLabel("AABBCCDDEEFF") = "")
Check("bridge_rejects_update_url", !ValidBridgeArgs("doupdate", ["doupdate","1","https://evil.invalid/a.zip"]))
Check("bridge_accepts_no_url_update", ValidBridgeArgs("doupdate", ["doupdate","1",""]))
Check("bridge_rejects_invalid_boolean", !ValidBridgeArgs("setmicswitch", ["setmicswitch","1","yes"]))
Check("bridge_rejects_unknown_command", !ValidBridgeArgs("exec", ["exec","1","calc.exe"]))
Check("bridge_address_not_name", ValidBridgeArgs("connect", ["connect","1","001122334455"]) && !ValidBridgeArgs("connect", ["connect","1","Same"]))
Check("invalid_date_falls_back", DaysSince("garbage") = 999 && DaysSince("20261399999999") = 999)
Check("calendar_day_arithmetic", DaysSince(DateAdd(A_Now, -16, "days")) = 16)
busy := true, loading := true
FinishBluetoothAction("A", "connect", deviceOps["A"].gen, Map("status", "fail"))
Check("worker_failure_releases_busy", !busy && !loading)
devices := []
SortDevices()
Check("empty_list_sort", devices.Length = 0)
PRIO_PATH := A_ScriptDir "\priority-test.txt", SETTINGS_PATH := A_ScriptDir "\settings-test.ini"
priorityList := ["鑰虫満 A","B","C"]
Check("priority_write_succeeds", SavePriority())
priorityList := []
LoadPriority()
Check("priority_reloads_all_entries", priorityList.Length = 3 && priorityList[1] = "鑰虫満 A" && priorityList[3] = "C")
Check("setting_initial_write", SettingWrite("test", "before"))
Check("setting_readback", SettingRead("test", "missing") = "before")
handle := DllCall("CreateFileW", "wstr", SETTINGS_PATH, "uint", 0x80000000, "uint", 0, "ptr", 0, "uint", 3, "uint", 0, "ptr", 0, "ptr")
Check("test_file_exclusively_locked", handle != -1)
Check("locked_target_reports_failure", !AtomicWriteText(SETTINGS_PATH, "test=after`n"))
DllCall("CloseHandle", "ptr", handle)
Check("failed_replace_keeps_old_content", SettingRead("test", "missing") = "before")
Check("setting_update_after_unlock", SettingWrite("test", "after") && SettingRead("test", "missing") = "after")
FileDelete(PRIO_PATH)
FileDelete(SETTINGS_PATH)
FileAppend("RESULT failures=" failures "`n", "*")
ExitApp(failures ? 1 : 0)
Check(name, ok) {
    global failures
    if !ok
        failures++
    FileAppend((ok ? "PASS " : "FAIL ") name "`n", "*")
}
LogMsg(*) {
}
FindAllAudioDevices() {
}
SetTrayLoading(on) {
    global loading
    loading := on
}
StartBackgroundJob(*) {
    throw Error("injected worker launch failure")
}
PushEvent(*) {
}
StartLinkVerify(*) {
}
StartDownVerify(*) {
}
AudioRouteMatches(*) {
    global routeFresh
    return routeFresh
}
'''
for name in names:
    start=source.index('\n'+name+'(');end=source.index('\n}',start)+2
    body+=source[start:end]+'\n'
path=ROOT/'verification/2026-09-26-all/state-tests.ahk';path.parent.mkdir(parents=True,exist_ok=True);path.write_text(body,encoding='utf-8-sig')
run=subprocess.run([str(ROOT/'tools/ahk_v2_portable/AutoHotkey64.exe'),'/ErrorStdOut=UTF-8',str(path)],capture_output=True,timeout=15)
output=(run.stdout+run.stderr).decode('utf-8-sig',errors='replace');print(output,end='')
path.with_suffix('.txt').write_text(output,encoding='utf-8');raise SystemExit(run.returncode)
