#!/system/bin/sh
# hide_dot_block must insert before PGHKS terminal RETURN, not append behind it.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
python3 - "$ROOT/scripts/apply.sh" <<'PY'
import sys
s=open(sys.argv[1],encoding='utf-8').read()
a=s.index('if [ "$(vpn_hide_conf hide_dot_block)" = "1" ]; then')
b=s.index('if [ "$(vpn_hide_conf hide_mtu_clamp)" = "1" ]; then',a)
seg=s[a:b]
for fam in ('fw4','fw6'):
    for proto in ('tcp','udp'):
        rule=f'{fam} -I PGHKS 1 -p {proto} --dport 853 -j REJECT'
        assert rule in seg, f'missing {rule}'
        assert f'{fam} -A PGHKS -p {proto} --dport 853 -j REJECT' not in seg, 'DoT rule must not append behind terminal RETURN'
print('PASS: IPv4/IPv6 TCP+UDP DoT rules inserted at chain head')
PY
sh -n "$ROOT/scripts/apply.sh"
echo 'FX VPN hide DoT priority regression: PASS'
