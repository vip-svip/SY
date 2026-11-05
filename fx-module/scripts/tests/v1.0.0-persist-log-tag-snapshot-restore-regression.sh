#!/system/bin/sh
# Regression: preserve user/ROM persist.log.tag and restore it on uninstall.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
U="$ROOT/uninstall.sh"
a=$(sed -n '/# logcat 采集防护/,/# ---------- 5b\./p' "$A")
printf '%s\n' "$a" | grep -Fq 'persist.log.tag.snapshot'
printf '%s\n' "$a" | grep -Fq 'getprop persist.log.tag'
printf '%s\n' "$a" | grep -Fq 'if [ "$(pg_get block_logcat 0)" = "1" ]; then'
if printf '%s\n' "$a" | grep -Fq 'setprop persist.log.tag ""'; then
  echo 'apply still clears persist.log.tag when feature is disabled' >&2; exit 1
fi
u=$(sed -n '/# 恢复 logcat 防护触碰的持久属性/,/# A7\. settings put 还原/p' "$U")
printf '%s\n' "$u" | grep -Fq 'setprop persist.log.tag "$_plto"'
printf '%s\n' "$u" | grep -Fq 'could not verify persist.log.tag restore'
printf '%s\n' "$u" | grep -Fq 'PG_KEEP_DATA=1'
sh -n "$A"
sh -n "$U"
echo 'FX persist.log.tag snapshot/restore regression: PASS'
