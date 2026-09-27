"""Headless regression for the operation-bound floating pet; no Bluetooth/UI changes."""
from pathlib import Path
import subprocess
import sys
import tempfile

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "airpods_buddy.ahk").read_text(encoding="utf-8-sig")


def function(name: str) -> str:
    start = source.index("\n" + name + "(")
    end = source.index("\n}", start) + 2
    return source[start:end] + "\n"


checks = {
    "no_fixed_timeout_for_active_operation": "if name != \"\" {\n        SetTimer(PetProgressTick, 500)" in source,
    "old_hide_timer_cancelled": "SetTimer(PetFade, 0), SetTimer(PetHideNow, 0), SetTimer(PetProgressTick, 0)" in source,
    "accepted_action_starts_pet": 'PetShow(action = "connect" ? "connecting" : "disconnecting", name, gen, fromBatch)' in source,
    "tray_disconnect_batch": "PetStartBatch(queue)" in source,
    "new_direct_action_invalidates_batch": 'if (name != "" && !preserveBatch)' in source and "petBatchTicket++" in function("PetShow"),
    "old_unsynchronized_terminal_calls_removed": not any(
        call in source for call in ('PetUpdate("ok")', 'PetUpdate("off")', 'PetUpdate("fail")')
    ),
}
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'} {name}")
if not all(checks.values()):
    raise SystemExit(1)

