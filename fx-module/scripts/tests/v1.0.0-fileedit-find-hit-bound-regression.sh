#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
F="$ROOT/scripts/fileedit.sh"
# Each hit and the aggregate response must be bounded and truncation explicit.
grep -Fq '_tx_sz=$(num ' "$F"
grep -Fq 'wc -c 2>/dev/null' "$F"
grep -Fq '[ "$_emit_sz" -gt 4096 ]' "$F"
grep -Fq 'head -c "$_emit_sz"' "$F"
grep -Fq 'cut\":$_hit_cut' "$F"
grep -Fq 'rm -f "$_tmp" "$_hit_tmp"' "$F"
echo 'FX file editor find hit bound regression: PASS'
