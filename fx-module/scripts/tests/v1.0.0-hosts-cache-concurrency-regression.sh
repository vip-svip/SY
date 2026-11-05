#!/bin/sh
# Same-URL host subscriptions may be downloaded concurrently by build_hosts.
# Verify their cache commits are serialized and the body always matches its SHA-256 sidecar.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-host-cache-concurrency.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
awk '/^hosts_fetch_cached\(\) \{/ {p=1} p {print} p && /^\}/ {exit}' "$A" > "$T/function.sh"
[ -s "$T/function.sh" ]
cat > "$T/worker.sh" <<'WORKER'
#!/bin/sh
set -eu
. "$FUNCTION_FILE"
PG="$TEST_ROOT/state"
HOSTS_CACHE_MIN=0
pg_log() { :; }
pg_fetch_t() {
  sleep 0.3
  printf 'worker-%s.example\nsecond-line.example\n' "$$" > "$2"
  return 0
}
hosts_fetch_cached 'https://same.example/rules' "$TEST_ROOT/out.$1"
WORKER
chmod 755 "$T/worker.sh"
export TEST_ROOT="$T" FUNCTION_FILE="$T/function.sh"
mkdir -p "$T/state/cache/rules"
"$T/worker.sh" a & p1=$!
"$T/worker.sh" b & p2=$!
wait "$p1"
wait "$p2"
key=$(printf '%s' 'https://same.example/rules' | cksum | awk '{print $1}')
cache="$T/state/cache/rules/$key"
actual=$(sha256sum "$cache" | awk '{print $1}')
expected=$(tr -d '[:space:]' < "$cache.sha256")
[ "$actual" = "$expected" ] || { echo 'FAIL: same-URL concurrent cache commit left a mismatched SHA-256 sidecar' >&2; exit 1; }
[ ! -d "$T/state/cache/rules/.lock.$key" ] || { echo 'FAIL: cache lock leaked after successful downloads' >&2; exit 1; }
[ -s "$T/out.a" ] && [ -s "$T/out.b" ]
echo 'FX hosts cache concurrency regression: PASS'
