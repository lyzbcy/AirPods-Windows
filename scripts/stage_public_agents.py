"""Stage the public AGENTS.md so the owner's local working notes are never committed.

The repository is public. AGENTS.md exists in two forms: a short public guide (committed) and
the owner's full working copy (local only). Run this before committing instead of letting
`git add -A` pick up the working copy. It stages the guide as committed in HEAD, refuses when
HEAD does not carry the public guide, and never touches the working file.

Usage: python scripts/stage_public_agents.py
"""
from pathlib import Path
import subprocess, sys

MARKER = '# AirPods Buddy development guide'
root = Path(__file__).resolve().parents[1]


def git(*args, data=None):
    return subprocess.run(['git', *args], cwd=root, input=data, capture_output=True, check=False)


head = git('show', 'HEAD:AGENTS.md')
if head.returncode or MARKER.encode() not in head.stdout:
    sys.exit('HEAD does not carry the public guide; refusing to stage AGENTS.md')
blob = git('hash-object', '-w', '--stdin', data=head.stdout)
if blob.returncode:
    sys.exit('could not write the public guide blob: ' + blob.stderr.decode('utf-8', 'replace'))
if git('update-index', '--cacheinfo', '100644,' + blob.stdout.decode().strip() + ',AGENTS.md').returncode:
    sys.exit('could not stage the public guide')
print('staged public AGENTS.md from HEAD; the working copy is left untouched')
