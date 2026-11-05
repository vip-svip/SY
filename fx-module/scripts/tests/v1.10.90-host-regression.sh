#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
U="$ROOT/uninstall.sh"
# Own hosts mount failure must preserve the source tree.
grep -Fq 'PG_KEEP_DATA=1' "$U"
grep -Fq 'preserving $PG so the live bind-mount source is not deleted' "$U"
grep -Fq 'if [ "$PG_KEEP_DATA" = 1 ]; then' "$U"
grep -Fq 'rm -rf "$PG" "$XDIR" 2>/dev/null' "$U"
# Unknown-source hosts branch must never unmount a third-party mount.
awk '/\*" on \/system\/etc\/hosts "\*\)/,/;;/' "$U" | grep -Fq 'preserving /system/etc/hosts mount'
if awk '/\*" on \/system\/etc\/hosts "\*\)/,/;;/' "$U" | grep -Eq '(^|[[:space:]])umount[[:space:]]'; then
  echo 'FAIL: unknown-source hosts branch contains umount' >&2; exit 1
fi
for f in "$ROOT"/*.sh "$ROOT"/scripts/*.sh "$ROOT"/scripts/tests/*.sh; do [ ! -f "$f" ] || sh -n "$f"; done
echo 'v1.10.90 host regression: PASS'
