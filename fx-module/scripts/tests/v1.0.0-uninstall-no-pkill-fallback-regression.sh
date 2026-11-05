#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
U="$ROOT/uninstall.sh"
# Uninstall must delegate process ownership validation to vpncore.sh and must not
# retain a weaker second PID/cmdline kill path.
grep -Fq 'sh "$MODDIR/scripts/vpncore.sh" stop' "$U"
grep -Fq 'if [ -e "$PG/singbox.pid" ]; then' "$U"
grep -Fq 'PG_KEEP_DATA=1' "$U"
! grep -Eq 'kill[[:space:]]+-9[[:space:]]+"?\$_vp' "$U"
! grep -Fq 'case "$_vpcmd" in' "$U"
! grep -Eq 'pkill[[:space:]]+-f' "$U"
sh -n "$U"
echo 'FX uninstall no weak process-kill fallback regression: PASS'
