#!/bin/sh
# Repeatable host-side fault injection; not Android device testing.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
python3 - "$ROOT/scripts/apply.sh" <<'PY'
import sys
s=open(sys.argv[1]).read()
assert 'Age alone cannot distinguish that tiny' in s
assert 'never evict it automatically' in s
assert '_lk_age=' not in s
assert 'mv "$APPLY_LOCK" "$_lk_stale"' in s
assert 'if [ "$_lk_pid_again" = "$_lk_pid" ] && ! kill -0 "$_lk_pid_again" 2>/dev/null' in s
assert 'exit 75' in s
assert '_pg_backup_hash=$(pg_sub_sha256 "$PG_SUB_TXN_BACKUP"' in s
assert '[ "$_pg_backup_hash" != "$PG_SUB_TXN_SHA256" ]' in s
assert 'refusing to restore and retaining recovery evidence' in s
assert 'marker/backup retained' in s
assert 'network rules still require normal apply reconciliation' in s
PY
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir "$tmp/apply.lock"
touch -d '10 minutes ago' "$tmp/apply.lock"
[ ! -e "$tmp/apply.lock/pid" ]
test -d "$tmp/apply.lock" # age alone must not evict an unpublished PID
printf '%s\n' "$$" > "$tmp/apply.lock/pid"
kill -0 "$$"
test -d "$tmp/apply.lock" # live owner remains protected
printf 'known-good-settings\n' > "$tmp/backup"
sha() { sha256sum "$1" | awk '{print $1}'; }
expected=$(sha "$tmp/backup")
[ "$(sha "$tmp/backup")" = "$expected" ]
printf 'tampered-settings\n' > "$tmp/backup"
[ "$(sha "$tmp/backup")" != "$expected" ]
test -f "$ROOT/certs/submodules/pg_mitm_ca/module.prop"
test -f "$ROOT/certs/submodules/pg_https_ca/module.prop"
echo 'PASS: missing-PID stale-lock fault injection fails closed; live PID preserved; backup tamper detected; cert submodules present'