body = r'''
#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
OnError((e, mode) => (FileAppend("ERROR " e.Message " line=" e.Line "`n", "*"), ExitApp(2)))
failures := 0, presentations := [], finished := []
petVisible := true, petOpName := "A", petOpAction := "connect", petOpGen := 1
petGui := 0, petWvc := 0
petBatch := [], petBatchGen := Map(), petBatchFailed := Map(), petBatchStarted := A_TickCount
deviceOps := Map(), pendingRetryDisconnect := 0, actionEpoch := 0
deviceOps["A"] := {gen:1,action:"connect",state:"audio_pending",started:A_TickCount-12000}
PetProgressTick()
Check("long_connect_keeps_pet_visible", finished.Length = 0 && presentations.Length = 1 && presentations[1].state = "connecting" && presentations[1].elapsed >= 12000)
Check("audio_phase_is_truthful", presentations[1].detail = "正在确认播放设备")
deviceOps["A"].state := "ready"
PetProgressTick()
Check("ready_waits_for_user_listening", finished.Length = 1 && finished[1].state = "ok" && InStr(finished[1].detail, "试听"))
finished := [], deviceOps["A"].state := "disconnected"
PetProgressTick()
Check("lost_link_during_connect_is_terminal_failure", finished.Length = 1 && finished[1].state = "fail")

presentations := [], finished := [], petOpAction := "disconnect", petOpGen := 2
deviceOps["A"] := {gen:2,action:"disconnect",state:"down_pending",started:A_TickCount-31000}
PetProgressTick()
Check("long_disconnect_keeps_pet_visible", finished.Length = 0 && presentations.Length = 1 && presentations[1].state = "disconnecting" && presentations[1].elapsed >= 31000)
deviceOps["A"].state := "disconnected"
PetProgressTick()
Check("disconnect_terminal_only_after_verified", finished.Length = 1 && finished[1].state = "off")

presentations := [], finished := [], actionEpoch := 4
pendingRetryDisconnect := {name:"A",epoch:4,started:A_TickCount-3000}
deviceOps["A"] := {gen:2,action:"connect",state:"retry_cancelled",started:A_TickCount-18000}
PetProgressTick()
Check("queued_cancel_does_not_claim_disconnected", finished.Length = 0 && presentations.Length = 1 && InStr(presentations[1].detail, "已排队"))
pendingRetryDisconnect := 0

presentations := [], finished := [], petBatch := ["A","B"], petBatchStarted := A_TickCount-35000
petBatchGen := Map("A",3,"B",4), petBatchFailed := Map()
deviceOps["A"] := {gen:3,action:"disconnect",state:"disconnected",started:A_TickCount-35000}
deviceOps["B"] := {gen:4,action:"disconnect",state:"down_pending",started:A_TickCount-33000}
PetProgressTick()
Check("batch_waits_for_all_devices", finished.Length = 0 && presentations.Length = 1 && InStr(presentations[1].detail, "1/2"))
deviceOps["B"].state := "disconnected"
PetProgressTick()
Check("batch_finishes_after_all_verified", finished.Length = 1 && finished[1].state = "off" && petBatch.Length = 0)

presentations := [], finished := [], petBatch := ["A","B"], petBatchGen := Map("A",3,"B",4)
deviceOps["B"].state := "service_failed"
PetProgressTick()
Check("batch_partial_failure_is_not_success", finished.Length = 1 && finished[1].state = "fail" && InStr(finished[1].detail, "未断开"))

presentations := [], finished := [], petBatch := [], petOpAction := "connect", petOpGen := 99
PetProgressTick()
Check("stale_generation_cannot_announce_success", finished.Length = 1 && finished[1].state = "fail")

petBatchTicket := 8, busy := false, batchCalls := 0, queue := ["B"]
DisconnectQueue(queue, 7)
Check("superseded_batch_cannot_disconnect_next_device", queue.Length = 1 && batchCalls = 0)

petBatch := ["A", "B"], petBatchGen := Map("A", 3), petBatchTicket := 10
PetShow("connecting", "A", 5)
Check("same_name_connect_clears_disconnect_batch", petBatch.Length = 0 && petBatchTicket = 11)
DisconnectQueue(["B"], 10)
Check("old_batch_timer_cannot_run_after_new_connect", batchCalls = 0)
petVisible := true, petOpName := "A", petOpAction := "connect", petOpGen := 5
deviceOps["A"] := {gen:5,action:"connect",state:"ready",started:A_TickCount-1000}
finished := []
PetProgressTick()
Check("new_connect_can_finish_after_old_batch", finished.Length = 1 && finished[1].state = "ok")
FileAppend("RESULT failures=" failures "`n", "*")
ExitApp(failures ? 1 : 0)
Check(name, ok) {
    global failures
    if !ok
        failures++
    FileAppend((ok ? "PASS " : "FAIL ") name "`n", "*")
}
PetProgress(state, detail, elapsed) {
    global presentations
    presentations.Push({state:state,detail:detail,elapsed:elapsed})
}
PetFinish(state, detail) {
    global finished
    finished.Push({state:state,detail:detail})
}
DeviceProgressJson(name) {
    global deviceOps
    state := deviceOps[name].state
    return state = "connect" || state = "disconnect" || state = "link_pending"
        || state = "link_up" || state = "link_retry_wait" || state = "link_retrying"
        || state = "audio_pending" || state = "down_pending" ? "active" : "null"
}
DoAction(name, action, fromBatch := false) {
    global batchCalls
    batchCalls++
    return "ok"
}
PetBatchFail(name) {
}
PushEvent(name, data) {
}
JsonStr(value) {
    return value
}
PetEnsure() {
    return false
}
PetFade() {
}
PetHideNow() {
}
PetApply(state) {
}
'''
for name in ("PetBatchContains", "PetShow", "PetPhaseText", "PetProgressTick", "DisconnectQueue"):
    body += function(name)

with tempfile.TemporaryDirectory(prefix="apb_pet_lifecycle_") as directory:
    path = Path(directory) / "pet_lifecycle.ahk"
    path.write_text(body, encoding="utf-8-sig")
    result = subprocess.run(
        [str(ROOT / "tools/ahk_v2_portable/AutoHotkey64.exe"), "/ErrorStdOut=UTF-8", str(path)],
        capture_output=True,
        timeout=15,
    )
    print((result.stdout + result.stderr).decode("utf-8-sig", errors="replace"), end="")
    raise SystemExit(result.returncode)
