#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
CONF="$T/settings.conf"
PG="$T"
export CONF PG
cat > "$CONF" <<'CFG'
vpn_node=old-node
vpn_mode=direct
[conf:vpn]
port=1080
CFG
. "$ROOT/scripts/util.sh"
pg_set vpn_node new-node
grep -qx 'vpn_node=new-node' "$CONF"
grep -qx 'vpn_mode=direct' "$CONF"
pg_set dns_forward 1
awk 'BEGIN{ok=0} /^dns_forward=1$/{ok=1} END{exit !ok}' "$CONF"
# Force atomic rename failure. A failed write must return nonzero and preserve source bytes.
cp "$CONF" "$T/before"
mkdir "$CONF.tmp.$$"
if pg_set vpn_node should-not-commit; then
  echo 'FAIL: pg_set reported success when its temporary path could not be replaced' >&2
  exit 1
fi
cmp -s "$T/before" "$CONF" || { echo 'FAIL: failed pg_set modified original settings' >&2; exit 1; }
rmdir "$CONF.tmp.$$"
if pg_set 'bad=key' invalid; then echo 'FAIL: invalid key accepted' >&2; exit 1; fi
cmp -s "$T/before" "$CONF" || { echo 'FAIL: invalid key modified settings' >&2; exit 1; }
echo 'FX pg_set atomic commit/failure propagation regression: PASS'
