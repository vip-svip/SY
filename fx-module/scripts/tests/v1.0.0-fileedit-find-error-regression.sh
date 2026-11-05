#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
F="$ROOT/scripts/fileedit.sh"
# grep rc=1 means no matches; rc>1 must not be silently reported as success.
grep -Fq 'if grep -n -i -m "$_max" -- "$_pat" "$_f" > "$_tmp" 2>/dev/null; then' "$F"
grep -Fq '_grep_rc=$?' "$F"
grep -Fq '[ "$_grep_rc" -gt 1 ]' "$F"
grep -Fq 'search failed (invalid pattern or read error)' "$F"
grep -Fq 'rm -f "$_tmp" 2>/dev/null' "$F"
echo 'FX file editor find error reporting regression: PASS'
