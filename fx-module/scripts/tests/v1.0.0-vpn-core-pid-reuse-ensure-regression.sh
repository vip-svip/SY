#!/bin/sh
# Regression: a live but unrelated/reused PID must not be treated as sing-box.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SRC="$ROOT/scripts/vpncore.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
awk 'BEGIN{p=0} /^vpn_core_ensure\(\) \{/ {p=1} p{print} p && /^\}/ {exit}' "$SRC" > "$TMP/ensure.sh"
grep -Fq 'vpncore_pid_matches "$_p"' "$TMP/ensure.sh"
cat > "$TMP/test.sh" <<'SH2'
#!/bin/sh
set -eu
PG="$1"; export PG
mkdir -p "$PG"; printf '4242\n' > "$PG/singbox.pid"
pg_get(){ echo 1; }
vpncore_conf(){ case "$1" in vpn_mode) echo proxy ;; esac; }
vpncore_pid(){ echo "$PG/singbox.pid"; }
kill(){ [ "${1:-}" = -0 ] && [ "${2:-}" = 4242 ]; }
vpncore_pid_matches(){ return 1; }
vpncore_listening(){ return 1; }
vpncore_start(){ echo started > "$PG/start.called"; return 0; }
pg_log(){ :; }
. "$2"
vpn_core_ensure
[ -f "$PG/start.called" ]
[ ! -f "$PG/singbox.pid" ]
echo 'FX VPN core PID-reuse ensure regression: PASS'
SH2
chmod +x "$TMP/test.sh"
sh "$TMP/test.sh" "$TMP/pg" "$TMP/ensure.sh"
