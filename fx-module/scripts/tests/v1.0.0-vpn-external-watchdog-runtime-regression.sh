#!/system/bin/sh
# End-to-end host simulation for the watcher state machine: none -> tunnel -> none.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-vpn-watchdog.XXXXXX")
trap 'FX_VPN_WATCH_INTERVAL=1 sh "$T/module/scripts/vpn-external-watchdog.sh" stop "$T/module" "$T/data" >/dev/null 2>&1 || :; rm -rf "$T"' EXIT HUP INT TERM
M="$T/module"
PG="$T/data"
mkdir -p "$M/scripts" "$PG" "$T/bin"
cp "$ROOT/module.prop" "$M/module.prop"
cp "$ROOT/scripts/vpn-external-watchdog.sh" "$M/scripts/"
cp "$ROOT/scripts/external-vpn-probe.sh" "$M/scripts/"
cp "$ROOT/scripts/util.sh" "$M/scripts/"
cp "$ROOT/scripts/vpncore.sh" "$M/scripts/"
printf 'vpn_external_compat=1\nvpn_mode=rule\n' > "$PG/settings.conf"
cat > "$T/state" <<'STATE'
none
STATE
cat > "$T/bin/ip" <<'IP'
#!/bin/sh
s=$(cat "$FX_TEST_STATE_FILE" 2>/dev/null)
case "$*" in
  '-o link show')
    printf '%s\n' '1: lo: <LOOPBACK,UP>'
    case "$s" in
      tunnel) printf '%s\n' '8: tun0: <POINTOPOINT,UP>' ;;
      unknown) printf '%s\n' '8: tun0: <POINTOPOINT,UP>' '9: wg0: <POINTOPOINT,UP>' ;;
    esac
    ;;
  '-o link show dev tun0')
    case "$s" in none) exit 1 ;; *) printf '%s\n' '8: tun0: <POINTOPOINT,UP>' ;; esac
    ;;
  '-o link show dev wg0')
    case "$s" in unknown) printf '%s\n' '9: wg0: <POINTOPOINT,UP>' ;; *) exit 1 ;; esac
    ;;
  *) exit 1 ;;
esac
IP
cat > "$T/bin/dumpsys" <<'DUMP'
#!/bin/sh
case "$(cat "$FX_TEST_STATE_FILE" 2>/dev/null)" in
  tunnel) printf '%s\n' 'mVpnInfo=VpnInfo{ownerUid=12345, vpnIface=tun0, primaryUnderlyingIface=wlan0}' ;;
  unknown) printf '%s\n' 'VpnInfo{ownerUid=12345, vpnIface=tun0, primaryUnderlyingIface=wlan0} VpnInfo{vpnIface=wg0, primaryUnderlyingIface=wlan0}' ;;
  *) printf '%s\n' 'No active VPN info' ;;
