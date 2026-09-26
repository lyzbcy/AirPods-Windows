#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
target="${1:?usage: ROLLBACK.sh TARGET_COPY}"
cmp -s "$target" "$script_dir/MODIFIED_FILE.py"
cp "$script_dir/ORIGINAL_FILE.py" "$target"
cmp -s "$target" "$script_dir/ORIGINAL_FILE.py"
echo "ROLLBACK_OK source=original live_audio_extractor_suite=absent"
