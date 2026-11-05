#!/bin/sh
# Regression: an owned live PID without a listener must not be reported ready.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SRC="$ROOT/scripts/vpncore.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
awk 'BEGIN{p=0} /^vpn_core_ensure\(\) \{/ {p=1} p{print} p && /^\}/ {exit}' "$SRC" > "$TMP/ensure.sh"
grep -Fq 'if vpncore_listening && vpncore_tun_interface_ready; then' "$TMP/ensure.sh"
grep -Fq 'if ! vpncore_stop; then' "$TMP/ensure.sh"
cat > "$TMP/test.sh" <<'SH2'
#!/bin/sh
set -eu
PG="$1"; export PG
mkdir -p "$PG"; printf '4242\n' > "$PG/singbox.pid"
pg_get(){ echo 1; }
vpncore_conf(){ case "$1" in vpn_mode) echo proxy ;; esac; }
vpncore_pid(){ echo "$PG/singbox.pid"; }
kill(){ [ "${1:-}" = -0 ] && [ "${2:-}" = 4242 ]; }
vpncore_pid_matches(){ return 0; }
vpncore_listening(){ return 1; }
vpncore_stop(){ echo stopped > "$PG/stop.called"; rm -f "$PG/singbox.pid"; return 0; }
vpncore_start(){ echo started > "$PG/start.called"; return 0; }
pg_log(){ :; }
pg_fail(){ :; }
. "$2"
vpn_core_ensure
[ -f "$PG/stop.called" ]
[ -f "$PG/start.called" ]
echo 'FX VPN owned PID without listener restart regression: PASS'
SH2
chmod +x "$TMP/test.sh"
sh "$TMP/test.sh" "$TMP/pg" "$TMP/ensure.sh"
