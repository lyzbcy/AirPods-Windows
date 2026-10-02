"""Run the production issue-submission function with offline log/send fakes."""
from pathlib import Path
import subprocess
import sys
import tempfile

sys.stdout.reconfigure(encoding="utf-8")
root = Path(__file__).resolve().parents[1]
source_path = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "airpods_buddy.ahk"
source = source_path.read_text(encoding="utf-8-sig")
start = source.index("\nSendIssueAsync(")
end = source.index("\n}", start) + 2
function = source[start:end]

body = r'''
#Requires AutoHotkey v2.0
#SingleInstance Off
OnError((e, mode) => (FileAppend("ERROR " e.Message " line=" e.Line "`n", "*"), ExitApp(2)))
feedbackBusy := false
gatherCalls := 0, fileCalls := 0, diagnosticCalls := 0, sentPayload := "", sentPath := ""
SendIssueAsync(1, "连接", "测试", "00", "")
Check("unchecked_never_reads_log_tail", gatherCalls = 0)
Check("unchecked_never_builds_log_file", fileCalls = 0)
Check("unchecked_payload_has_no_log", !InStr(sentPayload, "LOG_MARKER"))
Check("unchecked_payload_has_no_file_path", !InStr(sentPayload, "FILE_MARKER") && sentPath = "")
Check("unchecked_never_collects_diagnostics", diagnosticCalls = 0)
gatherCalls := 0, fileCalls := 0, diagnosticCalls := 0, sentPayload := "", sentPath := ""
SendIssueAsync(2, "连接", "测试", "01", "")
Check("checked_reads_log_tail", gatherCalls = 1)
Check("checked_builds_log_file", fileCalls = 1)
Check("checked_payload_has_log_tail", InStr(sentPayload, "LOG_MARKER") > 0)
Check("checked_payload_has_file_path", InStr(sentPayload, "FILE_MARKER") > 0 && sentPath = "FILE_MARKER")
Check("checked_collects_diagnostics_once", diagnosticCalls = 1)
Check("checked_tail_receives_diagnostic", InStr(sentPayload, "DIAGNOSTIC_MARKER") > 0)
FileAppend("RESULT failures=" failures "`n", "*")
ExitApp(failures ? 1 : 0)
Check(name, ok) {
    global failures
    if !ok
        failures++
    FileAppend((ok ? "PASS " : "FAIL ") name "`n", "*")
}
GatherLogTail(diagnostic := "") {
    global gatherCalls
    gatherCalls++
    return "LOG_MARKER " diagnostic
}
BuildIssueLogFile(diagnostic := "") {
    global fileCalls
    fileCalls++
    return "FILE_MARKER"
}
DiagnosticCollectFeedback() {
    global diagnosticCalls
    diagnosticCalls++
    return "DIAGNOSTIC_MARKER"
}
TruncateUtf8(s, n) => s
FbWebhook() => "WEBHOOK"
JsonStr(s) => '"' s '"'
Reply(id, result) {
    throw Error("Unexpected busy reply")
}
SendFeedbackJob(id, kind, payload, logPath := "") {
    global sentPayload, sentPath
    sentPayload := payload
    sentPath := logPath
}
'''
body = body.replace('feedbackBusy := false\n', 'feedbackBusy := false\nfailures := 0\n', 1)
body += function
with tempfile.TemporaryDirectory(prefix="apb_feedback_consent_") as directory:
    script = Path(directory) / "consent.ahk"
    script.write_text(body, encoding="utf-8-sig")
    run = subprocess.run(
        [str(root / "tools/ahk_v2_portable/AutoHotkey64.exe"),
         "/ErrorStdOut=UTF-8", str(script)],
        capture_output=True,
        timeout=15,
    )
    print((run.stdout + run.stderr).decode("utf-8-sig", errors="replace"), end="")
    raise SystemExit(run.returncode)
