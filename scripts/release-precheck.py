"""Offline release guard: strict gate or explicit known-issue acceptance, EXE parity.

This script reads evidence and artifacts. It never connects hardware, deploys, or publishes.
"""
from pathlib import Path
import argparse
from datetime import datetime
import hashlib
import importlib.util
import json
import re
import sys
import zipfile


ROOT = Path(__file__).resolve().parents[1]
PACKAGER_SPEC = importlib.util.spec_from_file_location(
    'package_windows_release', ROOT / 'scripts/package-windows-release.py')
packager = importlib.util.module_from_spec(PACKAGER_SPEC)
PACKAGER_SPEC.loader.exec_module(packager)
PHASES = ('disconnect', 'after-disconnect', 'delayed-disconnect',
          'connect', 'after-connect', 'delayed-connect')
SHA256 = re.compile(r'^[0-9A-F]{64}$')
ADDRESS = re.compile(r'^[0-9A-F]{12}$')
RUNTIME_INPUTS = ('airpods_buddy.ahk', 'lib/AudioRouting.ahk',
                  'lib/BackgroundJobs.ahk', 'scripts/background-worker.ps1',
                  'scripts/KsBluetooth.cs', 'scripts/KsBluetooth.psm1')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def require(ok, message):
    if not ok:
        raise ValueError(message)


def verified_hash(value, field):
    require(isinstance(value, str) and SHA256.fullmatch(value), f'invalid {field} hash')
    return value


def verify_gate(folder, package):
    folder = Path(folder)
    proof = json.loads((folder / 'gate-pass.json').read_text(encoding='utf-8'))
    rows_path = folder / 'results.json'
    rows = json.loads(rows_path.read_text(encoding='utf-8'))
    require(proof.get('result') == 'GATE_PASS' and proof.get('releaseGate') is True,
            'release gate has no pass record')
    require(proof.get('cycles') == 5 and isinstance(proof.get('dwell'), int)
            and 15 <= proof['dwell'] <= 30 and proof.get('productionPath') is True
            and proof.get('singleRequest') is False,
            'release gate is not five unmodified production-path cycles with adequate dwell')
    address, render = proof.get('address'), proof.get('renderId')
    require(isinstance(address, str) and ADDRESS.fullmatch(address), 'invalid gate target address')
    require(isinstance(render, str) and re.fullmatch(
        r'\{0\.0\.0\.00000000\}\.\{[0-9a-fA-F-]{36}\}', render), 'invalid gate render ID')
    require(verified_hash(proof.get('sourceSha256'), 'gate source') == package['sourceSha256'],
            'gate source differs from final build source')
    require(proof.get('runtimeInputs') == package['runtimeInputs'],
            'gate runtime inputs differ from final build inputs')
    require(verified_hash(proof.get('resultsSha256'), 'gate results') == digest(rows_path),
            'gate results changed after pass')
    settings = Path(proof.get('settings', ''))
    require(settings.is_file() and verified_hash(proof.get('settingsSha256'), 'gate settings') == digest(settings),
            'gate settings changed or missing')
    require(isinstance(rows, list) and len(rows) == 31, 'gate must contain baseline plus 30 cycle phases')
    expected = [(0, 'baseline', 'inspect')]
    expected += [(cycle, phase, phase if phase in ('connect', 'disconnect') else 'inspect')
                 for cycle in range(1, 6) for phase in PHASES]
    baseline_mic = None
    for row, (cycle, phase, mode) in zip(rows, expected):
        require(isinstance(row, dict) and row.get('cycle') == cycle and row.get('phase') == phase
                and type(row.get('exit')) is int and row['exit'] == 0,
                f'gate phase missing or failed: {cycle}-{phase}')
        command = ['python', 'tests/live_audio.py', mode, address, str(settings)]
        require(row.get('command') == command, f'gate command changed: {cycle}-{phase}')
        filename = f'{cycle}-{phase}.txt'
        require(row.get('file') == filename and (folder / filename).is_file(),
                f'gate phase log missing: {filename}')
        require(verified_hash(row.get('logSha256'), f'{filename} log') == digest(folder / filename),
                f'gate phase log changed after pass: {filename}')
        if mode == 'connect':
            log = (folder / filename).read_text(encoding='utf-8')
            requests = [int(value) for value in re.findall(
                r'^INFO bluetooth worker connect\b.*?\brequested=(\d+)\s', log, re.MULTILINE)]
            require(row.get('ksRequests') in ([1], [1, 1]) and requests == row['ksRequests'],
                    f'production connect request budget violated: {cycle}')
        if mode != 'inspect':
            continue
        require(row.get('link') in (0, 1) and row.get('renderState') in (1, 8),
                f'invalid inspected link/endpoint state: {cycle}-{phase}')
        output, mic = row.get('outputRoles'), row.get('micRoles')
        require(isinstance(output, list) and len(output) == 3
                and isinstance(mic, list) and len(mic) == 3,
                f'missing default roles: {cycle}-{phase}')
        if baseline_mic is None:
            baseline_mic = mic
        require(mic == baseline_mic, f'microphone defaults changed: {cycle}-{phase}')
        disconnected = phase in ('after-disconnect', 'delayed-disconnect')
        require(row['link'] == (0 if disconnected else 1)
                and row['renderState'] == (8 if disconnected else 1),
                f'link or render state failed: {cycle}-{phase}')
        require((all(value.lower() != render.lower() for value in output) if disconnected else
                 all(value.lower() == render.lower() for value in output)),
                f'default playback roles failed: {cycle}-{phase}')
    return proof


