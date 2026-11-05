#!/system/bin/sh
# Regression: IPv6 OUTPUT jumps must be removed from their owning tables
# before chain flush/delete, including nat redirects after interrupted apply.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
python3 - "$A" <<'PYCODE'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
start=s.index('# 重建链（filter PGUARD + nat PGNAT + VPN/hide 链）')
end=s.index('ANY_FW=0', start)
block=s[start:end]
assert 'for _dt in nat filter mangle; do' in block
assert 'ip6tables $FWWAIT -t "$_dt" -D OUTPUT -j "$_dc"' in block
for chain in ('PGNAT','PGVPN6','PGUARD','PGBLK6','PGHKS'):
    assert chain in block, f'missing IPv6 cleanup chain: {chain}'
assert block.index('ip6tables $FWWAIT -t "$_dt" -D OUTPUT') < block.index('ip6tables-restore -n')
PYCODE
sh -n "$A"
echo 'FX IPv6 firewall jump cleanup regression: PASS'
