#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
U="$ROOT/uninstall.sh"
# Only one owned-core stop entrypoint is allowed; unresolved PID state preserves retry data.
[ "$(grep -Fc 'sh "$MODDIR/scripts/vpncore.sh" stop' "$U")" -eq 1 ]
grep -Fq 'sing-box PID state remains after managed stop; preserving $PG for safe retry' "$U"
! grep -Eq 'kill[[:space:]]+-9[[:space:]]+"?\$_vp' "$U"
! grep -Fq 'case "$_vpcmd" in' "$U"
# Stop path must appear before firewall teardown and final data deletion.
stop_line=$(grep -nF 'sh "$MODDIR/scripts/vpncore.sh" stop' "$U" | cut -d: -f1)
fw_line=$(grep -nF '# A1. 防火墙链' "$U" | cut -d: -f1)
cleanup_line=$(grep -nF '# A firewall cleanup verification failure also needs a retry path.' "$U" | cut -d: -f1)
[ "$stop_line" -lt "$fw_line" ]
[ "$fw_line" -lt "$cleanup_line" ]
sh -n "$U"
echo 'FX uninstall single VPN-core stop path regression: PASS'
