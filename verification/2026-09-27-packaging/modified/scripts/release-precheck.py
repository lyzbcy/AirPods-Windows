"""Offline release guard: production gate, installed acceptance, packaged EXE parity.

This script reads evidence and artifacts. It never connects hardware, deploys, or publishes.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import sys
import zipfile


ROOT = Path(__file__).resolve().parents[1]
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
    manifest = json.loads((build_dir / 'build-manifest.json').read_text(encoding='utf-8-sig'))
    source_hash = digest(source)
    require(verified_hash(manifest.get('source'), 'manifest source') == source_hash,
            'build source differs from current source')
    version = re.search(r'APP_VERSION\s*:=\s*"([^"]+)"', source.read_text(encoding='utf-8-sig'))
    require(version is not None and manifest.get('version') == version.group(1),
            'build version differs from current source')
    exe_hash = verified_hash(manifest.get('sha256'), 'manifest exe')
    require(digest(build_dir / 'AirPodsBuddy.exe') == exe_hash,
            'built EXE differs from build manifest')
    inputs = manifest.get('inputs')
    require(isinstance(inputs, dict), 'build manifest has no input hashes')
    runtime = {name: digest(source.parent / name) for name in RUNTIME_INPUTS}
    require(all(verified_hash(inputs.get(name), name) == runtime[name] for name in RUNTIME_INPUTS),
            'build manifest runtime inputs differ from current files')
    with zipfile.ZipFile(archive_path) as archive:
        require(archive.testzip() is None, 'release ZIP failed CRC verification')
        require(archive.namelist() == ['AirPodsBuddy.exe'],
                'release ZIP must contain only one root AirPodsBuddy.exe')
        packaged_hash = hashlib.sha256(archive.read('AirPodsBuddy.exe')).hexdigest().upper()
    require(packaged_hash == exe_hash, 'release ZIP EXE differs from final build EXE')
    return {'version': manifest['version'], 'sourceSha256': source_hash,
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gate-dir', type=Path, required=True)
    parser.add_argument('--build-dir', type=Path, required=True)
    parser.add_argument('--zip', type=Path, required=True)
    parser.add_argument('--acceptance', type=Path, required=True,
                        help='manual installed-app restart/listening/mic-on receipt and hashed evidence')
    parser.add_argument('--source', type=Path, default=ROOT / 'airpods_buddy.ahk')
    args = parser.parse_args()
    try:
        package = verify_package(args.build_dir, args.zip, args.source)
        gate = verify_gate(args.gate_dir, package)
        verify_acceptance(args.acceptance, package, gate)
    except (OSError, ValueError, KeyError, json.JSONDecodeError, zipfile.BadZipFile) as exc:
        print(f'RELEASE_PRECHECK_FAIL {exc}')
        return 1
    print('RELEASE_PRECHECK_PASS cycles=5 productionPath=true installedAcceptance=true '
          f'version={package["version"]} sourceSha256={package["sourceSha256"]} '
          f'exeSha256={package["exeSha256"]} zipSha256={package["zipSha256"]}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
