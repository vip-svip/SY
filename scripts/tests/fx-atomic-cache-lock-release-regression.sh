#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MODULE=${1:-"$ROOT/fx-module"}
APPLY="$MODULE/scripts/apply.sh"
SUBFETCH="$MODULE/scripts/subfetch.sh"
HOST_TEST="$MODULE/scripts/tests/v1.0.0-hosts-cache-concurrency-regression.sh"
SUB_TEST="$MODULE/scripts/tests/v1.0.0-subfetch-concurrency-regression.sh"
PATCHER="$ROOT/fx-patches/patch_atomic_cache_lock_release.py"
HOST_FILE_LOCK_PATCHER="$ROOT/fx-patches/patch_hosts_file_lock.py"
FILE_LOCK_PATCHER="$ROOT/fx-patches/patch_subfetch_file_lock.py"
LEGACY_TEST_PATCHER="$ROOT/fx-patches/patch_subfetch_legacy_lock_tests.py"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for f in "$APPLY" "$SUBFETCH" "$HOST_TEST" "$SUB_TEST" "$PATCHER" "$HOST_FILE_LOCK_PATCHER" "$FILE_LOCK_PATCHER" "$LEGACY_TEST_PATCHER"; do
  [ -s "$f" ] || fail "required cache lock source/test missing: $f"
done

# The patch is part of both restore-from-Release build lanes. Prove it is
# idempotent against the exact restored module tree that will be tested.
python3 "$PATCHER" "$MODULE" || fail "first legacy lock compatibility patch application failed"
python3 "$PATCHER" "$MODULE" || fail "second legacy lock compatibility patch application failed"
python3 "$HOST_FILE_LOCK_PATCHER" "$MODULE" || fail "first Hosts file-lock patch application failed"
python3 "$HOST_FILE_LOCK_PATCHER" "$MODULE" || fail "second Hosts file-lock patch application failed"
python3 "$FILE_LOCK_PATCHER" "$MODULE" || fail "first subscription file-lock patch application failed"
python3 "$FILE_LOCK_PATCHER" "$MODULE" || fail "second subscription file-lock patch application failed"
python3 "$LEGACY_TEST_PATCHER" "$MODULE" || fail "first stale-lock compatibility test patch application failed"
python3 "$LEGACY_TEST_PATCHER" "$MODULE" || fail "second stale-lock compatibility test patch application failed"

# Run the canonical concurrency fixture, not an older copy embedded in the
# published module. The source fixture contains the deterministic transfer gate.
install -D -m 0755 "$ROOT/scripts/tests/v1.0.0-subfetch-concurrency-regression.sh" "$SUB_TEST"

grep -Fq 'FX_HOSTS_FILE_LOCK_V2' "$APPLY" || fail "Hosts cache does not use the reviewed atomic file lock"
grep -Fq 'set -C' "$APPLY" || fail "Hosts lock does not use noclobber atomic file creation"
grep -Fq 'mv "$_hf_lock" "$_hf_release"' "$APPLY" || fail "Hosts lock release does not atomically rename its owner file"
grep -Fq 'FX_SUBFETCH_FILE_LOCK_V2' "$SUBFETCH" || fail "subscription cache does not use the reviewed atomic file lock"
grep -Fq 'set -C' "$SUBFETCH" || fail "subscription lock does not use noclobber atomic file creation"
grep -Fq 'mv "$LOCK" "$_sl_release"' "$SUBFETCH" || fail "subscription file lock release does not atomically rename the owner file"
grep -Fq '_sl_read_lock_owner "$LOCK"' "$SUBFETCH" || fail "subscription lock owner validation missing"
grep -Fq 'FX_SUBFETCH_LEGACY_DIR_COMPAT_V1' "$MODULE/scripts/tests/v1.0.0-subfetch-stale-lock-ownership-regression.sh" || fail "legacy lock ownership regression was not migrated"
grep -Fq 'FX_SUBFETCH_LEGACY_DIR_COMPAT_V1' "$MODULE/scripts/tests/v1.0.0-subfetch-stale-lock-reclaim-regression.sh" || fail "legacy lock reclaim regression was not migrated"
if grep -Fq 'while ! mkdir "$LOCK"' "$SUBFETCH"; then
  fail "subscription lock still uses the flaky mkdir acquisition loop"
fi
python3 - "$APPLY" "$SUBFETCH" <<'PY'
from pathlib import Path
import sys
apply = Path(sys.argv[1]).read_text(encoding="utf-8")
subfetch = Path(sys.argv[2]).read_text(encoding="utf-8")
assert 'FX_HOSTS_FILE_LOCK_V2' in apply, "Hosts atomic file lock version marker missing"
assert '( umask 077; set -C; printf ' in apply, "Hosts lock must atomically create a private owner file"
assert '[ ! -L "$_hf_lock" ] && [ ! -e "$_hf_lock" ]' in apply, "Hosts lock must refuse symlink or pre-existing paths"
assert 'mv "$_hf_lock" "$_hf_release"' in apply, "Hosts lock release must atomically rename its owner file"
assert 'while ! mkdir "$_hf_lock"' not in apply, "Hosts lock still uses mkdir acquisition"
assert 'FX_SUBFETCH_FILE_LOCK_V2' in subfetch, "subscription file lock version marker missing"
assert '( umask 077; set -C; printf ' in subfetch, "subscription file lock must atomically create a private owner file"
assert '[ ! -L "$LOCK" ] && [ ! -e "$LOCK" ]' in subfetch, "subscription file lock must refuse symlink or pre-existing paths"
assert 'mv "$LOCK" "$_sl_release"' in subfetch, "subscription file lock release must atomically rename its owner file"
PY
if grep -Fq 'while ! mkdir "$_hf_lock"' "$APPLY"; then
  fail "Hosts lock still uses the legacy mkdir acquisition loop"
