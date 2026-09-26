"""Offline closure check for functions copied into the live-audio harness."""
import ast
from pathlib import Path
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")
root = Path(__file__).resolve().parents[1]
harness_path = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "tests/live_audio.py"
harness = ast.parse(harness_path.read_text(encoding="utf-8"))
names = next(
    ast.literal_eval(node.value)
    for node in harness.body
    if isinstance(node, ast.Assign)
    and any(isinstance(target, ast.Name) and target.id == "names" for target in node.targets)
)
source = (root / "airpods_buddy.ahk").read_text(encoding="utf-8-sig")


def body(name):
    start = source.index("\n" + name + "(")
    end = source.index("\n}", start) + 2
    return source[start:end]


failures = 0
for caller, callee in (("FindAllAudioDevices", "IsAudioCandidate"),
                       ("IsAudioCandidate", "IsAppleDevice")):
    referenced = re.search(r"\b" + callee + r"\s*\(", body(caller)) is not None
    extracted = callee in names
    ok = referenced and extracted
    print(("PASS " if ok else "FAIL ") + f"{caller}_includes_{callee}")
    failures += not ok
print(f"RESULT failures={failures}")
raise SystemExit(1 if failures else 0)
