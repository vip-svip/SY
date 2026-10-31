#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MODULE=${1:-$ROOT/fx-module}
HTML="$MODULE/webroot/index.html"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$HTML" ] || fail "FX WebUI missing"
[ "$(grep -o 'id="cardFxAdHook"' "$HTML" | wc -l | tr -d ' ')" = 1 ] || fail "must have exactly one Hook management card"
! grep -q 'privacyHookMasterCard' "$HTML" || fail "old separate privacy Hook card remains"
python3 - "$HTML" <<'PY2'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text(encoding="utf-8")
privacy = s.index('id="pagePrivacy"')
scripts = s.index('id="pageScript"')
card = s.index('<div class="card fxah-card" id="cardFxAdHook">')
assert privacy < card < scripts, "unified Hook card must be on the Privacy page"
for token in ('data-key="lsposed_enabled"', 'id="fxHookMaster"',
              'id="fxHookPrivacyMaster"', 'id="fxHookManage"', 'id="fxHookSync"'):
    assert s.count(token) == 1, f"missing/duplicate Hook control: {token}"
assert '统一应用内 Hook 管理' in s
assert 'FX Hook 模块' in s
assert 'PrivacyGuardHook' not in s
PY2
echo "PASS: one FX UI card contains privacy, ad, target-selection and sync controls"
