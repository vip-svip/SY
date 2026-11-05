#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
S="$ROOT/scripts/vpnsub.sh"
sh -n "$S"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/mod/scripts" "$T/pg"
cp "$ROOT/scripts/default.conf" "$T/mod/scripts/default.conf"
cat > "$T/pg/settings.conf" <<'CONF'
# damaged legacy config: top-level skeleton missing
[list:vpn_node]
vless://id@edge.example:443#Tokyo|Tokyo|1
[custom:my_rules]
example.org|Example|1
[custom:my_flags]
my_toggle=1
CONF
cat > "$T/run.sh" <<'RUN'
#!/system/bin/sh
set -eu
MODDIR="$MODROOT"
PG="$PGROOT"
CONF="$PG/settings.conf"
pg_log() { :; }
pg_fail() { echo "$*" >&2; }
. "$VPNSUB"
vpn_repair_conf
RUN
chmod 755 "$T/run.sh"
MODROOT="$T/mod" PGROOT="$T/pg" VPNSUB="$S" sh "$T/run.sh"
F="$T/pg/settings.conf"
grep -q '^vpn_mode=' "$F"
grep -q '^\[conf:vpn\]$' "$F"
grep -q '^\[list:vpn_node\]$' "$F"
grep -q '^\[custom:my_rules\]$' "$F"
grep -q '^example.org|Example|1$' "$F"
grep -q '^\[custom:my_flags\]$' "$F"
grep -q '^my_toggle=1$' "$F"
[ "$(grep -c '^\[conf:vpn\]$' "$F")" -eq 1 ] || { echo 'FAIL: duplicate [conf:vpn]'; exit 1; }
[ "$(grep -c '^\[list:vpn_node\]$' "$F")" -eq 1 ] || { echo 'FAIL: duplicate [list:vpn_node]'; exit 1; }
echo 'FX VPN repair custom-section preservation regression: PASS'
