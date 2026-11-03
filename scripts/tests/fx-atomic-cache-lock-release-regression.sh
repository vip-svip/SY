#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MODULE=\${1:-"$ROOT/fx-module"}
APPLY="$MODULE/scripts/apply.sh"
SUBFETCH="$MODULE/scripts/subfetch.sh"
HOST_TEST="$MODULE/scripts/tests/v1.0.0-hosts-cache-concurrency-regression.sh"
SUB_TEST="$MODULE/scripts/tests/v1.0.0-subfetch-concurrency-regression.sh"
PATCHER="$ROOT/fx-patches/patch_atomic_cache_lock_release.py"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for f in "$APPLY" "$SUBFETCH" "$HOST_TEST" "$SUB_TEST" "$PATCHER"; do
  [ -s "$f" ] || fail "required cache lock source/test missing: $f"
done

# The patch is part of both restore-from-Release build lanes. Prove it is
# idempotent against the exact restored module tree that will be tested.
python3 "$PATCHER" "$MODULE" || fail "first atomic-lock patch application failed"
python3 "$PATCHER" "$MODULE" || fail "second atomic-lock patch application failed"

grep -Fq 'mv "$_hf_lock" "$_hf_release"' "$APPLY" || fail "Hosts lock release does not atomically rename the owner directory"
grep -Fq 'mv "$LOCK" "$_sl_release"' "$SUBFETCH" || fail "subscription lock release does not atomically rename the owner directory"
grep -Fq 'cat "$_hf_lock/pid" 2>/dev/null || :' "$APPLY" || fail "Hosts waiter does not tolerate lock disappearance"
grep -Fq 'cat "$LOCK/pid" 2>/dev/null || :' "$SUBFETCH" || fail "subscription waiter does not tolerate lock disappearance"
if grep -Fq 'rm -f "$_hf_lock/pid" 2>/dev/null; rmdir "$_hf_lock"' "$APPLY"; then
  fail "Hosts lock still exposes a pid-less directory before rmdir"
fi
if grep -Fq 'rm -f "$LOCK/pid" 2>/dev/null; rmdir "$LOCK"' "$SUBFETCH"; then
  fail "subscription lock still exposes a pid-less directory before rmdir"
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
