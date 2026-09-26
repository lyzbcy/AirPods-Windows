"""Run offline regressions; this runner never connects devices or deploys the app."""
from pathlib import Path
import argparse, json, os, subprocess, sys

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, default=root/'verification/2026-09-26-ks/offline')
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
sys.stdout.reconfigure(encoding='utf-8')
env = {k: v for k, v in os.environ.items() if k.lower() != 'psmodulepath'}
commands = [
    ('behavior', ['python', 'tests/run_behavior.py', 'airpods_buddy.ahk']),
    ('state', ['python', 'tests/run_state_tests.py']),
    ('resource_identity', ['python', 'tests/resource_identity_test.py']),
    ('ks_retry', ['python', 'tests/ks_retry_behavior.py']),
    ('p0_timeline', ['python', 'tests/p0_timeline.py', '--self-test']),
    ('target_endpoint', ['python', 'tests/target_endpoint_test.py']),
    ('audio', ['python', 'tests/run_ahk.py', 'tests/audio_routing_test.ahk']),
    ('background', ['python', 'tests/run_ahk.py', 'tests/background_job_test.ahk']),
    ('rpc', ['node', 'tests/rpc_test.cjs']),
]
for name, script in [('windows','windows_regression.ps1'), ('update_health','update_health_test.ps1'), ('ks_backend','ks_backend_test.ps1')]:
    commands.append((name, ['powershell','-NoProfile','-ExecutionPolicy','Bypass','-File','tests/'+script]))
records = []
for name, command in commands:
    p = subprocess.run(command, cwd=root, env=env, capture_output=True, timeout=120)
    output = (p.stdout+p.stderr).decode('utf-8-sig', errors='replace')
    (args.output/(name+'.txt')).write_text(output, encoding='utf-8')
    record = {'name':name, 'command':subprocess.list2cmdline(command), 'input':command[-1], 'exit':p.returncode,
              'passes':sum(line.startswith('PASS ') for line in output.splitlines()), 'output':output}
    records.append(record)
    (args.output/'results.json').write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding='utf-8')
    print(name, 'PASS='+str(record['passes']), 'EXIT='+str(p.returncode), flush=True)
    if p.returncode:
        print(output)
        raise SystemExit(p.returncode)
print('OFFLINE_PASS assertions='+str(sum(r['passes'] for r in records))+' suites='+str(len(records)))
