"""Read-only, same-clock Windows link/endpoint/default-route sampler.

Use --action cycle for one bounded disconnect/connect source-app contrast.
No adapter, pairing, PnP, service, audio-default or event-channel mutation.
"""
from pathlib import Path
import argparse
import json
import re
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/2026-09-26-timeline'
SOURCE = ROOT / 'airpods_buddy.ahk'
AHK = ROOT / 'tools/ahk_v2_portable/AutoHotkey64.exe'
ADDRESS = re.compile(r'^[0-9A-F]{12}$')
ENDPOINT = re.compile(r'^\{0\.0\.0\.00000000\}\.\{[0-9a-fA-F-]{36}\}$')


def source_function(name):
    source = SOURCE.read_text(encoding='utf-8-sig')
    start = source.index('\n' + name + '(')
    end = source.index('\n}', start) + 2
    return source[start:end]


BODY = r'''#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include lib\AudioRouting.ahk
FileEncoding("UTF-8-RAW")
OnError((e, mode) => (FileAppend("ERROR`t" e.Message "`n", "*"), ExitApp(2)))
address := A_Args[1], targetId := A_Args[2], samples := Integer(A_Args[3])
api := CoreAudioBackend()
Loop samples {
    stamp := Buffer(8, 0)
    DllCall("kernel32\GetSystemTimePreciseAsFileTime", "ptr", stamp)
    utcFiletime := NumGet(stamp, 0, "int64")
    step := A_TickCount
    link := GetLinkState(address)
    linkMs := A_TickCount - step
    state := -1
    step := A_TickCount
    try {
        for ep in api.Endpoints(0, 15)
            if (StrLower(ep.id) = StrLower(targetId))
                state := ep.state
    } catch as e {
        state := -2
    }
    endpointMs := A_TickCount - step
    roles := []
    step := A_TickCount
    Loop 3 {
        try roles.Push(api.DefaultId(0, A_Index - 1))
        catch {
            roles.Push("UNAVAILABLE")
        }
    }
    defaultMs := A_TickCount - step
    FileAppend("SAMPLE`t" utcFiletime "`t" A_TickCount "`t" link "`t" state "`t" roles[1] "`t" roles[2] "`t" roles[3] "`t" linkMs "`t" endpointMs "`t" defaultMs "`n", "*")
    if (A_Index < samples)
        Sleep(500)
}
ExitApp(0)
LogMsg(msg, level := "INFO") {
    FileAppend("LOG`t" level "`t" msg "`n", "*")
}
'''


def parse_samples(output):
    rows = []
    for line in output.splitlines():
        if not line.startswith('SAMPLE\t'):
            continue
        cols = line.split('\t')
        if len(cols) != 11:
            raise ValueError('Malformed sample: ' + line)
        rows.append(dict(utcFiletime=int(cols[1]), tick=int(cols[2]),
                         link=int(cols[3]), endpointState=int(cols[4]),
                         defaultRoles=cols[5:8], linkMs=int(cols[8]),
                         endpointMs=int(cols[9]), defaultMs=int(cols[10])))
    return rows


def write_heartbeat(path, stop, interval=0.5):
    """Independent process heartbeat: distinguish sampler stalls from host pauses."""
    with path.open('w', encoding='ascii') as out:
        while not stop.is_set():
            out.write(f'{time.time_ns()}\t{time.monotonic_ns()}\n')
            out.flush()
            stop.wait(interval)


