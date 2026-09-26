#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo 'usage: ROLLBACK.sh TARGET_DIRECTORY' >&2
  exit 2
fi
evidence="$(cd "$(dirname "$0")" && pwd -P)"
target="$(cd "$1" && pwd -P)"
hashes="$evidence/rollback-hashes.tsv"
hash_file() {
  sha256sum "$1" | awk '{print toupper($1)}'
}

# Reject unknown target contents before changing any file.
while IFS=$'\t' read -r relative modified original; do
  current="$target/$relative"
  if [[ ! -f "$current" || "$(hash_file "$current")" != "$modified" ]]; then
    echo "ROLLBACK_REFUSED modified hash differs: $relative" >&2
    exit 1
  fi
  if [[ "$original" != 'ABSENT' ]]; then
    baseline="$evidence/original/$relative"
    if [[ ! -f "$baseline" || "$(hash_file "$baseline")" != "$original" ]]; then
      echo "ROLLBACK_REFUSED baseline hash differs: $relative" >&2
      exit 1
    fi
  fi
done < "$hashes"

while IFS=$'\t' read -r relative modified original; do
  current="$target/$relative"
  if [[ "$original" == 'ABSENT' ]]; then
    rm -- "$current"
    [[ ! -e "$current" ]]
  else
    cp -- "$evidence/original/$relative" "$current"
    [[ "$(hash_file "$current")" == "$original" ]]
  fi
done < "$hashes"
echo "ROLLBACK_OK original_sha256=$(hash_file "$target/tests/run_suite.py") new_files_removed=true"
