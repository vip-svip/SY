#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/pg-cache-sha.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
awk '/^hosts_fetch_cached\(\) \{/ {p=1} p {print} p && /^\}/ {exit}' "$A" > "$T/function.sh"
[ -s "$T/function.sh" ]
cat >> "$T/function.sh" <<'TEST'
PG="${TESTROOT}/state"
HOSTS_CACHE_MIN=120
mkdir -p "$PG/cache/rules"
pg_log() { :; }
pg_fetch_t() { printf '0.0.0.0 fresh.example\n' > "$2"; return 0; }
TEST
TESTROOT="$T"; export TESTROOT
. "$T/function.sh"
url='https://rules.example/list.txt'
key=$(printf '%s' "$url" | cksum | cut -d' ' -f1)
cache="$PG/cache/rules/$key"
out="$T/out"
# Successful fetch must write a 64-hex checksum sidecar.
hosts_fetch_cached "$url" "$out"
[ "$(cat "$cache")" = '0.0.0.0 fresh.example' ]
sum=$(cat "$cache.sha256")
[ "${#sum}" -eq 64 ]
case "$sum" in *[!0-9a-f]*) echo 'FAIL: malformed checksum sidecar' >&2; exit 1 ;; esac
# A second successful generation must preserve the first verified cache as rollback.
printf 'previous-successful-build\n' > "$PG/cache/hosts-config.cksum"
pg_fetch_t() { printf '0.0.0.0 newer.example\n' > "$2"; return 0; }
HOSTS_CACHE_MIN=0
hosts_fetch_cached "$url" "$out"
[ "$(cat "$cache")" = '0.0.0.0 newer.example' ]
[ -s "$cache.prev" ] && [ -s "$cache.prev.sha256" ]
[ "$(cat "$cache.prev")" = '0.0.0.0 fresh.example' ]
[ ! -e "$PG/cache/hosts-config.cksum" ] || { echo 'FAIL: changed cache did not invalidate generated-hosts fingerprint' >&2; exit 1; }
# Simulate crash/tamper between the cache and sidecar renames. With network down,
# recovery must restore the prior verified generation, not accept corrupted bytes.
printf '0.0.0.0 tampered.example\n' > "$cache"
pg_fetch_t() { return 28; }
if ! hosts_fetch_cached "$url" "$out"; then
  echo 'FAIL: verified previous cache was not restored' >&2; exit 1
fi
[ "$(cat "$out")" = '0.0.0.0 fresh.example' ]
if grep -q tampered "$out" 2>/dev/null; then echo 'FAIL: tampered cache copied to output' >&2; exit 1; fi
# No cache/backup + incomplete download must fail and not leave a cache artifact.
rm -f "$cache" "$cache.sha256" "$cache.ts" "$cache.prev" "$cache.prev.sha256" "$out"
pg_fetch_t() { printf 'partial.example\n' > "$2"; return 28; }
if hosts_fetch_cached "$url" "$out"; then echo 'FAIL: partial download accepted' >&2; exit 1; fi
[ ! -s "$cache" ]
echo 'PrivacyGuard 1.0.0 cache SHA-256 regression: PASS'
