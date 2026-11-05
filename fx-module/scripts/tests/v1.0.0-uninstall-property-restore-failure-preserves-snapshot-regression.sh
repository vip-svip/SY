#!/system/bin/sh
# Regression: resetprop failures must be read-back verified and preserve retry state.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
U="$ROOT/uninstall.sh"
block=$(sed -n '/B\. 属性伪装还原/,/A7\. settings put 还原/p' "$U")
printf '%s\n' "$block" | grep -Fq 'getprop "$pk"'
printf '%s\n' "$block" | grep -Fq 'could not verify property restore'
printf '%s\n' "$block" | grep -Fq 'could not verify property deletion'
printf '%s\n' "$block" | grep -Fq 'PG_CLEANUP_INCOMPLETE=1'
printf '%s\n' "$block" | grep -Fq 'PG_KEEP_DATA=1'
fail_line=$(grep -nF 'could not verify property restore' "$U" | cut -d: -f1)
keep_line=$(grep -nF 'PG_KEEP_DATA=1' "$U" | awk -F: -v fail="$fail_line" '$1 > fail {print $1; exit}')
cleanup_line=$(grep -nF 'rm -rf "$PG" "$XDIR"' "$U" | cut -d: -f1)
[ -n "$fail_line" ] && [ -n "$keep_line" ] && [ -n "$cleanup_line" ]
[ "$fail_line" -lt "$keep_line" ] && [ "$keep_line" -lt "$cleanup_line" ]
sh -n "$U"
echo 'FX uninstall property restore failure snapshot preservation regression: PASS'
