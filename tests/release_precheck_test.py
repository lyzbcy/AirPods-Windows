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
    for name in guard.packager.STATIC_INPUTS:
        path = folder / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b'build input fixture\n')
    source = folder / 'airpods_buddy.ahk'
    source.write_text('APP_VERSION := "1.9.21"\n', encoding='utf-8')
    for name in guard.RUNTIME_INPUTS:
        path = folder / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if name != 'airpods_buddy.ahk':
            path.write_text('runtime fixture\n', encoding='utf-8')
    (folder / 'webui/assets').mkdir(parents=True, exist_ok=True)
    (folder / 'assets').mkdir(parents=True, exist_ok=True)
    runtime = {name: sha((folder / name).read_bytes()) for name in guard.RUNTIME_INPUTS}
    inputs = {name: sha((folder / name).read_bytes())
              for name in guard.packager.expected_inputs(folder)}
    build = folder / 'build'
    build.mkdir()
    exe = b'MZ final candidate fixture'
    (build / 'AirPodsBuddy.exe').write_bytes(exe)
    (build / 'build-manifest.json').write_text(json.dumps({
        'source': sha(source.read_bytes()), 'sha256': sha(exe),
        'version': '1.9.21', 'inputs': inputs}), encoding='utf-8')
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

    ui = source.parent / 'webui/index_built.html'
    original_ui = ui.read_bytes()
    ui.write_bytes(b'stale UI after build')
    check('stale_ui_build_input_rejected', fails(lambda: guard.verify_package(build, archive, source)))
    ui.write_bytes(original_ui)
    manifest_path = build / 'build-manifest.json'
    original_manifest = manifest_path.read_bytes()
    incomplete_manifest = json.loads(original_manifest.decode('utf-8'))
    incomplete_manifest['inputs'].pop('webui/index_built.html')
    manifest_path.write_text(json.dumps(incomplete_manifest), encoding='utf-8')
    check('missing_ui_build_inventory_rejected', fails(lambda: guard.verify_package(build, archive, source)))
    manifest_path.write_bytes(original_manifest)

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

    source.write_text('APP_VERSION := "1.9.22"\n', encoding='utf-8')
    check('changed_source_rejected', fails(lambda: guard.verify_package(build, archive, source)))

for args in [('--cycles', '1', '--release-gate'),
             ('--cycles', '5', '--single-request', '--release-gate')]:
    p = subprocess.run(['python', 'tests/strict_gate.py', '--address', 'AABBCCDDEEFF', *args],
                       cwd=ROOT, capture_output=True)
    check('release_gate_rejects_invalid_cli_' + args[1], p.returncode == 2)


def known_issue_fixture(folder):
    source, build, archive, _gate, _strict_receipt = fixture(folder)
    package = guard.verify_package(build, archive, source)
    failure_dir = folder / 'historical-failure'
    failure_dir.mkdir()
    baseline = {'cycle': 0, 'phase': 'baseline', 'exit': 0,
                'command': ['python', 'tests/live_audio.py', 'inspect', 'AABBCCDDEEFF', 'fixture.ini'],
                'file': '0-baseline.txt'}
    failed = {'cycle': 1, 'phase': 'disconnect', 'exit': 5,
              'command': ['python', 'tests/live_audio.py', 'disconnect', 'AABBCCDDEEFF', 'fixture.ini'],
              'file': '1-disconnect.txt'}
    (failure_dir / '0-baseline.txt').write_text('RESULT baseline link=1 render=1\n', encoding='utf-8')
    log = failure_dir / '1-disconnect.txt'
    log.write_text('RESULT state=disconnect_failed link=1\n', encoding='utf-8')
    failed['logSha256'] = sha(log.read_bytes())
    (failure_dir / 'results.json').write_text(json.dumps([baseline, failed]), encoding='utf-8')
    (failure_dir / 'failure.txt').write_text('1-disconnect source action failed with exit 5\n', encoding='utf-8')
    known_issues = folder / 'known-issues.md'
    known_issues.write_text('# 已知问题\nWindows 蓝牙可能偶发连接、断开或路由失败。'
                            '用户可在设置中手动恢复 Windows 蓝牙；应用不自动全局重置。'
                            '请通过反馈入口提交日志。\n', encoding='utf-8')
    decision = folder / 'decision.json'
    decision_text = '非常好，非常好，实测下来没有任何问题，发版吧'
    accepted_at = '2026-09-27T22:00:00+08:00'
    decision.write_text(json.dumps({
        'releaseVersion': package['version'], 'releaseKind': 'formal',
        'acceptedAt': accepted_at, 'decisionText': decision_text,
        'knownIssueContext': {
            'version': '1.9.20',
            'userText': '直接发正式 Release 并写明已知问题'}},
        ensure_ascii=False), encoding='utf-8')
    installed = folder / 'installed-AirPodsBuddy.exe'
    checks = {}
    for name in ('launch', 'defaultOutputListening', 'feedbackEntry'):
        evidence = f'known-{name}.txt'
        data = f'{name} manually recorded fixture\n'.encode()
        (folder / evidence).write_bytes(data)
        checks[name] = {'passed': True, 'evidence': evidence, 'sha256': sha(data)}
    checks['defaultOutputListening']['userConfirmed'] = True
    receipt = folder / 'accepted-known-issue.json'
    receipt.write_text(json.dumps({
        'releaseProfile': 'accepted-known-issue', 'hardwareGate': 'failed',
        'acceptedKnownIssue': True, 'failureEvidenceHistorical': True,
        'releaseVersion': package['version'], 'decisionText': decision_text,
        'acceptedBy': 'projectOwner', 'acceptedAt': accepted_at,
        'decisionEvidence': decision.name, 'decisionEvidenceSha256': sha(decision.read_bytes()),
        'sourceSha256': package['sourceSha256'], 'exeSha256': package['exeSha256'],
        'zipSha256': package['zipSha256'], 'failureSourceSha256': sha(b'historical source'),
        'failureResultsSha256': sha((failure_dir / 'results.json').read_bytes()),
        'failureTextSha256': sha((failure_dir / 'failure.txt').read_bytes()),
        'failureLogSha256': sha(log.read_bytes()), 'knownIssuesSha256': sha(known_issues.read_bytes()),
        'installedExePath': str(installed), 'installedExeSha256': sha(installed.read_bytes()),
        'checks': checks}, ensure_ascii=False), encoding='utf-8')
    return {'source': source, 'build': build, 'archive': archive, 'package': package,
            'failure': failure_dir, 'known': known_issues, 'receipt': receipt, 'installed': installed}