fi

sh -n "$APPLY" || fail "patched apply.sh has invalid POSIX shell syntax"
sh -n "$SUBFETCH" || fail "patched subfetch.sh has invalid POSIX shell syntax"

# Use a deterministic transfer gate, not a timing-only sleep. The first
# same-URL fetch stays inside hosts_fetch_cached() while the second process
# contends for the exact restored release function. Then validate the committed
# cache body against its SHA-256 sidecar and require a fully serialized timeline.
_GATE_TMP=$(mktemp -d "/tmp/fx-hosts-cache-gate.XXXXXX")
trap 'rm -rf "$_GATE_TMP"' EXIT HUP INT TERM
cat > "$_GATE_TMP/hosts-gate.sh" <<'HOST_GATE'
#!/bin/sh
set -eu
APPLY=$1
T=$(mktemp -d "/tmp/fx-host-cache-gate.XXXXXX")
cleanup(){ rm -rf "$T"; }
trap cleanup EXIT HUP INT TERM
awk '/^hosts_fetch_cached\(\) \{/ {p=1} p {print} p && /^\}/ {exit}' "$APPLY" > "$T/function.sh"
[ -s "$T/function.sh" ] || { echo "FAIL: could not extract restored hosts_fetch_cached()" >&2; exit 1; }
cat > "$T/worker.sh" <<'WORKER'
#!/bin/sh
set -eu
. "$FUNCTION_FILE"
PG="$TEST_ROOT/state"
HOSTS_CACHE_MIN=0
pg_log(){ :; }
pg_fetch_t(){
  printf 'START|%s\n' "$$" >> "$TEST_ROOT/fetch-events"
  tries=0
  while [ ! -e "$TEST_ROOT/release-fetch" ]; do
    tries=$((tries+1))
    [ "$tries" -lt 500 ] || { echo "mock Hosts fetch gate timed out" >&2; return 70; }
    sleep 0.01
  done
  printf 'worker-%s.example\nsecond-line.example\n' "$$" > "$2"
  printf 'END|%s\n' "$$" >> "$TEST_ROOT/fetch-events"
  return 0
}
hosts_fetch_cached 'https://same.example/rules' "$TEST_ROOT/out.$1"
WORKER
chmod 0755 "$T/worker.sh"
export TEST_ROOT="$T" FUNCTION_FILE="$T/function.sh"
mkdir -p "$T/state/cache/rules"
"$T/worker.sh" a & p1=$!
"$T/worker.sh" b & p2=$!
tries=0
while [ ! -s "$T/fetch-events" ] && [ "$tries" -lt 200 ]; do
  tries=$((tries+1))
  sleep 0.01
done
sleep 0.25
starts=$(grep -c '^START|' "$T/fetch-events" 2>/dev/null || echo 0)
touch "$T/release-fetch"
if [ "$starts" -ne 1 ]; then
  echo "FAIL: second same-URL Hosts fetch entered while first response was blocked (START count=$starts)" >&2
  cat "$T/fetch-events" >&2 || :
  wait "$p1" || :
  wait "$p2" || :
  exit 1
fi
wait "$p1" || { rc=$?; echo "FAIL: Hosts worker A exited with $rc" >&2; cat "$T/fetch-events" >&2; exit "$rc"; }
wait "$p2" || { rc=$?; echo "FAIL: Hosts worker B exited with $rc" >&2; cat "$T/fetch-events" >&2; exit "$rc"; }
key=$(printf '%s' 'https://same.example/rules' | cksum | awk '{print $1}')
cache="$T/state/cache/rules/$key"
actual=$(sha256sum "$cache" | awk '{print $1}')
expected=$(tr -d '[:space:]' < "$cache.sha256")
[ "$actual" = "$expected" ] || {
  echo "FAIL: same-URL Hosts cache SHA mismatch actual=$actual expected=$expected" >&2
  echo "cache body:" >&2; cat "$cache" >&2 || :
  echo "sidecar:" >&2; cat "$cache.sha256" >&2 || :
  echo "fetch timeline:" >&2; cat "$T/fetch-events" >&2 || :
  find "$T/state/cache/rules" -maxdepth 1 -type f -print >&2
  exit 1
}
[ -s "$T/out.a" ] && [ -s "$T/out.b" ] || { echo "FAIL: Host destination files missing" >&2; exit 1; }
[ ! -e "$T/state/cache/rules/.lock.$key" ] && [ ! -L "$T/state/cache/rules/.lock.$key" ] || {
  echo "FAIL: Hosts lock path remained after both workers exited" >&2
  find "$T/state/cache/rules" -maxdepth 1 -name '.lock.*' -print >&2
  exit 1
}
awk -F'|' '
$1=="START" { if (active!="") exit 1; active=$2; starts++ }
$1=="END" { if (active!=$2) exit 1; active=""; ends++ }
END { exit !(starts==2 && ends==2 && active=="") }
' "$T/fetch-events" || { echo "FAIL: Hosts fetches were not strictly serialized" >&2; cat "$T/fetch-events" >&2; exit 1; }
echo "PASS: deterministic Hosts same-URL fetch gate, ordered cache commits and SHA-256 sidecar"
HOST_GATE
chmod 0755 "$_GATE_TMP/hosts-gate.sh"
i=1
while [ "$i" -le 6 ]; do
  if command -v timeout >/dev/null 2>&1; then
    timeout 10 sh "$_GATE_TMP/hosts-gate.sh" "$APPLY" || fail "deterministic Hosts cache gate run $i failed"
  else
    sh "$_GATE_TMP/hosts-gate.sh" "$APPLY" || fail "deterministic Hosts cache gate run $i failed"
  fi
  i=$((i+1))
done
i=1
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
