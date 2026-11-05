#!/system/bin/sh
# Regression: firewall cleanup uncertainty must preserve the retry state tree.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
U="$ROOT/uninstall.sh"
python3 - "$U" <<'PYCODE'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
marker='if [ "$PG_FW_INCOMPLETE" = 1 ]; then\n  PG_KEEP_DATA=1\nfi\nif [ "$PG_KEEP_DATA" = 1 ]; then\n  _mitm_warn "cleanup is incomplete; preserving $PG and its state/source files for a safe retry"'
assert marker in s, 'firewall-incomplete state must set PG_KEEP_DATA before the deletion branch'
assert s.index('if [ "$PG_FW_INCOMPLETE" = 1 ]; then\n  PG_KEEP_DATA=1\nfi') < s.index('if [ "$PG_KEEP_DATA" = 1 ]; then\n  _mitm_warn "cleanup is incomplete; preserving')
assert '为保护重试所需的状态、脚本或挂载源，已保留 $PG' in s
PYCODE
sh -n "$U"
echo 'FX uninstall firewall-incomplete retry-state preservation regression: PASS'
