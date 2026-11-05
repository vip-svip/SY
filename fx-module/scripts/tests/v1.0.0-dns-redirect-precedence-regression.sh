#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
grep -Fq 'DNS_FWD="$DNS_SAFE"' "$A"
grep -Fq '&& [ -z "$DNS_FWD" ]; then' "$A"
grep -Fq 'nat4 -A PGNAT -p udp --dport 53 -j DNAT --to-destination "$DNS_FWD"' "$A"
grep -Fq 'nat4 -A PGNAT -p tcp --dport 53 -j DNAT --to-destination "$DNS_FWD"' "$A"
python3 - "$A" <<'PY'
import sys
s=open(sys.argv[1],encoding='utf-8').read()
a=s.index('DNS_FWD=""'); b=s.index('# 透明代理：',a); seg=s[a:b]
assert seg.count('&& [ -z "$DNS_FWD" ]; then') == 2
assert 'pg_get dns_block 0' not in seg
assert seg.index('DNS_FWD="$DNS_SAFE"') < seg.index('if [ "$(pg_get custom_dns 0)"') < seg.index('if [ "$(pg_get global_dns 0)"')
print('PASS: DNS redirect precedence + no retired DNS toggle')
PY
sh -n "$A"
echo 'FX DNS redirect precedence regression: PASS'
