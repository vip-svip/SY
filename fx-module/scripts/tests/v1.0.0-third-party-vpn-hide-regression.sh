#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
# The same active-VpnInfo/owner UID probe is performed before the VPN-mode branch, including direct mode.
grep -Fq '_PG_EXT_VPN_INFO=$(vpncore_android_active_vpn_info 2>/dev/null || true)' "$A"
grep -Fq 'VPN_EXTERNAL_UID=${_PG_EXT_VPN_UID:-}' "$A"
# Hide-only path must be independent of FX's own VPN mode and only run with a detected external tunnel.
grep -Fq '独立第三方 VPN 隐藏（FX 直连模式也可用）' "$A"
grep -Fq '[ "$(pg_get vpn_hide 0)" = "1" ] && [ "$VPN_MODE" = "direct" ] && [ -n "$_PG_EXT_VPN_IF" ]' "$A"
# Exempt third-party VPN app's tunnel UID before UDP blocks, for IPv4 and IPv6.
grep -Fq 'fw4 -A PGHKS -m owner --uid-owner "$VPN_EXTERNAL_UID" -j RETURN' "$A"
grep -Fq 'fw6 -A PGHKS -m owner --uid-owner "$VPN_EXTERNAL_UID" -j RETURN' "$A"
# Don't redirect DNS or globally block IPv6 in direct-mode hide-only path.
BLOCK=$(awk '
  /独立第三方 VPN 隐藏（FX 直连模式也可用）/ { active=1; next }
  active && /^# IP\/CIDR 黑名单/ { exit }
  active { print }
' "$A")
BLOCK_CODE=$(printf "%s\n" "$BLOCK" | sed "s/#.*$//")
case "$BLOCK_CODE" in
  *DNAT*|*PGBLK6*|*'--dport 53'*)
    echo 'FAIL: direct-mode hide-only path must not redirect DNS or globally block IPv6' >&2
    exit 1
    ;;
esac
printf '%s\n' "$BLOCK" | grep -F 'independent hide filters active' >/dev/null
for f in "$ROOT"/*.sh "$ROOT"/scripts/*.sh "$ROOT"/scripts/tests/*.sh; do [ ! -f "$f" ] || sh -n "$f"; done
echo 'FX v1.0.0 third-party VPN hide regression: PASS'