def max_heartbeat_gap_ms(path):
    ticks = [int(line.split('\t')[1]) for line in path.read_text(encoding='ascii').splitlines()]
    return max(((ticks[i] - ticks[i - 1]) // 1_000_000 for i in range(1, len(ticks))), default=0)


def self_test():
    rows = parse_samples('SAMPLE\t134349076453976566\t10\t0\t8\tA\tB\tC\t2\t3\t4\n')
    assert rows == [{'utcFiletime': 134349076453976566, 'tick': 10,
                     'link': 0, 'endpointState': 8, 'defaultRoles': ['A', 'B', 'C'],
                     'linkMs': 2, 'endpointMs': 3, 'defaultMs': 4}]
    assert 'BluetoothFindFirstDevice' in source_function('GetLinkState')
    assert 'GetSystemTimePreciseAsFileTime' in BODY
    assert not any(word in BODY for word in ('SetDefault(', 'BluetoothSetServiceState',
                                              'BluetoothRemoveDevice', 'Set-PnpDevice'))
    assert 'raise SystemExit(actions[-1][1].returncode)' in Path(__file__).read_text(encoding='utf-8')
    with tempfile.TemporaryDirectory() as folder:
        stop = threading.Event()
        path = Path(folder) / 'heartbeat.tsv'
        thread = threading.Thread(target=write_heartbeat, args=(path, stop, 0.01))
        thread.start()
        time.sleep(0.035)
        stop.set()
        thread.join()
        assert len(path.read_text(encoding='ascii').splitlines()) >= 2
        assert max_heartbeat_gap_ms(path) >= 0
    print('PASS timeline_parser_and_read_only_sampler')
    print('RESULT failures=0 tests=1')


def powershell_json(script):
    p = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
                       cwd=ROOT, capture_output=True, timeout=25)
    if p.returncode:
        raise RuntimeError((p.stderr or p.stdout).decode('utf-8-sig', errors='replace'))
    return json.loads(p.stdout.decode('utf-8-sig', errors='replace'))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--address')
    parser.add_argument('--seconds', type=int, default=15)
    parser.add_argument('--action', choices=['none', 'connect', 'cycle'], default='none')
    parser.add_argument('--single-request', action='store_true',
                        help='diagnostic connect uses one KS request and suppresses delayed retry')
    parser.add_argument('--settings', type=Path,
                        help='optional repository-local settings fixture for source action')
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    address = (args.address or '').upper()
    if not ADDRESS.fullmatch(address) or not 1 <= args.seconds <= 120:
        parser.error('exact 12-digit address and 1..120 seconds required')
    if args.single_request and args.action == 'none':
        parser.error('single-request requires a connect or cycle action')
    settings = args.settings.resolve() if args.settings else None
    if settings and (not settings.is_file() or ROOT not in settings.parents):
        parser.error('settings fixture must be an existing file inside the repository')
    if args.single_request and not settings:
        parser.error('single-request requires an isolated settings fixture')
    OUT.mkdir(parents=True, exist_ok=True)
    probe = powershell_json("Import-Module './scripts/KsBluetooth.psm1' -Force; "
                            f"Get-KsBluetoothProbe '{address}' | ConvertTo-Json -Depth 8 -Compress")
    render = [e for e in probe['endpoints'] if e['Flow'] == 0 and e['State'] in (1, 8)
              and 'BTHHFENUM' not in (e.get('FilterId') or '').upper()]
    if len(render) != 1 or not ENDPOINT.fullmatch(render[0]['Id']):
        raise RuntimeError('exact target render endpoint not unique')
    target = render[0]['Id']
    (OUT / 'probe.json').write_text(json.dumps(probe, ensure_ascii=False, indent=2), encoding='utf-8')
    samples = args.seconds * 2
    script = BODY + source_function('GetLinkState') + '\n'
    with tempfile.NamedTemporaryFile(mode='w', suffix='.ahk', prefix='apb_timeline_',
                                     dir=ROOT, encoding='utf-8-sig', delete=False) as f:
        f.write(script)
        temp = Path(f.name)
    observer = None
    actions = []
    heartbeat_stop = threading.Event()
    heartbeat_path = OUT / 'heartbeat.tsv'
    heartbeat = threading.Thread(target=write_heartbeat, args=(heartbeat_path, heartbeat_stop), daemon=True)
    try:
        heartbeat.start()
        observer = subprocess.Popen([str(AHK), '/ErrorStdOut=UTF-8', str(temp), address,
                                     target, str(samples)], cwd=ROOT,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if args.action != 'none':
            time.sleep(1)
            modes = ['disconnect', 'connect'] if args.action == 'cycle' else ['connect']
            for mode in modes:
                command = ['python', 'tests/live_audio.py', mode, address]
                if settings:
                    command += [str(settings)]
                if mode == 'connect' and args.single_request:
                    command += ['--single-request']
                action = subprocess.run(command,
                                        cwd=ROOT, capture_output=True, timeout=100)
                (OUT / ('single-' + mode + '.txt')).write_bytes(action.stdout + action.stderr)
                actions.append((mode, action))
                if action.returncode:
                    break
        raw, _ = observer.communicate(timeout=args.seconds + 15)
        heartbeat_stop.set()
        heartbeat.join(timeout=2)
        output = raw.decode('utf-8-sig', errors='replace')
        (OUT / 'timeline-raw.txt').write_text(output, encoding='utf-8')
        rows = parse_samples(output)
        if observer.returncode or len(rows) != samples:
            raise RuntimeError('sampler failed: exit=' + str(observer.returncode) + ' samples=' +
                               str(len(rows)) + '/' + str(samples) + '\n' + output[-1200:])
        (OUT / 'timeline.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding='utf-8')
        # Snapshot exact target PnP node and native events; disabled channels remain untouched.
        events = powershell_json("$ErrorActionPreference='Stop'; $addr='"+address+"'; "
            "$node=@(Get-PnpDevice -Class Bluetooth | Where-Object {$_.InstanceId.StartsWith(('BTHENUM\\DEV_'+$addr+'\\'),[StringComparison]::OrdinalIgnoreCase)}); "
            "$since=(Get-Date).AddMinutes(-4); "
            "$ev=@(Get-WinEvent -FilterHashtable @{LogName='System';StartTime=$since} -ErrorAction SilentlyContinue | "
            "Where-Object ProviderName -Match 'BTH|Bluetooth|Audio' | "
            "Select-Object TimeCreated,ProviderName,Id,LevelDisplayName,Message); "
            "@{nodes=@($node | Select-Object InstanceId,Status,Class);events=$ev;"
            "eventCount=$ev.Count} | ConvertTo-Json -Depth 5 -Compress")
        (OUT / 'pnp-events.json').write_text(json.dumps(events, ensure_ascii=False, indent=2), encoding='utf-8')
        print(f'RESULT samples={len(rows)} target={target} action={args.action} '
              f'actionExit={actions[-1][1].returncode if actions else "NA"} '
              f'lastLink={rows[-1]["link"]} lastEndpointState={rows[-1]["endpointState"]} '
              f'events={events["eventCount"]} '
              f'maxGapMs={max((rows[i]["utcFiletime"]-rows[i-1]["utcFiletime"])//10000 for i in range(1,len(rows))) if len(rows)>1 else 0} '
              f'maxLinkMs={max(r["linkMs"] for r in rows)} '
              f'maxEndpointMs={max(r["endpointMs"] for r in rows)} '
              f'maxDefaultMs={max(r["defaultMs"] for r in rows)} '
              f'maxHeartbeatGapMs={max_heartbeat_gap_ms(heartbeat_path)}')
        for mode, action in actions:
            print('ACTION_RESULT', mode, *(line for line in action.stdout.decode('utf-8-sig', errors='replace').splitlines()
                                           if line.startswith('RESULT state=')), sep=' ')
        if actions and actions[-1][1].returncode:
            raise SystemExit(actions[-1][1].returncode)
    finally:
        heartbeat_stop.set()
        if heartbeat.is_alive():
            heartbeat.join(timeout=2)
        if observer is not None and observer.poll() is None:
            observer.kill()
            observer.communicate(timeout=5)
        temp.unlink(missing_ok=True)


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    main()
