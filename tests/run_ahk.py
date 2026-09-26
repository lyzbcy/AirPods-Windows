"""Wait for GUI-subsystem AHK executables and propagate their real exit code."""
from pathlib import Path
import subprocess,sys
sys.stdout.reconfigure(encoding='utf-8')
root=Path(__file__).resolve().parents[1]
run=subprocess.run([str(root/'tools/ahk_v2_portable/AutoHotkey64.exe'),'/ErrorStdOut=UTF-8',*sys.argv[1:]],capture_output=True,timeout=60,cwd=root)
print((run.stdout+run.stderr).decode('utf-8-sig',errors='replace'),end='')
raise SystemExit(run.returncode)
