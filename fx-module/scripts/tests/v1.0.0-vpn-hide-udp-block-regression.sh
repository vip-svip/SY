#!/system/bin/sh
# hide_udp_block_all must insert its rules before PGHKS' terminal RETURN.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
python3 - "$A" <<'PY'
import sys
s=open(sys.argv[1],encoding='utf-8').read()
a=s.index('if [ "$(vpn_hide_conf hide_udp_block_all)" = "1" ]; then')
b=s.index('if [ "$(vpn_hide_conf hide_dot_block)" = "1" ]; then',a)
seg=s[a:b]
assert 'fw4 -I PGHKS 1 -p udp -m owner ! --uid-owner 0:9999 -j REJECT' in seg
assert 'fw6 -I PGHKS 1 -p udp -m owner ! --uid-owner 0:9999 -j REJECT' in seg
assert 'fw4 -A PGHKS -p udp -m owner ! --uid-owner 0:9999 -j REJECT' not in seg
assert 'fw6 -A PGHKS -p udp -m owner ! --uid-owner 0:9999 -j REJECT' not in seg
assert '--dport 53 -j RETURN' in seg, 'DNS exception should be explicit for L2 mode'
assert seg.index('fw4 -I PGHKS 1 -p udp -m owner ! --uid-owner 0:9999 -j REJECT') < seg.index('fw4 -I PGHKS 1 -p udp --dport 53 -j RETURN'), 'DNS exception must be inserted last so it precedes the general UDP reject'
print('PASS: L2 UDP rules are inserted before terminal RETURN and preserve DNS exception')
PY
sh -n "$A"
echo 'FX VPN hide UDP block regression: PASS'
