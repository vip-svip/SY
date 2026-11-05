#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
grep -Fq 'vpn-auto-update.sh' "$ROOT/service.sh"
! grep -Fq 'echo "$_pg_now" > "$_pg_stamp"' "$ROOT/service.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-autoupdate-stamp.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
MOD="$T/module"; PG="$T/state"; TOOLS="$T/tools"
mkdir -p "$MOD/scripts" "$PG" "$TOOLS"
: > "$MOD/module.prop"
cp "$ROOT/scripts/vpn-auto-update.sh" "$MOD/scripts/vpn-auto-update.sh"
cat > "$MOD/scripts/apply.sh" <<'APPLY'
#!/bin/sh
[ "${1:-}" = vpn-sub ] || exit 64
n=0; [ ! -f "$CALLS" ] || n=$(cat "$CALLS")
n=$((n+1)); printf '%s\n' "$n" > "$CALLS"
exit "${MOCK_APPLY_RC:-0}"
APPLY
chmod 755 "$MOD/scripts/apply.sh" "$MOD/scripts/vpn-auto-update.sh"
cat > "$TOOLS/date" <<'DATE'
#!/bin/sh
if [ "${1:-}" = +%s ]; then printf '%s\n' "$TEST_NOW"; else exec /bin/date "$@"; fi
DATE
chmod 755 "$TOOLS/date"
export CALLS="$T/calls" TEST_NOW=100000 PATH="$TOOLS:$PATH"
cat > "$PG/settings.conf" <<'CONF'
vpn_auto_update=1
[conf:vpn]
auto_update_h=0001
CONF
# First boot update fails: must not create/update the last-success stamp.
MOCK_APPLY_RC=7 sh "$MOD/scripts/vpn-auto-update.sh" "$MOD" "$PG" > "$T/failed1.log"
[ ! -f "$PG/vpn-sub-last" ]
grep -Fq 'previous success stamp preserved for retry' "$T/failed1.log"
# Retry at the exact same clock must execute again and commit stamp only on success.
MOCK_APPLY_RC=0 sh "$MOD/scripts/vpn-auto-update.sh" "$MOD" "$PG" > "$T/success1.log"
[ "$(cat "$PG/vpn-sub-last")" = 100000 ]
[ "$(cat "$CALLS")" = 2 ]
# A successful stamp suppresses another update within the configured interval.
MOCK_APPLY_RC=0 sh "$MOD/scripts/vpn-auto-update.sh" "$MOD" "$PG" > "$T/skip.log"
[ "$(cat "$CALLS")" = 2 ]
# At the next due time, failed refresh must preserve the last successful stamp.
TEST_NOW=103601; export TEST_NOW
MOCK_APPLY_RC=9 sh "$MOD/scripts/vpn-auto-update.sh" "$MOD" "$PG" > "$T/failed2.log"
[ "$(cat "$PG/vpn-sub-last")" = 100000 ]
[ "$(cat "$CALLS")" = 3 ]
# And the failed due update is retried immediately on a later service invocation.
MOCK_APPLY_RC=0 sh "$MOD/scripts/vpn-auto-update.sh" "$MOD" "$PG" > "$T/success2.log"
[ "$(cat "$PG/vpn-sub-last")" = 103601 ]
[ "$(cat "$CALLS")" = 4 ]
echo 'PASS: service uses tested updater; failed VPN subscription updates do not advance success stamp; retries are not delayed; leading-zero interval is safe'
