#!/system/bin/sh
# Static regression guard for Hosts sidecar transaction safety.
# This test checks source structure only; it is not a runtime fault-injection test.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
V="$ROOT/scripts/vpncore.sh"

# Stage files separately and preserve the previous generation before publishing.
grep -Fq '_hb_wlexc_stage="$PG/cache/wlexc.stage.$$"' "$A"
grep -Fq '_hb_ip_stage="$PG/cache/subnet-ips.list.stage.$$"' "$A"
grep -Fq 'WL_EXC="$_hb_wlexc_stage"' "$A"
grep -Fq '_hb_ip_backup="$PG/cache/subnet-ips.list.rollback.$$"' "$A"
grep -Fq '_hb_wlexc_backup="$PG/cache/wlexc.rollback.$$"' "$A"
grep -Fq '_hb_txn="$PG/cache/sidecar.txn.$$"' "$A"
grep -Fq 'mv -f "$_hb_txn" "$PG/cache/sidecar.txn"' "$A"

# Recovery paths must be unique per process and reject invalid transaction markers.
grep -Fq 'pg_hosts_sidecar_recover() {' "$A"
grep -Fq 'pg_hosts_sidecar_recover || {' "$A"
grep -Fq '_hsr_ip_restore="$PG/cache/subnet-ips.list.recover.$$"' "$A"
grep -Fq '_hsr_wlexc_restore="$PG/cache/wlexc.tmp.recover.$$"' "$A"
grep -Fq 'invalid sidecar transaction marker flags' "$A"
grep -Fq 'invalid sidecar transaction phase' "$A"
grep -Fq 'phase=active' "$A"
grep -Fq 'phase=committed' "$A"
grep -Fq 'previous cache generation restored' "$A"
grep -Fq 'transaction marker and recovery copies preserved' "$A"
grep -Fq '_hb_ip_rollback_tmp="$PG/cache/subnet-ips.list.rollback-restore.$$"' "$A"
grep -Fq '_hb_wlexc_rollback_tmp="$PG/cache/wlexc.rollback-restore.$$"' "$A"
grep -Fq 'recovery copy preserved at $_hb_ip_backup' "$A"
grep -Fq 'recovery copy preserved at $_hb_wlexc_backup' "$A"
grep -Fq '_hb_commit_marker="$PG/cache/sidecar.txn.commit.$$"' "$A"
grep -Fq 'pg_log "=== apply start (pid $$) ==="' "$A"

# DNS exception cache is consumed and Adblock exception wrappers are normalized.
grep -Fq '[ -s "$PG/cache/wlexc.tmp" ] && cat "$PG/cache/wlexc.tmp"' "$V"
grep -Fq 's/^@@||//;s/\^$//' "$V"

python3 - "$A" <<'PY'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text()
fn = s.index('pg_hosts_sidecar_recover() {')
call = s.index('pg_hosts_sidecar_recover || {')
assert fn < call, (fn, call)
ip_publish = s.index('if ! mv -f "$_hb_ip_stage" "$PG/cache/subnet-ips.list"')
wl_publish = s.index('if ! mv -f "$_hb_wlexc_stage" "$PG/cache/wlexc.tmp"')
rollback_cp = s.index('cp -p "$_hb_ip_backup" "$_hb_ip_rollback_tmp"', wl_publish)
rollback_mv = s.index('mv -f "$_hb_ip_rollback_tmp" "$PG/cache/subnet-ips.list"', rollback_cp)
assert ip_publish < wl_publish < rollback_cp < rollback_mv, (ip_publish, wl_publish, rollback_cp, rollback_mv)
for bad in ('recover.$"', 'commit.$"', 'printf \'pid=%s\\n\' "$"'):
    assert bad not in s, f"unexpanded PID placeholder remains: {bad}"
# Match a lone dollar, not the second character of the valid shell $ PID.
import re
for line in s.splitlines():
    if 're.search' not in line:
        assert not re.search(r'(?<!\$)pid \$\) ==="', line), 'unexpanded PID placeholder remains'
# Recovery marker must not be removed until both sidecars have been handled.
recovery = s[fn:call]
assert recovery.index('if [ "$_hsr_had_ip" = 1 ]') < recovery.index('if [ "$_hsr_had_wlexc" = 1 ]')
# There is an earlier marker removal in the committed-transaction cleanup branch.
# Check the final active-transaction recovery removal, after both sidecars are handled.
assert recovery.rindex('rm -f "$_hsr_marker"') > recovery.index('if [ "$_hsr_had_wlexc" = 1 ]')
PY
echo 'FX Hosts sidecar transaction static regression: PASS'
