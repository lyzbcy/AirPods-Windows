"""Exercise the production classic-device candidate predicate without Bluetooth I/O."""
from pathlib import Path
import subprocess
import sys
import tempfile

sys.stdout.reconfigure(encoding="utf-8")
root = Path(__file__).resolve().parents[1]
source = (root / "airpods_buddy.ahk").read_text(encoding="utf-8-sig")


def function(name):
    start = source.index("\n" + name + "(")
    end = source.index("\n}", start) + 2
    return source[start:end]


integration = 'if IsAudioCandidate(cod, StrGet(deviceInfo.Ptr + 64, "UTF-16")) {' in source
print(("PASS " if integration else "FAIL ") + "classic_enumeration_uses_candidate_predicate")
if not integration:
    raise SystemExit(1)

body = r'''
#Requires AutoHotkey v2.0
#SingleInstance Off
OnError((e, mode) => (FileAppend("ERROR " e.Message " line=" e.Line "`n", "*"), ExitApp(2)))
failures := 0
Check("normal_audio_video_class_unchanged", IsAudioCandidate(0x0400, "Generic Headset"))
Check("airpods5_unknown_class_allowed", IsAudioCandidate(0, "AirPods 5"))
Check("beats_peripheral_class_allowed", IsAudioCandidate(0x0500, "Beats Studio Pro"))
Check("apple_match_case_insensitive", IsAudioCandidate(0x0100, "alice's aIrPoDs"))
Check("nonapple_peripheral_rejected", !IsAudioCandidate(0x0500, "Magic Keyboard"))
Check("nonapple_unknown_class_rejected", !IsAudioCandidate(0, "Generic Headset"))
Check("nonapple_lookalike_rejected", !IsAudioCandidate(0x0500, "AirPod 5"))
Check("empty_name_unknown_class_rejected", !IsAudioCandidate(0, ""))
FileAppend("RESULT failures=" failures "`n", "*")
ExitApp(failures ? 1 : 0)
Check(name, ok) {
    global failures
    if !ok
        failures++
    FileAppend((ok ? "PASS " : "FAIL ") name "`n", "*")
}
'''
body += function("IsAppleDevice") + function("IsAudioCandidate")
with tempfile.TemporaryDirectory(prefix="apb_classifier_") as directory:
    script = Path(directory) / "classifier.ahk"
    script.write_text(body, encoding="utf-8-sig")
    run = subprocess.run(
        [str(root / "tools/ahk_v2_portable/AutoHotkey64.exe"), "/ErrorStdOut=UTF-8", str(script)],
        capture_output=True,
        timeout=15,
    )
    print((run.stdout + run.stderr).decode("utf-8-sig", errors="replace"), end="")
    raise SystemExit(run.returncode)
