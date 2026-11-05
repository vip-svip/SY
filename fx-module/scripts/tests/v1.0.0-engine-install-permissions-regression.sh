#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
C="$ROOT/customize.sh"
for f in "$ROOT/bin/arm64/qjs" "$ROOT/bin/arm64/pg-mitm" "$ROOT/bin/arm64/sing-box"; do
  [ -s "$f" ] || { echo "FAIL: bundled engine missing: $f" >&2; exit 1; }
done
grep -Fq 'set_perm "$MODPATH/bin/arm64/qjs"' "$C" && { echo 'FAIL: expected generic engine loop, not a hardcoded qjs-only check' >&2; exit 1; } || :
grep -Fq '"$MODPATH/bin/arm64/qjs"' "$C"
grep -Fq '"$MODPATH/bin/arm64/pg-mitm"' "$C"
grep -Fq 'set_perm "$_engine" 0 0 0755' "$C"
sh -n "$C"
echo 'FX engine install permissions regression: PASS'
