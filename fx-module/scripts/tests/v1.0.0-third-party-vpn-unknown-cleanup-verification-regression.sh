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
assert '_PGHKS_STALE_LEFT=0' in safe
assert 'iptables $FWWAIT -S' in safe and 'ip6tables $FWWAIT -S' in safe
assert 'PGHKS 清理未完全验证' in safe
assert '已验证 PGHKS 双栈跳转与链均已清理' in safe
assert safe.index('iptables $FWWAIT -X PGHKS') < safe.index('_PGHKS_STALE_LEFT=0')
assert '_PGHKS_VERIFY_UNKNOWN=1' in safe
assert '[ "$_PGHKS_STALE_LEFT" -gt 0 ] || [ "$_PGHKS_VERIFY_UNKNOWN" = "1" ]' in safe
PY
sh -n "$A"
echo 'FX third-party VPN unknown-UID cleanup verification regression: PASS'