def verify_package(build_dir, archive_path, source):
    build_dir, archive_path, source = Path(build_dir), Path(archive_path), Path(source)
    require(archive_path.name == 'AirPodsBuddy-Windows.zip', 'release asset name is not updater-compatible')
    require(source.name == 'airpods_buddy.ahk', 'source must be airpods_buddy.ahk')
    build = packager.verify_build(build_dir, source.parent)
    source_hash, exe_hash = build['sourceSha256'], build['exeSha256']
    runtime = {name: digest(source.parent / name) for name in RUNTIME_INPUTS}
    require(all(build['inputs'].get(name) == runtime[name] for name in RUNTIME_INPUTS),
            'build manifest runtime inputs differ from current files')
    with zipfile.ZipFile(archive_path) as archive:
        require(archive.testzip() is None, 'release ZIP failed CRC verification')
        require(archive.namelist() == ['AirPodsBuddy.exe'],
                'release ZIP must contain only one root AirPodsBuddy.exe')
        packaged_hash = hashlib.sha256(archive.read('AirPodsBuddy.exe')).hexdigest().upper()
    require(packaged_hash == exe_hash, 'release ZIP EXE differs from final build EXE')
    return {'version': build['version'], 'sourceSha256': source_hash,
            'runtimeInputs': runtime,
            'exeSha256': exe_hash, 'zipSha256': digest(archive_path)}


def verify_acceptance(receipt_path, package, gate):
    """Require manually supplied, hash-bound installed/restart/listening/mic-on evidence."""
    receipt_path = Path(receipt_path)
    receipt = json.loads(receipt_path.read_text(encoding='utf-8'))
    installed = Path(receipt.get('installedExePath', ''))
    require(installed.is_absolute() and installed.is_file(), 'installed EXE evidence missing')
    require(verified_hash(receipt.get('installedExeSha256'), 'installed EXE') == package['exeSha256']
            and digest(installed) == package['exeSha256'],
            'installed EXE differs from final release build')
    require(receipt.get('gateResultsSha256') == gate['resultsSha256'],
            'installed acceptance is not bound to this production gate')
    checks = receipt.get('checks')
    require(isinstance(checks, dict), 'installed acceptance checks missing')
    for name in ('restartReconnect', 'defaultOutputListening', 'micOn'):
        row = checks.get(name)
        require(isinstance(row, dict) and row.get('passed') is True,
                f'installed acceptance not passed: {name}')
        filename = row.get('evidence')
        require(isinstance(filename, str) and filename == Path(filename).name
                and filename not in ('.', '..'), f'bad acceptance evidence path: {name}')
        evidence = receipt_path.parent / filename
        require(evidence.is_file() and verified_hash(row.get('sha256'), name) == digest(evidence),
                f'acceptance evidence missing or changed: {name}')
    require(checks['defaultOutputListening'].get('userConfirmed') is True,
            'default-output listening lacks user confirmation')
    require(checks['micOn'].get('autoMicSwitch') == '1',
            'common mic-on preference was not tested')
    return receipt


