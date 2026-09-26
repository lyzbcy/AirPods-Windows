"""Offline fault injection for the manual Windows release precheck."""
from pathlib import Path
import hashlib
import importlib.util
import json
import subprocess
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/release-precheck.py'
spec = importlib.util.spec_from_file_location('release_precheck', SCRIPT)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)
passes = 0


def check(name, condition):
    global passes
    if not condition:
        raise AssertionError(name)
    passes += 1
    print('PASS', name)


def fails(callback):
    try:
        callback()
    except (ValueError, OSError, KeyError, zipfile.BadZipFile):
        return True
    return False


def sha(data):
    return hashlib.sha256(data).hexdigest().upper()


def fixture(folder):
    source = folder / 'airpods_buddy.ahk'
    source.write_text('APP_VERSION := "1.9.20"\n', encoding='utf-8')
    runtime = {}
    for name in guard.RUNTIME_INPUTS:
        path = folder / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if name != 'airpods_buddy.ahk':
            path.write_text('runtime fixture\n', encoding='utf-8')
        runtime[name] = sha(path.read_bytes())
    build = folder / 'build'
    build.mkdir()
    exe = b'MZ final candidate fixture'
    (build / 'AirPodsBuddy.exe').write_bytes(exe)
    (build / 'build-manifest.json').write_text(json.dumps({
        'source': sha(source.read_bytes()), 'sha256': sha(exe),
        'version': '1.9.20', 'inputs': runtime}), encoding='utf-8')
    archive = folder / 'AirPodsBuddy-Windows.zip'
    with zipfile.ZipFile(archive, 'w') as z:
        z.writestr('AirPodsBuddy.exe', exe)
    settings = folder / 'mic-off.ini'
    settings.write_text('auto_mic_switch=0\nmic_restore_pending=0\n', encoding='utf-8')
    gate = folder / 'gate'
    gate.mkdir()
    address = 'AABBCCDDEEFF'
    render = '{0.0.0.00000000}.{11111111-1111-1111-1111-111111111111}'
    mic = ['original'] * 3
    rows = []
    expected = [(0, 'baseline', 'inspect')]
    expected += [(cycle, phase, phase if phase in ('connect', 'disconnect') else 'inspect')
                 for cycle in range(1, 6) for phase in guard.PHASES]
    for cycle, phase, mode in expected:
        filename = f'{cycle}-{phase}.txt'
        command = ['python', 'tests/live_audio.py', mode, address, str(settings)]
        row = {'cycle': cycle, 'phase': phase, 'command': command, 'exit': 0, 'file': filename}
        if mode == 'connect':
            row['ksRequests'] = [1]
            (gate / filename).write_text('INFO bluetooth worker connect address=AABBCCDDEEFF requested=1 ksTrace=x\n', encoding='utf-8')
        else:
            (gate / filename).write_text('RESULT ok\n', encoding='utf-8')
        row['logSha256'] = sha((gate / filename).read_bytes())
        if mode == 'inspect':
            disconnected = phase in ('after-disconnect', 'delayed-disconnect')
            row.update({'link': 0 if disconnected else 1,
                        'renderState': 8 if disconnected else 1,
                        'outputRoles': ['other'] * 3 if disconnected else [render] * 3,
                        'micRoles': mic})
        rows.append(row)
    results = gate / 'results.json'
    results.write_text(json.dumps(rows), encoding='utf-8')
    proof = {'result': 'GATE_PASS', 'releaseGate': True, 'cycles': 5, 'dwell': 15,
             'productionPath': True, 'singleRequest': False, 'address': address, 'renderId': render,
             'settings': str(settings), 'settingsSha256': sha(settings.read_bytes()),
             'sourceSha256': sha(source.read_bytes()), 'runtimeInputs': runtime,
             'resultsSha256': sha(results.read_bytes())}
    (gate / 'gate-pass.json').write_text(json.dumps(proof), encoding='utf-8')
    receipt = folder / 'installed-acceptance.json'
    installed = folder / 'installed-AirPodsBuddy.exe'
    installed.write_bytes(exe)
    checks = {}
    for name in ('restartReconnect', 'defaultOutputListening', 'micOn'):
        evidence = f'{name}.txt'
        data = f'{name} fixture pass\n'.encode()
        (folder / evidence).write_bytes(data)
        checks[name] = {'passed': True, 'evidence': evidence, 'sha256': sha(data)}
    checks['defaultOutputListening']['userConfirmed'] = True
    checks['micOn']['autoMicSwitch'] = '1'
    receipt.write_text(json.dumps({'installedExePath': str(installed),
                                   'installedExeSha256': sha(exe),
                                   'gateResultsSha256': proof['resultsSha256'],
                                   'checks': checks}), encoding='utf-8')
    return source, build, archive, gate, receipt


