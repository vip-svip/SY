#!/system/bin/sh
# Host regression: failed apply restores the last-known-good whitelist config.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=${TMPDIR:-/tmp}/fx-whitelist-apply-rollback-$$
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/module/scripts" "$TMP/state"
cp "$ROOT/scripts/whitelist.sh" "$TMP/module/scripts/whitelist.sh"
CONF="$TMP/state/settings.conf"
cat > "$CONF" <<'CFG'
[general]
mode|test|1
[list:domain]
old.example|baseline|1
CFG
cp "$CONF" "$CONF.whitelist.previous"
cat > "$TMP/module/scripts/apply.sh" <<'APPLY'
#!/bin/sh
n=0
[ ! -f "$COUNTER" ] || n=$(cat "$COUNTER")
n=$((n+1)); echo "$n" > "$COUNTER"
[ "$n" -ge 2 ]
APPLY
chmod +x "$TMP/module/scripts/apply.sh"
COUNTER="$TMP/state/counter"
export COUNTER
# Inject test config path without touching real device paths.
set +e
PG="$TMP/state" CONF="$CONF" sh "$TMP/module/scripts/whitelist.sh" add new.example test >/dev/null 2>&1
add_rc=$?
set -e
[ "$add_rc" -eq 0 ] || { echo 'FAIL: setup add failed' >&2; exit 1; }
# First apply fails; second apply during rollback succeeds.
set +e
PG="$TMP/state" CONF="$CONF" sh "$TMP/module/scripts/whitelist.sh" apply >/dev/null 2>&1
apply_rc=$?
set -e
[ "$apply_rc" -ne 0 ] || { echo 'FAIL: expected initial apply failure' >&2; exit 1; }
grep -q '^old.example|baseline|1$' "$CONF" || { echo 'FAIL: baseline config not restored' >&2; exit 1; }
! grep -q '^new.example|' "$CONF" || { echo 'FAIL: failed whitelist entry remained active' >&2; exit 1; }
[ "$(cat "$COUNTER")" = 2 ] || { echo 'FAIL: expected expected apply + rollback apply count mismatch' >&2; exit 1; }
echo 'PASS: failed apply restores baseline config and retries apply with restored settings'
