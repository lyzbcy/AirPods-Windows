"""Execute production microphone ownership and route observations with synthetic endpoints."""
from pathlib import Path
import argparse, subprocess, sys, tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.stdout.reconfigure(encoding='utf-8')
parser = argparse.ArgumentParser()
parser.add_argument('--source-root', type=Path, default=ROOT)
selected = parser.parse_args().source_root
main = (selected/'airpods_buddy.ahk').read_text(encoding='utf-8-sig')
audio = (selected/'lib/AudioRouting.ahk').read_text(encoding='utf-8-sig')
contracts = {
    'unset_mic_preference_is_off': 'SettingRead("auto_mic_switch", "1")' not in main,
    'owned_mic_route_implemented': 'class OwnedCaptureRoute' in audio,
    'off_releases_owned_capture_only_after_save': 'ReleaseOwnedMicRoute()' in main,
    'route_query_failure_is_not_known_loss': 'observation.reason = "query_failed"' in main,
}
for name, ok in contracts.items():
    print(('PASS ' if ok else 'FAIL ')+name)
if not all(contracts.values()):
    raise SystemExit(1)

body = r'''
#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Warn LocalSameAsGlobal, Off
#Include AUDIO_LIB
#Include DIAGNOSTIC_LIB
OnError((e, mode) => (FileAppend("ERROR " e.Message " line=" e.Line "`n", "*"), ExitApp(2)))
failures := 0
APP_VERSION := "1.9.22"
SETTINGS_PATH := A_ScriptDir "\preferences.ini"
api := CallAudio(), ownedMicRoute := BoundCaptureRoute(api)
Check("unset_preference_preserves_mic", SettingRead("auto_mic_switch", "0") = "0" && api.writes = 0)
Check("explicit_on_is_saved", MicPreferenceSet("1") && SettingRead("auto_mic_switch", "0") = "1")
ownedMicRoute.Switch("micA", api)
Check("production_off_restores_owned_capture", MicPreferenceSet("0") && api.defaults[1] = "old0" && SettingRead("auto_mic_switch", "1") = "0")
MicPreferenceSet("1"), ownedMicRoute.Switch("micA", api)
handle := DllCall("CreateFileW", "wstr", SETTINGS_PATH, "uint", 0x80000000, "uint", 0, "ptr", 0, "uint", 3, "uint", 0, "ptr", 0, "ptr")
Check("save_failure_does_not_restore_or_change_preference", !MicPreferenceSet("0") && api.defaults[1] = "micA")
DllCall("CloseHandle", "ptr", handle)
Check("off_after_unlock_restores", MicPreferenceSet("0") && api.defaults[1] = "old0")
api := CallAudio(), owner := OwnedCaptureRoute()
Check("opt_in_switch_changes_capture_three_roles", owner.Switch("micA", api) && api.defaults[1] = "micA" && api.writes = 3)
r := owner.Restore(api)
Check("off_restores_each_original_role", r.restored = 3 && r.failed = 0 && api.defaults[1] = "old0" && api.defaults[2] = "old1" && api.defaults[3] = "old2")
Check("off_again_is_noop", owner.Restore(api).restored = 0 && api.writes = 6)
Check("restore_does_not_touch_render", api.renderWrites = 0)
api := CallAudio(), owner := OwnedCaptureRoute()
owner.Switch("micA", api), owner.Switch("micA", api)
Check("repeat_connect_keeps_original_receipt", owner.Restore(api).restored = 3 && api.defaults[1] = "old0")
api := CallAudio(), owner := OwnedCaptureRoute()
owner.Switch("micA", api), owner.Switch("micB", api)
Check("second_headset_keeps_original_baseline", owner.Restore(api).restored = 3 && api.defaults[1] = "old0")
api := CallAudio(), owner := OwnedCaptureRoute()
api.defaults := ["micA", "old1", "old2"]
owner.Switch("micA", api)
Check("preexisting_headset_role_not_owned", owner.Restore(api).restored = 2 && api.defaults[1] = "micA")
api := CallAudio(), owner := OwnedCaptureRoute()
api.defaults := ["micA", "old1", "old2"]
owner.Switch("micA", api), owner.Switch("micB", api)
Check("preexisting_headset_role_restored_after_switching_target", owner.Restore(api).restored = 3 && api.defaults[1] = "micA")
api := CallAudio(), owner := OwnedCaptureRoute()
owner.Switch("micA", api), api.defaults[2] := "external"
r := owner.Restore(api)
Check("external_selection_preserved", r.restored = 2 && api.defaults[2] = "external")
api := CallAudio(), owner := OwnedCaptureRoute()
owner.Switch("micA", api), api.oldState := 8
Check("unavailable_original_not_reenabled", owner.Restore(api).restored = 0 && api.writes = 3)
api := CallAudio(), owner := OwnedCaptureRoute()
api.failRole := 1
Check("failed_switch_not_acquired", !owner.Switch("micA", api) && owner.Restore(api).restored = 0)
Check("failed_switch_rolls_back_partial_writes", api.defaults[1] = "old0" && api.defaults[2] = "old1")
api := CallAudio(), owner := OwnedCaptureRoute()
Check("obsolete_action_does_not_switch", !owner.Switch("micA", api, () => false) && api.writes = 0)
api := CallAudio(), owner := OwnedCaptureRoute()
Check("superseded_during_switch_restores_owned_changes", !owner.Switch("micA", api, () => api.writes = 0) && api.defaults[1] = "old0")
api := CallAudio(), owner := OwnedCaptureRoute()
owner.Switch("micA", api), api.restoreFail := true
Check("restore_failure_reported", owner.Restore(api).failed = 3)
api.restoreFail := false
Check("failed_restore_receipt_retained_for_explicit_retry", owner.Restore(api).restored = 3)
api := CallAudio(), owner := OwnedCaptureRoute()
Check("new_process_has_no_guessed_original", owner.Restore(api).restored = 0 && api.writes = 0)
api := CallAudio(), owner := OwnedCaptureRoute()
api.throwDefault := true
Check("default_query_failure_never_routes", !owner.Switch("micA", api) && api.writes = 0)
api := CallAudio()
r := AudioRouteObservation("render", api)
Check("matching_active_route_is_ready", r.matches && r.reason = "ready" && r.matchedRoles = 7)
api.renderState := 8
r := AudioRouteObservation("render", api)
Check("unplugged_endpoint_is_explicit", !r.matches && r.reason = "endpoint_inactive" && r.state = 8)
api := CallAudio(), api.renderDefaults[3] := "speaker"
r := AudioRouteObservation("render", api)
Check("changed_communications_role_distinguished", !r.matches && r.reason = "default_changed" && r.matchedRoles = 3)
api := CallAudio(), api.throwDefault := true
Check("com_error_is_unknown_not_inactive", AudioRouteObservation("render", api).reason = "query_failed")
api := CallAudio(), api.absent := true
Check("missing_endpoint_distinguished", AudioRouteObservation("render", api).reason = "endpoint_missing")
api := CallAudio(), api.dropAfterRoles := true
Check("endpoint_rechecked_after_default_readback", AudioRouteObservation("render", api).reason = "endpoint_inactive")
Check("observations_never_write_or_open_stream", api.writes = 0 && api.renderWrites = 0 && api.probes = 0)
api := CallAudio(), api.defaults := ["{0.0.1.00000000}.{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}", "{0.0.1.00000000}.{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}", "{0.0.1.00000000}.{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}"]
summary := DiagnosticAudioSummary(api)
Check("feedback_capture_sessions_are_anonymous", InStr(summary, "observedActive=1") && !InStr(summary, "AAAAAAAA"))
Check("feedback_snapshot_deduplicates_same_capture_id", api.sessionReads = 1 && api.writes = 0 && api.probes = 0)
Check("snapshot_does_not_claim_complete_capture_coverage", InStr(summary, "complete=unverified"))
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
PushEvent(*) {
}
class BoundCaptureRoute extends OwnedCaptureRoute {
 __New(api) {
  super.__New()
  this.api := api
 }
 Restore(backend?) {
  return super.Restore(this.api)
 }
}
class CallAudio {
 __New() {
  this.defaults := ["old0", "old1", "old2"], this.renderDefaults := ["render", "render", "render"]
  this.writes := 0, this.renderWrites := 0, this.probes := 0, this.failRole := -1
  this.oldState := 1, this.renderState := 1, this.restoreFail := false, this.throwDefault := false
  this.absent := false, this.dropAfterRoles := false, this.reads := 0
  this.sessionReads := 0
 }
 DefaultId(flow, role) {
  if this.throwDefault
   throw Error("synthetic query failure")
  this.reads++
  if this.dropAfterRoles && this.reads = 3
   this.renderState := 8
  return flow = 1 ? this.defaults[role+1] : this.renderDefaults[role+1]
 }
 SetDefault(id, role) {
  this.writes++
  if id = "render"
   this.renderWrites++
  if (id = "micA" && role = this.failRole) || (this.restoreFail && InStr(id, "old") = 1)
   return -1
  this.defaults[role+1] := id
  return 0
 }
 CaptureUse(id) {
  this.sessionReads++
  return 1
 }
 Endpoints(flow, states := 1) {
  if flow = 0
   return this.absent ? [] : [{id:"render", name:"Synthetic render", state:this.renderState}]
  return [{id:"micA",name:"Synthetic A",state:1},{id:"micB",name:"Synthetic B",state:1},
   {id:"old0",name:"Synthetic 0",state:this.oldState},{id:"old1",name:"Synthetic 1",state:this.oldState},{id:"old2",name:"Synthetic 2",state:this.oldState}]
 }
}
'''.replace('AUDIO_LIB', str(selected/'lib/AudioRouting.ahk')).replace('DIAGNOSTIC_LIB', str(selected/'lib/Diagnostics.ahk'))
for name in ['SettingRead','AtomicWriteText','Join','MicPreferenceSet','ReleaseOwnedMicRoute','JsonStr','IsAppleDevice','IsAudioCandidate']:
    start = main.index('\n'+name+'(')
    end = main.index('\n}', start)+2
    body += main[start:end]+'\n'
with tempfile.TemporaryDirectory(prefix='apb_call_audio_') as d:
    script=Path(d)/'test.ahk'
    script.write_text(body, encoding='utf-8-sig')
    p=subprocess.run([str(ROOT/'tools/ahk_v2_portable/AutoHotkey64.exe'),'/ErrorStdOut=UTF-8',str(script)],capture_output=True,timeout=60)
    print((p.stdout+p.stderr).decode('utf-8-sig',errors='replace'),end='')
    raise SystemExit(p.returncode)
