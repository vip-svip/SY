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
assert 'if [ -z "$VPN_EXTERNAL_UID" ]; then' in block
assert 'fw4 -A PGHKS -m owner --uid-owner "$VPN_EXTERNAL_UID" -j RETURN 2>/dev/null || _PGHKS_BUILD_OK=0' in block
assert 'fw6 -A PGHKS -m owner --uid-owner "$VPN_EXTERNAL_UID" -j RETURN 2>/dev/null || _PGHKS_BUILD_OK=0' in block
assert 'if [ "$_PGHKS_BUILD_OK" = "1" ] && fw_flush' in block
assert block.index('fw4 -N PGHKS') < block.index('fw4 -F PGHKS')
assert block.index('fw6 -N PGHKS') < block.index('fw6 -F PGHKS')
assert '[ "$_PGHKS_HOOK_OK" != "1" ] || fw_flush 2>/dev/null || _PGHKS_HOOK_OK=0' in block
assert 'while [ "$_PGHKS_HOOK_N" -lt 64 ] && iptables $FWWAIT -D OUTPUT -j PGHKS' in block
assert 'while [ "$_PGHKS_HOOK_N" -lt 64 ] && ip6tables $FWWAIT -D OUTPUT -j PGHKS' in block
assert 'pg_fail vpn_hide "第三方 VPN PGHKS 规则提交或双栈 OUTPUT 挂载失败' in block
assert block.index('pg_fail vpn_hide "检测到第三方 VPN') < block.index('fw4 -F PGHKS')
PY
sh -n "$A"
echo 'FX external VPN hide transaction regression: PASS'
