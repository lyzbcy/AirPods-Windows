"""Build the exact Windows update ZIP from a fresh build-only directory.

This command never builds, installs, connects hardware, or publishes a release.
The output directory must be new so an older asset cannot be silently reused.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import zipfile


ROOT = Path(__file__).resolve().parents[1]
ASSET = 'AirPodsBuddy-Windows.zip'
EXE = 'AirPodsBuddy.exe'
SHA256 = re.compile(r'[0-9A-F]{64}')
VERSION = re.compile(r'APP_VERSION\s*:=\s*"([^"]+)"')
STATIC_INPUTS = (
    'airpods_buddy.ahk', 'webui/index.html', 'webui/index_built.html',
    'webui/pet.html', 'webui/pet_built.html', 'webui/build_ui.ps1',
    'tools/noise_mode.ps1', 'tools/ahk2exe_stable/Ahk2Exe.exe',
    'tools/ahk_v2_portable/AutoHotkey64.exe', 'scripts/background-worker.ps1',
    'scripts/KsBluetooth.cs', 'scripts/KsBluetooth.psm1',
    'THIRD_PARTY_NOTICES.md', 'scripts/UpdateCore.psm1',
    'scripts/update-swap.ps1',
)


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest().upper()


def expected_inputs(root: Path) -> set[str]:
    names = set(STATIC_INPUTS)
    names.update(path.relative_to(root).as_posix() for path in (root / 'lib').rglob('*')
                 if path.is_file() and path.suffix.lower() in ('.ahk', '.dll'))
    names.update(path.relative_to(root).as_posix() for path in (root / 'assets').glob('*.ico')
                 if path.is_file())
    names.update(path.relative_to(root).as_posix() for path in (root / 'webui/assets').iterdir()
                 if path.is_file())
    return names


def verify_build(build_dir: Path, root: Path) -> dict:
    manifest_path = build_dir / 'build-manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
    if not isinstance(manifest, dict):
        raise ValueError('invalid build manifest object')
    inputs = manifest.get('inputs')
    if not isinstance(inputs, dict):
        raise ValueError('build manifest has no input snapshot')
    expected = expected_inputs(root)
    if set(inputs) != expected:
        raise ValueError('build manifest input inventory differs from current source tree')
    if any(not isinstance(value, str) or not SHA256.fullmatch(value) for value in inputs.values()):
        raise ValueError('invalid build input hash')
    for name, expected_hash in inputs.items():
        if digest(root / name) != expected_hash:
            raise ValueError(f'stale build manifest input: {name}')
    source_hash = inputs['airpods_buddy.ahk']
    if manifest.get('source') != source_hash:
        raise ValueError('build manifest source hash differs from input snapshot')
    source = (root / 'airpods_buddy.ahk').read_text(encoding='utf-8-sig')
    version = VERSION.search(source)
    if version is None or manifest.get('version') != version.group(1):
        raise ValueError('build manifest version differs from current source')
    exe_hash = manifest.get('sha256')
    if not isinstance(exe_hash, str) or not SHA256.fullmatch(exe_hash):
        raise ValueError('invalid build exe hash')
    if digest(build_dir / EXE) != exe_hash:
        raise ValueError('build exe differs from manifest')
    return {'manifestSha256': digest(manifest_path), 'exeSha256': exe_hash,
            'sourceSha256': source_hash, 'inputs': inputs, 'version': version.group(1)}


def verify_zip(archive_path: Path, expected_exe_hash: str) -> str:
    with zipfile.ZipFile(archive_path) as archive:
        if archive.namelist() != [EXE]:
            raise ValueError('release ZIP must contain only one root AirPodsBuddy.exe')
        if archive.testzip() is not None:
            raise ValueError('release ZIP CRC check failed')
        value = hashlib.sha256()
        with archive.open(EXE) as exe:
            for chunk in iter(lambda: exe.read(1024 * 1024), b''):
                value.update(chunk)
        if value.hexdigest().upper() != expected_exe_hash:
            raise ValueError('ZIP root exe differs from build manifest and source exe')
    return digest(archive_path)


def package(build_dir: Path, output_dir: Path, root: Path = ROOT) -> dict:
    build_dir = build_dir.resolve(strict=True)
    root = root.resolve(strict=True)
    output_dir = output_dir.absolute()
    if output_dir.exists():
        raise ValueError('output directory already exists; choose a new directory')
    before = verify_build(build_dir, root)
    output_dir.mkdir(parents=False, exist_ok=False)
    archive_path = output_dir / ASSET
    try:
        with zipfile.ZipFile(archive_path, 'x', compression=zipfile.ZIP_DEFLATED,
                             compresslevel=9) as archive:
            archive.write(build_dir / EXE, arcname=EXE)
        zip_hash = verify_zip(archive_path, before['exeSha256'])
        after = verify_build(build_dir, root)
        if after != before:
            raise ValueError('build inputs or manifest changed during packaging')
        if verify_zip(archive_path, after['exeSha256']) != zip_hash:
            raise ValueError('release ZIP changed during final verification')
    except Exception:
        archive_path.unlink(missing_ok=True)
        output_dir.rmdir()
        raise
    return {'path': str(archive_path), 'zipSha256': zip_hash, **before}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir', type=Path, required=True,
                        help='final build-only dist/build-... directory')
    parser.add_argument('--output-dir', type=Path, required=True,
                        help='new directory for the exact Windows Release asset')
    args = parser.parse_args(argv)
    try:
        result = package(args.build_dir, args.output_dir)
    except (OSError, ValueError, KeyError, json.JSONDecodeError, zipfile.BadZipFile) as exc:
        print(f'PACKAGE_FAIL {exc}')
        return 1
    print(f'PACKAGE_OK asset={result["path"]} version={result["version"]} '
          f'exeSha256={result["exeSha256"]} zipSha256={result["zipSha256"]}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