def edit_receipt(case, callback):
    value = json.loads(case['receipt'].read_text(encoding='utf-8'))
    callback(value)
    case['receipt'].write_text(json.dumps(value, ensure_ascii=False), encoding='utf-8')


def edit_decision(case, callback):
    path = case['receipt'].parent / 'decision.json'
    value = json.loads(path.read_text(encoding='utf-8'))
    callback(value)
    path.write_text(json.dumps(value, ensure_ascii=False), encoding='utf-8')
    edit_receipt(case, lambda row: row.update(decisionEvidenceSha256=sha(path.read_bytes())))


def change_decision_text(case, field, value):
    edit_decision(case, lambda row: row.update({field: value}))
    edit_receipt(case, lambda row: row.update({field: value}))


with tempfile.TemporaryDirectory() as tmp:
    base = Path(tmp)
    def fresh(name):
        folder = base / name
        folder.mkdir()
        return known_issue_fixture(folder)

    case = fresh('valid')
    check('accepted_known_issue_valid_historical_failure',
          guard.verify_accepted_known_issue(case['receipt'], case['failure'], case['known'],
                                            case['package'])['hardwareGate'] == 'failed')
    cmd = ['python', 'scripts/release-precheck.py', '--accepted-known-issue',
           '--failure-dir', str(case['failure']), '--known-issues', str(case['known']),
           '--build-dir', str(case['build']), '--zip', str(case['archive']),
           '--acceptance', str(case['receipt']), '--source', str(case['source'])]
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True)
    cli_output = p.stdout.decode('utf-8-sig')
    check('accepted_known_issue_cli_has_honest_status', p.returncode == 0
          and 'hardwareGate=failed acceptedKnownIssue=true' in cli_output
          and 'historicalFailureNotFinalBuildRetest=true' in cli_output
          and 'HUMAN_ATTESTATION_NOT_MACHINE_VERIFIED' in cli_output
          and 'GATE_PASS' not in cli_output)
    strict_case = fresh('strict-cli')
    strict_cmd = ['python', 'scripts/release-precheck.py',
                  '--gate-dir', str(strict_case['receipt'].parent / 'gate'),
                  '--build-dir', str(strict_case['build']), '--zip', str(strict_case['archive']),
                  '--acceptance', str(strict_case['receipt'].parent / 'installed-acceptance.json'),
                  '--source', str(strict_case['source'])]
    strict_p = subprocess.run(strict_cmd, cwd=ROOT, capture_output=True)
    check('strict_cli_still_requires_five_passed_cycles', strict_p.returncode == 0
          and 'cycles=5 productionPath=true' in strict_p.stdout.decode('utf-8-sig')
          and 'hardwareGate=failed' not in strict_p.stdout.decode('utf-8-sig'))

    def rejected(name, change):
        item = fresh(name)
        change(item)
        def verify():
            current_package = guard.verify_package(item['build'], item['archive'], item['source'])
            guard.verify_accepted_known_issue(item['receipt'], item['failure'],
                                              item['known'], current_package)
        check(name, fails(verify))

    rejected('known_issue_requires_explicit_consent',
             lambda item: edit_receipt(item, lambda row: row.update(acceptedKnownIssue=False)))
    rejected('known_issue_requires_owner_decision',
             lambda item: edit_receipt(item, lambda row: row.update(decisionText='consider release')))
    rejected('known_issue_requires_current_release_version',
             lambda item: edit_receipt(item, lambda row: row.update(releaseVersion='1.9.20')))
    rejected('known_issue_rejects_stale_versioned_decision_evidence',
             lambda item: edit_decision(item, lambda row: row.update(releaseVersion='1.9.20')))
    rejected('known_issue_rejects_non_formal_release_decision',
             lambda item: edit_decision(item, lambda row: row.update(releaseKind='prerelease')))
    rejected('known_issue_rejects_matching_but_denied_release_text',
             lambda item: change_decision_text(item, 'decisionText', '先别发版吧，继续测'))
    rejected('known_issue_rejects_matching_but_disagreed_release_text',
             lambda item: change_decision_text(item, 'decisionText', '不同意正式发版'))
    rejected('known_issue_rejects_denied_historical_issue_context',
             lambda item: edit_decision(item, lambda row:
                                        row['knownIssueContext'].update(userText='可以发版，别写已知问题')))
    rejected('known_issue_rejects_missing_historical_issue_context',
             lambda item: edit_decision(item, lambda row: row.pop('knownIssueContext')))
    rejected('known_issue_rejects_future_issue_context',
             lambda item: edit_decision(item, lambda row:
                                        row['knownIssueContext'].update(version='1.9.22')))
    rejected('known_issue_rejects_unhashed_consent_evidence',
             lambda item: (item['receipt'].parent / 'decision.json').write_text('changed\n', encoding='utf-8'))
    rejected('known_issue_requires_failure_source_hash',
             lambda item: edit_receipt(item, lambda row: row.pop('failureSourceSha256')))
    def zero_exit(item):
        path = item['failure'] / 'results.json'
        rows = json.loads(path.read_text(encoding='utf-8'))
        rows[-1]['exit'] = 0
        path.write_text(json.dumps(rows), encoding='utf-8')
        edit_receipt(item, lambda row: row.update(failureResultsSha256=sha(path.read_bytes())))
    rejected('known_issue_rejects_zero_failure_exit', zero_exit)
    rejected('known_issue_rejects_tampered_failure_log',
             lambda item: (item['failure'] / '1-disconnect.txt').write_text('changed\n', encoding='utf-8'))
    rejected('known_issue_rejects_fake_gate_pass',
             lambda item: (item['failure'] / 'gate-pass.json').write_text('{}', encoding='utf-8'))
    def missing_disclosure(item):
        item['known'].write_text('# 已知问题\nWindows 蓝牙可能失败。\n', encoding='utf-8')
        edit_receipt(item, lambda row: row.update(knownIssuesSha256=sha(item['known'].read_bytes())))
    rejected('known_issue_requires_recovery_and_feedback_disclosure', missing_disclosure)
    rejected('known_issue_rejects_installed_exe_drift',
             lambda item: item['installed'].write_bytes(b'MZ stale installed'))
    rejected('known_issue_requires_launch_evidence',
             lambda item: (item['receipt'].parent / 'known-launch.txt').unlink())
    rejected('known_issue_requires_listening_confirmation',
             lambda item: edit_receipt(item, lambda row:
                                       row['checks']['defaultOutputListening'].update(userConfirmed=False)))
    rejected('known_issue_requires_feedback_entry_evidence',
             lambda item: (item['receipt'].parent / 'known-feedbackEntry.txt').write_text('changed\n', encoding='utf-8'))
    rejected('known_issue_rejects_final_source_drift',
             lambda item: item['source'].write_text('APP_VERSION := "1.9.22"\n', encoding='utf-8'))
    rejected('known_issue_rejects_final_zip_drift',
             lambda item: edit_receipt(item, lambda row: row.update(zipSha256='0' * 64)))
    p = subprocess.run([*cmd, '--gate-dir', str(case['failure'])], cwd=ROOT, capture_output=True)
    check('known_issue_cli_rejects_mixed_gate_paths', p.returncode == 2)

print(f'RESULT failures=0 tests={passes}')