def verify_accepted_known_issue(receipt_path, failure_dir, known_issues_path, package):
    """Check hash-bound records, not the truth of a human attestation."""
    receipt_path = Path(receipt_path)
    failure_dir = Path(failure_dir)
    known_issues_path = Path(known_issues_path)
    receipt = json.loads(receipt_path.read_text(encoding='utf-8'))
    require(receipt.get('releaseProfile') == 'accepted-known-issue'
            and receipt.get('hardwareGate') == 'failed'
            and receipt.get('acceptedKnownIssue') is True
            and receipt.get('failureEvidenceHistorical') is True,
            'known-issue release decision fields missing')
    require(receipt.get('acceptedBy') == 'projectOwner',
            'explicit project-owner release decision missing')
    try:
        accepted_at = datetime.fromisoformat(receipt.get('acceptedAt', '').replace('Z', '+00:00'))
    except (TypeError, ValueError) as exc:
        raise ValueError('acceptedAt is not an ISO timestamp') from exc
    require(accepted_at.tzinfo is not None, 'acceptedAt must include a timezone')
    for name, expected in (('sourceSha256', package['sourceSha256']),
                           ('exeSha256', package['exeSha256']),
                           ('zipSha256', package['zipSha256'])):
        require(verified_hash(receipt.get(name), name) == expected,
                f'known-issue decision differs from final package: {name}')
    verified_hash(receipt.get('failureSourceSha256'), 'historical failure source')

    def check_receipt_file(name, folder, filename):
        require(isinstance(filename, str) and filename == Path(filename).name
                and filename not in ('.', '..'), f'invalid {name} evidence filename')
        path = folder / filename
        require(path.is_file() and verified_hash(receipt.get(name), name) == digest(path),
                f'{name} evidence missing or changed')
        return path

    decision_path = check_receipt_file('decisionEvidenceSha256', receipt_path.parent,
                                       receipt.get('decisionEvidence'))
    decision = json.loads(decision_path.read_text(encoding='utf-8'))
    require(isinstance(decision, dict)
            and receipt.get('releaseVersion') == package['version']
            and decision.get('releaseVersion') == package['version']
            and decision.get('releaseKind') == 'formal'
            and decision.get('acceptedAt') == receipt.get('acceptedAt')
            and decision.get('decisionText') == receipt.get('decisionText'),
            'versioned project-owner release decision differs from receipt or final package')
    release_text = receipt.get('decisionText')
    def explicitly_approves(text):
        return (isinstance(text, str) and not re.search(
                    r'不要|先别|别发|别写|暂不|不发|不发布|不同意|不可以|不行|不提|不用(?:写|披露)|取消', text)
                and re.search(r'(?:可以|同意|直接|现在|马上|请|就|仍|准备好).*?(?:正式\s*Release|发版|发布)|(?:发版|发布)吧',
                              text, re.IGNORECASE))
    require(explicitly_approves(release_text),
            'versioned project-owner text does not authorize formal release')
    context = decision.get('knownIssueContext')
    require(isinstance(context, dict), 'known-issue consent context missing')
    context_version = context.get('version')
    require(isinstance(context_version, str) and re.fullmatch(r'\d+\.\d+\.\d+', context_version)
            and tuple(map(int, context_version.split('.'))) <= tuple(map(int, package['version'].split('.'))),
            'known-issue consent context has no valid current or historical version')
    context_text = context.get('userText')
    require(explicitly_approves(context_text)
            and re.search(r'已知问题|偶发.*(?:连接|断开|无声)|五轮', context_text)
            and re.search(r'知悉|知道|接受|同意|写明|披露|仍', context_text),
            'known-issue consent context does not acknowledge a formal release with known issues')
    require(not (failure_dir / 'gate-pass.json').exists(),
            'failed hardware gate cannot contain gate-pass.json')
    results_path = check_receipt_file('failureResultsSha256', failure_dir, 'results.json')
    failure_text_path = check_receipt_file('failureTextSha256', failure_dir, 'failure.txt')
    require(failure_text_path.read_text(encoding='utf-8').strip(), 'failure.txt is empty')
    rows = json.loads(results_path.read_text(encoding='utf-8'))
    require(isinstance(rows, list) and len(rows) >= 2
            and all(isinstance(row, dict) for row in rows),
            'failure results require baseline and action records')
    baseline, failed = rows[0], rows[-1]
    require(baseline.get('phase') == 'baseline' and baseline.get('exit') == 0,
            'failure results have no successful baseline')
    require(failed.get('phase') in ('connect', 'disconnect')
            and type(failed.get('exit')) is int and failed['exit'] != 0
            and all(type(row.get('exit')) is int and row['exit'] == 0 for row in rows[:-1]),
            'failure results have no terminal nonzero action exit')
    command = failed.get('command')
    require(isinstance(command, list) and len(command) >= 5
            and command[:3] == ['python', 'tests/live_audio.py', failed['phase']]
            and isinstance(command[3], str) and ADDRESS.fullmatch(command[3]),
            'failure action is not a recorded target source command')
    log_path = check_receipt_file('failureLogSha256', failure_dir, failed.get('file'))
    if 'logSha256' in failed:
        require(verified_hash(failed['logSha256'], 'failure row log') == digest(log_path),
                'failure row log hash differs from failure action log')
    require(str(failed['exit']) in failure_text_path.read_text(encoding='utf-8'),
            'failure.txt does not report terminal action exit')

    known_text = known_issues_path.read_text(encoding='utf-8')
    require(verified_hash(receipt.get('knownIssuesSha256'), 'known issues') == digest(known_issues_path)
            and all(term in known_text for term in ('已知问题', 'Windows 蓝牙', '手动恢复', '反馈')),
            'known-issues disclosure missing, changed or incomplete')
    installed = Path(receipt.get('installedExePath', ''))
    require(installed.is_absolute() and installed.is_file()
            and verified_hash(receipt.get('installedExeSha256'), 'installed EXE') == package['exeSha256']
            and digest(installed) == package['exeSha256'],
            'installed EXE differs from final release build')
    checks = receipt.get('checks')
    require(isinstance(checks, dict), 'installed known-issue acceptance checks missing')
    for name in ('launch', 'defaultOutputListening', 'feedbackEntry'):
        row = checks.get(name)
        require(isinstance(row, dict) and row.get('passed') is True,
                f'installed known-issue acceptance missing: {name}')
        filename = row.get('evidence')
        require(isinstance(filename, str) and filename == Path(filename).name
                and filename not in ('.', '..'), f'invalid {name} evidence filename')
        evidence = receipt_path.parent / filename
        require(evidence.is_file() and verified_hash(row.get('sha256'), name) == digest(evidence),
                f'{name} evidence missing or changed')
    require(checks['defaultOutputListening'].get('userConfirmed') is True,
            'default-output listening lacks user confirmation')
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gate-dir', type=Path)
    parser.add_argument('--accepted-known-issue', action='store_true')
    parser.add_argument('--failure-dir', type=Path)
    parser.add_argument('--known-issues', type=Path)
    parser.add_argument('--build-dir', type=Path, required=True)
    parser.add_argument('--zip', type=Path, required=True)
    parser.add_argument('--acceptance', type=Path, required=True,
                        help='manual installed-app restart/listening/mic-on receipt and hashed evidence')
    parser.add_argument('--source', type=Path, default=ROOT / 'airpods_buddy.ahk')
    args = parser.parse_args()
    if args.accepted_known_issue:
        if args.gate_dir or not args.failure_dir or not args.known_issues:
            parser.error('known-issue path requires --failure-dir and --known-issues, not --gate-dir')
    elif not args.gate_dir or args.failure_dir or args.known_issues:
        parser.error('strict path requires --gate-dir and no known-issue inputs')
    try:
        package = verify_package(args.build_dir, args.zip, args.source)
        if args.accepted_known_issue:
            verify_accepted_known_issue(args.acceptance, args.failure_dir, args.known_issues, package)
        else:
            gate = verify_gate(args.gate_dir, package)
            verify_acceptance(args.acceptance, package, gate)
    except (OSError, ValueError, KeyError, json.JSONDecodeError, zipfile.BadZipFile) as exc:
        print(f'RELEASE_PRECHECK_FAIL {exc}')
        return 1
    if args.accepted_known_issue:
        print('RELEASE_PRECHECK_PASS hardwareGate=failed acceptedKnownIssue=true '
              'failureEvidenceHistorical=true historicalFailureNotFinalBuildRetest=true '
              'installedAcceptance=true '
              f'version={package["version"]} sourceSha256={package["sourceSha256"]} '
              f'exeSha256={package["exeSha256"]} zipSha256={package["zipSha256"]}')
        print('HUMAN_ATTESTATION_NOT_MACHINE_VERIFIED receipt and listening authenticity '
              'must be checked by the human release approver')
    else:
        print('RELEASE_PRECHECK_PASS cycles=5 productionPath=true installedAcceptance=true '
              f'version={package["version"]} sourceSha256={package["sourceSha256"]} '
              f'exeSha256={package["exeSha256"]} zipSha256={package["zipSha256"]}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