esac
DUMP
cat > "$M/scripts/apply.sh" <<'APPLY'
#!/bin/sh
printf '%s %s\n' "$1" "$(cat "$FX_TEST_STATE_FILE" 2>/dev/null)" >> "$FX_TEST_APPLY_LOG"
exit 0
APPLY
chmod 755 "$T/bin/ip" "$T/bin/dumpsys" "$M/scripts/apply.sh" "$M/scripts/vpn-external-watchdog.sh" "$M/scripts/external-vpn-probe.sh"
export PATH="$T/bin:/usr/bin:/bin" PG CONF="$PG/settings.conf" MODDIR="$M" PG_MODDIR="$M"
export FX_TEST_STATE_FILE="$T/state" FX_TEST_APPLY_LOG="$T/apply.log" FX_VPN_WATCH_INTERVAL=1
: > "$FX_TEST_APPLY_LOG"
sh "$M/scripts/vpn-external-watchdog.sh" snapshot "$M" "$PG"
# A valid owner row plus a second incomplete VpnInfo row is still ambiguous.
# The probe must not discard the malformed row and bind to the first VPN.
printf 'unknown\n' > "$FX_TEST_STATE_FILE"
_probe=$(sh "$M/scripts/external-vpn-probe.sh")
case "$_probe" in *'"status":"unknown"'*) ;; *) echo "FAIL: ambiguous VpnInfo rows were accepted: $_probe" >&2; exit 1 ;; esac
printf 'none\n' > "$FX_TEST_STATE_FILE"
# Represents the initial boot apply that already consumed the snapshot.
echo 'initial none' >> "$FX_TEST_APPLY_LOG"
sh "$M/scripts/vpn-external-watchdog.sh" mark-applied "$M" "$PG"
sh "$M/scripts/vpn-external-watchdog.sh" start "$M" "$PG"
wait_for_count() {
  want=$1; tries=0
  while [ "$tries" -lt 12 ]; do
    got=$(grep -c '^fast ' "$FX_TEST_APPLY_LOG" 2>/dev/null || true)
    [ "$got" -ge "$want" ] && return 0
    sleep 1
    tries=$((tries+1))
  done
  echo "FAIL: expected at least $want state-change applies, saw $(cat "$FX_TEST_APPLY_LOG")" >&2
  return 1
}
wait_for_applied_state() {
  want=$1; tries=0
  while [ "$tries" -lt 12 ]; do
    got=$(cat "$PG/vpn-external-watchdog.applied-state" 2>/dev/null || true)
    [ "$got" = "$want" ] && return 0
    sleep 1
    tries=$((tries+1))
  done
  echo "FAIL: watchdog did not commit applied state '$want'; marker=$(cat "$PG/vpn-external-watchdog.applied-state" 2>/dev/null || true)" >&2
  cat "$PG/vpn-external-watchdog.log" >&2 2>/dev/null || :
  return 1
}
dump_diagnostics() {
  echo "--- apply log ---" >&2
  cat "$FX_TEST_APPLY_LOG" >&2 2>/dev/null || :
  echo "--- watcher log ---" >&2
  cat "$PG/vpn-external-watchdog.log" >&2 2>/dev/null || :
  echo "--- state markers ---" >&2
  for p in "$PG/vpn-external-watchdog.state" "$PG/vpn-external-watchdog.applied-state" "$PG/vpn-external-watchdog.pid"; do
    printf '%s=' "$p" >&2; cat "$p" >&2 2>/dev/null || :
  done
}
# Repeat transitions to expose timing races instead of trusting a single pass.
for cycle in 1 2 3; do
  tunnel_count=$((cycle * 2 - 1))
  none_count=$((cycle * 2))
  printf 'tunnel\n' > "$FX_TEST_STATE_FILE.next"
  mv -f "$FX_TEST_STATE_FILE.next" "$FX_TEST_STATE_FILE"
  wait_for_count "$tunnel_count"
  wait_for_applied_state 'tunnel|tun0|12345'
  sleep 2
  [ "$(grep -c '^fast ' "$FX_TEST_APPLY_LOG")" -eq "$tunnel_count" ] || {
    echo "FAIL: stable tunnel state caused repeated applies during cycle $cycle" >&2
    dump_diagnostics; exit 1
  }
  printf 'none\n' > "$FX_TEST_STATE_FILE.next"
  mv -f "$FX_TEST_STATE_FILE.next" "$FX_TEST_STATE_FILE"
  wait_for_count "$none_count"
  wait_for_applied_state none
  sleep 2
  [ "$(grep -c '^fast ' "$FX_TEST_APPLY_LOG")" -eq "$none_count" ] || {
    echo "FAIL: disconnect caused repeated applies during cycle $cycle" >&2
    dump_diagnostics; exit 1
  }
done
sh "$M/scripts/vpn-external-watchdog.sh" stop "$M" "$PG"
[ ! -s "$PG/vpn-external-watchdog.pid" ] || { echo 'FAIL: watcher PID marker survived stop' >&2; dump_diagnostics; exit 1; }
printf '%s\n' 'PASS: three simulated VPN connect/disconnect cycles each trigger exactly one apply per stable state'
