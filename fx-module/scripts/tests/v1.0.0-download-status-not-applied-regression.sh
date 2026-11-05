#!/system/bin/sh
# A successful fetch must not be reported as an applied/effective rule.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
sh "$ROOT/scripts/tests/v1.0.0-rule-status-after-parse-regression.sh"
python3 - "$ROOT/scripts/apply.sh" <<'PY'
import sys
s=open(sys.argv[1], encoding='utf-8').read()
assert '最终系统应用/实际拦截尚未确认' in s, 'final application must remain explicitly unverified'
assert 'record rule "$_entry" ok "" "$_n_lines 行"' not in s, 'premature ok status remains'
PY
echo 'PASS: download/parse status is not mislabeled as applied/effective'
