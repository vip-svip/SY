#!/bin/sh
# Host-side regression assertions for transaction recovery/lock policy. No Android
# mounts, firewall changes, or real sing-box/network operations are performed.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
python3 - "$ROOT/scripts/apply.sh" <<'PY'
import sys
s=open(sys.argv[1]).read()
# Current policy fails closed for missing/malformed PID to avoid mkdir/PID publication race.
assert 'Never evict a lock whose recorded owner is still alive' in s
assert 'Age alone cannot distinguish that tiny' in s
assert '_lk_age=' not in s
assert 'mv "$APPLY_LOCK" "$_lk_stale"' in s
# Restored config validation must happen before core restart on both recovery paths.
assert 'pg_sub_validate_restored_core()' in s
assert 'vpncore_genconf "$_pg_vbin"' in s
assert 'vpncore_check_conf "$_pg_vbin" "$_pg_vcfg"' in s
assert 'restored settings failed sing-box config validation' in s
# Reject traversal paths and invalid core state values in persistent marker.
assert '_pg_crash_suffix=${_pg_crash_bak#"$PG"/settings.conf.vpn-sub-backup.}' in s
assert "case \"$_pg_crash_suffix\" in ''|*[!A-Za-z0-9._-]*|*/*)" in s
assert 'case "$_pg_crash_core" in 0|1)' in s
# Never guess a restore when a backup is orphaned without a transaction marker.
assert 'orphan backup found without transaction marker' in s
assert 'current settings left untouched pending manual review' in s
PY
# Ensure the module has two independent certificate submodules.
test -f "$ROOT/certs/submodules/pg_mitm_ca/module.prop"
test -f "$ROOT/certs/submodules/pg_https_ca/module.prop"
echo 'PASS: lock-owner safety, strict recovery-marker validation, restored-config check ordering, orphan-backup handling, independent cert submodules'
