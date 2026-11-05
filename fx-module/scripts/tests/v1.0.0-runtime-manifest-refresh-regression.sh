#!/bin/sh
# Source-contract regression: config commits/rollbacks and repeated start must republish runtime manifests.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
python3 - "$ROOT/scripts/apply.sh" "$ROOT/scripts/mitm-engine.sh" <<'PY'
import sys
apply = open(sys.argv[1], encoding='utf-8').read()
engine = open(sys.argv[2], encoding='utf-8').read()
trap = apply[apply.index('pg_apply_exit() {'):apply.index("trap 'pg_apply_exit' EXIT")]
assert 'sync-mitm-hosts.sh sync-urlrewrite.sh' in trap
assert trap.index('sync-mitm-hosts.sh sync-urlrewrite.sh') < trap.index('rm -rf "$APPLY_LOCK"')
start = engine[engine.index('  start)'):engine.index('  stop)', engine.index('  start)'))]
assert start.index('sync-mitm-hosts.sh') < start.index('already running pid=')
assert start.index('sync-urlrewrite.sh') < start.index('already running pid=')
assert start.index('sync-subs.sh') < start.index('already running pid=')
print('FX runtime manifests refresh after final apply state and before repeated-start early return: PASS')
PY
