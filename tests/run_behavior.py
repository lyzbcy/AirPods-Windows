"""Execute actual application functions headlessly with injected device/UI fakes.
No GUI, radio changes, default-device changes, or production settings writes.
"""
from pathlib import Path
import argparse, subprocess
import sys
sys.stdout.reconfigure(encoding='utf-8')

ROOT = Path(__file__).resolve().parents[1]
V = ROOT / "verification/2026-09-26-all"
V.mkdir(parents=True,exist_ok=True)
parser = argparse.ArgumentParser()
parser.add_argument('source', type=Path)
args = parser.parse_args()
source = args.source.read_text(encoding='utf-8-sig')
def function(name):
    start = source.find('\n' + name + '(')
    if start < 0:
        return ''
    end = source.index('\n}', start) + 2
    return source[start:end] + '\n'

body = r'''
#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
OnError((e, mode) => (FileAppend("ERROR " e.Message " line=" e.Line "`n", "*"), ExitApp(2)))
failures := 0
events := [], petStates := [], successCount := 0
audioVerifyGen := 1, endpointFailStreak := 0, linkFailStreak := 0, btRescueDone := true
deviceOps := Map(), operationSerial := 0, routeOwner := "", actionEpoch := 0
routeWorks := false
gen := BeginDeviceOp("Test", "connect")
deviceOps["Test"].renderId := "{0.0.0.00000000}.{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}"
AudioVerifyTick("Test", 1, gen)
announced := false
for ev in events
    if (ev.name = "audiook" || InStr(ev.data, "音频已切到电脑"))
        announced := true
Check("failed_route_never_announces_audio_success", !announced)
events := [], petStates := [], successCount := 0
gen := BeginDeviceOp("Test", "connect")
LinkVerifyTick("Test", 8, gen)
Check("link_only_does_not_increment_success", successCount = 0)
petOk := false
for state in petStates
    if (state = "ok")
        petOk := true
Check("link_only_does_not_show_pet_success", !petOk)
Check("control_char_json_escaped", JsonStr("a`rb`t" Chr(1)) = '"a\u000Db\u0009\u0001"')
before := events.Length
AudioVerifyTick("Test", 1, gen - 1)
Check("stale_audio_callback_is_ignored", events.Length = before)
FileAppend("RESULT failures=" failures "`n", "*")
ExitApp(failures ? 1 : 0)
Check(name, condition) {
    global failures
    if !condition
        failures++
    FileAppend((condition ? "PASS " : "FAIL ") name "`n", "*")
}
DeviceLabel(name) {
    return name
}
LogMsg(*) {
}
RenderSwitchToId(id) {
    global routeWorks
    return routeWorks && id = "{0.0.0.00000000}.{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}"
}
MicSwitchTo(*) {
}
PushEvent(name, data) {
    global events
    events.Push({name: name, data: data})
}
PetUpdate(state) {
    global petStates
    petStates.Push(state)
}
TrayTip(*) {
}
OnConnectSuccess() {
    global successCount
    successCount++
}
IsLinkUp(*) {
    return true
}
ScheduleKsConnectRetry(*) {
    return false
}
IsAppleDevice(*) {
    return false
}
BtRadioRescue(*) {
    return false
}
BtRescueGiveUpTip(*) {
}
'''
for name in ['AudioVerifyTick', 'LinkVerifyTick', 'JsonStr', 'BeginDeviceOp', 'OpCurrent', 'SetOpState', 'CanRoute']:
    body += function(name)
if function('BeginDeviceOp'):
    extra = '''
ga := BeginDeviceOp("A", "disconnect")
gb := BeginDeviceOp("B", "disconnect")
Check("bulk_disconnect_keeps_both_tasks", OpCurrent("A",ga) && OpCurrent("B",gb))
ga2 := BeginDeviceOp("A", "connect")
Check("same_device_invalidates_old_callback", !OpCurrent("A",ga) && OpCurrent("A",ga2))
gb2 := BeginDeviceOp("B", "connect")
Check("latest_connect_owns_audio_route", !CanRoute("A",ga2) && CanRoute("B",gb2))
BeginDeviceOp("B", "disconnect")
Check("disconnect_cancels_mic_retry", !CanRoute("B",gb2))
'''
    body = body.replace('FileAppend("RESULT failures="', extra+'\nFileAppend("RESULT failures="', 1)
if not function('BeginDeviceOp'):
    body += '\nBeginDeviceOp(*) {\n global audioVerifyGen\n return ++audioVerifyGen\n}\n'
script = V / ('behavior_' + args.source.stem + '.ahk')
script.write_text(body, encoding='utf-8-sig')
run = subprocess.run([str(ROOT/'tools/ahk_v2_portable/AutoHotkey64.exe'), '/ErrorStdOut=UTF-8', str(script)], capture_output=True, timeout=15)
output = run.stdout.decode('utf-8-sig', errors='replace') + run.stderr.decode('utf-8-sig', errors='replace')
print(output, end='')
(V / ('behavior_' + args.source.stem + '.txt')).write_text(output, encoding='utf-8')
raise SystemExit(run.returncode)
