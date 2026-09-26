"""Headless integration of source functions with UI-only sinks.
Modes: inspect, connect, disconnect. Playback is tested separately.
"""
from pathlib import Path
import re, subprocess, sys
sys.stdout.reconfigure(encoding='utf-8')
ROOT=Path(__file__).resolve().parents[1]; V=ROOT/"verification/2026-09-26-ks"
V.mkdir(parents=True, exist_ok=True)
source=(ROOT/'airpods_buddy.ahk').read_text(encoding='utf-8-sig')
mode=sys.argv[1] if len(sys.argv)>1 else 'inspect'
assert mode in ('inspect','connect','disconnect')
target_address=sys.argv[2].upper() if len(sys.argv)>2 else ''
if target_address and not re.fullmatch(r'[0-9A-F]{12}', target_address):
    raise SystemExit('target address must be 12 hexadecimal digits')
names=['FindAllAudioDevices','FindDevByName','IsLinkUp','GetLinkState','TargetEndpointsInactive','DoAction','BeginDeviceOp','OpCurrent','SetOpState','CanRoute','StartLinkVerify','LinkVerifyTick','ScheduleKsConnectRetry','TryKsConnectRetry','FinishKsConnectRetry','DrainRetryDisconnect','RunQueuedRetryDisconnect','AudioVerifyTick','MicSwitchTo','MicSwitchTick','StartDownVerify','DownVerifyTick','JsonStr','SettingRead','DeviceKey','DeviceLabel','FinishBluetoothAction','ValidEndpointId']
functions=[]
for name in names:
    start=source.index('\n'+name+'(');end=source.index('\n}',start)+2
    functions.append(source[start:end])
body=r'''
#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include lib\AudioRouting.ahk
#Include lib\BackgroundJobs.ahk
FileEncoding("UTF-8-RAW")
OnError((e, mode) => (FileAppend("ERROR " e.Message " line=" e.Line "`n", "*"), ExitApp(2)))
backgroundJobs := [], appRoot := A_ScriptDir
OnExit(StopBackgroundJobs)
devices := [], busy := false, maxRetries := 10
deviceOps := Map(), operationSerial := 0, routeOwner := 0, actionEpoch := 0, pendingRetryDisconnect := 0
SETTINGS_PATH := "C:\Users\24676\Desktop\AirPodsBuddy\app_settings.ini"
FindAllAudioDevices()
targets := []
targetAddress := A_Args.Length ? StrUpper(A_Args[1]) : ""
for dev in devices {
    address := Format("{:012X}",NumGet(dev.info,8,"uint64"))
    FileAppend("BLUETOOTH " dev.name " connected=" dev.connected " address=" address "`n", "*")
    if (targetAddress != "" ? address = targetAddress : InStr(StrLower(dev.name), "airpods"))
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
    if A_TickCount-started > 80000
        break
}
FileAppend("RESULT state=" state " link=" IsLinkUp(name) " render=" deviceOps[name].renderId " capture=" deviceOps[name].captureId "`n", "*")
if (state = "ready") {
    ; Playback is tested separately against the current default endpoint.
    FileAppend("ROUTE_READY playback_test_separate`n", "*")
    Sleep(7000) ; allow bounded microphone retry timers to complete
    if (!IsLinkUp(name) || !AudioRouteMatchesId(deviceOps[name].renderId)) {
        FileAppend("RESULT state=post_dwell_failed link=" IsLinkUp(name) " render=" deviceOps[name].renderId " capture=" deviceOps[name].captureId "`n", "*")
        ExitApp(5)
    }
    FileAppend("POST_DWELL_ROUTE_VERIFIED link=1 roles=0/1/2 active=1`n", "*")
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
script=ROOT/'apb_integration_20260926.ahk'
script.write_text(body+'\n'.join(functions),encoding='utf-8-sig')
proc=None
try:
    command=[str(ROOT/'tools/ahk_v2_portable/AutoHotkey64.exe'),'/ErrorStdOut=UTF-8',str(script)]
    if target_address:
        command.append(target_address)
    proc=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    try:
        raw,_=proc.communicate(timeout=100)
        code=proc.returncode
    except subprocess.TimeoutExpired:
        subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],capture_output=True,timeout=10)
        raw,_=proc.communicate(timeout=10)
        raw+=b'\nRESULT harness_timeout\n'
        code=124
    output=raw.decode('utf-8-sig',errors='replace')
    print(output,end='')
    (V/('live_'+mode+'.txt')).write_text(output,encoding='utf-8')
finally:
    if proc and proc.poll() is None:
        subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],capture_output=True,timeout=10)
        proc.communicate(timeout=10)
    script.unlink(missing_ok=True)
raise SystemExit(code)
