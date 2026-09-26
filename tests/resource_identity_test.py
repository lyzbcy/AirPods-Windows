"""Headless regression for compiled resource directory identity and cleanup names."""
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


checks = {
    "runtime_path_uses_guid": 'APP_VERSION "-" DllCall("GetCurrentProcessId") "-" NewResourceRunId()' in source,
    "cleanup_uses_shared_parser": "pid := ManagedTempPid(kind, name)" in source,
}
for name, ok in checks.items():
    print(("PASS " if ok else "FAIL ") + name)
if not all(checks.values()):
    raise SystemExit(1)

body = r'''
#Requires AutoHotkey v2.0
#SingleInstance Off
OnError((e, mode) => (FileAppend("ERROR " e.Message " line=" e.Line "`n", "*"), ExitApp(2)))
failures := 0
a := NewResourceRunId(), b := NewResourceRunId()
Check("guid_is_32_hex", RegExMatch(a, "^[0-9a-f]{32}$") && RegExMatch(b, "^[0-9a-f]{32}$"))
Check("same_pid_launches_are_isolated", a != b)
Check("new_app_folder_cleanup_pid", ManagedTempPid("AirPodsBuddy_app", "1.9.20-12345-" a) = 12345)
Check("legacy_app_folder_cleanup_pid", ManagedTempPid("AirPodsBuddy_app", "1.9.19-12345") = 12345)
Check("job_folder_cleanup_pid", ManagedTempPid("AirPodsBuddy_jobs", "12345-678-9") = 12345)
Check("malformed_app_folder_ignored", ManagedTempPid("AirPodsBuddy_app", "1.9.20-12345-notaguid") = 0)
Check("foreign_folder_ignored", ManagedTempPid("other", "1.9.20-12345-" a) = 0)
FileAppend("RESULT failures=" failures "`n", "*")
ExitApp(failures ? 1 : 0)
Check(name, ok) {
    global failures
    if !ok
        failures++
    FileAppend((ok ? "PASS " : "FAIL ") name "`n", "*")
}
'''
body += function("NewResourceRunId") + function("ManagedTempPid")
with tempfile.TemporaryDirectory(prefix="apb_resource_test_") as directory:
    script = Path(directory) / "resource_test.ahk"
    script.write_text(body, encoding="utf-8-sig")
    run = subprocess.run(
        [str(ROOT / "tools/ahk_v2_portable/AutoHotkey64.exe"), "/ErrorStdOut=UTF-8", str(script)],
        capture_output=True,
        timeout=15,
    )
    output = (run.stdout + run.stderr).decode("utf-8-sig", errors="replace")
    print(output, end="")
    raise SystemExit(run.returncode)
