#!/system/bin/sh
# PGHKS must be rebuilt on re-apply and not reported active after partial hook failure.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
python3 - "$ROOT/scripts/apply.sh" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
start=s.index('# (2) QUIC/STUN/mDNS/SSDP/本地发现全断')
end=s.index('# (4) IPv6：隐藏态下 IPv6', start)
b=s[start:end]
assert 'fw4 -F PGHKS' in b and 'fw6 -F PGHKS' in b
assert 'if fw_flush 2>/dev/null && fw4 -I OUTPUT -j PGHKS && fw6 -I OUTPUT -j PGHKS; then' in b
assert 'pg_fail vpn_hide "PGHKS 规则提交或 IPv4/IPv6 OUTPUT 挂载失败' in b
assert b.index('if fw_flush') < b.index('HIDE_FW=1')
assert 'iptables $FWWAIT -D OUTPUT -j PGHKS' in b
assert 'ip6tables $FWWAIT -D OUTPUT -j PGHKS' in b
PY
sh -n "$ROOT/scripts/apply.sh"
echo 'FX PGHKS commit failure and idempotency regression: PASS'
