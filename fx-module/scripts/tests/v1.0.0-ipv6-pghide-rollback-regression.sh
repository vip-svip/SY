#!/system/bin/sh
# IPv6 leak-guard hooks and PGHIDE must not report success after failed commit/mount.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
python3 - "$A" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
# Normal IPv6 fail-closed path must gate hook and success log on commit+hook success.
a=s.index('    fw6 -F PGBLK6', s.index('# (h) IPv6'))
b=s.index('  # ---------- vpn_hide', a)
block=s[a:b]
assert 'if fw_flush 2>/dev/null && fw6 -I OUTPUT -j PGBLK6; then' in block
assert 'pg_fail vpn "PGBLK6 规则提交或 OUTPUT 挂载失败' in block
assert block.index('if fw_flush') < block.index('pg_log "vpn: ipv6 blocked for apps')
# PGHIDE failure branch attempts to detach and remove the failed chain.
a=s.index('if fw_flush 2>/dev/null && nat_flush 2>/dev/null && nat4 -I OUTPUT -j PGHIDE')
b=s.index('    # (2) QUIC/STUN', a)
block=s[a:b]
assert 'iptables $FWWAIT -t nat -D OUTPUT -j PGHIDE' in block
assert 'iptables $FWWAIT -t nat -F PGHIDE' in block
assert 'iptables $FWWAIT -t nat -X PGHIDE' in block
assert 'pg_fail vpn_hide' in block
# Hide-mode IPv6 block is gated similarly.
a=s.index('if [ "$HIDE_LEVEL" != "0" ] && [ "$(pg_get vpn_ipv6 0)" != "1" ]')
b=s.index('    # (5) TCP 指纹规范化', a)
block=s[a:b]
assert 'if fw_flush 2>/dev/null && fw6 -I OUTPUT -j PGBLK6; then' in block
assert 'pg_fail vpn_hide "隐藏模式 PGBLK6' in block
assert block.index('if fw_flush') < block.index('pg_log "vpn_hide: IPv6 强制全断')
PY
sh -n "$A"
echo 'FX IPv6 leak-guard and PGHIDE rollback regression: PASS'
