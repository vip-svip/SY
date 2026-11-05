#!/system/bin/sh
# Regression: never send UDP DNS datagrams to the TCP-only sing-box redirect inbound.
set -eu
MODDIR=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
APPLY="$MODDIR/scripts/apply.sh"
[ -f "$APPLY" ] || { echo 'FAIL: apply.sh missing'; exit 1; }
# Static invariant across both IPv4 and IPv6 transparent chains.
if grep -E 'nat[46]?[[:space:]]+-A[[:space:]]+PGVPN6?[[:space:]].*-p[[:space:]]+udp[[:space:]].*--dport[[:space:]]+53.*-j[[:space:]]+REDIRECT' "$APPLY" >/dev/null; then
  echo 'FAIL: UDP/53 is redirected into TCP redirect inbound'; exit 1
fi
grep -F 'nat4 -A PGVPN -p tcp --dport 53 -j REDIRECT --to-ports "$VPN_LP"' "$APPLY" >/dev/null
grep -F 'nat6 -A PGVPN6 -p tcp --dport 53 -j REDIRECT --to-ports "$VPN_LP"' "$APPLY" >/dev/null
grep -F 'UDP/53 left untouched' "$APPLY" >/dev/null
echo 'PASS: UDP/53 is not sent to TCP redirect inbound; TCP/53 behavior remains explicit'
