#!/usr/bin/env bash
set -euo pipefail

# Apply only to an explicit separate copy, never to the live source by default.
target=${1:?usage: ROLLBACK.sh SEPARATE_COPY_PATH}
source='verification/2026-09-27-feedback-consent/ORIGINAL_FILE'
case "$target" in
  verification/2026-09-27-feedback-consent/rollback-copy/*) ;;
  *) echo 'ROLLBACK_REFUSED target must be a separate rollback-copy file'; exit 2 ;;
esac
cp "$source" "$target"
cmp -s "$source" "$target"
echo 'ROLLBACK_OK copy restored to original source bytes'
