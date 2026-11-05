#!/system/bin/sh
# Regression: failed Settings restoration must preserve its snapshot before cleanup.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
U="$ROOT/uninstall.sh"
settings_block=$(sed -n '/A7\. settings put 还原/,/C\. 用户数据备份/p' "$U")
printf '%s\n' "$settings_block" | grep -Fq 'PG_CLEANUP_INCOMPLETE=1'
printf '%s\n' "$settings_block" | grep -Fq 'PG_KEEP_DATA=1'
printf '%s\n' "$settings_block" | grep -Fq 'preserving snapshot for retry/manual recovery'
settings_fail_line=$(grep -nF 'could not verify Settings restore' "$U" | cut -d: -f1)
cleanup_line=$(grep -nF 'rm -rf "$PG" "$XDIR"' "$U" | cut -d: -f1)
keep_line=$(grep -nF 'PG_KEEP_DATA=1' "$U" | awk -F: -v fail="$settings_fail_line" '$1 > fail {print $1; exit}')
[ -n "$settings_fail_line" ] && [ -n "$keep_line" ] && [ -n "$cleanup_line" ]
[ "$settings_fail_line" -lt "$keep_line" ]
[ "$keep_line" -lt "$cleanup_line" ]
sh -n "$U"
echo 'FX uninstall settings restore failure snapshot preservation regression: PASS'
