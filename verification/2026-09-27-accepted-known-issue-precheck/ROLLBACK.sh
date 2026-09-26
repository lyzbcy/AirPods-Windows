#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"
TARGET_ROOT="${1:-$ROOT}"
FILES=(scripts/release-precheck.py tests/release_precheck_test.py)
MODIFIED=(b6d6ca47831a96790bc26f64e3a723cfebe46c7bcdc1e1a46914e339a796f16e 0bb7379a5998c79f83999787bb54c5f3e434f40c07d4e460f4e293b2a73bbf09)
ORIGINAL=(2a2e3bab8a11d1d0ee6dbd1846fe386ebf6ecb6bfe9ff56867d8f2b65fcb8843 5c9a5327bb86cdf55410f42b38f7087faaba62ab8ecd68d3304d9ae972455f34)

hash_file() { sha256sum -- "$1" | cut -d ' ' -f 1; }

for i in 0 1; do
    target="$TARGET_ROOT/${FILES[$i]}"
    [[ -f "$target" ]] || { echo "ROLLBACK_ERROR missing_target=$target" >&2; exit 2; }
    [[ "$(hash_file "$target")" == "${MODIFIED[$i]}" ]] || {
        echo "ROLLBACK_ERROR modified_hash_mismatch target=$target" >&2; exit 3;
    }
    stored="$(unzip -p "$SCRIPT_DIR/ORIGINAL_FILE" "${FILES[$i]}" | sha256sum | cut -d ' ' -f 1)"
    [[ "$stored" == "${ORIGINAL[$i]}" ]] || {
        echo "ROLLBACK_ERROR original_hash_mismatch file=${FILES[$i]}" >&2; exit 4;
    }
done

for i in 0 1; do
    target="$TARGET_ROOT/${FILES[$i]}"
    unzip -p "$SCRIPT_DIR/ORIGINAL_FILE" "${FILES[$i]}" > "$target"
    [[ "$(hash_file "$target")" == "${ORIGINAL[$i]}" ]] || {
        echo "ROLLBACK_ERROR restore_hash_mismatch target=$target" >&2; exit 5;
    }
    echo "ROLLBACK_OK file=${FILES[$i]} restored_sha256=${ORIGINAL[$i]}"
done
