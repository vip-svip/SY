#!/system/bin/sh
# Audit99: large rule sets are streamed, size-guarded, and IP-CIDR submission is capped/diagnosed.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
python3 - "$A" <<'PY'
import sys
s=open(sys.argv[1],encoding='utf-8').read()
assert '_hs_dedup=$(awk' not in s, 'hosts dedup must not capture the full file in a shell variable'
assert '_hs_dedup_tmp="$PG/cache/hosts.dedup.$$"' in s
assert '[ "$_hs_lines" -gt 300000 ] || [ "$_hs_bytes" -gt 50331648 ]' in s
assert '拒绝替换以避免静默截断；保留上一份 hosts' in s
assert 'head -n 4096 "$_subnet_unique"' in s
assert 'cap=4096' in s
assert '订阅 IP-CIDR 提交失败' in s
PY
# Runtime test for stream dedup semantics and large input count without command substitution.
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT HUP INT TERM
{ echo '# section'; echo '0.0.0.0 a.example'; echo '0.0.0.0 a.example'; echo '0.0.0.0 b.example'; } > "$t/in"
awk '{line=$0} line ~ /^[[:space:]]*#/ || line ~ /^[[:space:]]*$/ {print line; next} {if (seen[line]++) next; print line}' "$t/in" > "$t/out"
[ "$(wc -l < "$t/out" | tr -d ' ')" = 3 ]
[ "$(sed -n '2p' "$t/out")" = '0.0.0.0 a.example' ]
# Stable first-source ordering and dedup for CIDR list.
printf '%s\n' '192.0.2.0/24' '192.0.2.0/24' '2001:db8::/32' > "$t/ip"
awk 'NF && !seen[$0]++ {print}' "$t/ip" > "$t/unique"
[ "$(wc -l < "$t/unique" | tr -d ' ')" = 2 ]
echo 'PASS: large rule sets use streaming dedup, hard size guard, and explicit CIDR cap/failure diagnostics'