with tempfile.TemporaryDirectory() as tmp:
    source, build, archive, gate, receipt_file = fixture(Path(tmp))
    package = guard.verify_package(build, archive, source)
    check('final_archive_matches_build_manifest_and_exe', package['exeSha256'] == sha((build / 'AirPodsBuddy.exe').read_bytes()))
    check('five_production_cycles_accepted', guard.verify_gate(gate, package)['cycles'] == 5)
    check('installed_restart_listening_micon_receipts_accepted',
          guard.verify_acceptance(receipt_file, package, guard.verify_gate(gate, package))['checks']['micOn']['passed'])

    receipt = json.loads(receipt_file.read_text(encoding='utf-8'))
    receipt['checks']['defaultOutputListening']['userConfirmed'] = False
    receipt_file.write_text(json.dumps(receipt), encoding='utf-8')
    check('missing_user_listening_confirmation_rejected',
          fails(lambda: guard.verify_acceptance(receipt_file, package, guard.verify_gate(gate, package))))
    receipt['checks']['defaultOutputListening']['userConfirmed'] = True
    receipt_file.write_text(json.dumps(receipt), encoding='utf-8')
    receipt['checks']['micOn']['autoMicSwitch'] = '0'
    receipt_file.write_text(json.dumps(receipt), encoding='utf-8')
    check('mic_off_only_acceptance_rejected',
          fails(lambda: guard.verify_acceptance(receipt_file, package, guard.verify_gate(gate, package))))
    receipt['checks']['micOn']['autoMicSwitch'] = '1'
    receipt_file.write_text(json.dumps(receipt), encoding='utf-8')

    proof_file = gate / 'gate-pass.json'
    proof = json.loads(proof_file.read_text(encoding='utf-8'))
    proof['cycles'] = 1
    proof_file.write_text(json.dumps(proof), encoding='utf-8')
    check('one_cycle_cannot_pass_release', fails(lambda: guard.verify_gate(gate, package)))
    proof['cycles'] = 5
    proof_file.write_text(json.dumps(proof), encoding='utf-8')

    proof['productionPath'], proof['singleRequest'] = False, True
    proof_file.write_text(json.dumps(proof), encoding='utf-8')
    check('diagnostic_single_request_report_rejected', fails(lambda: guard.verify_gate(gate, package)))
    proof['productionPath'], proof['singleRequest'] = True, False
    proof_file.write_text(json.dumps(proof), encoding='utf-8')

    proof['runtimeInputs']['scripts/KsBluetooth.cs'] = '0' * 64
    proof_file.write_text(json.dumps(proof), encoding='utf-8')
    check('gate_runtime_drift_rejected', fails(lambda: guard.verify_gate(gate, package)))
    proof['runtimeInputs']['scripts/KsBluetooth.cs'] = package['runtimeInputs']['scripts/KsBluetooth.cs']
    proof_file.write_text(json.dumps(proof), encoding='utf-8')

    log = gate / '2-connect.txt'
    rows_file = gate / 'results.json'
    rows = json.loads(rows_file.read_text(encoding='utf-8'))
    connect_row = next(row for row in rows if row['cycle'] == 2 and row['phase'] == 'connect')
    connect_row['ksRequests'] = [1, 1]
    log.write_text('INFO bluetooth worker connect requested=1 x\n' * 2, encoding='utf-8')
    connect_row['logSha256'] = sha(log.read_bytes())
    rows_file.write_text(json.dumps(rows), encoding='utf-8')
    proof['resultsSha256'] = sha(rows_file.read_bytes())
    proof_file.write_text(json.dumps(proof), encoding='utf-8')
    check('bounded_production_retry_accepted', guard.verify_gate(gate, package)['cycles'] == 5)

    log.write_text('INFO bluetooth worker connect requested=1 x\n' * 3, encoding='utf-8')
    check('tampered_phase_log_rejected', fails(lambda: guard.verify_gate(gate, package)))
    connect_row['ksRequests'] = [1, 1, 1]
    connect_row['logSha256'] = sha(log.read_bytes())
    rows_file.write_text(json.dumps(rows), encoding='utf-8')
    proof['resultsSha256'] = sha(rows_file.read_bytes())
    proof_file.write_text(json.dumps(proof), encoding='utf-8')
    check('third_ks_connect_request_rejected', fails(lambda: guard.verify_gate(gate, package)))
    connect_row['ksRequests'] = [1]
    log.write_text('INFO bluetooth worker connect address=AABBCCDDEEFF requested=1 ksTrace=x\n', encoding='utf-8')
    connect_row['logSha256'] = sha(log.read_bytes())
    rows_file.write_text(json.dumps(rows), encoding='utf-8')
    proof['resultsSha256'] = sha(rows_file.read_bytes())
    proof_file.write_text(json.dumps(proof), encoding='utf-8')

    rows[-1]['exit'] = 5
    rows_file.write_text(json.dumps(rows), encoding='utf-8')
    check('changed_or_failed_results_rejected', fails(lambda: guard.verify_gate(gate, package)))

    with zipfile.ZipFile(archive, 'w') as z:
        z.writestr('AirPodsBuddy.exe', (build / 'AirPodsBuddy.exe').read_bytes())
        z.writestr('extra.txt', b'not part of the updater asset')
    check('extra_zip_entry_rejected', fails(lambda: guard.verify_package(build, archive, source)))

    with zipfile.ZipFile(archive, 'w') as z:
        z.writestr('AirPodsBuddy.exe', b'MZ stale candidate')
    check('stale_zip_exe_rejected', fails(lambda: guard.verify_package(build, archive, source)))

    runtime_file = source.parent / 'scripts/KsBluetooth.cs'
    runtime_file.write_text('changed runtime fixture\n', encoding='utf-8')
    check('build_runtime_drift_rejected', fails(lambda: guard.verify_package(build, archive, source)))

    source.write_text('APP_VERSION := "1.9.21"\n', encoding='utf-8')
    check('changed_source_rejected', fails(lambda: guard.verify_package(build, archive, source)))

for args in [('--cycles', '1', '--release-gate'),
             ('--cycles', '5', '--single-request', '--release-gate')]:
    p = subprocess.run(['python', 'tests/strict_gate.py', '--address', 'AABBCCDDEEFF', *args],
                       cwd=ROOT, capture_output=True)
    check('release_gate_rejects_invalid_cli_' + args[1], p.returncode == 2)

print(f'RESULT failures=0 tests={passes}')
