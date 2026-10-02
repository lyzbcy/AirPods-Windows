"""Execute production privacy, discovery formatting, dedup and feedback export offline."""
from pathlib import Path
import argparse, subprocess, sys, tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.stdout.reconfigure(encoding='utf-8')
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=ROOT/'airpods_buddy.ahk')
args = parser.parse_args()
source = args.source.read_text(encoding='utf-8-sig')
contracts = {
    'local_log_has_privacy_boundary': 'try msg := DiagnosticSanitize(msg)' in source,
    'discovery_has_deduplicated_diagnostics': 'try DiagnosticObserveDiscovery(diagnostic, diagnosticRows)' in source,
    'feedback_snapshot_requires_log_consent': 'diagnostic := wantFile ? DiagnosticCollectFeedback() : ""' in source,
    'legacy_logs_resanitized_on_export': 'fw.Write(DiagnosticSanitize(body))' in source,
    'rpc_does_not_log_raw_message': ' : "rpc: " msg)' not in source and '"rpc: " cmd " id=" id' in source,
}
failed = 0
for name, ok in contracts.items():
    print(('PASS ' if ok else 'FAIL ')+name)
    failed += not ok
if failed:
    print(f'RESULT failures={failed} contractOnly=true')
    raise SystemExit(1)

def function(name):
    start = source.index('\n'+name+'(')
    end = source.index('\n}', start)+2
    return source[start:end]

