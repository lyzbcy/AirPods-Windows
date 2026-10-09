from pathlib import Path
import subprocess,sys
sys.stdout.reconfigure(encoding='utf-8')
ROOT=Path(__file__).resolve().parents[1]
source=(ROOT/'airpods_buddy.ahk').read_text(encoding='utf-8-sig')
names=['DoAction','BeginDeviceOp','OpCurrent','SetOpState','CanRoute','ProbeDeviceRender','StateProbeCurrent','FindDevByName','ValidEndpointId','AtomicWriteText','SavePriority','LoadPriority','SettingRead','SettingWrite','MicPreferenceSet','Join','SortDevices','DevLess','DeviceSortKey','IsAppleDevice','DeviceAudioState','DeviceProgressJson','BuildDevicesJson','StartLinkVerify','StartDownVerify','DeviceKey','DeviceLabel','JsonStr','FinishBluetoothAction','DaysSince','ValidBridgeArgs','AutostartEnabled','AutostartSet','WatchAudioRoutes']
body=r'''
#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
FileEncoding("UTF-8-RAW")
OnError((e, mode) => (FileAppend("ERROR " e.Message " line=" e.Line "`n", "*"), ExitApp(2)))
SETTINGS_PATH := A_ScriptDir "\settings-test.ini"
failures := 0, busy := false, loading := false, maxRetries := 1
routeEvents := []
routeQueryFailed := false
probeResult := "supported", probeCalls := 0, probeSideEffect := ""
linkStarts := 0, downStarts := 0
deviceOps := Map(), operationSerial := 0, routeOwner := 0, actionEpoch := 0, pendingRetryDisconnect := 0
petStates := []
workerFails := true, petFails := false
devices := [{name:"A",info:Buffer(560)}]
result := DoAction("A", "connect")
Check("backend_exception_returns_failure", result = "fail")
Check("backend_exception_releases_busy", !busy && !loading)
Check("failed_task_state_preserved", deviceOps["A"].state = "service_failed")
Check("no_operation_progress_is_null", DeviceProgressJson("missing") = "null" && DeviceProgressJson("A") = "null")
busy := true, epochBefore := actionEpoch
Check("rejected_busy_action_does_not_invalidate_epoch", DoAction("A", "connect") = "busy" && actionEpoch = epochBefore)
busy := false
progressGen := BeginDeviceOp("P", "connect")
Check("connect_request_progress_schema", InStr(DeviceProgressJson("P"), '"action":"connect","phase":"request","step":1,"steps":4,"elapsedMs":') && InStr(DeviceProgressJson("P"), '"phaseBudgetMs":30000}'))
deviceOps["P"].phaseStarted := 3
SetOpState("P", progressGen, "connect")
Check("repeat_state_preserves_phase_clock", deviceOps["P"].phaseStarted = 3)
StartLinkVerify("P", progressGen)
Check("link_phase_exposes_bounded_observation", linkStarts = 1 && InStr(DeviceProgressJson("P"), '"phase":"link","step":2,"steps":4') && InStr(DeviceProgressJson("P"), '"phaseBudgetMs":9600}'))
SetOpState("P", progressGen, "link_retry_wait")
Check("retry_wait_exposes_15s_window", InStr(DeviceProgressJson("P"), '"phase":"retry_wait"') && InStr(DeviceProgressJson("P"), '"phaseBudgetMs":15000}'))
SetOpState("P", progressGen, "link_retrying")
Check("retry_worker_is_explicit_phase", InStr(DeviceProgressJson("P"), '"phase":"retrying"'))
busy := true, pendingRetryDisconnect := 0, epochBefore := actionEpoch
Check("retry_cancel_queues_without_claiming_submission", DoAction("P", "disconnect") = "ok" && actionEpoch = epochBefore + 1 && InStr(DeviceProgressJson("P"), '"action":"disconnect","phase":"queued"'))
Check("queued_cancel_shows_disconnect_pet", petStates.Length = 1 && petStates[1] = "disconnecting")
epochBefore := actionEpoch
Check("duplicate_queued_cancel_is_busy_without_epoch_change", DoAction("P", "disconnect") = "busy" && actionEpoch = epochBefore)
Check("rejected_busy_action_does_not_flash_pet", petStates.Length = 1)
busy := false, pendingRetryDisconnect := 0
SetOpState("P", progressGen, "audio_pending")
Check("audio_phase_is_distinct", InStr(DeviceProgressJson("P"), '"phase":"audio","step":3,"steps":4') && InStr(DeviceProgressJson("P"), '"phaseBudgetMs":13500}'))
Check("poll_does_not_end_active_connect_without_link", DeviceAudioState("P", false) = "audio_pending" && deviceOps["P"].state = "audio_pending")
savedDevices := devices
devices := [{id:"P",name:"Progress Headphones",connected:false}]
Check("device_list_serializes_progress", InStr(BuildDevicesJson(), '"progress":{"action":"connect","phase":"audio"'))
devices := savedDevices
SetOpState("P", progressGen - 1, "ready")
Check("stale_state_cannot_end_progress", InStr(DeviceProgressJson("P"), '"phase":"audio"'))
SetOpState("P", progressGen, "ready")
Check("connect_terminal_clears_progress", DeviceProgressJson("P") = "null")
progressGen := BeginDeviceOp("P", "disconnect")
Check("disconnect_request_progress_schema", InStr(DeviceProgressJson("P"), '"action":"disconnect","phase":"request","step":1,"steps":3'))
StartDownVerify("P", progressGen)
Check("disconnect_down_phase_observed", downStarts = 1 && InStr(DeviceProgressJson("P"), '"phase":"down","step":2,"steps":3') && InStr(DeviceProgressJson("P"), '"phaseBudgetMs":30000}'))
Check("poll_preserves_down_phase_while_link_up", DeviceAudioState("P", true) = "down_pending" && InStr(DeviceProgressJson("P"), '"phase":"down"'))
Check("poll_does_not_end_unverified_disconnect", DeviceAudioState("P", false) = "down_pending" && deviceOps["P"].state = "down_pending")
SetOpState("P", progressGen, "disconnect_failed")
Check("disconnect_terminal_clears_progress", DeviceProgressJson("P") = "null")
Check("poll_preserves_strict_disconnect_failure", DeviceAudioState("P", false) = "disconnect_failed")
SetOpState("P", progressGen, "service_failed")
Check("poll_preserves_disconnect_worker_failure", DeviceAudioState("P", false) = "service_failed")
SetOpState("P", progressGen, "disconnected")
oldGen := BeginDeviceOp("Old", "connect")
SetOpState("Old", oldGen, "audio_pending")
devices := [{id:"New",name:"New",info:Buffer(560)}]
Check("accepted_new_action_ends_superseded_progress", DoAction("New", "connect") = "fail" && DeviceProgressJson("Old") = "null" && deviceOps["Old"].state = "superseded")
devices := [{name:"A",info:Buffer(560)}]
routeOwner := deviceOps["A"].gen
linkStarts := 0
routeFresh := true
deviceOps["A"].renderId := "{0.0.0.00000000}.{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}"
deviceOps["A"].state := "ready"
Check("ready_state_revalidated", DeviceAudioState("A", true) = "ready")
routeQueryFailed := true
Check("query_failure_preserves_route_state_without_claiming_ready", DeviceAudioState("A", true) = "unknown" && deviceOps["A"].state = "ready")
routeQueryFailed := false
routeFresh := false
Check("changed_output_invalidates_ready", DeviceAudioState("A", true) = "audio_lost")
routeFresh := false
deviceOps["A"].state := "audio_failed"
Check("late_route_does_not_steal_external_output", DeviceAudioState("A", true) = "audio_failed")
routeFresh := true
routeOwner := deviceOps["A"].gen + 1
Check("late_route_ignores_superseded_operation", DeviceAudioState("A", true) = "audio_failed")
routeOwner := deviceOps["A"].gen
before := routeEvents.Length
Check("late_route_reconciles_exact_current_output", DeviceAudioState("A", true) = "ready" && routeEvents.Length = before + 1 && routeEvents[before + 1] = "audiook")
Check("late_route_emits_success_once", DeviceAudioState("A", true) = "ready" && routeEvents.Length = before + 1)
probeResult := "unsupported", deviceOps["A"].probeAt := A_TickCount - 30001
before := routeEvents.Length
Check("supported_route_losing_shared_stream_not_ready", DeviceAudioState("A", true) = "playback_unavailable" && routeEvents.Length = before)
calls := probeCalls
Check("unsupported_watchdog_uses_cache", DeviceAudioState("A", true) = "playback_unavailable" && probeCalls = calls)
probeResult := "supported", deviceOps["A"].probeAt := A_TickCount - 30001
Check("playback_positive_recheck_does_not_announce_ready", DeviceAudioState("A", true) = "playback_unverified" && routeEvents.Length = before)
routeFresh := false, deviceOps["A"].state := "playback_unavailable", deviceOps["A"].probeAt := A_TickCount - 30001
calls := probeCalls, before := routeEvents.Length
Check("negative_preflight_reprobes_without_default_route", DeviceAudioState("A", true) = "playback_unverified" && probeCalls = calls + 1 && routeEvents.Length = before)
routeFresh := true
deviceOps["A"].state := "audio_failed", deviceOps["A"].probeAt := -1
probeResult := "unsupported", before := routeEvents.Length
Check("late_route_only_cannot_promote_unsupported", DeviceAudioState("A", true) = "playback_unavailable" && routeEvents.Length = before)
probeResult := "unknown", deviceOps["A"].probeAt := -1
Check("unknown_probe_remains_unverified", DeviceAudioState("A", true) = "playback_unverified" && routeEvents.Length = before)
probeResult := "supported", deviceOps["A"].probeAt := -1
before := routeEvents.Length, probeSideEffect := "new_other", deviceOps["A"].state := "audio_failed"
Check("late_probe_new_owner_cannot_emit_audiook", DeviceAudioState("A", true) = "unknown" && deviceOps["A"].state = "audio_failed" && routeEvents.Length = before)
routeOwner := deviceOps["A"].gen
before := routeEvents.Length, probeSideEffect := "new_other", deviceOps["A"].state := "playback_unavailable", deviceOps["A"].probeAt := -1
Check("passive_probe_new_owner_cannot_mutate_state", DeviceAudioState("A", true) = "unknown" && deviceOps["A"].state = "playback_unavailable" && routeEvents.Length = before)
routeOwner := deviceOps["A"].gen
before := routeEvents.Length, probeSideEffect := "new_other", deviceOps["A"].state := "ready", deviceOps["A"].probeAt := -1
Check("ready_probe_new_owner_cannot_mutate_state", DeviceAudioState("A", true) = "unknown" && deviceOps["A"].state = "ready" && routeEvents.Length = before)
routeOwner := deviceOps["A"].gen
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
gen := BeginDeviceOp("A", "connect")
FinishBluetoothAction("A", "connect", gen, Map("status", "ok", "backend", "ks", "container", "{11111111-1111-1111-1111-111111111111}", "renderId", "{0.0.0.00000000}.{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}", "captureId", "{0.0.1.00000000}.{BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB}", "requested", 2))
Check("ks_result_saves_exact_ids_before_verify", linkStarts = 1 && deviceOps["A"].renderId = "{0.0.0.00000000}.{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}" && deviceOps["A"].captureId != "")
gen := BeginDeviceOp("A", "connect")
FinishBluetoothAction("A", "connect", gen, Map("status", "ok", "backend", "ks", "container", "{11111111-1111-1111-1111-111111111111}", "renderId", "{0.0.0.00000000}.{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}", "requested", 0))
Check("healthy_zero_request_still_verifies", linkStarts = 2 && deviceOps["A"].state = "link_pending")
gen := BeginDeviceOp("A", "connect")
FinishBluetoothAction("A", "connect", gen, Map("status", "ok", "backend", "ks", "container", "{11111111-1111-1111-1111-111111111111}", "requested", 1))
Check("missing_render_id_never_starts_verify", linkStarts = 2 && deviceOps["A"].state = "service_failed")
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
Check("mic_off_preference_written", MicPreferenceSet("0") && SettingRead("auto_mic_switch", "") = "0" && SettingRead("mic_restore_pending", "") = "0")
Check("explicit_mic_on_arms_once", MicPreferenceSet("1") && SettingRead("auto_mic_switch", "") = "1" && SettingRead("mic_restore_pending", "") = "1")
Check("idempotent_mic_on_keeps_pending", MicPreferenceSet("1") && SettingRead("mic_restore_pending", "") = "1")
Check("invalid_mic_preference_rejected", !MicPreferenceSet("yes") && SettingRead("mic_restore_pending", "") = "1")
devices := [{id:"AABBCCDDEEFF",name:"Headphones",info:Buffer(560)}]
NumPut("uint64", 0xAABBCCDDEEFF, devices[1].info, 8)
Check("failed_migration_worker_restores_one_time_pending", DoAction("AABBCCDDEEFF", "connect") = "fail" && SettingRead("mic_restore_pending", "") = "1")
Check("mic_off_clears_pending", MicPreferenceSet("0") && SettingRead("mic_restore_pending", "") = "0")
MicPreferenceSet("1"), SettingWrite("mic_restore_pending", "0")
gen := BeginDeviceOp("AABBCCDDEEFF", "connect")
deviceOps["AABBCCDDEEFF"].micRestore := true
FinishBluetoothAction("AABBCCDDEEFF", "connect", gen, Map("status", "fail", "micRepair", "disabled"))
Check("failed_target_mic_migration_restores_old_preference", SettingRead("auto_mic_switch", "") = "0" && SettingRead("mic_restore_pending", "") = "0")
MicPreferenceSet("1"), SettingWrite("mic_restore_pending", "0")
gen := BeginDeviceOp("AABBCCDDEEFF", "connect")
deviceOps["AABBCCDDEEFF"].micRestore := true
FinishBluetoothAction("AABBCCDDEEFF", "connect", gen, Map("status", "ok", "backend", "ks", "container", "11111111-1111-1111-1111-111111111111", "requested", "1", "renderId", "{0.0.0.00000000}.{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}", "captureId", "{0.0.1.00000000}.{BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB}", "micRepair", "restored"))
Check("verified_target_mic_migration_keeps_new_preference", SettingRead("auto_mic_switch", "") = "1")
MicPreferenceSet("0")
devices := [{id:"001122334455",name:"Headphones",connected:true}]
routeEvents := [], routeFresh := false
gen := BeginDeviceOp("001122334455", "connect")
deviceOps["001122334455"].renderId := "{0.0.0.00000000}.{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}"
SetOpState("001122334455", gen, "audio_failed")
routeFresh := true
WatchAudioRoutes()
Check("hidden_ui_reconciles_late_audio", deviceOps["001122334455"].state = "ready" && routeEvents.Length = 1 && routeEvents[1] = "audiook")
routeEvents := [], routeFresh := false
SetOpState("001122334455", gen, "ready")
WatchAudioRoutes()
Check("hidden_ui_observes_route_loss", deviceOps["001122334455"].state = "audio_lost" && routeEvents.Length = 1)
Check("route_loss_event_is_specific", routeEvents[1] = "routelost")
WatchAudioRoutes()
Check("route_loss_event_not_repeated", routeEvents.Length = 1)
routeEvents := [], routeFresh := true, probeResult := "unsupported"
SetOpState("001122334455", gen, "ready")
deviceOps["001122334455"].probeAt := -1
WatchAudioRoutes()
Check("playback_failure_emits_audioheld_not_routelost", deviceOps["001122334455"].state = "playback_unavailable" && routeEvents.Length = 1 && routeEvents[1] = "audioheld")
probeResult := "supported"
devices[1].connected := false
SetOpState("001122334455", gen, "ready")
WatchAudioRoutes()
Check("hidden_ui_observes_disconnection", deviceOps["001122334455"].state = "disconnected")
RUN_NAME := "AirPodsBuddyTest_" DllCall("GetCurrentProcessId")
RUN_KEY := "Software\AirPodsBuddyTests\" RUN_NAME
approved := "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
lnk := A_ScriptDir "\shortcut-fixture.lnk"
FileAppend("original shortcut bytes", lnk)
try {
    SettingWrite("autostart", "1")
    RegWrite("030000000000000000000000", "REG_BINARY", approved, RUN_NAME)
    Check("disabled_startup_returns_failure", AutostartSet(true, lnk) = "fail")
    Check("failed_startup_restores_shortcut", FileExist(lnk) && FileRead(lnk) = "original shortcut bytes")
    Check("failed_startup_restores_preference", SettingRead("autostart", "") = "1")
    Check("failed_startup_restores_missing_run", RegRead("HKCU\" RUN_KEY, RUN_NAME, "absent") = "absent")
    RegDelete(approved, RUN_NAME)
    Check("startup_enable_migrates_shortcut", AutostartSet(true, lnk) = "ok" && !FileExist(lnk))
    Check("startup_disable_verified", AutostartSet(false, lnk) = "ok" && AutostartEnabled(lnk) = "off")
} finally {
    try RegDelete(approved, RUN_NAME)
    try RegDeleteKey("HKCU\" RUN_KEY)
    try FileDelete(lnk)
}
devices := [{id:"AABBCCDDEEFF",name:"Headphones",info:Buffer(560)}]
NumPut("uint64", 0xAABBCCDDEEFF, devices[1].info, 8)
busy := false, workerFails := false, petFails := true
Check("pet_display_error_does_not_fail_accepted_worker", DoAction("AABBCCDDEEFF", "connect") = "ok" && busy)
workerFails := true, petFails := false, busy := false
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
    global workerFails
    if workerFails
        throw Error("injected worker launch failure")
    return true
}
PetSchedule(state, *) {
    global petStates, petFails
    petStates.Push(state)
    if petFails
        throw Error("injected pet display failure")
}
PushEvent(event, data) {
    global routeEvents
    routeEvents.Push(event)
}
LinkVerifyTick(*) {
    global linkStarts
    linkStarts++
}
DownVerifyTick(*) {
    global downStarts
    downStarts++
}
ReleaseOwnedMicRoute(*) {
}
AudioRouteObservation(*) {
    global routeFresh, routeQueryFailed
    return {matches: routeFresh && !routeQueryFailed, reason: routeQueryFailed ? "query_failed" : (routeFresh ? "ready" : "default_changed"), state: 1, matchedRoles: routeFresh ? 7 : 0, failedRole: -1}
}
AudioRouteMatchesId(*) {
    global routeFresh
    return routeFresh
}
AudioRenderProbe(*) {
    global probeResult, probeCalls, probeSideEffect
    probeCalls++
    effect := probeSideEffect, probeSideEffect := ""
    if effect = "new_other"
        BeginDeviceOp("Other", "connect")
    return {status: probeResult, reason: probeResult = "supported" ? "shared stream initialized" : "injected negative"}
}
'''
for name in names:
    start=source.index('\n'+name+'(');end=source.index('\n}',start)+2
    body+=source[start:end]+'\n'
path=ROOT/'verification/2026-09-26-all/state-tests.ahk';path.parent.mkdir(parents=True,exist_ok=True);path.write_text(body,encoding='utf-8-sig')
run=subprocess.run([str(ROOT/'tools/ahk_v2_portable/AutoHotkey64.exe'),'/ErrorStdOut=UTF-8',str(path)],capture_output=True,timeout=15)
output=(run.stdout+run.stderr).decode('utf-8-sig',errors='replace');print(output,end='')
path.with_suffix('.txt').write_text(output,encoding='utf-8');raise SystemExit(run.returncode)
