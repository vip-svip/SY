#!/system/bin/sh
# Uninstall must not flush a chain while any table chain references it.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
U="$ROOT/uninstall.sh"
python3 - "$U" <<'PYCODE'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
start=s.index('_pg_fw_clean_chain() {')
end=s.index('\n# 再次收敛本模块命名的链', start)
b=s[start:end]
loop=b.index('while [ "$_pf_i" -lt 64 ]')
query=b.index('-S 2>/dev/null', loop)
refcheck=b.index('grep -E "^-A .* -j ${_pf_target}', query)
warn=b.index('preserving chain for retry', refcheck)
ret=b.index('return 0', warn)
flush=b.index('-F "$_pf_chain"', ret)
assert loop < query < refcheck < warn < ret < flush, 'must query all table references and return before flushing'
assert 'table query failed; preserving $_pf_chain for retry' in b
# No eager -F/-X may run before the guarded cleanup function is defined/called.
a1=s.index('# A1. 防火墙链')
fn=s.index('_pg_fw_clean_chain() {', a1)
pre=s[a1:fn]
assert '-F PGUARD' not in pre and '-F PGNAT' not in pre and '-F PGVPN' not in pre, 'must not flush chains before reference checks'
PYCODE
sh -n "$U"
echo 'FX uninstall preserves referenced firewall chains regression: PASS'