body = r'''
#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Warn LocalSameAsGlobal, Off
#Include DIAGNOSTIC_LIB
#Include AUDIO_LIB
OnError((e, mode) => (FileAppend("ERROR " e.Message " line=" e.Line "`n", "*"), ExitApp(2)))
failures := 0, APP_VERSION := "1.9.22"
LOG_DIR := A_ScriptDir "\logs"
DirCreate(LOG_DIR)
logFile := LOG_DIR "\app-" FormatTime(A_Now, "yyyy-MM-dd") ".log"
privateName := "私密测试用户的耳机"
DiagnosticPrivateNames(privateName)
address := "70AE2AA42B80"
endpoint := "{0.0.0.00000000}.{12345678-1234-1234-1234-123456789ABC}"
container := "87654321-4321-4321-4321-CBA987654321"
raw := "name=" privateName " address=" address " mac=70:AE:2A:A4:2B:80 endpoint=" endpoint " container=" container
safe := DiagnosticSanitize(raw)
Check("redacts_custom_device_name", !InStr(safe, privateName))
Check("redacts_raw_and_colon_mac", !InStr(safe, address) && !InStr(safe, "70:AE:2A:A4:2B:80"))
Check("redacts_endpoint_and_container", !InStr(safe, endpoint) && !InStr(safe, "12345678") && !InStr(safe, "87654321"))
Check("preserves_alias_correlation", InStr(safe,"address=device#1") && InStr(safe,"mac=device#1"))
Check("alias_not_raw_or_persistent_hash", DiagnosticAlias("device", address) = "device#1")
Check("session_random_format", RegExMatch(DiagnosticSession(),"^s[0-9A-F]{8}$"))
Check("redacts_profile_path_spaces", !InStr(DiagnosticSanitize("failed C:\Users\Private Owner\Documents\secret.log status=fail"),"Private Owner"))
Check("path_redaction_keeps_numeric_status", InStr(DiagnosticSanitize("failed C:\Users\Private Owner\secret.log HRESULT=0x80070005"),"HRESULT=0x80070005"))
Check("redacts_unc_path", !InStr(DiagnosticSanitize("failed \\private-host\private-share\file.txt"),"private-host"))
Check("redacts_pnp_serial", !InStr(DiagnosticSanitize("node=USB\VID_1234&PID_5678\PRIVATE_SERIAL"),"PRIVATE_SERIAL"))
Check("redacts_email_phone", !InStr(DiagnosticSanitize("private@example.invalid 13812345678"),"private@example") && !InStr(DiagnosticSanitize("private@example.invalid 13812345678"),"13812345678"))
Check("redacts_ip_and_webhook_secret", !InStr(DiagnosticSanitize("ip=192.168.1.22 url=https://example.invalid/?key=PRIVATE_SECRET"),"PRIVATE_SECRET") && !InStr(DiagnosticSanitize("ip=192.168.1.22"),"192.168"))
Check("redacts_bearer_token", !InStr(DiagnosticSanitize("Authorization: Bearer PRIVATE_ACCESS_TOKEN"),"PRIVATE_ACCESS_TOKEN"))
Check("redacts_sid_and_jwt", !InStr(DiagnosticSanitize("S-1-5-21-123456789-987654321-555555555-1001 eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJwcml2YXRlIn0.signature"),"123456789") && !InStr(DiagnosticSanitize("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJwcml2YXRlIn0.signature"),"eyJ"))
Check("sanitizer_is_idempotent", DiagnosticSanitize(safe)=safe)
Check("redacts_legacy_priority_labels", !InStr(DiagnosticSanitize("priority updated: UnknownPrivateName"),"UnknownPrivateName"))
Check("redacts_legacy_rpc_labels", !InStr(DiagnosticSanitize("rpc: setprio" Chr(31) "1" Chr(31) "OtherPrivateName"),"OtherPrivateName"))
Check("redacts_legacy_js_payload", !InStr(DiagnosticSanitize('[JS-ERROR] rawlist=[{"name":"OtherPrivateName"}]'),"OtherPrivateName"))
Check("redacts_legacy_noise_label", !InStr(DiagnosticSanitize("noise mode auto -> OtherPrivateName (" address ")"),"OtherPrivateName"))
Check("keeps_hresult_and_technical_phase", InStr(DiagnosticSanitize("link_pending HRESULT=0x88890008 requested=2"),"HRESULT=0x88890008 requested=2"))

LogMsg(raw)
Check("local_log_privacy_boundary_works", !InStr(FileRead(logFile,"UTF-8"),privateName) && !InStr(FileRead(logFile,"UTF-8"),address))
stats := DiagnosticNewStats("authenticated"), rows := []
info := MakeInfo(privateName " AirPods Pro", address, 0, 32, 1, 1)
DiagnosticTrackRow(stats, rows, info)
DiagnosticTrackRow(stats, rows, MakeInfo("HiddenUnknownName", "000000000011", 0, 0, 1, 0))
DiagnosticTrackRow(stats, rows, MakeInfo("PrivateKeyboard", "000000000012", 0x0500, 0, 1, 1))
Check("discovery_counts_and_filter_reasons", stats.raw=3 && stats.accepted=1 && stats.rejected=2 && stats.unknownClass=1 && stats.nonAudio=1)
Check("normalizes_boolean_flags", stats.connected=1 && stats.remembered=3 && stats.authenticated=2)
summary := DiagnosticDiscoveryText(stats, rows)
Check("summary_category_only", InStr(summary,"nameHint=airpods-pro") && !InStr(summary,privateName) && !InStr(summary,"PrivateKeyboard"))
Check("summary_marks_classic_and_no_inquiry", InStr(summary,"inquiry=off coverage=classic-only"))
Check("summary_flags_errors_present", InStr(summary,"authenticated=2") && InStr(summary,"error=0"))
stats.refreshErrors:=1,stats.refreshError:=87
Check("refresh_error_code_preserved", InStr(DiagnosticDiscoveryText(stats,rows),"refreshError=87"))
Check("first_discovery_logged", DiagnosticObserveDiscovery(stats,rows,100))
size := FileGetSize(logFile)
stats.elapsedMs := 77
Check("same_snapshot_not_logged_each_poll", !DiagnosticObserveDiscovery(stats,rows,4100) && FileGetSize(logFile)=size)
stats.status := "api_error", stats.error := 5
Check("error_change_logged", DiagnosticObserveDiscovery(stats,rows,8100))
Check("unchanged_error_deduplicated", !DiagnosticObserveDiscovery(stats,rows,12100))
Check("five_minute_heartbeat", DiagnosticObserveDiscovery(stats,rows,308100))
many := DiagnosticNewStats("cached"), details := []
loop 40
    DiagnosticTrackRow(many,details,MakeInfo("AirPods",Format("{:012X}", A_Index+100),0x0400,0,1,1))
Check("detail_bounded_counts_complete", many.raw=40 && many.accepted=40 && details.Length=16 && InStr(DiagnosticDiscoveryText(many,details),"details=bounded"))

fake := FakeBackend()
snapshot := DiagnosticCollectFeedback(fake)
Check("feedback_compares_broader_cached_search", InStr(snapshot,"mode=authenticated") && InStr(snapshot,"mode=cached") && InStr(snapshot,"authenticated_filter_gap"))
Check("feedback_reports_os_arch_and_schema", InStr(snapshot,"schema=1") && InStr(snapshot,"os=") && InStr(snapshot,"arch="))
Check("radio_presence_not_called_power", InStr(snapshot,"power=unverified"))
Check("snapshot_never_promises_root_cause", InStr(snapshot,"notRootCause=true"))
Check("snapshot_no_persistent_ids", !InStr(snapshot,address) && !InStr(snapshot,privateName) && !InStr(snapshot,endpoint))
Check("snapshot_failure_has_no_exception_text", !InStr(DiagnosticCollectFeedback(BrokenBackend()),"SecretUser"))
Check("partial_enumeration_not_reported_as_empty", InStr(DiagnosticCollectFeedback(PartialBackend()),"classic_partial_result"))

; Legacy files may predate the new logger: export must sanitize them as well.
yesterday := LOG_DIR "\app-" FormatTime(DateAdd(A_Now,-1,"days"),"yyyy-MM-dd") ".log"
FileAppend("priority updated: OldPrivateDevice`r`n",yesterday,"UTF-8")
FileAppend("boot scriptdir=C:\Users\OldPrivateUser\Desktop\App`r`n",logFile,"UTF-8")
FileAppend("address=" address " render=" endpoint " CURRENT_DAY_MARKER`r`n",logFile,"UTF-8")
tail := GatherLogTail(snapshot)
Check("tail_resanitizes_legacy_private_data", !InStr(tail,"OldPrivateUser") && !InStr(tail,"OldPrivateDevice") && !InStr(tail,address))
Check("tail_prefers_current_day_and_keeps_snapshot", InStr(tail,"CURRENT_DAY_MARKER") && InStr(tail,"authenticated_filter_gap"))
attachmentPath := BuildIssueLogFile(snapshot)
attachment := FileRead(attachmentPath,"UTF-8")
Check("attachment_has_snapshot", InStr(attachment,"authenticated_filter_gap"))
Check("attachment_has_no_personal_path_or_device_id", !InStr(attachment,"OldPrivateUser") && !InStr(attachment,address) && !InStr(attachment,endpoint))
Check("attachment_sections_do_not_expose_paths", !InStr(attachment,A_ScriptDir) && !InStr(attachment,A_Temp))
FileDelete(attachmentPath)
; Redact before tail truncation, so cutting a legacy path/name cannot expose a fragment.
padding := ""
loop 49135
    padding .= "X"
FileAppend("`r`nboot scriptdir=C:\Users\BoundaryPrivateOwner\secret.log`r`n" padding, yesterday,"UTF-8")
attachmentPath := BuildIssueLogFile(snapshot)
Check("legacy_redaction_precedes_size_truncation", !InStr(FileRead(attachmentPath,"UTF-8"),"BoundaryPrivateOwner"))
FileDelete(attachmentPath)
FileAppend("RESULT failures=" failures "`n", "*")
ExitApp(failures ? 1 : 0)

Check(name, ok) {
    global failures
    if !ok
        failures++
    FileAppend((ok ? "PASS " : "FAIL ") name "`n", "*")
}
MakeInfo(name,address,cod,connected,remembered,authenticated) {
    info:=Buffer(560,0)
    NumPut("uint",560,info,0),NumPut("uint64",Integer("0x" address),info,8)
    NumPut("uint",cod,info,16),NumPut("uint",connected,info,20)
    NumPut("uint",remembered,info,24),NumPut("uint",authenticated,info,28)
    StrPut(name,info.Ptr+64,248,"UTF-16")
    return info
}
class FakeBackend {
    Classic(mode) {
        global privateName,address
        stats:=DiagnosticNewStats(mode),rows:=[]
        if mode="cached"
            DiagnosticTrackRow(stats,rows,MakeInfo(privateName " AirPods",address,0,0,1,0))
        else
            stats.status:="no_match",stats.error:=259
        return {stats:stats,rows:rows}
    }
    Radios() => "radios visible=1 error=0 power=unverified"
    Audio() => "`n  audio flow=render active=1 disabled=1 absent=0 unplugged=1 role0=endpoint#1"
}
class BrokenBackend {
    Classic(*) {
        throw Error("private C:\Users\SecretUser\file")
    }
}
class PartialBackend extends FakeBackend {
    Classic(mode) {
        value := super.Classic(mode)
        value.stats.status := "partial",value.stats.nextError := 5
        return value
    }
}
'''
body = body.replace('DIAGNOSTIC_LIB', str(ROOT/'lib/Diagnostics.ahk'))
body = body.replace('AUDIO_LIB', str(ROOT/'lib/AudioRouting.ahk'))
body += '\n'.join(function(n) for n in ('LogMsg','IsAppleDevice','IsAudioCandidate','GatherLogTail','BuildIssueLogFile'))
with tempfile.TemporaryDirectory(prefix='apb_private_diagnostics_') as directory:
    script = Path(directory)/'diagnostics.ahk'
    script.write_text(body,encoding='utf-8-sig')
    p = subprocess.run([str(ROOT/'tools/ahk_v2_portable/AutoHotkey64.exe'),'/ErrorStdOut=UTF-8',str(script)],capture_output=True,timeout=25)
    print((p.stdout+p.stderr).decode('utf-8-sig',errors='replace'),end='')
    raise SystemExit(p.returncode)
