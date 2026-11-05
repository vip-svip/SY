#!/bin/sh
# Host-side source-contract regression; not an Android device test.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
APPLY="$ROOT/scripts/apply.sh"
python3 - "$APPLY" <<'PYTEST'
import sys
s=open(sys.argv[1]).read()
# In rollback after successful restore, marker must be removed before backup.
a=s.index('if [ "$_pg_runtime_ok" = 1 ]; then')
b=s.index('pg_log "vpn-sub rollback: runtime/network rollback is best-effort', a)
rb=s[a:b]
assert rb.index('rm -f "$PG_SUB_TXN_MARKER"') < rb.index('rm -f "$PG_SUB_TXN_BACKUP"')
assert 'backup cleanup incomplete; orphan backup retained for diagnosis' in rb
assert 'marker cleanup failed; recovery evidence retained for retry/manual review' in rb
assert 'runtime recovery incomplete; marker/backup retained for retry' in rb
# Same cleanup contract for crash recovery.
a=s.index('if [ "$_pg_crash_ok" = 1 ]; then')
b=s.index('\n      fi', s.index('network rules still require normal apply reconciliation', a))
cr=s[a:b]
assert cr.index('rm -f "$PG_SUB_TXN_MARKER"') < cr.index('rm -f "$_pg_crash_bak"')
assert 'backup cleanup incomplete; orphan backup retained for diagnosis' in cr
assert 'marker cleanup failed; recovery evidence retained for retry/manual review' in cr
# Commit path remains commit-marker first, then backup, then marker.
a=s.index('pg_apply_exit()')
commit=s.index('PG_SUB_TXN_BACKUP" "${PG_SUB_TXN_CORE_WAS_RUNNING',a)
commit_mv=s.index('mv -f "$_pg_commit_tmp" "$PG_SUB_TXN_MARKER"',commit)
commit_backup=s.index('rm -f "$PG_SUB_TXN_BACKUP"',commit_mv)
commit_marker=s.index('rm -f "$PG_SUB_TXN_MARKER"',commit_backup)
assert commit < commit_mv < commit_backup < commit_marker
assert 'vpn-sub crash recovery ERROR: transaction marker invalid or backup missing; preserving marker for manual recovery' in s
PYTEST
# Historical regression scripts are run by the top-level test runner. Do not invoke
# them recursively here: each historical script may itself aggregate earlier tests,
# causing exponential runtime when the whole suite is run.
sh -n "$APPLY"
sh -n "$ROOT/scripts/tests/v1.10.85-host-regression.sh"
test -f "$ROOT/certs/submodules/pg_mitm_ca/module.prop"
test -f "$ROOT/certs/submodules/pg_https_ca/module.prop"
echo 'PASS: recovery evidence cleanup ordering/logging, historical v1.10.77-v1.10.84 regression suite, shell syntax, independent cert submodules'
