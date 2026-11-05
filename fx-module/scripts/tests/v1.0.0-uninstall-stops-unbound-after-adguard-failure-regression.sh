#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
U="$ROOT/uninstall.sh"
sh -n "$U"
python3 - "$U" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text(encoding='utf-8')
a=s.index('sh "$MODDIR/scripts/adguardhome.sh" stop "$MODDIR" "$PG"')
u=s.index('sh "$MODDIR/scripts/unbound.sh" stop "$MODDIR" "$PG"',a)
end=s.index('# ============================================================\n# A2.',a)
block=s[a:end]
if not a < u < end: raise SystemExit('FAIL: standalone Unbound stop not after AdGuard Home stop')
if 'elif [ -x "$MODDIR/scripts/unbound.sh" ]' in block: raise SystemExit('FAIL: Unbound cleanup remains an elif branch')
if block.count('PG_KEEP_DATA=1') < 2: raise SystemExit('FAIL: failed front-end/resolver stops must both preserve state')
if s.index('sh "$MODDIR/scripts/localdns-watchdog.sh" stop "$MODDIR" "$PG"') > a:
    raise SystemExit('FAIL: watchdog must be stopped before DNS engines')
print('PASS: uninstall independently stops Unbound even if AdGuard Home wrapper fails; preserves recovery state on either failure')
PY
