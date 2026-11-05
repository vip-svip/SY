#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
U="$ROOT/uninstall.sh"
# Core shutdown must happen before firewall chain removal and before PG data deletion.
stop_line=$(grep -nF 'sh "$MODDIR/scripts/vpncore.sh" stop' "$U" | head -n1 | cut -d: -f1)
fw_line=$(grep -nF 'A1. 防火墙链' "$U" | head -n1 | cut -d: -f1)
[ -n "$stop_line" ] && [ -n "$fw_line" ] && [ "$stop_line" -lt "$fw_line" ]
grep -Fq 'could not confirm stopping the module-managed sing-box core' "$U"
grep -Fq 'PG_KEEP_DATA=1' "$U"
# Do not add broad process-name killing as an uninstall fallback.
! grep -Eq '(^|[;&[:space:]])(pkill|killall)[[:space:]].*sing-box' "$U"
sh -n "$U"
echo 'FX uninstall stops owned VPN core regression: PASS'
