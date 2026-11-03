#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MODULE=${1:-"$ROOT/fx-module"}
APPLY="$MODULE/scripts/apply.sh"
SUBFETCH="$MODULE/scripts/subfetch.sh"
HOST_TEST="$MODULE/scripts/tests/v1.0.0-hosts-cache-concurrency-regression.sh"
SUB_TEST="$MODULE/scripts/tests/v1.0.0-subfetch-concurrency-regression.sh"
PATCHER="$ROOT/fx-patches/patch_atomic_cache_lock_release.py"
FILE_LOCK_PATCHER="$ROOT/fx-patches/patch_subfetch_file_lock.py"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for f in "$APPLY" "$SUBFETCH" "$HOST_TEST" "$SUB_TEST" "$PATCHER" "$FILE_LOCK_PATCHER"; do
  [ -s "$f" ] || fail "required cache lock source/test missing: $f"
done

# The patch is part of both restore-from-Release build lanes. Prove it is
# idempotent against the exact restored module tree that will be tested.
python3 "$PATCHER" "$MODULE" || fail "first atomic-lock patch application failed"
python3 "$PATCHER" "$MODULE" || fail "second atomic-lock patch application failed"
python3 "$FILE_LOCK_PATCHER" "$MODULE" || fail "first subscription file-lock patch application failed"
python3 "$FILE_LOCK_PATCHER" "$MODULE" || fail "second subscription file-lock patch application failed"

# Run the canonical concurrency fixture, not an older copy embedded in the
# published module. The source fixture contains the deterministic transfer gate.
install -D -m 0755 "$ROOT/scripts/tests/v1.0.0-subfetch-concurrency-regression.sh" "$SUB_TEST"

grep -Fq 'mv "$_hf_lock" "$_hf_release"' "$APPLY" || fail "Hosts lock release does not atomically rename the owner directory"
grep -Fq 'set -C' "$SUBFETCH" || fail "subscription lock does not use noclobber atomic file creation"
grep -Fq 'mv "$LOCK" "$_sl_release"' "$SUBFETCH" || fail "subscription file lock release does not atomically rename the owner file"
grep -Fq '_sl_read_lock_owner "$LOCK"' "$SUBFETCH" || fail "subscription lock owner validation missing"
if grep -Fq 'while ! mkdir "$LOCK"' "$SUBFETCH"; then
  fail "subscription lock still uses the flaky mkdir acquisition loop"
fi
python3 - "$APPLY" "$SUBFETCH" <<'PY'
from pathlib import Path
import sys
apply = Path(sys.argv[1]).read_text(encoding="utf-8")
subfetch = Path(sys.argv[2]).read_text(encoding="utf-8")
assert '_hf_owner=$(cat "$_hf_lock/pid" 2>/dev/null)\\n' not in apply, "Hosts waiter still has an unguarded owner read"
assert '_hf_owner2=$(cat "$_hf_lock/pid" 2>/dev/null)\\n' not in apply, "Hosts stale-owner recheck still has an unguarded read"
assert 'FX_SUBFETCH_FILE_LOCK_V2' in subfetch, "subscription file lock version marker missing"
assert '( umask 077; set -C; printf ' in subfetch, "subscription file lock must atomically create a private owner file"
assert '[ ! -L "$LOCK" ] && [ ! -e "$LOCK" ]' in subfetch, "subscription file lock must refuse symlink or pre-existing paths"
assert 'mv "$LOCK" "$_sl_release"' in subfetch, "subscription file lock release must atomically rename its owner file"
PY
if grep -Fq 'rm -f "$_hf_lock/pid" 2>/dev/null; rmdir "$_hf_lock"' "$APPLY"; then
  fail "Hosts lock still exposes a pid-less directory before rmdir"
fi

sh -n "$APPLY" || fail "patched apply.sh has invalid POSIX shell syntax"
sh -n "$SUBFETCH" || fail "patched subfetch.sh has invalid POSIX shell syntax"

# Repeated real two-worker races exercise both critical sections. A worker failure
# now emits its identity and exit code instead of leaving an empty CI test log.
i=1
while [ "$i" -le 6 ]; do
  if command -v timeout >/dev/null 2>&1; then
    timeout 8 sh "$HOST_TEST" || fail "Hosts concurrent cache run $i failed"
  else
    sh "$HOST_TEST" || fail "Hosts concurrent cache run $i failed"
  fi
  i=$((i+1))
done
i=1
while [ "$i" -le 4 ]; do
  if command -v timeout >/dev/null 2>&1; then
    timeout 8 sh "$SUB_TEST" || fail "subscription concurrent cache run $i failed"
  else
    sh "$SUB_TEST" || fail "subscription concurrent cache run $i failed"
  fi
  i=$((i+1))
done
echo "PASS: atomic Hosts/subscription lock release; 6 Hosts and 4 subscription concurrency runs passed"
