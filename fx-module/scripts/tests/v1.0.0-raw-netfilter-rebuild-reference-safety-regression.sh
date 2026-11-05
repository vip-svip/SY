#!/system/bin/sh
# Host-side source regression: rebuild must not flush a raw chain while referenced.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SRC="$ROOT/scripts/apply.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
grep -Fq '_pg_knf_prepare_family()' "$SRC" || fail 'missing per-family cleanup helper'
grep -Fq '"$_pk_bin" $FWWAIT -t raw -D OUTPUT -j "$_pk_chain"' "$SRC" || fail 'does not remove repeated OUTPUT hooks'
grep -Fq '[ "$_pk_i" -lt 64 ]' "$SRC" || fail 'duplicate hook cleanup is not bounded'
grep -Fq '"$_pk_bin" $FWWAIT -t raw -S 2>/dev/null' "$SRC" || fail 'missing whole-table query'
grep -Fq '仍有规则引用 $_pk_chain' "$SRC" || fail 'does not preserve referenced chain'
grep -Fq '规则表查询失败；保留 $_pk_chain 并跳过本族重建' "$SRC" || fail 'query failure is not fail-closed'
grep -Fq '[ "$_PGNF4_READY" != "1" ] || [ "$_PGNF6_READY" != "1" ]' "$SRC" || fail 'does not prevent rebuild when either family cleanup is uncertain'
# Ensure the old unsafe one-shot cleanup loop is gone.
if grep -Fq 'for _knf in PGNF PGNF6; do' "$SRC"; then fail 'legacy one-shot cleanup loop remains'; fi
echo 'PASS: raw netfilter rebuild reference-safety regression'
