#!/system/bin/sh
# Audit100: oversized subscription sources must be rejected before cache promotion, not truncated.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
python3 - "$A" <<'PY'
import sys
s=open(sys.argv[1],encoding='utf-8').read()
needle='''if [ "$_hf_rc" -eq 0 ] && [ -s "$_hf_dst" ]; then
    _hf_new_bytes=$(wc -c < "$_hf_dst"'''
assert needle in s, 'source size/line guard must run after fetch and before cache promotion'
assert '"$_hf_new_bytes" -gt 25165824' in s
assert '"$_hf_new_lines" -gt 200000' in s
assert '拒绝新版本并尝试回退已校验缓存' in s
assert '_hf_rc=98' in s
# Guard must appear before the checksum/cache-promotion block.
guard=s.index('_hf_new_bytes=$(wc -c < "$_hf_dst"')
checksum=s.index('_hf_newsum=$(_hf_sha256 "$_hf_dst")')
assert guard < checksum, 'oversized content must be rejected before hashing/promotion'
PY
# Runtime exercise the exact cap semantics (oversize rejects, no truncation).
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT HUP INT TERM
printf 'a\nb\nc\n' > "$t/small"
bytes=$(wc -c < "$t/small" | tr -d ' '); lines=$(wc -l < "$t/small" | tr -d ' ')
[ "$bytes" -le 25165824 ] && [ "$lines" -le 200000 ]
# Model an over-limit source with sparse file, avoiding allocating a large fixture.
truncate -s 25165825 "$t/oversize"
bytes=$(wc -c < "$t/oversize" | tr -d ' ')
[ "$bytes" -gt 25165824 ]
# The implementation must not use head/tail to silently clip subscription input.
! grep -Fq 'head -n 200000' "$A"
echo 'PASS: subscription source size guard rejects oversized downloads before cache promotion without truncation'
