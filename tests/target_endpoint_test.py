"""Fault injection for exact target endpoint post-disconnect verification."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'airpods_buddy.ahk').read_text(encoding='utf-8-sig')


def function(name):
    start = source.index('\n' + name + '(')
    end = source.index('\n}', start) + 2
    return source[start:end]


body = r'''#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
OnError((e, mode) => (FileAppend("ERROR " e.Message " line=" e.Line "`n", "*"), ExitApp(2)))
failures := 0
render := "{0.0.0.00000000}.{11111111-1111-1111-1111-111111111111}"
capture := "{0.0.1.00000000}.{22222222-2222-2222-2222-222222222222}"
spec := "0|" render ";1|" capture
api := FakeEndpoints(render, capture)
Check("inactive_render_and_capture_verified", TargetEndpointsInactive(spec, api))
api.renderState := 1
Check("active_render_rejected", !TargetEndpointsInactive(spec, api))
api.renderState := 8, api.captureState := 1
Check("active_capture_rejected", !TargetEndpointsInactive(spec, api))
api.captureState := 8, api.missing := true
Check("missing_id_is_not_verified", !TargetEndpointsInactive(spec, api))
Check("invalid_id_is_not_verified", !TargetEndpointsInactive("0|SWD\MMDEVAPI", api))
Check("empty_id_list_is_not_verified", !TargetEndpointsInactive("", api))
FileAppend("RESULT failures=" failures "`n", "*")
ExitApp(failures ? 1 : 0)
Check(name, ok) {
    global failures
    if !ok
        failures++
    FileAppend((ok ? "PASS " : "FAIL ") name "`n", "*")
}
class FakeEndpoints {
    __New(render, capture) {
        this.render := render, this.capture := capture
        this.renderState := 8, this.captureState := 8, this.missing := false
    }
    Endpoints(flow, states := 1) {
        if flow = 0
            return [{id: this.render, state: this.renderState}]
        return this.missing ? [] : [{id: this.capture, state: this.captureState}]
    }
}
'''
body += function('ValidEndpointId') + function('TargetEndpointsInactive')
with tempfile.TemporaryDirectory(prefix='apb_endpoint_') as directory:
    script = Path(directory) / 'endpoint_test.ahk'
    script.write_text(body, encoding='utf-8-sig')
    run = subprocess.run([str(ROOT / 'tools/ahk_v2_portable/AutoHotkey64.exe'),
                          '/ErrorStdOut=UTF-8', str(script)], capture_output=True, timeout=15)
    print((run.stdout + run.stderr).decode('utf-8-sig', errors='replace'), end='')
    raise SystemExit(run.returncode)
