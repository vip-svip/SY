#!/system/bin/sh
# Static regression: failed transaction commit-marker publication must attempt rollback.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SRC="$ROOT/scripts/apply.sh"
[ -s "$SRC" ] || { echo 'FAIL: apply.sh missing'; exit 1; }
python3 - "$SRC" <<'PY'
import sys
s=open(sys.argv[1], encoding='utf-8').read()
needle='pg_log "vpn-sub commit-marker failure: attempting immediate rollback"'
assert needle in s, 'commit-marker failure must trigger immediate rollback'
start=s.index(needle)
end=s.index('\n        fi', start)
block=s[start:end]
for token in ('pg_sub_sha256', 'PG_SUB_TXN_SHA256', 'cp "$PG_SUB_TXN_BACKUP"', 'mv -f "$_pg_commit_restore" "$CONF"', 'pg_sub_restore_core_runtime', 'recovery evidence retained'):
    assert token in block, 'missing rollback safeguard: '+token
print('PASS: commit-marker failure rollback guards present')
PY
