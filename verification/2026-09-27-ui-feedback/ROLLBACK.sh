#!/usr/bin/env bash
set -euo pipefail

root="${1:?usage: ROLLBACK.sh TARGET_ROOT}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -d "$root/webui" && -d "$root/tests" ]] || { echo 'TARGET_MISSING'; exit 2; }

paths=(webui/index.html webui/index_built.html tests/rpc_test.cjs)
copies=(original-index.html original-index_built.html original-rpc_test.cjs)
modified=(
  b42c78a16b29ead2e5b90324c06e051d9a2a51b2dbddd776dee869e57f23d542
  8c0c0e4fe76c6b7669cea62f1103e1052cfc3793b353ed0e31f2566edc62b1f3
  ce25fb9569742eb78ebd2cc803cdcae1aaff67248250d361c4126fffed38c222
)
original=(
  f3b47f8160d9fe15fc38bad814056a373b92bf248a17e11c86023312fef97ae9
  4b7933e6b0227937b60118cc302d591904d272fa2becab9752842f9abf495cef
  025adeddefc0dade60c0e6b32dbf144a2d5739f72a8ad54b8e6d5562a7b9b8ac
)
for i in "${!paths[@]}"; do
  current="$(sha256sum "$root/${paths[$i]}" | cut -d' ' -f1)"
  [[ "$current" == "${modified[$i]}" ]] || { echo "HASH_MISMATCH ${paths[$i]} $current"; exit 3; }
  backup="$(sha256sum "$here/${copies[$i]}" | cut -d' ' -f1)"
  [[ "$backup" == "${original[$i]}" ]] || { echo "BACKUP_MISMATCH ${copies[$i]} $backup"; exit 4; }
done
for i in "${!paths[@]}"; do
  cp "$here/${copies[$i]}" "$root/${paths[$i]}"
  result="$(sha256sum "$root/${paths[$i]}" | cut -d' ' -f1)"
  [[ "$result" == "${original[$i]}" ]] || { echo "RESTORE_FAILED ${paths[$i]} $result"; exit 5; }
  echo "RESTORED ${paths[$i]} SHA256=$result"
done
echo ROLLBACK_OK
