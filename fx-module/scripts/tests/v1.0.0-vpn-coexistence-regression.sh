#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
M="$ROOT/module.prop"
grep -Fq 'version=1.0.0' "$M"
grep -Fq 'versionCode=10000' "$M"
# External VPN detection must be before PGNAT global DNS/transparent-proxy hooks.
D=$(grep -n '^_PG_EXT_VPN_IF=""' "$A" | head -1 | cut -d: -f1)
G=$(grep -n '^# 全局 DNS 替换' "$A" | head -1 | cut -d: -f1)
[ -n "$D" ] && [ -n "$G" ] && [ "$D" -lt "$G" ]
grep -Fq 'pg_get global_dns 0)" = "1" ] && [ "$_PG_VPN_INTERCEPTION_BLOCKED" = "0"' "$A"
grep -Fq 'pg_get transparent_proxy 0)" = "1" ] && [ "$_PG_VPN_INTERCEPTION_BLOCKED" = "0"' "$A"
grep -Fq 'bypassing PG VPN REDIRECT to avoid VPN conflict' "$A"
for f in "$ROOT"/*.sh "$ROOT"/scripts/*.sh "$ROOT"/scripts/tests/*.sh; do [ ! -f "$f" ] || sh -n "$f"; done
echo 'PrivacyGuard 1.0.0 VPN coexistence regression: PASS'
