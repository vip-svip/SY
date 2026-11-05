#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
W="$ROOT/scripts/vpn-external-watchdog.sh"
S="$ROOT/service.sh"
U="$ROOT/uninstall.sh"
C="$ROOT/scripts/vpncore.sh"
[ -x "$W" ] || { echo 'FAIL: external VPN watchdog must be executable' >&2; exit 1; }
grep -Fq 'vpn-external-watchdog.sh" snapshot' "$S"
grep -Fq 'vpn-external-watchdog.sh" mark-applied' "$S"
grep -Fq 'vpn-external-watchdog.sh" start' "$S"
SNAP=$(grep -n 'vpn-external-watchdog.sh" snapshot' "$S" | head -1 | cut -d: -f1)
APPLY=$(grep -n 'sh "$MODDIR/scripts/apply.sh"' "$S" | head -1 | cut -d: -f1)
MARK=$(grep -n 'vpn-external-watchdog.sh" mark-applied' "$S" | head -1 | cut -d: -f1)
START=$(grep -n 'vpn-external-watchdog.sh" start' "$S" | head -1 | cut -d: -f1)
[ "$SNAP" -lt "$APPLY" ] && [ "$APPLY" -lt "$MARK" ] && [ "$MARK" -lt "$START" ] || {
  echo 'FAIL: service boot order must snapshot -> apply -> commit -> start watchdog' >&2; exit 1;
}
STOP=$(grep -n 'vpn-external-watchdog.sh" stop' "$U" | head -1 | cut -d: -f1)
PROXY=$(grep -n 'yulong-root-proxy.sh" uninstall' "$U" | head -1 | cut -d: -f1)
FW=$(grep -n 'yulong-app-firewall.sh" uninstall' "$U" | head -1 | cut -d: -f1)
[ -n "$STOP" ] && [ -n "$PROXY" ] && [ -n "$FW" ] && \
  [ "$STOP" -lt "$PROXY" ] && [ "$PROXY" -lt "$FW" ] || {
  echo 'FAIL: uninstall must stop the external VPN watcher before Root Proxy and firewall cleanup' >&2; exit 1;
}
grep -Fq 'apply.sh" fast' "$W"
grep -Fq 'state reconciled successfully' "$W"
grep -Fq 'leaving applied marker unchanged for retry' "$W"
grep -Fq '_valid_pid' "$W"
grep -Fq 'vpn-external-watchdog.applied-state' "$W"
for f in "$W" "$S" "$U" "$C"; do sh -n "$f"; done
printf '%s\n' 'PASS: boot lifecycle, change-triggered serialized reconciliation, retry semantics, and uninstall ordering are wired'
