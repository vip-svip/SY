#!/usr/bin/env python3
"""Regenerate restored-release stale-lock tests for the POSIX file-lock protocol."""
from pathlib import Path
import sys

module = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
test_root = module / "scripts/tests"
ownership_test = test_root / "v1.0.0-subfetch-stale-lock-ownership-regression.sh"
reclaim_test = test_root / "v1.0.0-subfetch-stale-lock-reclaim-regression.sh"

def stale_lock_test_source(label: str) -> str:
    return r'''#!/bin/sh
set -eu
# FX_SUBFETCH_LEGACY_DIR_COMPAT_V1
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
F="$ROOT/scripts/subfetch.sh"
fail(){ echo "FAIL: ''' + label + r''': $*" >&2; exit 1; }
[ -s "$F" ] || fail "subfetch source missing"
grep -Fq 'FX_SUBFETCH_FILE_LOCK_V2' "$F" || fail "v2 file-lock marker missing"
grep -Fq '_sl_stale="$LOCK.stale.' "$F" || fail "stale quarantine path must be unique per reaper"
grep -Fq '$_sl_try"' "$F" || fail "stale quarantine path must include a per-attempt suffix"
grep -Fq 'mv "$LOCK" "$_sl_stale"' "$F" || fail "lock must be quarantined by atomic rename"
grep -Fq '_sl_moved_owner=$(_sl_read_lock_owner "$_sl_stale"' "$F" || fail "quarantined owner must be re-read"
grep -Fq '[ "$_sl_moved_owner" = "$_sl_owner" ]' "$F" || fail "quarantined owner must match the observed owner"
if grep -Fq 'mv "$_sl_stale" "$LOCK"' "$F"; then fail "unverified quarantine must not be restored into a replacement lock"; fi
if grep -Eq 'rm -f "\$LOCK/pid"|rmdir "\$LOCK"' "$F"; then fail "stale reaper must not unlink a pid and directory separately"; fi
sh -n "$F" || fail "subfetch shell syntax invalid"

# Exercise the production helpers against hostile filesystem entries.
command -v mkfifo >/dev/null 2>&1 || fail "mkfifo is required for FIFO lock regression"
command -v timeout >/dev/null 2>&1 || fail "timeout is required to bound FIFO owner reads"
HELPER_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fx-subfetch-lock-helpers.XXXXXX")
sed -n '/^_sl_read_lock_owner() {/,/^}/p' "$F" > "$HELPER_ROOT/read-owner.sh"
sed -n '/^_sl_remove_owned_lock_path() {/,/^}/p' "$F" > "$HELPER_ROOT/remove-lock.sh"
[ -s "$HELPER_ROOT/read-owner.sh" ] && [ -s "$HELPER_ROOT/remove-lock.sh" ] || fail "production lock helpers could not be extracted"
. "$HELPER_ROOT/read-owner.sh"
. "$HELPER_ROOT/remove-lock.sh"

mkdir "$HELPER_ROOT/valid-directory"
printf '%s\n' "$" > "$HELPER_ROOT/valid-directory/pid"
[ "$(_sl_read_lock_owner "$HELPER_ROOT/valid-directory")" = "$" ] || fail "ordinary legacy PID directory owner was not read"
_sl_remove_owned_lock_path "$HELPER_ROOT/valid-directory" || fail "ordinary PID-only lock directory was not removed"
[ ! -e "$HELPER_ROOT/valid-directory" ] || fail "ordinary PID-only lock directory remains"

printf '%s\n' "$" > "$HELPER_ROOT/valid-file"
[ "$(_sl_read_lock_owner "$HELPER_ROOT/valid-file")" = "$" ] || fail "ordinary file-lock owner was not read"
_sl_remove_owned_lock_path "$HELPER_ROOT/valid-file" || fail "ordinary file lock was not removed"
[ ! -e "$HELPER_ROOT/valid-file" ] || fail "ordinary file lock remains"

mkdir "$HELPER_ROOT/unknown-directory"
printf '%s\n' "$" > "$HELPER_ROOT/unknown-directory/pid"
printf 'preserve\n' > "$HELPER_ROOT/unknown-directory/sentinel"
printf 'hidden\n' > "$HELPER_ROOT/unknown-directory/.sentinel"
if _sl_remove_owned_lock_path "$HELPER_ROOT/unknown-directory"; then
  fail "lock directory with unknown entries was recursively removed"
fi
[ -s "$HELPER_ROOT/unknown-directory/pid" ] && [ -s "$HELPER_ROOT/unknown-directory/sentinel" ] && [ -s "$HELPER_ROOT/unknown-directory/.sentinel" ] || fail "unknown lock-directory contents were modified"

printf '%s\n' "$" > "$HELPER_ROOT/pid-target"
mkdir "$HELPER_ROOT/symlink-pid-directory"
ln -s "$HELPER_ROOT/pid-target" "$HELPER_ROOT/symlink-pid-directory/pid"
if _sl_read_lock_owner "$HELPER_ROOT/symlink-pid-directory" >/dev/null 2>&1; then
  fail "legacy lock reader followed a symlinked PID file"
fi
if _sl_remove_owned_lock_path "$HELPER_ROOT/symlink-pid-directory"; then
  fail "legacy lock remover accepted a symlinked PID file"
fi
[ -L "$HELPER_ROOT/symlink-pid-directory/pid" ] && [ -s "$HELPER_ROOT/pid-target" ] || fail "symlinked PID fixture was modified"

mkdir "$HELPER_ROOT/symlink-target"
printf '%s\n' "$" > "$HELPER_ROOT/symlink-target/pid"
ln -s "$HELPER_ROOT/symlink-target" "$HELPER_ROOT/symlink-lock"
if _sl_read_lock_owner "$HELPER_ROOT/symlink-lock" >/dev/null 2>&1; then
  fail "legacy lock reader followed a symlinked lock directory"
fi
if _sl_remove_owned_lock_path "$HELPER_ROOT/symlink-lock"; then
  fail "legacy lock remover accepted a symlinked lock directory"
fi
[ -s "$HELPER_ROOT/symlink-target/pid" ] || fail "symlinked lock target was modified"

mkdir "$HELPER_ROOT/fifo-directory"
mkfifo "$HELPER_ROOT/fifo-directory/pid"
set +e
timeout 2 sh -c '. "$1"; _sl_read_lock_owner "$2" >/dev/null 2>&1' sh "$HELPER_ROOT/read-owner.sh" "$HELPER_ROOT/fifo-directory"
_fifo_read_rc=$?
set -e
[ "$_fifo_read_rc" -ne 0 ] || fail "legacy lock reader accepted a FIFO PID"
[ "$_fifo_read_rc" -ne 124 ] || fail "legacy lock reader blocked while opening a FIFO PID"
if _sl_remove_owned_lock_path "$HELPER_ROOT/fifo-directory"; then
  fail "legacy lock remover accepted a FIFO PID"
fi
[ -p "$HELPER_ROOT/fifo-directory/pid" ] || fail "FIFO PID fixture was removed"

rm -rf "$HELPER_ROOT"

run_stale_case() {
  kind=$1
  T=$(mktemp -d "${TMPDIR:-/tmp}/fx-subfetch-stale-$kind.XXXXXX")
  trap 'rm -rf "$T"' EXIT HUP INT TERM
  mkdir -p "$T/state/subs" "$T/bin"
  url="https://example.invalid/stale-$kind"
  key=$(printf '%s' "$url" | cksum | awk '{print $1}')
  lock="$T/state/subs/.lock.$key"
  if [ "$kind" = directory ]; then
    mkdir "$lock"
    printf '99999999\n' > "$lock/pid"
  else
    printf '99999999\n' > "$lock"
  fi
  printf '#!%s\n' "$(command -v sh)" > "$T/bin/curl"
  cat >> "$T/bin/curl" <<'CURL'
#!/bin/sh
out=''
while [ "$#" -gt 0 ]; do
  if [ "$1" = '-o' ]; then shift; out=$1; fi
  shift
done
[ -n "$out" ] || exit 64
body='vless://123e4567-e89b-12d3-a456-426614174000@edge.example:443?encryption=none#test'
if [ "$out" = '-' ]; then printf '%s\n' "$body"; else printf '%s\n' "$body" > "$out"; fi
CURL
  chmod 0755 "$T/bin/curl"
  printf '#!%s\n' "$(command -v sh)" > "$T/bin/timeout"
  cat >> "$T/bin/timeout" <<'TIMEOUT'
#!/bin/sh
shift
exec "$@"
TIMEOUT
  chmod 0755 "$T/bin/timeout"
  PATH="$T/bin:$PATH" PG="$T/state" MODDIR="$ROOT" sh "$F" "$url" --force > "$T/out" || fail "$kind stale lock request exited non-zero"
  grep -Fq '"ok":1' "$T/out" || { cat "$T/out" >&2; fail "$kind stale lock was not reclaimed"; }
  [ -s "$T/state/subs/$key.txt" ] || fail "$kind stale lock did not produce cache body"
  [ -s "$T/state/subs/$key.meta" ] || fail "$kind stale lock did not produce cache metadata"
  [ ! -e "$lock" ] && [ ! -L "$lock" ] || fail "$kind stale lock path remains after successful fetch"
  rm -rf "$T"
  trap - EXIT HUP INT TERM
}
run_stale_case directory
run_stale_case file
echo 'PASS: stale subscription directory and file locks are reclaimed after owner verification'
'''

if not (module / "scripts/subfetch.sh").is_file():
    raise SystemExit("restored FX subfetch source missing")
if not test_root.is_dir():
    raise SystemExit(f"restored FX stale-lock test directory missing: {test_root}")
ownership_test.write_text(stale_lock_test_source("ownership"), encoding="utf-8")
reclaim_test.write_text(stale_lock_test_source("reclaim"), encoding="utf-8")
ownership_test.chmod(0o755)
reclaim_test.chmod(0o755)
print("Updated stale-lock tests for legacy PID directories and atomic file locks.")
