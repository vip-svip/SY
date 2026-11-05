#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
python3 - "$A" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
anchor='if [ "$(pg_get vpn_hide 0)" = "1" ] && [ "$VPN_MODE" = "direct" ] && [ -n "$_PG_EXT_VPN_IF" ]; then'
a=s.index(anchor)
b=s.index('\nfi\n\n# IP/CIDR 黑名单', a)
block=s[a:b]
unknown=block.index('if [ -z "$VPN_EXTERNAL_UID" ]; then')
known=block.index('else\n    _PGHKS_BUILD_OK=1', unknown)
safe=block[unknown:known]
assert 'while [ "$_PGHKS_STALE_N" -lt 64 ] && iptables $FWWAIT -D OUTPUT -j PGHKS' in safe
assert 'while [ "$_PGHKS_STALE_N" -lt 64 ] && ip6tables $FWWAIT -D OUTPUT -j PGHKS' in safe
for cmd in ('iptables $FWWAIT -F PGHKS', 'iptables $FWWAIT -X PGHKS', 'ip6tables $FWWAIT -F PGHKS', 'ip6tables $FWWAIT -X PGHKS'):
    assert cmd in safe, cmd
assert '为避免破坏外层隧道，跳过 PGHKS 防火墙过滤' in safe
assert safe.index('pg_fail vpn_hide') < safe.index('iptables $FWWAIT -D OUTPUT -j PGHKS')
assert 'fw4 -A PGHKS -m owner --uid-owner "$VPN_EXTERNAL_UID" -j RETURN' in block
PY
sh -n "$A"
echo 'FX third-party VPN unknown UID stale-hook cleanup regression: PASS'
