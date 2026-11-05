#!/system/bin/sh
# A failed iptables -S query must never be interpreted as zero references.
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
assert '_PGHKS_REF4=1\n      if _PGHKS_RULES4=$(iptables $FWWAIT -S 2>/dev/null); then' in safe
assert '_PGHKS_REF6=1\n      if _PGHKS_RULES6=$(ip6tables $FWWAIT -S 2>/dev/null); then' in safe
assert 'if _PGHKS_RULES4=$(iptables $FWWAIT -S 2>/dev/null); then' in safe
assert 'if _PGHKS_RULES6=$(ip6tables $FWWAIT -S 2>/dev/null); then' in safe
assert '_PGHKS_VERIFY_UNKNOWN=1' in safe
assert '[ "$_PGHKS_STALE_LEFT" -gt 0 ] || [ "$_PGHKS_VERIFY_UNKNOWN" = "1" ]' in safe
# A bare pipeline would mask the iptables exit code and is specifically forbidden.
assert '$(iptables $FWWAIT -S 2>/dev/null | grep -cE' not in safe
assert '$(ip6tables $FWWAIT -S 2>/dev/null | grep -cE' not in safe
print('PGHKS firewall-query failure safe regression: PASS')
PY
