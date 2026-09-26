"""Headless fault-injection of the bounded KS link retry state machine."""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "airpods_buddy.ahk").read_text(encoding="utf-8-sig")


def function(name):
    start = source.index("\n" + name + "(")
    end = source.index("\n}", start) + 2
    return source[start:end]


if "SetTimer(() => TryKsConnectRetry(name, gen, op.retryEpoch), -15000)" not in function("ScheduleKsConnectRetry"):
    raise SystemExit("FAIL bounded_15_second_timer")
print("PASS bounded_15_second_timer")
if 'ScheduleKsConnectRetry(name, gen, "audio")' not in function("AudioVerifyTick"):
    raise SystemExit("FAIL audio_exhaustion_shares_retry")
print("PASS audio_exhaustion_shares_retry")
if 'DownVerifyTick(name, 26, gen)' not in function('StartDownVerify'):
    raise SystemExit('FAIL delayed_disconnect_30_second_window')
print('PASS delayed_disconnect_30_second_window')

body = r'''
#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
OnError((e, mode) => (FileAppend("ERROR " e.Message " line=" e.Line "`n", "*"), ExitApp(2)))
failures := 0, deviceOps := Map(), operationSerial := 0, routeOwner := 0, actionEpoch := 0, pendingRetryDisconnect := 0
busy := false, linkUp := false, renderActive := false, endpointOff := true, jobCount := 0, audioChecks := 0, events := [], lastPayload := ""
devices := [{id: "AABBCCDDEEFF", info: Buffer(560)}, {id: "112233445566", info: Buffer(560)}]
NumPut("uint64", 0xAABBCCDDEEFF, devices[1].info, 8)
NumPut("uint64", 0x112233445566, devices[2].info, 8)
gen := BeginDeviceOp("AABBCCDDEEFF", "connect")
deviceOps["AABBCCDDEEFF"].backend := "ks"
deviceOps["AABBCCDDEEFF"].address := "AABBCCDDEEFF"
deviceOps["AABBCCDDEEFF"].renderId := "{0.0.0.00000000}.{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}"
LinkVerifyTick("AABBCCDDEEFF", 1, gen)
Check("successful_ks_no_link_enters_one_wait", deviceOps["AABBCCDDEEFF"].state = "link_retry_wait" && deviceOps["AABBCCDDEEFF"].retryCount = 1 && jobCount = 0)
Check("ui_poll_keeps_retry_wait", DeviceAudioState("AABBCCDDEEFF", false) = "link_retry_wait")
TryKsConnectRetry("AABBCCDDEEFF", gen, deviceOps["AABBCCDDEEFF"].retryEpoch)
Check("one_same_target_worker_only", jobCount = 1 && InStr(lastPayload, '"AABBCCDDEEFF"') && deviceOps["AABBCCDDEEFF"].state = "link_retrying")
Check("ui_poll_keeps_retry_inflight", DeviceAudioState("AABBCCDDEEFF", false) = "link_retrying")
FinishKsConnectRetry("AABBCCDDEEFF", gen, actionEpoch, Map("status", "fail", "error", "HRESULT 80004005"))
Check("failed_retry_is_terminal", deviceOps["AABBCCDDEEFF"].state = "service_failed" && !busy && jobCount = 1)
LinkVerifyTick("AABBCCDDEEFF", 1, gen)
Check("retry_limit_one", deviceOps["AABBCCDDEEFF"].state = "link_failed" && jobCount = 1)

gen := BeginDeviceOp("AABBCCDDEEFF", "connect")
deviceOps["AABBCCDDEEFF"].backend := "ks"
deviceOps["AABBCCDDEEFF"].address := "AABBCCDDEEFF"
deviceOps["AABBCCDDEEFF"].renderId := "{0.0.0.00000000}.{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}"
LinkVerifyTick("AABBCCDDEEFF", 1, gen)
linkUp := true
renderActive := true
TryKsConnectRetry("AABBCCDDEEFF", gen, deviceOps["AABBCCDDEEFF"].retryEpoch)
Check("external_link_skips_second_request", jobCount = 1 && audioChecks = 1)
linkUp := false
renderActive := false

gen := BeginDeviceOp("AABBCCDDEEFF", "connect")
deviceOps["AABBCCDDEEFF"].backend := "ks"
deviceOps["AABBCCDDEEFF"].address := "AABBCCDDEEFF"
LinkVerifyTick("AABBCCDDEEFF", 1, gen)
epoch := deviceOps["AABBCCDDEEFF"].retryEpoch
BeginDeviceOp("AABBCCDDEEFF", "disconnect")
TryKsConnectRetry("AABBCCDDEEFF", gen, epoch)
Check("stale_same_device_timer_cannot_resend", jobCount = 1)

gen := BeginDeviceOp("AABBCCDDEEFF", "connect")
deviceOps["AABBCCDDEEFF"].backend := "ks"
deviceOps["AABBCCDDEEFF"].address := "AABBCCDDEEFF"
LinkVerifyTick("AABBCCDDEEFF", 1, gen)
epoch := deviceOps["AABBCCDDEEFF"].retryEpoch
Check("new_other_device_action_starts", DoAction("112233445566", "disconnect") = "ok")
TryKsConnectRetry("AABBCCDDEEFF", gen, epoch)
Check("new_other_device_action_cancels_retry", jobCount = 2 && deviceOps["AABBCCDDEEFF"].state = "retry_cancelled")
LinkVerifyTick("AABBCCDDEEFF", 1, gen)
Check("old_link_timer_does_not_overwrite_cancel", deviceOps["AABBCCDDEEFF"].state = "retry_cancelled")
busy := false

gen := BeginDeviceOp("AABBCCDDEEFF", "connect")
deviceOps["AABBCCDDEEFF"].backend := "ks"
deviceOps["AABBCCDDEEFF"].address := "AABBCCDDEEFF"
Check("other_disconnect_before_wait_starts", DoAction("112233445566", "disconnect") = "ok")
busy := false
LinkVerifyTick("AABBCCDDEEFF", 1, gen)
Check("new_action_before_deadline_prevents_retry", deviceOps["AABBCCDDEEFF"].state = "connect" && deviceOps["AABBCCDDEEFF"].retryCount = 0)

gen := BeginDeviceOp("AABBCCDDEEFF", "connect")
deviceOps["AABBCCDDEEFF"].backend := "ks"
deviceOps["AABBCCDDEEFF"].address := "AABBCCDDEEFF"
deviceOps["AABBCCDDEEFF"].renderId := "{0.0.0.00000000}.{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}"
linkUp := true
AudioVerifyTick("AABBCCDDEEFF", 1, gen)
Check("audio_exhaustion_enters_shared_wait", deviceOps["AABBCCDDEEFF"].state = "link_retry_wait" && deviceOps["AABBCCDDEEFF"].retryCount = 1 && deviceOps["AABBCCDDEEFF"].retryReason = "audio")
TryKsConnectRetry("AABBCCDDEEFF", gen, deviceOps["AABBCCDDEEFF"].retryEpoch)
Check("link_up_render_inactive_resends_ks", jobCount = 4 && deviceOps["AABBCCDDEEFF"].state = "link_retrying")
FinishKsConnectRetry("AABBCCDDEEFF", gen, actionEpoch, Map("status", "fail", "error", "HRESULT 80004005"))
Check("audio_retry_failure_is_terminal", deviceOps["AABBCCDDEEFF"].state = "service_failed" && deviceOps["AABBCCDDEEFF"].retryCount = 1)
linkUp := false

gen := BeginDeviceOp("AABBCCDDEEFF", "connect")
deviceOps["AABBCCDDEEFF"].backend := "ks"
deviceOps["AABBCCDDEEFF"].address := "AABBCCDDEEFF"
deviceOps["AABBCCDDEEFF"].renderId := "{0.0.0.00000000}.{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}"
Check("active_audio_wait_scheduled", ScheduleKsConnectRetry("AABBCCDDEEFF", gen, "audio"))
linkUp := true, renderActive := true
TryKsConnectRetry("AABBCCDDEEFF", gen, deviceOps["AABBCCDDEEFF"].retryEpoch)
Check("link_and_render_active_skip_second_request", jobCount = 4 && audioChecks = 3)
linkUp := false, renderActive := false

gen := BeginDeviceOp("AABBCCDDEEFF", "connect")
deviceOps["AABBCCDDEEFF"].backend := "ks"
deviceOps["AABBCCDDEEFF"].address := "AABBCCDDEEFF"
LinkVerifyTick("AABBCCDDEEFF", 1, gen)
TryKsConnectRetry("AABBCCDDEEFF", gen, deviceOps["AABBCCDDEEFF"].retryEpoch)
Check("retry_worker_inflight", busy && jobCount = 5)
Check("busy_disconnect_queues_target_only", DoAction("AABBCCDDEEFF", "disconnect") = "ok" && deviceOps["AABBCCDDEEFF"].state = "retry_cancelled" && IsObject(pendingRetryDisconnect) && pendingRetryDisconnect.name = "AABBCCDDEEFF")
Check("repeat_cancel_keeps_latest_disconnect", DoAction("AABBCCDDEEFF", "disconnect") = "ok" && pendingRetryDisconnect.epoch = actionEpoch)
FinishKsConnectRetry("AABBCCDDEEFF", gen, actionEpoch - 1, Map("status", "ok"))
Sleep(50)
Check("cancelled_worker_result_does_not_verify", audioChecks = 3 && jobCount = 6 && InStr(lastPayload, '"disconnect"'))
busy := false

gen := BeginDeviceOp("AABBCCDDEEFF", "connect")
FinishBluetoothAction("AABBCCDDEEFF", "connect", gen, Map("status", "fail", "error", "driver unsupported"))
Check("initial_ks_failure_never_schedules_retry", deviceOps["AABBCCDDEEFF"].retryCount = 0 && deviceOps["AABBCCDDEEFF"].state = "service_failed" && jobCount = 6)
gen := BeginDeviceOp("AABBCCDDEEFF", "disconnect")
linkUp := true
DownVerifyTick("AABBCCDDEEFF", 1, gen)
Check("disconnect_still_up_at_deadline_fails", deviceOps["AABBCCDDEEFF"].state = "disconnect_failed")
gen := BeginDeviceOp("AABBCCDDEEFF", "disconnect")
linkUp := false
deviceOps["AABBCCDDEEFF"].targetEndpoints := "known-target"
DownVerifyTick("AABBCCDDEEFF", 1, gen)
Check("delayed_link_down_succeeds_without_new_request", deviceOps["AABBCCDDEEFF"].state = "disconnected" && jobCount = 6)
gen := BeginDeviceOp("AABBCCDDEEFF", "disconnect")
deviceOps["AABBCCDDEEFF"].targetEndpoints := "known-target"
endpointOff := false
DownVerifyTick("AABBCCDDEEFF", 1, gen)
Check("active_target_endpoint_cannot_claim_disconnect", deviceOps["AABBCCDDEEFF"].state = "disconnect_failed")
endpointOff := true
gen := BeginDeviceOp("AABBCCDDEEFF", "disconnect")
linkUp := -1
DownVerifyTick("AABBCCDDEEFF", 1, gen)
Check("unknown_link_query_cannot_claim_disconnect", deviceOps["AABBCCDDEEFF"].state = "disconnect_failed")
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
PetUpdate(*) {
}
PushEvent(event, data) {
    global events
    events.Push({name: event, data: data})
}
SetTrayLoading(*) {
}
IsLinkUp(*) {
    global linkUp
    return linkUp = 1
}
GetLinkState(*) {
    global linkUp
    return linkUp
}
TargetEndpointsInactive(*) {
    global endpointOff
    return endpointOff
}
RenderSwitchToId(*) {
    global audioChecks
    audioChecks++
    return AudioEndpointIdActive()
}
OnConnectSuccess() {
}
MicSwitchTo(*) {
}
TrayTip(*) {
}
AudioEndpointIdActive(*) {
    global renderActive
    return renderActive
}
StartBackgroundJob(kind, payload, callback, timeout) {
    global jobCount, lastPayload
    jobCount++, lastPayload := payload
    return true
}
FindAllAudioDevices() {
}
FindDevByName(name) {
    global devices
    for dev in devices
        if dev.id = name
            return dev
    return false
}
DeviceKey(dev) {
    return dev.id
}
SettingRead(*) {
    return "0"
}
'''
for name in ["BeginDeviceOp", "OpCurrent", "CanRoute", "SetOpState", "DoAction", "LinkVerifyTick", "ScheduleKsConnectRetry", "TryKsConnectRetry", "FinishKsConnectRetry", "DrainRetryDisconnect", "RunQueuedRetryDisconnect", "AudioVerifyTick", "StartDownVerify", "DownVerifyTick", "FinishBluetoothAction", "ValidEndpointId", "DeviceAudioState", "JsonStr"]:
    body += function(name)
with tempfile.TemporaryDirectory(prefix="apb_ks_retry_") as directory:
    script = Path(directory) / "retry_test.ahk"
    script.write_text(body, encoding="utf-8-sig")
    run = subprocess.run(
        [str(ROOT / "tools/ahk_v2_portable/AutoHotkey64.exe"), "/ErrorStdOut=UTF-8", str(script)],
        capture_output=True,
        timeout=15,
    )
    output = (run.stdout + run.stderr).decode("utf-8-sig", errors="replace")
    print(output, end="")
    raise SystemExit(run.returncode)
