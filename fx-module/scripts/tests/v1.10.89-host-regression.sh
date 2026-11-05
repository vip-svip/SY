#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
U="$ROOT/uninstall.sh"
# Static ownership guard: never unconditional-unmount hosts target.
grep -Fq '"$PG/hosts on /system/etc/hosts "*' "$U"
grep -Fq 'hosts mount source is not PrivacyGuard-owned; preserving /system/etc/hosts mount' "$U"
# Unknown / third-party source branch must not call umount.
awk '/\*" on \/system\/etc\/hosts "\*\)/,/;;/' "$U" | grep -Fq 'preserving /system/etc/hosts mount'
if awk '/\*" on \/system\/etc\/hosts "\*\)/,/;;/' "$U" | grep -Eq '(^|[[:space:]])umount[[:space:]]'; then
  echo 'FAIL: unknown-source hosts branch contains umount' >&2; exit 1
fi
for f in "$ROOT"/*.sh "$ROOT"/scripts/*.sh "$ROOT"/scripts/tests/*.sh; do [ ! -f "$f" ] || sh -n "$f"; done
echo 'v1.10.89 host regression: PASS'
