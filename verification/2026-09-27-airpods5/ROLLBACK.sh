#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source_file="$source_dir/ORIGINAL_FILE.ahk"
target_file="${1:?usage: ROLLBACK.sh TARGET_FILE}"
original_hash=93910b72b164e7ca95f4f3dc98133274d82cbc61e035162415e57710585a3745
modified_hash=ea411aefbd0eae77da558deb7a37b092bd8ba0b8ed5ed0ba133d558e22baf8ee

hash_of() {
    sha256sum -- "$1" | cut -d ' ' -f 1
}

[[ -f "$source_file" && -f "$target_file" ]] || { echo 'ROLLBACK_MISSING_FILE'; exit 2; }
[[ "$(hash_of "$source_file")" == "$original_hash" ]] || { echo 'ROLLBACK_ORIGINAL_HASH_MISMATCH'; exit 3; }
[[ "$(hash_of "$target_file")" == "$modified_hash" ]] || { echo 'ROLLBACK_TARGET_HASH_MISMATCH'; exit 4; }
cp -- "$source_file" "$target_file"
[[ "$(hash_of "$target_file")" == "$original_hash" ]] || { echo 'ROLLBACK_RESTORE_HASH_MISMATCH'; exit 5; }
echo "ROLLBACK_OK sha256=$original_hash"
