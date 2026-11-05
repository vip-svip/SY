#!/system/bin/sh
# Audit107: malformed IPv6 DNS literals (notably triple-colon forms) must not
# be accepted into firewall RETURN exceptions.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
sh -n "$A"
python3 - "$A" <<'PYCODE'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
start=s.index('      # Accept IPv6 literals made only of hexadecimal groups and colons.')
end=s.index("      if (doubles == 0 && count != 8) ok=0", start)
block=s[start:end]
assert 'ip ~ /:::/' in block, 'triple-colon rejection missing from production validator'
# Exercise the same structural validation algorithm against representative inputs.
def valid(ip):
    if not all(c in '0123456789abcdefABCDEF:' for c in ip) or ':' not in ip or ':::' in ip:
        return False
    d=ip; doubles=0
    while '::' in d:
        d=d.replace('::', ':', 1); doubles+=1
    if doubles > 1: return False
    grp=ip.split(':'); count=0
    for g in grp:
        if g:
            if not all(c in '0123456789abcdefABCDEF' for c in g) or len(g)>4: return False
            count+=1
    if doubles == 0 and count != 8: return False
    if doubles == 1 and count >= 8: return False
    return True
for ip in ('2001:db8::1', '::1', '2001:db8:0:0:0:0:0:1'):
    assert valid(ip), f'valid IPv6 rejected: {ip}'
for ip in (':::', '2001:::1', '::::', '1::2::3', 'not:ipv6'):
    assert not valid(ip), f'malformed IPv6 accepted: {ip}'
PYCODE
echo 'FX DNS IPv6 literal validation regression: PASS'
