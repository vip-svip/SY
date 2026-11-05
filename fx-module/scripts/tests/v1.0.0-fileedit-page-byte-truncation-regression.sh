#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
F="$ROOT/scripts/fileedit.sh"
# The response must compare the untruncated selected page to maxBytes and
# expose both a specific byteTrunc flag and the general truncation flag.
grep -Fq '_sel_sz=$(num "$(size_of "$_sel")")' "$F"
grep -Fq '[ "$_sel_sz" -gt "$_maxb" ] && _byte_trunc=1' "$F"
grep -Fq '"byteTrunc":%s' "$F"
grep -Fq '[ "$_byte_trunc" -eq 1 ] && _trunc=1' "$F"
# Ensure the output is cut only after preserving the selected-page byte count.
sel_line=$(grep -nF ' _sel_sz=$(num "$(size_of "$_sel")")' "$F" | head -n1 | cut -d: -f1)
head_line=$(grep -nF 'head -c "$_maxb" "$_sel" > "$_tmp"' "$F" | head -n1 | cut -d: -f1)
[ "$sel_line" -lt "$head_line" ]
echo 'FX file editor page byte-truncation regression: PASS'
