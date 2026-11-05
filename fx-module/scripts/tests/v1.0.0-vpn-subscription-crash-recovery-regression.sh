#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
PG="$T/state"
CONF="$PG/settings.conf"
export PG CONF
mkdir -p "$PG/cache" "$PG/backup"
pg_log() { :; }
pg_fail() { printf '%s\n' "$*" >&2; return 1; }
. "$ROOT/scripts/util.sh"
. "$ROOT/scripts/vpnsub.sh"
cat > "$CONF" <<'CFG'
vpn_node=old-node
vpn_mode=direct
[list:vpn_node]
old-node-uri|Old node|1
[conf:vpn]
port=1080
CFG
cp -p "$CONF" "$PG/backup/settings.conf.crash-test"
# Simulate SIGKILL after candidate settings.conf and selected node were both replaced,
# but before the transaction journal could be cleared.
cat > "$CONF" <<'CFG'
vpn_node=new-node
vpn_mode=global
[list:vpn_node]
new-node-uri|New node|1
[conf:vpn]
port=1080
CFG
printf '%s\n' "$PG/backup/settings.conf.crash-test" > "$PG/cache/vpn-update.transaction"
vpn_recover_subs_transaction
cmp -s "$CONF" "$PG/backup/settings.conf.crash-test" || { echo 'FAIL: crash recovery did not restore exact pre-transaction snapshot' >&2; exit 1; }
[ ! -e "$PG/cache/vpn-update.transaction" ] || { echo 'FAIL: successful recovery left journal behind' >&2; exit 1; }
# Unknown/out-of-scope backup path must fail closed and retain the journal.
printf '%s\n' "$T/untrusted-backup" > "$PG/cache/vpn-update.transaction"
if vpn_recover_subs_transaction; then echo 'FAIL: invalid journal path was accepted' >&2; exit 1; fi
[ -e "$PG/cache/vpn-update.transaction" ] || { echo 'FAIL: invalid journal was deleted' >&2; exit 1; }
# A prefix-shaped path containing traversal components must not be accepted.
printf '%s\n' "$PG/backup/settings.conf.fake/../../outside" > "$PG/cache/vpn-update.transaction"
if vpn_recover_subs_transaction; then echo 'FAIL: traversal backup path was accepted' >&2; exit 1; fi
[ -e "$PG/cache/vpn-update.transaction" ] || { echo 'FAIL: traversal journal was deleted' >&2; exit 1; }
# Appended journal records are ambiguous and must fail closed.
printf '%s\n%s\n' "$PG/backup/settings.conf.crash-test" "$T/extra" > "$PG/cache/vpn-update.transaction"
if vpn_recover_subs_transaction; then echo 'FAIL: multi-line journal was accepted' >&2; exit 1; fi
[ -e "$PG/cache/vpn-update.transaction" ] || { echo 'FAIL: malformed journal was deleted' >&2; exit 1; }
echo 'FX subscription crash-recovery regression: PASS'
