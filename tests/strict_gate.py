"""Stop-on-first-failure, source-level Windows headset acceptance gate.

This intentionally changes only the exact target through the app's KS path.
It never installs, deploys, publishes, resets the adapter or alters pairing.
"""
from pathlib import Path
import argparse
import json
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / 'verification/2026-09-26-final/strict-gate'


def parse_inspect(output, address, render):
    link = None
    state = None
    defaults = {0: {}, 1: {}}
    for line in output.splitlines():
        if line.startswith('BLUETOOTH ') and line.endswith('address=' + address):
            match = re.search(r'connected=([01]) address=', line)
            if match:
                if link is not None:
                    raise ValueError('exact target appears more than once')
                link = int(match.group(1))
        match = re.match(r'BEFORE 0 state=(\d+) .* (\{0\.0\.0\.00000000\}\.\{[0-9a-fA-F-]{36}\})$', line)
        if match and match.group(2).lower() == render.lower():
            if state is not None:
                raise ValueError('exact target render appears more than once')
            state = int(match.group(1))
        match = re.match(r'DEFAULT ([01])/([012]) (\S+)$', line)
        if match:
            defaults[int(match.group(1))][int(match.group(2))] = match.group(3)
    if link is None or state is None or any(len(defaults[f]) != 3 for f in (0, 1)):
        raise ValueError('inspect output missing exact link, render or default roles')
    return {'link': link, 'renderState': state,
            'outputRoles': [defaults[0][i] for i in range(3)],
            'micRoles': [defaults[1][i] for i in range(3)]}


def self_test():
    example = ('BLUETOOTH X connected=1 address=AABBCCDDEEFF\n'
               'BEFORE 0 state=1 X {0.0.0.00000000}.{11111111-1111-1111-1111-111111111111}\n'
               + ''.join(f'DEFAULT 0/{i} target\nDEFAULT 1/{i} original\n' for i in range(3)))
    row = parse_inspect(example, 'AABBCCDDEEFF',
                        '{0.0.0.00000000}.{11111111-1111-1111-1111-111111111111}')
    assert row['link'] == row['renderState'] == 1
    assert row['outputRoles'] == ['target'] * 3 and row['micRoles'] == ['original'] * 3
    print('PASS strict_gate_parser_exact_target_and_roles')
    print('RESULT failures=0 tests=1')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--address')
    parser.add_argument('--settings', type=Path)
    parser.add_argument('--cycles', type=int, default=5)
    parser.add_argument('--dwell', type=int, default=15)
    parser.add_argument('--output', type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    address = (args.address or '').upper()
    if not re.fullmatch(r'[0-9A-F]{12}', address):
        parser.error('exact target address required')
    if not 1 <= args.cycles <= 5 or not 0 <= args.dwell <= 30:
        parser.error('bounded cycles/dwell required')
    settings = args.settings.resolve() if args.settings else None
    if not settings or not settings.is_file() or ROOT not in settings.parents:
        parser.error('existing repository-local settings fixture required')
    prefs = dict(line.split('=', 1) for line in settings.read_text(encoding='utf-8-sig').splitlines() if '=' in line)
    if prefs.get('auto_mic_switch') != '0' or prefs.get('mic_restore_pending', '0') != '0':
        parser.error('strict gate fixture must disable automatic microphone switching and migration')
    out = args.output.resolve()
    if ROOT not in out.parents:
        parser.error('output must remain inside repository')
    out.mkdir(parents=True, exist_ok=True)
    probe_command = ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command',
                     "Import-Module './scripts/KsBluetooth.psm1' -Force; "
                     f"Get-KsBluetoothProbe '{address}' | ConvertTo-Json -Depth 8 -Compress"]
    probe = subprocess.run(probe_command, cwd=ROOT, capture_output=True, timeout=30)
    if probe.returncode:
        raise RuntimeError(probe.stderr.decode('utf-8-sig', errors='replace'))
    data = json.loads(probe.stdout.decode('utf-8-sig', errors='replace'))
    render = [row['Id'] for row in data['endpoints'] if row['Flow'] == 0
              and row['State'] in (1, 8) and 'BTHHFENUM' not in (row.get('FilterId') or '').upper()]
    if len(render) != 1:
        raise RuntimeError('target stereo render not unique')
    render = render[0]
    records = []

    def run(cycle, phase, mode):
        command = ['python', 'tests/live_audio.py', mode, address, str(settings)]
        started = time.monotonic()
        p = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=115)
        text = (p.stdout + p.stderr).decode('utf-8-sig', errors='replace')
        (out / f'{cycle}-{phase}.txt').write_text(text, encoding='utf-8')
        record = {'cycle': cycle, 'phase': phase, 'command': command, 'exit': p.returncode,
                  'seconds': round(time.monotonic() - started, 2), 'file': f'{cycle}-{phase}.txt'}
        if mode == 'inspect' and p.returncode == 0:
            record.update(parse_inspect(text, address, render))
        records.append(record)
        (out / 'results.json').write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding='utf-8')
        print(f'{cycle}-{phase} exit={p.returncode} seconds={record["seconds"]}'
              + (f' link={record["link"]} render={record["renderState"]}' if mode == 'inspect' and p.returncode == 0 else ''), flush=True)
        if p.returncode:
            raise RuntimeError(f'{cycle}-{phase} source action failed with exit {p.returncode}')
        return record

    def check(row, link, state, target_roles, mic_roles):
        if row['link'] != link or row['renderState'] != state:
            raise RuntimeError(f'{row["cycle"]}-{row["phase"]}: link/render mismatch')
        if target_roles and [v.lower() for v in row['outputRoles']] != [render.lower()] * 3:
            raise RuntimeError(f'{row["cycle"]}-{row["phase"]}: three output roles did not hold target')
        if not target_roles and any(v.lower() == render.lower() for v in row['outputRoles']):
            raise RuntimeError(f'{row["cycle"]}-{row["phase"]}: disconnected output still targets headset')
        if row['micRoles'] != mic_roles:
            raise RuntimeError(f'{row["cycle"]}-{row["phase"]}: microphone defaults changed despite micOff')

    baseline = run(0, 'baseline', 'inspect')
    check(baseline, 1, 1, True, baseline['micRoles'])
    try:
        for cycle in range(1, args.cycles + 1):
            run(cycle, 'disconnect', 'disconnect')
            check(run(cycle, 'after-disconnect', 'inspect'), 0, 8, False, baseline['micRoles'])
            time.sleep(args.dwell)
            check(run(cycle, 'delayed-disconnect', 'inspect'), 0, 8, False, baseline['micRoles'])
            run(cycle, 'connect', 'connect')
            check(run(cycle, 'after-connect', 'inspect'), 1, 1, True, baseline['micRoles'])
            time.sleep(args.dwell)
            check(run(cycle, 'delayed-connect', 'inspect'), 1, 1, True, baseline['micRoles'])
    except Exception as exc:
        (out / 'failure.txt').write_text(str(exc), encoding='utf-8')
        print('GATE_FAIL', exc)
        raise SystemExit(5)
    print(f'GATE_PASS cycles={args.cycles} dwell={args.dwell}')


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    main()
