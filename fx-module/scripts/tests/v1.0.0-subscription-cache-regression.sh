#!/system/bin/sh
set -u
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/pg-cache-test.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
awk '/^hosts_fetch_cached\(\) \{/ {p=1} p {print} p && /^\}/ {exit}' "$A" > "$T/function.sh"
[ -s "$T/function.sh" ]
cat >> "$T/function.sh" <<'TEST'
PG="${TESTROOT}/state"
HOSTS_CACHE_MIN=0
mkdir -p "$PG/cache/rules"
pg_log() { :; }
pg_fetch_t() { i=0; while [ "$i" -lt 1200 ]; do printf 'partial.example\n'; i=$((i+1)); done > "$2"; return 28; }
TEST
TESTROOT="$T"; export TESTROOT
. "$T/function.sh"
url='https://rules.example/list.txt'
key=$(printf '%s' "$url" | cksum | cut -d' ' -f1)
cache="$PG/cache/rules/$key"
printf '0.0.0.0 old.example\n' > "$cache"
printf '1\n' > "$PG/cache/rules/$key.ts"
out="$T/out"
hosts_fetch_cached "$url" "$out"
[ "$(cat "$cache")" = '0.0.0.0 old.example' ]
[ "$(cat "$out")" = '0.0.0.0 old.example' ]
# Fast apply must use a verified cache even if stale and must never try the network.
APPLY_FAST=1
HOSTS_CACHE_MIN=0
pg_fetch_t() { printf 'called\n' > "$TESTROOT/network-called"; return 28; }
if ! hosts_fetch_cached "$url" "$out"; then echo 'FAIL: quick apply did not use stale verified cache' >&2; exit 1; fi
[ "$(cat "$out")" = '0.0.0.0 old.example' ]
[ ! -e "$TESTROOT/network-called" ] || { echo 'FAIL: quick apply tried network despite verified cache' >&2; exit 1; }
# With no verified current/previous cache, quick apply must fail without network.
rm -f "$cache" "$cache.sha256" "$cache.ts" "$cache.prev" "$cache.prev.sha256" "$out"
if hosts_fetch_cached "$url" "$out"; then echo 'FAIL: quick apply accepted missing cache' >&2; exit 1; fi
[ ! -e "$TESTROOT/network-called" ] || { echo 'FAIL: quick apply network fallback is enabled' >&2; exit 1; }
[ ! -e "$out" ] || { echo 'FAIL: quick apply left a partial output file' >&2; exit 1; }
unset APPLY_FAST
pg_fetch_t() { i=0; while [ "$i" -lt 1200 ]; do printf 'partial.example\n'; i=$((i+1)); done > "$2"; return 28; }
rm -f "$cache" "$out"
if hosts_fetch_cached "$url" "$out"; then
  echo 'FAIL: first partial download without cache was accepted' >&2; exit 1
fi
[ "$(cat "$PG/cache/rules/$key" 2>/dev/null || :)" = '' ]

# A damaged current cache must recover only from a previous generation whose
# SHA-256 sidecar matches its content; a failed network refresh then serves that
# verified generation rather than accepting partial output.
printf 'corrupt-current.example\n' > "$cache"
printf '%064d\n' 0 > "$cache.sha256"
printf '0.0.0.0 verified-previous.example\n' > "$cache.prev"
sha256sum "$cache.prev" | awk '{print $1}' > "$cache.prev.sha256"
printf '1\n' > "$cache.ts"
if ! hosts_fetch_cached "$url" "$out"; then
  echo 'FAIL: verified previous cache generation was not recovered' >&2; exit 1
fi
[ "$(cat "$out")" = '0.0.0.0 verified-previous.example' ] || {
  echo 'FAIL: recovered output does not match verified previous generation' >&2; exit 1;
}
[ "$(cat "$cache")" = '0.0.0.0 verified-previous.example' ] || {
  echo 'FAIL: recovered cache was not restored to current generation' >&2; exit 1;
}

# A previous generation with a mismatching checksum must never be promoted.
printf 'tampered-previous.example\n' > "$cache.prev"
printf '%064d\n' 0 > "$cache.prev.sha256"
rm -f "$cache" "$cache.sha256" "$out"
if hosts_fetch_cached "$url" "$out"; then
  echo 'FAIL: unverified previous cache generation was accepted' >&2; exit 1
fi
[ ! -s "$out" ] || {
  echo 'FAIL: partial response leaked to caller after all cache generations failed validation' >&2; exit 1;
}
echo 'PrivacyGuard 1.0.0 subscription cache regression: PASS'
