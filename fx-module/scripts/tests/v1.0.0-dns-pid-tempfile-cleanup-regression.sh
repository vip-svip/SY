#!/system/bin/sh
# Failed PID marker publication must not leave stale per-process temp files.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
for name in ('unbound.sh','adguardhome.sh'):
    text=(root/'scripts'/name).read_text()
    write='> "$PIDFILE.tmp.$$" || { rm -f "$PIDFILE.tmp.$$" 2>/dev/null || :; kill "$_new" 2>/dev/null || :; return 1; }'
    rename='mv -f "$PIDFILE.tmp.$$" "$PIDFILE" || { rm -f "$PIDFILE.tmp.$$" 2>/dev/null || :; kill "$_new" 2>/dev/null || :; return 1; }'
    if write not in text or rename not in text:
        raise SystemExit(f'FAIL: PID temp cleanup missing in {name}')
print('PASS: DNS engine PID publication failures clean temp markers and terminate unregistered child')
PY
