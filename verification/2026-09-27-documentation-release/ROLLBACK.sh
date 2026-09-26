#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
target="${1:?usage: ROLLBACK.sh TARGET_COPY_ROOT}"
target="$(cd "$target" && pwd)"
for file in README.md CHANGELOG.md SKILL.md AGENTS.md doc/04-项目进度.md doc/07-审计修复清单.md doc/08-更新与后台任务.md doc/09-Windows连接方案选型.md; do
  mkdir -p "$target/$(dirname "$file")"
  cp "$here/original/$file" "$target/$file"
done
rm -f "$target/RELEASE_NOTES_v1.9.20.md"
echo 'ROLLBACK_OK documentation restored from original copies'
