#!/system/bin/sh
# Regression: uninstall must discover Magisk's `magisk resetprop` subcommand
# when the standalone resetprop executable is absent, matching post-fs-data.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
U="$ROOT/uninstall.sh"
P="$ROOT/post-fs-data.sh"
block=$(sed -n '/B\. 属性伪装还原/,/A7\. settings put 还原/p' "$U")
printf '%s\n' "$block" | grep -Fq '[ -x /data/adb/magisk/magisk ] && RP="/data/adb/magisk/magisk resetprop"'
printf '%s\n' "$block" | grep -Fq 'if [ -n "$RP" ] && [ -f "$BK/props.snapshot" ]'
printf '%s\n' "$block" | grep -Fq '$RP "$pk" "$pv"'
printf '%s\n' "$block" | grep -Fq '$RP --delete "$pk"'
grep -Fq 'elif [ -x /data/adb/magisk/magisk ]; then RP="/data/adb/magisk/magisk resetprop"' "$P"
sh -n "$U"
sh -n "$P"
echo 'FX uninstall Magisk resetprop subcommand fallback regression: PASS'
