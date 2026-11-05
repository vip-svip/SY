#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
BLOCK=$(sed -n '/独立第三方 VPN 隐藏（FX 直连模式也可用）/,/# IP 黑名单（block 字段里的 IP 段）/p' "$A")
printf '%s\n' "$BLOCK" | grep -F 'if [ -z "$VPN_EXTERNAL_UID" ]; then' >/dev/null
printf '%s\n' "$BLOCK" | grep -F '跳过 PGHKS 防火墙过滤' >/dev/null
# The broad UDP rules must only be reachable after the UID-known safety gate.
GATE=$(printf '%s\n' "$BLOCK" | grep -nF 'if [ -z "$VPN_EXTERNAL_UID" ]; then' | head -1 | cut -d: -f1)
RULE=$(printf '%s\n' "$BLOCK" | grep -nF 'fw4 -A PGHKS -m owner ! --uid-owner 0:9999 -p udp --dport 443 -j REJECT' | head -1 | cut -d: -f1)
[ "$RULE" -gt "$GATE" ]
printf '%s\n' "$BLOCK" | grep -F 'fw4 -A PGHKS -m owner --uid-owner "$VPN_EXTERNAL_UID" -j RETURN' >/dev/null
printf '%s\n' "$BLOCK" | grep -F 'fw6 -A PGHKS -m owner --uid-owner "$VPN_EXTERNAL_UID" -j RETURN' >/dev/null
for f in "$ROOT"/*.sh "$ROOT"/scripts/*.sh "$ROOT"/scripts/tests/*.sh; do [ ! -f "$f" ] || sh -n "$f"; done
echo 'FX third-party VPN unknown UID safe-fail regression: PASS'
