#!/system/bin/sh
# A failed chain-specific query is ambiguous; verify absence via a successful full-table snapshot.
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
assert '_pf_after_rules=$(_pg_fw_call "$_pf_bin" "$_pf_table" -S 2>/dev/null)' in b
assert 'grep -E "^-N ${_pf_chain}([[:space:]]|$)"' in b
assert 'final table listing failed; cannot verify $_pf_chain cleanup' in b
assert '-S "$_pf_chain"' not in b, 'must not rely on ambiguous chain-specific query to prove absence'
sh=b.index('if _pf_after_rules=')
check=b.index('grep -E "^-N ${_pf_chain}', sh)
warn=b.index('still exists after cleanup', check)
assert sh < check < warn
PYCODE
sh -n "$U"
echo 'FX uninstall chain-absence verification regression: PASS'
