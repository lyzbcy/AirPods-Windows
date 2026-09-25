#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
  echo "usage: ROLLBACK.sh TARGET_FILE" >&2
  exit 2
fi
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cp -- "$here/ORIGINAL_FILE.ahk" "$1"
cmp -- "$here/ORIGINAL_FILE.ahk" "$1"
echo "restored original bytes"
