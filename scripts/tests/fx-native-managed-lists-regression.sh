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

# A symlink at PG must be rejected before settings or lock files are touched.
mkdir "$TMP/external-state"
cp "$CONF" "$TMP/external-state/settings.conf"
ln -s "$TMP/external-state" "$TMP/state-link"
if env MP="$MOD" PG="$TMP/state-link" CONF="$TMP/state-link/settings.conf" \
    LOCK="$TMP/state-link/native-managed-lists.lock" sh "$SCRIPT" list ruleList >/dev/null 2>&1; then
  fail "symlinked state directory was accepted"
fi
cmp -s "$CONF" "$TMP/external-state/settings.conf" || fail "symlinked state directory changed external settings"
[ ! -e "$TMP/external-state/native-managed-lists.lock" ] || fail "symlinked state directory created an outside lock"
rm "$TMP/state-link"

# Reject symlinked ancestors, not only a symlink at the final PG component.
mkdir "$TMP/real-parent"
ln -s "$TMP/real-parent" "$TMP/parent-link"
if env MP="$MOD" PG="$TMP/parent-link/state" CONF="$TMP/parent-link/state/settings.conf" \
    LOCK="$TMP/parent-link/state/native-managed-lists.lock" sh "$SCRIPT" list ruleList >/dev/null 2>&1; then
  fail "state below a symlinked parent was accepted"
fi
[ ! -e "$TMP/real-parent/state" ] || fail "symlinked parent created an external state directory"
rm "$TMP/parent-link"

# Environment overrides must not redirect settings or lock writes outside PG.
if env MP="$MOD" PG="$PG" CONF="$TMP/outside-settings.conf" LOCK="$LOCK" sh "$SCRIPT" list ruleList >/dev/null 2>&1; then
  fail "external CONF override was accepted"
fi
if env MP="$MOD" PG="$PG" CONF="$CONF" LOCK="$TMP/outside-lock" sh "$SCRIPT" list ruleList >/dev/null 2>&1; then
  fail "external LOCK override was accepted"
fi
[ ! -e "$TMP/outside-settings.conf" ] && [ ! -e "$TMP/outside-lock" ] || fail "rejected path overrides created external files"
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

# A live owner must remain in place and must block writes without touching user data.
printf '%s\n' "$PPID" > "$LOCK"
before_live=$(sha256sum "$CONF" | awk '{print $1}')
if FX_MANAGED_LIST_LOCK_RETRIES=1 run add domainList live-lock.example 'Must wait' >/dev/null 2>&1; then
  fail "live PID lock was accepted"
else
  rc=$?
  [ "$rc" -eq 10 ] || fail "live PID lock returned unexpected status $rc"
fi
[ "$(cat "$LOCK")" = "$PPID" ] || fail "live PID lock was removed or changed"
after_live=$(sha256sum "$CONF" | awk '{print $1}')
[ "$before_live" = "$after_live" ] || fail "live PID lock rejection changed settings.conf"
rm "$LOCK"

# An ownerless legacy mkdir lock is ambiguous: preserve it rather than guessing it is stale.
mkdir "$LOCK"
if FX_MANAGED_LIST_LOCK_RETRIES=1 run add domainList legacy-lock.example 'Must wait' >/dev/null 2>&1; then
  fail "ownerless legacy lock was accepted"
else
  rc=$?
  [ "$rc" -eq 10 ] || fail "ownerless legacy lock returned unexpected status $rc"
fi
[ -d "$LOCK" ] || fail "ownerless legacy lock was removed"
rmdir "$LOCK"

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
# Competing writers must serialize; neither successful update may overwrite the other.
run add domainList parallel-a.example 'Parallel A' &
parallel_a_pid=$!
run add blockList parallel-b.example 'Parallel B' &
parallel_b_pid=$!
if ! wait "$parallel_a_pid"; then fail "first concurrent managed-list writer failed"; fi
if ! wait "$parallel_b_pid"; then fail "second concurrent managed-list writer failed"; fi
printf '%s\n' "$(run list domainList)" | grep -Fq 'parallel-a.example|Parallel A|1' || fail "first concurrent update was lost"
printf '%s\n' "$(run list blockList)" | grep -Fq 'parallel-b.example|Parallel B|1' || fail "second concurrent update was lost"

python3 - "$SCRIPT" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text(encoding="utf-8")
for token in ('umask 077', 'set -C', '_nl_read_lock_owner()', '_nl_unlock()',
              "IFS=' ' read -r _nl_lock_pid _nl_rest < /proc/self/stat",
              'printf \'%s\\n\' "$_nl_lock_pid" > "$LOCK"',
              '_nl_lock_pid', 'kill -0', '.stale.$_nl_lock_pid.', 'legacy ownerless managed-list lock',
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
python3 - "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" <<'PY'
from pathlib import Path
import sys

activity = Path(sys.argv[1]).read_text(encoding="utf-8")
start = activity.index("private void writeHostsPage(")
end = activity.index("private void applyNativeHosts()", start)
writer = activity[start:end]
# MainActivity embeds the shell program inside Java string literals. Decode
# Java's escaped double quotes before checking the actual shell command.
writer = writer.replace(chr(92) + '"', '"')
for token in (
    "for path in /data /data/local /data/local/tmp; do",
    '[ -d "$path" ] && [ ! -L "$path" ]',
    "umask 077;",
    "mktemp /data/local/tmp/fx-hosts.XXXXXXXX",
    """trap 'rm -f "$tmp"' EXIT;""",
    'if [ ! -f "$tmp" ] || [ -L "$tmp" ]; then',
    "shellQuote(encoded)",
    'base64 -d > "$tmp" || exit 42;',
    "fileedit.sh",
    "replacepage",
):
    assert token in writer, f"Hosts page save temp-path invariant missing: {token}"
ordered = (
    writer.index("for path in /data /data/local /data/local/tmp; do"),
    writer.index("umask 077;"),
    writer.index("mktemp /data/local/tmp/fx-hosts.XXXXXXXX"),
    writer.index("""trap 'rm -f "$tmp"' EXIT;"""),
    writer.index('base64 -d > "$tmp"'),
    writer.index("replacepage"),
)
assert ordered == tuple(sorted(ordered)), \
    "Hosts page save must validate parent paths before creating and using its private temp file"
print("PASS: Hosts page save rejects symlinked temp parents and uses a private, checked temporary file")
PY
echo "PASS: native managed lists CRUD, validation, locking, apply modes, rollback and file permissions"
