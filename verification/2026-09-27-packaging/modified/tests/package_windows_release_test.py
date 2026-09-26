"""Offline release ZIP packaging tests; never build, deploy, or use hardware."""
from pathlib import Path
import hashlib
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
from unittest.mock import patch
import zipfile


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/package-windows-release.py'
spec = importlib.util.spec_from_file_location('release_packager', SCRIPT)
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)
passes = 0


def check(name, condition):
    global passes
    if not condition:
        raise AssertionError(name)
    passes += 1
    print('PASS', name)


def rejects(callback):
    try:
        callback()
    except (OSError, ValueError, KeyError, json.JSONDecodeError, zipfile.BadZipFile):
        return True
    return False


def sha(data):
    return hashlib.sha256(data).hexdigest().upper()


def fixture(base):
    root = base / 'source'
    root.mkdir()
    for name in packager.STATIC_INPUTS:
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b'fixture input\n')
    (root / 'airpods_buddy.ahk').write_text('APP_VERSION := "1.9.20"\n', encoding='utf-8')
    for name in ('lib/AudioRouting.ahk', 'assets/icon.ico', 'webui/assets/pet.png'):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b'dynamic fixture\n')
    inputs = {name: packager.digest(root / name) for name in packager.expected_inputs(root)}
    build = base / 'build-final'
    build.mkdir()
    exe = b'MZ final build-only executable fixture'
    (build / packager.EXE).write_bytes(exe)
    manifest = {'version': '1.9.20', 'source': inputs['airpods_buddy.ahk'],
                'sha256': sha(exe), 'inputs': inputs, 'builtAt': '2026-09-27T00:00:00Z'}
    (build / 'build-manifest.json').write_text(json.dumps(manifest), encoding='utf-8')
    return root, build, manifest, exe


with tempfile.TemporaryDirectory(prefix='AirPodsBuddy_package_test_') as temp:
    base = Path(temp)
    root, build, manifest, exe = fixture(base)
    output = base / 'new-release-output'
    result = packager.package(build, output, root)
    asset = output / packager.ASSET
    check('new_directory_contains_exact_asset', asset.is_file() and list(output.iterdir()) == [asset])
    with zipfile.ZipFile(asset) as archive:
        check('zip_has_only_root_exe', archive.namelist() == [packager.EXE])
        check('zip_root_exe_matches_source_exe', archive.read(packager.EXE) == exe)
    check('zip_exe_matches_manifest_hash', result['exeSha256'] == manifest['sha256'])
    check('zip_sha256_readback', result['zipSha256'] == packager.digest(asset))
    original_asset_hash = packager.digest(asset)
    check('existing_output_refused', rejects(lambda: packager.package(build, output, root)))
    check('existing_asset_untouched', packager.digest(asset) == original_asset_hash)

    script_in_fixture = root / 'scripts/package-windows-release.py'
    script_in_fixture.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(SCRIPT, script_in_fixture)
    cli_output = base / 'cli-output'
    cli = subprocess.run([sys.executable, str(script_in_fixture), '--build-dir', str(build),
                          '--output-dir', str(cli_output)], cwd=root, capture_output=True, text=True)
    check('cli_success_and_hashes', cli.returncode == 0 and 'PACKAGE_OK asset=' in cli.stdout
          and manifest['sha256'] in cli.stdout and (cli_output / packager.ASSET).is_file())
    cli_repeat = subprocess.run([sys.executable, str(script_in_fixture), '--build-dir', str(build),
                                 '--output-dir', str(cli_output)], cwd=root, capture_output=True, text=True)
    check('cli_repeat_refuses_overwrite', cli_repeat.returncode == 1
          and 'PACKAGE_FAIL output directory already exists' in cli_repeat.stdout)

    (build / packager.EXE).write_bytes(b'MZ stale or modified exe')
    check('changed_exe_refused_before_creating_output',
          rejects(lambda: packager.package(build, base / 'bad-exe', root))
          and not (base / 'bad-exe').exists())
    (build / packager.EXE).write_bytes(exe)
    source = root / 'airpods_buddy.ahk'
    original_source = source.read_bytes()
    source.write_text('APP_VERSION := "1.9.21"\n', encoding='utf-8')
    check('stale_source_refused', rejects(lambda: packager.package(build, base / 'stale-source', root)))
    source.write_bytes(original_source)
    ui = root / 'webui/index_built.html'
    original_ui = ui.read_bytes()
    ui.write_bytes(b'changed UI fixture')
    check('stale_ui_input_refused', rejects(lambda: packager.package(build, base / 'stale-ui', root)))
    ui.write_bytes(original_ui)

    new_lib = root / 'lib/new-module.ahk'
    new_lib.write_bytes(b'new build input')
    check('new_build_input_refused', rejects(lambda: packager.package(build, base / 'new-input', root)))
    new_lib.unlink()

    manifest_path = build / 'build-manifest.json'
    original_manifest = manifest_path.read_bytes()
    missing = dict(manifest)
    missing['inputs'] = {k: v for k, v in manifest['inputs'].items() if k != 'webui/index.html'}
    manifest_path.write_text(json.dumps(missing), encoding='utf-8')
    check('missing_build_input_refused', rejects(lambda: packager.package(build, base / 'missing-input', root)))
    manifest_path.write_bytes(original_manifest)

    bad_hash = dict(manifest)
    bad_hash['sha256'] = '0' * 64
    manifest_path.write_text(json.dumps(bad_hash), encoding='utf-8')
    check('manifest_exe_mismatch_refused', rejects(lambda: packager.package(build, base / 'bad-hash', root)))
    manifest_path.write_bytes(original_manifest)

    changed_during = base / 'changed-during'
    real_verify = packager.verify_build
    calls = 0

    def mutate_on_second_check(build_dir, source_root):
        global calls
        calls += 1
        if calls == 2:
            ui.write_bytes(b'changed during zip write')
        return real_verify(build_dir, source_root)

    with patch.object(packager, 'verify_build', side_effect=mutate_on_second_check):
        check('concurrent_source_change_refused_and_partial_removed',
              rejects(lambda: packager.package(build, changed_during, root))
              and not changed_during.exists())
    ui.write_bytes(original_ui)

    tampered_zip = base / 'tampered.zip'
    with zipfile.ZipFile(tampered_zip, 'w') as archive:
        archive.writestr(packager.EXE, b'MZ stale fixture')
    check('tampered_zip_exe_rejected', rejects(lambda: packager.verify_zip(tampered_zip, manifest['sha256'])))
    with zipfile.ZipFile(tampered_zip, 'w') as archive:
        archive.writestr(packager.EXE, exe)
        archive.writestr('extra.txt', b'not allowed')
    check('extra_zip_entry_rejected', rejects(lambda: packager.verify_zip(tampered_zip, manifest['sha256'])))

print(f'RESULT failures=0 tests={passes}')
