#!/system/bin/sh
# Regression: a still-live, verified core must retain its PID file if TERM/KILL
# do not stop it, so later retries do not lose ownership information.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SRC="$ROOT/scripts/vpncore.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
awk '/^vpncore_stop\(\)/,/^}/ {print}' "$SRC" > "$TMP/stop.sh"
# Static guard: live-process failure branch returns before PID-file removal.
grep -Fq 'stop failed; process $_p still alive, preserving PID file' "$TMP/stop.sh"
awk '/stop failed; process/ {fail=NR} /rm -f "\$_pidf"/ {last=NR} END {exit !(fail>0 && last>fail)}' "$TMP/stop.sh"
cat > "$TMP/harness.sh" <<'SH'
#!/bin/sh
set -eu
PG="$1"
export PG
mkdir -p "$PG"
printf '4242\n' > "$PG/singbox.pid"
vpncore_pid() { printf '%s\n' "$PG/singbox.pid"; }
vpncore_pid_matches() { [ "$1" = 4242 ]; }
# Simulate an uninterruptible but verified process: it remains alive after TERM/KILL.
kill() { [ "${1:-}" = -0 ] && [ "${2:-}" = 4242 ]; }
sleep() { :; }
pg_log() { :; }
. "$2"
if vpncore_stop; then echo 'unexpected stop success' >&2; exit 1; fi
[ -f "$PG/singbox.pid" ] || { echo 'PID file was incorrectly removed' >&2; exit 1; }
[ "$(cat "$PG/singbox.pid")" = 4242 ] || exit 1
echo 'FX VPN-core stop failure retains PID file: PASS'
SH
chmod +x "$TMP/harness.sh"
"$TMP/harness.sh" "$TMP/pg" "$TMP/stop.sh"
echo 'FX VPN-core stop failure static guard: PASS'

# Startup readiness timeout must not erase the PID record or roll back config
# if stopping the newly started core fails (the process may still own fx0/routes).
awk '/^vpncore_start\(\)/,/^vpn_core_ensure\(\)/ {print}' "$SRC" > "$TMP/start.sh"
grep -Fq 'readiness timeout; attempting to stop core before config rollback' "$TMP/start.sh"
awk '
  /if ! vpncore_stop; then/ {stopfail=NR}
  /保留 PID\/当前配置/ {failmsg=NR}
  /return 1/ && stopfail && !ret {ret=NR}
  /mv -f "\$_cfg_backup" "\$_cfg"/ {rollback=NR}
  /rm -f "\$_pidf"/ {pidrm=NR}
  END {exit !(stopfail>0 && failmsg>stopfail && ret>stopfail && rollback>ret && pidrm>ret)}
' "$TMP/start.sh"
echo 'FX startup timeout preserves live-core ownership before rollback: PASS'
