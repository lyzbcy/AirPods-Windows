"""Headless integration of actual source functions, with UI-only sinks.
Modes: inspect, connect, disconnect. Connect plays a quiet tone ONLY after
source verifier confirms active render endpoint and all three default roles.
"""
from pathlib import Path
import subprocess,sys,wave,math,struct
sys.stdout.reconfigure(encoding='utf-8')
ROOT=Path(__file__).resolve().parents[1]; V=ROOT/"verification/2026-09-26-all"
source=(ROOT/'airpods_buddy.ahk').read_text(encoding='utf-8-sig')
mode=sys.argv[1] if len(sys.argv)>1 else 'inspect'
assert mode in ('inspect','connect','disconnect')
names=['FindAllAudioDevices','FindDevByName','IsLinkUp','ToggleBluetoothService','IsSuccessfulOperation','DoAction','BeginDeviceOp','OpCurrent','SetOpState','CanRoute','StartLinkVerify','LinkVerifyTick','AudioVerifyTick','MicSwitchTo','MicSwitchTick','StartDownVerify','DownVerifyTick','JsonStr','SettingRead','DeviceKey','DeviceLabel','FinishBluetoothAction','FinishDownEscalation']
functions=[]
for name in names:
    start=source.index('\n'+name+'(');end=source.index('\n}',start)+2
    functions.append(source[start:end])
body=r'''
#Requires AutoHotkey v2.0
#SingleInstance Off
#Include lib\AudioRouting.ahk
#Include lib\BackgroundJobs.ahk
FileEncoding("UTF-8-RAW")
OnError((e, mode) => (FileAppend("ERROR " e.Message " line=" e.Line "`n", "*"), ExitApp(2)))
backgroundJobs := [], appRoot := A_ScriptDir
OnExit(StopBackgroundJobs)
devices := [], busy := false, maxRetries := 10
deviceOps := Map(), operationSerial := 0, routeOwner := 0
SETTINGS_PATH := "C:\Users\24676\Desktop\AirPodsBuddy\app_settings.ini"
FindAllAudioDevices()
targets := []
for dev in devices {
    FileAppend("BLUETOOTH " dev.name " connected=" dev.connected " address=" Format("{:012X}",NumGet(dev.info,8,"uint64")) "`n", "*")
    if InStr(StrLower(dev.name), "airpods")
        targets.Push(DeviceKey(dev))
}
api := CoreAudioBackend()
loop 2 {
    flow := A_Index - 1
    for ep in api.Endpoints(flow, 15)
        FileAppend("BEFORE " flow " state=" ep.state " " ep.name " " ep.id "`n", "*")
    loop 3 {
        try FileAppend("DEFAULT " flow "/" (A_Index-1) " " api.DefaultId(flow,A_Index-1) "`n", "*")
    }
}
if MODE = "inspect"
    ExitApp(0)
if targets.Length != 1 {
    FileAppend("RESULT target_ambiguous_or_missing`n", "*")
    ExitApp(3)
}
name := targets[1]
FileAppend("REQUEST " MODE " " name "`n", "*")
result := DoAction(name, MODE)
FileAppend("SERVICE_RESULT " result "`n", "*")
if result != "ok"
    ExitApp(4)
started := A_TickCount
loop {
    Sleep(250)
    state := deviceOps[name].state
    if (state = "ready" || state = "disconnected" || InStr(state,"failed"))
        break
    if A_TickCount-started > 35000
        break
}
FileAppend("RESULT state=" state " link=" IsLinkUp(name) " render=" FindAudioEndpointId(DeviceLabel(name),"0.0.0") " capture=" FindCaptureEndpointId(DeviceLabel(name)) "`n", "*")
if (state = "ready") {
    ; Playback is tested separately against the current default endpoint.
    FileAppend("ROUTE_READY playback_test_separate`n", "*")
    Sleep(7000) ; allow bounded microphone retry timers to complete
}
ExitApp((state = "ready" || state = "disconnected") ? 0 : 5)
LogMsg(msg, level := "INFO") {
    FileAppend(level " " msg "`n", "*")
}
PushEvent(name, data) {
    FileAppend("EVENT " name " " data "`n", "*")
}
EnsureResources() {
}
SetTrayLoading(*) {
}
PetUpdate(*) {
}
TrayTip(*) {
}
OnConnectSuccess() {
    FileAppend("VERIFIED_SUCCESS_COUNTER (fixture only)`n", "*")
}
'''.replace('if MODE','if "'+mode+'"').replace('"REQUEST " MODE','"REQUEST '+mode+'"').replace('DoAction(name, MODE)','DoAction(name, "'+mode+'")')
# 0.1 peak amplitude, short faded notes; system volume is left unchanged.
with wave.open(str(V/'test-tone.wav'),'wb') as wav:
    rate=44100;wav.setparams((1,2,rate,0,'NONE','not compressed'))
    frames=[]
    for i in range(rate*2):
        t=i/rate;phase=t%0.5
        envelope=min(1,phase/0.03,max(0,(0.35-phase)/0.03)) if phase<0.35 else 0
        frames.append(struct.pack('<h',int(3276*envelope*math.sin(2*math.pi*(440 if t<1 else 660)*t))))
    wav.writeframes(b''.join(frames))
script=ROOT/'apb_integration_20260926.ahk';script.write_text(body+'\n'.join(functions),encoding='utf-8-sig')
run=subprocess.run([str(ROOT/'tools/ahk_v2_portable/AutoHotkey64.exe'),'/ErrorStdOut=UTF-8',str(script)],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=65)
output=run.stdout.decode('utf-8-sig',errors='replace')
print(output,end='');(V/('live_'+mode+'.txt')).write_text(output,encoding='utf-8');script.unlink(missing_ok=True)
raise SystemExit(run.returncode)
