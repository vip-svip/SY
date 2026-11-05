#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
U="$ROOT/uninstall.sh"
sh -n "$U"
stop=$(grep -nF 'sh "$MODDIR/scripts/localdns-watchdog.sh" stop "$MODDIR" "$PG"' "$U" | head -n1 | cut -d: -f1)
fw=$(grep -nF 'A1. 防火墙链' "$U" | head -n1 | cut -d: -f1)
[ -n "$stop" ] && [ -n "$fw" ] && [ "$stop" -lt "$fw" ] || { echo 'FAIL: watchdog not stopped before firewall teardown' >&2; exit 1; }
grep -Fq 'could not confirm stopping local DNS watchdog; aborting uninstall before firewall cleanup' "$U"
grep -Fq 'PG_KEEP_DATA=1' "$U"
echo 'PASS: uninstall stops and verifies watchdog before removing FX-owned OUTPUT hooks'
