#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/scripts/native-managed-lists.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$SCRIPT" ] || fail "native managed list backend missing"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fx-native-managed-lists.XXXXXX")
cleanup(){ rm -rf "$TMP"; }
trap cleanup EXIT HUP INT TERM
MOD="$TMP/module"
PG="$TMP/state"
mkdir -p "$MOD/scripts" "$PG"
printf 'id=privacyguard\n' > "$MOD/module.prop"
cat > "$MOD/scripts/apply.sh" <<'APPLY'
#!/system/bin/sh
set -eu
printf '%s\n' "$1" >> "$APPLY_LOG"
[ "${APPLY_FAIL:-0}" != 1 ]
APPLY
chmod 700 "$MOD/scripts/apply.sh"
cat > "$PG/settings.conf" <<'CONF'
[list:rule]
https://original.example/filter.txt|Original|1
https://disabled.example/filter.txt|Disabled|0

[list:domain]
allow.example|Allow note|1

[list:block]
block.example|Block note|1
CONF
CONF="$PG/settings.conf"
LOCK="$PG/native-managed-lists.lock"
APPLY_LOG="$TMP/apply.log"
export MP="$MOD" PG CONF LOCK APPLY_LOG
run(){ sh "$SCRIPT" "$@"; }

initial=$(run list ruleList)
printf '%s\n' "$initial" | grep -qx 'FXLIST1' || fail "rule list header missing"
printf '%s\n' "$initial" | grep -Fq '0|https://original.example/filter.txt|Original|1' || fail "existing subscription missing"
printf '%s\n' "$initial" | grep -Fq '1|https://disabled.example/filter.txt|Disabled|0' || fail "disabled subscription missing"

added=$(run add ruleList https://new.example/filter.txt New)
printf '%s\n' "$added" | grep -qx 'applied=1' || fail "rule add did not apply"
list=$(run list ruleList)
printf '%s\n' "$list" | grep -Fq '2|https://new.example/filter.txt|New|1' || fail "new subscription missing from list"
if run add ruleList https://new.example/filter.txt Duplicate >/dev/null 2>&1; then
  fail "duplicate subscription was accepted"
else
  rc=$?
  [ "$rc" -eq 3 ] || fail "duplicate returned unexpected status $rc"
fi
if run add ruleList ftp://invalid.example/list Invalid >/dev/null 2>&1; then fail "non-HTTP subscription was accepted"; fi
if run add unknownList value note >/dev/null 2>&1; then fail "unknown list id was accepted"; fi
if run add domainList 'bad|value' note >/dev/null 2>&1; then fail "separator injection was accepted"; fi
if run add blockList "line
break" note >/dev/null 2>&1; then fail "control-character injection was accepted"; fi

run edit ruleList 2 https://edited.example/filter.txt Edited >/dev/null
list=$(run list ruleList)
printf '%s\n' "$list" | grep -Fq '2|https://edited.example/filter.txt|Edited|1' || fail "edit did not persist"
run toggle ruleList 1 1 >/dev/null
list=$(run list ruleList)
printf '%s\n' "$list" | grep -Fq '1|https://disabled.example/filter.txt|Disabled|1' || fail "toggle did not persist"
run delete ruleList 0 >/dev/null
list=$(run list ruleList)
if printf '%s\n' "$list" | grep -Fq 'https://original.example/filter.txt'; then fail "delete did not remove selected row"; fi
printf '%s\n' "$list" | grep -Fq '0|https://disabled.example/filter.txt|Disabled|1' || fail "post-delete indexes were not rebuilt"

run add domainList second.example 'Second allow' >/dev/null
run add blockList second-block.example 'Second block' >/dev/null
printf '%s\n' "$(run list domainList)" | grep -Fq '1|second.example|Second allow|1' || fail "domain allow list add failed"
printf '%s\n' "$(run list blockList)" | grep -Fq '1|second-block.example|Second block|1' || fail "block list add failed"
[ "$(stat -c '%a' "$CONF")" = 600 ] || fail "settings.conf mode is not 0600"
grep -qx 'full' "$APPLY_LOG" || fail "rule mutations did not use full apply"
grep -qx 'fast' "$APPLY_LOG" || fail "domain/block mutations did not use fast apply"
[ ! -e "$LOCK" ] || fail "managed list lock was not released"

before=$(sha256sum "$CONF" | awk '{print $1}')
if APPLY_FAIL=1 run edit ruleList 0 https://rollback.example/filter.txt Rollback 1 >/dev/null 2>&1; then
  fail "apply failure was reported as success"
fi
after=$(sha256sum "$CONF" | awk '{print $1}')
[ "$before" = "$after" ] || fail "failed apply did not restore prior settings.conf"
[ ! -e "$LOCK" ] || fail "lock was not released after rollback"
python3 - "$SCRIPT" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text(encoding="utf-8")
for token in ('umask 077', 'mktemp "$CONF.native-list.XXXXXX"',
              'mktemp "$CONF.native-list-rollback.XXXXXX"',
              'mktemp "$CONF.restore.XXXXXX"', 'trap cleanup EXIT',
              'normalize_domain()', 'normalize_value()', 'value_exists()'):
    assert token in s, f"managed list safety invariant missing: {token}"
assert '$CONF.native-list.$' not in s and '$CONF.restore.$' not in s
print("PASS: managed list backend uses private random temp paths and strict validators")
PY
echo "PASS: native managed lists CRUD, validation, locking, apply modes, rollback and file permissions"
