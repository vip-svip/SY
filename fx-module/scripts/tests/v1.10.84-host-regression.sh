#!/bin/sh
# Repeatable host-side transaction recovery tests; not Android device tests.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
APPLY="$ROOT/scripts/apply.sh"
python3 - "$APPLY" <<'PYTEST'
import sys
s=open(sys.argv[1]).read()
# Commit decision must be published before recovery data is removed.
commit=s.index('PG_SUB_TXN_BACKUP" "${PG_SUB_TXN_CORE_WAS_RUNNING', s.index('pg_apply_exit()'))
commit_mv=s.index('mv -f "$_pg_commit_tmp" "$PG_SUB_TXN_MARKER"', commit)
commit_backup_rm=s.index('rm -f "$PG_SUB_TXN_BACKUP"', commit_mv)
commit_marker_rm=s.index('rm -f "$PG_SUB_TXN_MARKER"', commit_backup_rm)
assert commit < commit_mv < commit_backup_rm < commit_marker_rm
assert 'vpn-sub transaction commit marker failed; recovery data retained' in s
assert 'cleanup incomplete, committed marker/backup retained where possible for retry' in s
assert 'committed transaction cleanup incomplete; retry on next apply' in s
assert '[ -z "${PG_SUB_TXN_SHA256:-}" ] || [ "$_pg_backup_hash" != "$PG_SUB_TXN_SHA256" ]' in s
assert 'refusing to restore and retaining recovery evidence' in s
assert 'settings restore failed; backup retained' in s
assert 'core lifecycle restoration failed; recovery marker retained for retry' in s
assert 'core lifecycle restoration failed; marker/backup retained for retry' in s
assert 'if [ -n "$_pg_crash_bak" ] && [ "$_pg_crash_phase" = committed ]; then' in s
assert 'if [ -n "$_pg_crash_bak" ] && [ "$_pg_crash_phase" != committed ] && [ -s "$_pg_crash_bak" ]; then' in s
assert 'network rules still require normal apply reconciliation' in s
start=s.index('pg_sub_restore_core_runtime() {')
fn=s[start:s.index('\n}\n', start)+3]
assert 'if [ "$_pg_core_live" = 1 ]; then' in fn
assert 'vpncore_start >/dev/null 2>&1' in fn
assert 'If a previous retry already stopped the core, go straight to start.' in fn
PYTEST
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
printf 'old-settings\n' > "$TMP/settings.backup"
expected=$(sha256sum "$TMP/settings.backup" | awk '{print $1}')
[ "$(sha256sum "$TMP/settings.backup" | awk '{print $1}')" = "$expected" ]
printf 'tampered-settings\n' > "$TMP/settings.backup"
[ "$(sha256sum "$TMP/settings.backup" | awk '{print $1}')" != "$expected" ]
printf 'current-settings\n' > "$TMP/settings.current"
printf '%s\n%s\n%s\ncommitted\n' "$TMP/settings.backup" 0 "$expected" > "$TMP/marker"
[ "$(sed -n '4p' "$TMP/marker")" = committed ]
# Simulate cleanup interruption: orphan backup must not be auto-restored.
rm -f "$TMP/marker"
[ -f "$TMP/settings.backup" ]
grep -q current-settings "$TMP/settings.current"
printf 'active\n' > "$TMP/marker"
[ -f "$TMP/marker" ] && [ -f "$TMP/settings.backup" ]
test -f "$ROOT/certs/submodules/pg_mitm_ca/module.prop"
test -f "$ROOT/certs/submodules/pg_https_ca/module.prop"
echo 'PASS: commit ordering, checksum tamper, cleanup interruption, retained recovery evidence, core retry contract, cert submodules'
