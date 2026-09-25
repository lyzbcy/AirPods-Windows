import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8-sig")
action = source.split("DoAction(name, action) {", 1)[1].split("\n}", 1)[0]
pet = source.split("\nPetEnsure() {", 1)[1].split("\n}", 1)[0]
autostart = source.split("AutostartRepair() {", 1)[1].split("\n}", 1)[0] if "AutostartRepair() {" in source else ""
tests = {
    "disconnect micWanted initialized": action.index('micWanted :=') < action.index('if (action = "connect")') if 'micWanted :=' in action else False,
    "pet resource restored on demand": 'FileInstall "webui\\pet_built.html", p, 1' in pet,
    "deleted Run entry repaired after explicit opt-in": 'preference := SettingRead("autostart", "")' in autostart and 'if (preference != "1")' in autostart and 'RegWrite(exe, "REG_SZ"' in autostart,
    "stale Run path and disabled state checked": 'observed := RegRead("HKCU\\" RUN_KEY, RUN_NAME)' in autostart and 'if (observed = exe)' in autostart and 'state := AutostartEnabled()' in autostart and 'StrUpper(SubStr(bin, 2, 1))' in source,
    "startup repair precedes network update": 'AutostartRepair()   ; startup must check before a network-bound update timer can block' in source,
}
for name, ok in tests.items():
    print(f"{'PASS' if ok else 'FAIL'} {name}")
sys.exit(0 if all(tests.values()) else 1)
