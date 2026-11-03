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

run_stale_case() {
  kind=$1
  T=$(mktemp -d "\${TMPDIR:-/tmp}/fx-subfetch-stale-$kind.XXXXXX")
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
