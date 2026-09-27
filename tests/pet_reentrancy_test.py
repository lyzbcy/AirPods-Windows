"""Exercise the real AHK pet readiness guard with a reentrant pending controller."""
from pathlib import Path
import argparse
import subprocess
import sys
import tempfile

sys.stdout.reconfigure(encoding="utf-8")
root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path, default=root / "airpods_buddy.ahk")
parser.add_argument("--baseline", action="store_true")
args = parser.parse_args()
source = args.source.read_text(encoding="utf-8-sig")
if args.baseline:
    old = "pet controller ready elapsedMs=" not in source and "PetSchedule(" not in source
    print("BASELINE_PASS legacy_sync_pet_creation=true" if old else "BASELINE_FAIL legacy_sync_pet_creation=false")
    raise SystemExit(0 if old else 1)


def function(name: str) -> str:
    start = source.find("\n" + name + "(")
    if start < 0:
        return ""
    end = source.index("\n}", start) + 2
    return source[start:end] + "\n"


checks = {
    "rpc_defers_pet_controller_creation": "SetTimer(() => PetRunScheduled(state, name, gen, fromBatch, seq), -1)" in function("PetSchedule")
    and 'PetSchedule(action = "connect" ? "connecting" : "disconnecting", name, gen, fromBatch)' in function("DoAction"),
    "controller_not_gui_is_ready": "return IsSet(petControllerReady) && petControllerReady && IsSet(petWvc) && IsObject(petWvc)" in function("PetEnsure"),
    "shared_environment_first": "sharedEnv := wv.Environment" in function("PetEnsure"),
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
failures := 0, fills := 0, shown := []
petGui := FakeGui(), petWvc := 0, petWv := 0, petControllerReady := false
petVisible := false, petDeferred := "", petShowSeq := 1
appRoot := "", wv2Fallback := "", wvDll := "", wv := 0
PetShow("connecting", "A", 1, false, 1)
Check("reentrant_gui_without_controller_defers_not_fills", IsObject(petDeferred) && petDeferred.name = "A" && fills = 0)
petShowSeq := 2
PetShow("disconnecting", "B", 2, false, 2)
Check("newer_request_replaces_pending", IsObject(petDeferred) && petDeferred.name = "B" && petDeferred.seq = 2 && fills = 0)
PetRunScheduled("connecting", "A", 1, false, 1)
Check("stale_ticket_cannot_replace_newer_request", IsObject(petDeferred) && petDeferred.name = "B")
petWvc := FakeController(), petWv := {}, petControllerReady := true
PetResumeDeferred()
Check("ready_controller_displays_only_latest", fills = 1 && shown.Length = 1 && shown[1] = "disconnecting" && !IsObject(petDeferred))
FileAppend("RESULT failures=" failures "`n", "*")
ExitApp(failures ? 1 : 0)
Check(name, ok) {
    global failures
    if !ok
        failures++
    FileAppend((ok ? "PASS " : "FAIL ") name "`n", "*")
}
class FakeGui {
    Hwnd := 0
    Show(*) {
    }
}
class FakeController {
    IsVisible := false
    Fill() {
        global fills
        fills++
    }
}
class WebView2 {
    static create(*) {
        return FakeController()
    }
}
EnsureResources() {
}
PetOnMsg(*) {
}
PetFade() {
}
PetHideNow() {
}
PetProgressTick() {
}
PetApply(state) {
    global shown
    shown.Push(state)
}
LogMsg(*) {
}
'''
for name in ("PetEnsure", "PetRunScheduled", "PetResumeDeferred", "PetShow"):
    body += function(name)

with tempfile.TemporaryDirectory(prefix="apb_pet_reentrant_") as directory:
    path = Path(directory) / "pet_reentrant.ahk"
    path.write_text(body, encoding="utf-8-sig")
    result = subprocess.run(
        [str(root / "tools/ahk_v2_portable/AutoHotkey64.exe"), "/ErrorStdOut=UTF-8", str(path)],
        capture_output=True,
        timeout=10,
    )
    print((result.stdout + result.stderr).decode("utf-8-sig", errors="replace"), end="")
    raise SystemExit(result.returncode)
