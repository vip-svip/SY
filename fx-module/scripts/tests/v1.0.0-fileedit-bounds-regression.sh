#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
F="$ROOT/scripts/fileedit.sh"
# Prevent out-of-range edit/delete requests from reporting success as no-op writes.
grep -Fq '[ "$_n" -le "$_total" ] || { echo '\''{"ok":0,"err":"line out of range"}'\''; exit 0; }' "$F"
[ "$(grep -Fc 'line out of range' "$F")" -ge 2 ]
echo 'FX file editor bounds regression: PASS'
