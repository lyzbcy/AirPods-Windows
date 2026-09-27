"""Headless cold-start test: terminal pet feedback waits until WebView2 is ready."""
from pathlib import Path
import subprocess
import sys
import tempfile

sys.stdout.reconfigure(encoding="utf-8")
root = Path(__file__).resolve().parents[1]
source = (root / "airpods_buddy.ahk").read_text(encoding="utf-8-sig")


def function(name: str) -> str:
    start = source.index("\n" + name + "(")
    end = source.index("\n}", start) + 2
    return source[start:end] + "\n"


body = r'''
#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
OnError((e, mode) => (FileAppend("ERROR " e.Message " line=" e.Line "`n", "*"), ExitApp(2)))
failures := 0, fadeCount := 0, applied := []
petReady := false, petVisible := true, petPending := ""
petWv := 0
PetFinish("fail", "连接未完成")
Sleep(85)
Check("terminal_does_not_fade_before_petready", fadeCount = 0 && IsObject(petPending) && petPending.state = "fail")
core := {Source:"https://app.airpods.local/pet_built.html"}
PetOnMsg(core, MockArgs())
Check("petready_replays_terminal_state", petReady && applied.Length = 1 && applied[1].state = "fail" && applied[1].detail = "连接未完成")
Sleep(85)
Check("full_terminal_dwell_starts_after_petready", fadeCount = 1)
FileAppend("RESULT failures=" failures "`n", "*")
ExitApp(failures ? 1 : 0)
Check(name, ok) {
    global failures
    if !ok
        failures++
    FileAppend((ok ? "PASS " : "FAIL ") name "`n", "*")
}
class MockArgs {
    Source := "https://app.airpods.local/pet_built.html"
    TryGetWebMessageAsString() {
        return "petready"
    }
}
PetApply(state, detail := "") {
    global applied
    applied.Push({state:state, detail:detail})
}
PetProgressTick() {
}
PetFade() {
    global fadeCount
    fadeCount++
}
JsonStr(s) {
    return s
}
'''
for name in ("PetOnMsg", "PetUpdate", "PetFinish"):
    body += function(name).replace("-2500", "-40")

with tempfile.TemporaryDirectory(prefix="apb_pet_ready_") as directory:
    path = Path(directory) / "ready_race.ahk"
    path.write_text(body, encoding="utf-8-sig")
    result = subprocess.run(
        [str(root / "tools/ahk_v2_portable/AutoHotkey64.exe"), "/ErrorStdOut=UTF-8", str(path)],
        capture_output=True,
        timeout=10,
    )
    print((result.stdout + result.stderr).decode("utf-8-sig", errors="replace"), end="")
    raise SystemExit(result.returncode)
