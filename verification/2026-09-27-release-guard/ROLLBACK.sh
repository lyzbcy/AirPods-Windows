#!/usr/bin/env bash
set -euo pipefail

base='verification/2026-09-27-release-guard'
target="$base/rollback-test-copy"
if [[ "${1:-}" != "$target" ]]; then
  echo 'ROLLBACK_TARGET_REJECTED' >&2
  exit 2
fi

# Build only this disposable target from the still-modified workspace.
mkdir -p "$target/tests" "$target/scripts" "$target/doc"
cp tests/strict_gate.py "$target/tests/strict_gate.py"
cp tests/run_suite.py "$target/tests/run_suite.py"
cp scripts/release-precheck.py "$target/scripts/release-precheck.py"
cp tests/release_precheck_test.py "$target/tests/release_precheck_test.py"
cp doc/04-项目进度.md "$target/doc/04-项目进度.md"
cp doc/08-更新与后台任务.md "$target/doc/08-更新与后台任务.md"
cp CHANGELOG.md "$target/CHANGELOG.md"
cp .gitattributes "$target/.gitattributes"

check() {
  local file="$1" expected="$2" actual
  actual=$(sha256sum "$file" | cut -d' ' -f1)
  if [[ "${actual^^}" != "$expected" ]]; then
    echo "ROLLBACK_INPUT_HASH_MISMATCH $file" >&2
    exit 3
  fi
}

check "$target/tests/strict_gate.py" 066BD831AF24C5CCED45C93BD4E9AE91BE5B45F8CF3CFC82657390724EC20F7B
check "$target/tests/run_suite.py" 4D0267191C8A075D3092FED635B3A0768F2ED5892128885D196D03D94465BC8F
check "$target/scripts/release-precheck.py" 28D94180582FC982987311F9C5AFC5FB80052FA5A307A1F1A8637B12CE3FCC49
check "$target/tests/release_precheck_test.py" ACDA8F3930CAD2D513699923D857119567F6003666B743D319A28C441E4F8B49
check "$target/doc/04-项目进度.md" 5237B26C2933EB28DC71463A80502ECF2B91FF3AA3F61077C01A737E6F1398D1
check "$target/doc/08-更新与后台任务.md" 0797A8AB01837D7427FD18C0CFC6CF5A468F6388B10EF7505708E490033A1EDF
check "$target/CHANGELOG.md" AB675659BA65F670F64BF74CFBA78A428BB8EE3ECFAB3CD504D45780FA7708BC
check "$target/.gitattributes" 5BBB7B98B16DC39CC0399BFDA40D4AFCD71FFB3CA549ED21BF39D59C152F6635

cp "$base/original/strict_gate.py" "$target/tests/strict_gate.py"
cp "$base/original/run_suite.py" "$target/tests/run_suite.py"
cp "$base/original/04-项目进度.md" "$target/doc/04-项目进度.md"
cp "$base/original/08-更新与后台任务.md" "$target/doc/08-更新与后台任务.md"
cp "$base/original/CHANGELOG.md" "$target/CHANGELOG.md"
rm "$target/scripts/release-precheck.py" "$target/tests/release_precheck_test.py"
rm "$target/.gitattributes"

check "$target/tests/strict_gate.py" 54EE20FBA471343C64DEAC5FE37A165EFBEBFF886254A6DED861281CA50605B8
check "$target/tests/run_suite.py" 5FA693A6D3A23D927C6218C40B93CD9C4DBB4BC0AAAD97E8133FF615D991B11F
check "$target/doc/04-项目进度.md" 055D33E2F91F55931F293930D20C3FBDB92BC4B290C66E69D1E1FB87FADED9F9
check "$target/doc/08-更新与后台任务.md" 66350CFE7E71C6B71DF2CF4E35242E48B175B19911ECEFB7A3526EC4102509FD
check "$target/CHANGELOG.md" C1C0C47679FC4E35ADDB6460EEAE48DAF3259ACA913857B69C0632F4BA32CFCA
[[ ! -e "$target/scripts/release-precheck.py" && ! -e "$target/tests/release_precheck_test.py" && ! -e "$target/.gitattributes" ]]
echo 'ROLLBACK_OK original_sha256=54EE20FBA471343C64DEAC5FE37A165EFBEBFF886254A6DED861281CA50605B8'
