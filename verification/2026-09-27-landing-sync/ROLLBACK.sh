#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo 'usage: ROLLBACK.sh PAGE_TARGET SKILL_TARGET AGENTS_TARGET RUNBOOK_TARGET' >&2
  exit 2
fi

here="$(cd "$(dirname "$0")" && pwd)"
sources=(
  "$here/original/airpods-buddy.html"
  "$here/original/SKILL.md"
  "$here/original/AGENTS.md"
  "$here/original/08-更新与后台任务.md"
)
targets=("$1" "$2" "$3" "$4")

for i in 0 1 2 3; do
  cp -- "${sources[$i]}" "${targets[$i]}"
  if ! cmp -s -- "${sources[$i]}" "${targets[$i]}"; then
    echo "ROLLBACK_MISMATCH index=$i" >&2
    exit 1
  fi
done

echo 'ROLLBACK_PASS files=4 hashes=restored'
