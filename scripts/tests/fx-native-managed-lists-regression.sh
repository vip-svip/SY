#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/scripts/native-managed-lists.sh"
PACKAGED="$ROOT/fx-module/scripts/native-managed-lists.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$SCRIPT" ] || fail "native managed list backend missing"
[ -s "$PACKAGED" ] || fail "packaged managed list backend missing"
cmp -s "$SCRIPT" "$PACKAGED" || fail "packaged managed list backend is stale"
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

# Legacy duplicate section emitted by older append-only code.
[list:rule]
https://legacy.example/filter.txt|Legacy second section|1
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

# A stale PID-bearing lock must be reclaimed before the first mutation.
printf '999999999\n' > "$LOCK"
added=$(run add ruleList https://new.example/filter.txt New)
printf '%s\n' "$added" | grep -qx 'applied=1' || fail "rule add did not apply after stale lock recovery"
[ ! -e "$LOCK" ] || fail "stale lock was not reclaimed and released"
list=$(run list ruleList)
printf '%s\n' "$list" | grep -Fq '3|https://new.example/filter.txt|New|1' || fail "new subscription missing from list"
[ "$(printf '%s\n' "$list" | grep -F -c 'https://new.example/filter.txt')" -eq 1 ] || fail "new subscription was inserted more than once across repeated sections"
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
break" note >/dev/null 2>&1; then fail "control-character value was accepted"; fi
if run add blockList good-note.example "line
break" >/dev/null 2>&1; then fail "newline in note was accepted"; fi
if run add domainList "trailing-newline.example
" note >/dev/null 2>&1; then fail "trailing newline in domain was accepted"; fi
if run add domainList backslash.example 'literal\x0a payload' >/dev/null 2>&1; then fail "AWK escape in note was accepted"; fi

before_invalid_edit=$(sha256sum "$CONF" | awk '{print $1}')
if run edit ruleList 3 ftp://invalid.example/filter.txt Invalid 1 >/dev/null 2>&1; then
  fail "non-HTTP subscription edit was accepted"
fi
after_invalid_edit=$(sha256sum "$CONF" | awk '{print $1}')
[ "$before_invalid_edit" = "$after_invalid_edit" ] || fail "invalid subscription edit changed settings.conf"

run edit ruleList 3 https://edited.example/filter.txt Edited 1 >/dev/null
list=$(run list ruleList)
printf '%s\n' "$list" | grep -Fq '3|https://edited.example/filter.txt|Edited|1' || fail "edit did not persist at its stable index across legacy duplicate sections"
run toggle ruleList 1 1 >/dev/null
list=$(run list ruleList)
printf '%s\n' "$list" | grep -Fq '1|https://disabled.example/filter.txt|Disabled|1' || fail "toggle did not persist"
run delete ruleList 0 >/dev/null
list=$(run list ruleList)
if printf '%s\n' "$list" | grep -Fq 'https://original.example/filter.txt'; then fail "delete did not remove selected row"; fi
printf '%s\n' "$list" | grep -Fq '0|https://disabled.example/filter.txt|Disabled|1' || fail "post-delete indexes were not rebuilt"

# A lock-path symlink is rejected without touching its target or user data.
outside_lock_target="$TMP/outside-lock-target"
printf 'external lock data\n' > "$outside_lock_target"
before_symlink=$(sha256sum "$CONF" | awk '{print $1}')
ln -s "$outside_lock_target" "$LOCK"
if run add domainList symlink.example 'Must not write' >/dev/null 2>&1; then
  fail "symbolic-link lock path was accepted"
fi
[ -L "$LOCK" ] || fail "symbolic-link lock path was replaced"
[ "$(cat "$outside_lock_target")" = 'external lock data' ] || fail "symbolic-link target was modified"
after_symlink=$(sha256sum "$CONF" | awk '{print $1}')
[ "$before_symlink" = "$after_symlink" ] || fail "symlink lock rejection changed settings.conf"
rm "$LOCK"

run add domainList second.example 'Second allow' >/dev/null
run add blockList second-block.example 'Second block' >/dev/null
printf '%s\n' "$(run list domainList)" | grep -Fq '1|second.example|Second allow|1' || fail "domain allow list add failed"
printf '%s\n' "$(run list blockList)" | grep -Fq '1|second-block.example|Second block|1' || fail "block list add failed"
[ "$(stat -c '%a' "$CONF")" = 600 ] || fail "settings.conf mode is not 0600"
grep -qx 'full' "$APPLY_LOG" || fail "rule mutations did not use full apply"
grep -qx 'fast' "$APPLY_LOG" || fail "domain/block mutations did not use fast apply"
[ "$(stat -c '%a' "$CONF")" = 600 ] || fail "settings.conf mode is not 0600"
[ ! -e "$LOCK" ] || fail "managed list lock was not released"
find "$PG" -maxdepth 1 -type f -name 'settings.conf.native-list.*' -print | grep -q . && fail "random candidate temp file was not cleaned"
find "$PG" -maxdepth 1 -type f -name 'settings.conf.native-list-rollback.*' -print | grep -q . && fail "random rollback file was not cleaned"

before=$(sha256sum "$CONF" | awk '{print $1}')
if APPLY_FAIL=1 run edit ruleList 0 https://rollback.example/filter.txt Rollback 1 >/dev/null 2>&1; then
  fail "apply failure was reported as success"
fi
after=$(sha256sum "$CONF" | awk '{print $1}')
[ "$before" = "$after" ] || fail "failed apply did not restore prior settings.conf"
[ ! -e "$LOCK" ] || fail "lock was not released after rollback"
tail -n 1 "$APPLY_LOG" | grep -qx full || fail "rule rollback did not reconcile with full apply"
run apply >/dev/null
tail -n 1 "$APPLY_LOG" | grep -qx full || fail "default apply command did not select full mode"
run apply fast >/dev/null
tail -n 1 "$APPLY_LOG" | grep -qx fast || fail "explicit fast apply command did not select fast mode"
python3 - "$SCRIPT" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text(encoding="utf-8")
for token in ('umask 077', 'set -C', '_nl_read_lock_owner()', '_nl_unlock()',
              'kill -0', '.stale.$$.', 'legacy ownerless managed-list lock',
              'refusing to follow it', 'trap cleanup EXIT',
              'normalize_domain()', 'normalize_value()', 'value_exists()'):
    assert token in s, f"managed list safety invariant missing: {token}"
assert '$CONF.native-list.$' not in s and '$CONF.restore.$' not in s
print("PASS: managed list backend uses atomic PID lock, stale-owner recovery and strict validators")
PY
python3 - "$SCRIPT" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
normalize = source.split("normalize_value() {", 1)[1].split("\nlist_rows() {", 1)[0]
assert "grep -Eq" in normalize, "URL subscription validation is missing"
assert 'printf \'%s\\n\' "$raw"' in normalize, "validated URL must be returned to the caller"
assert "lines=$(printf '%s' \"$1\" | wc -l" in source, "literal LF must be rejected by a portable line-count check"
print("PASS: managed list normalizer returns URLs and rejects LF/control separators")
PY
echo "PASS: native managed lists CRUD, validation, locking, apply modes, rollback and file permissions"
