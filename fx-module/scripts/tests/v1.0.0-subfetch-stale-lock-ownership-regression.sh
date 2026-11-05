#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
F="$ROOT/scripts/subfetch.sh"
# Static guard: stale reaping must rename the lock as a whole, verify the moved
# owner, and must not unlink pid + rmdir the contested path independently.
grep -Fq 'mv "$LOCK" "$_sl_stale"' "$F"
grep -Fq '_sl_moved_owner=$(cat "$_sl_stale/pid"' "$F"
grep -Fq '[ "$_sl_moved_owner" = "$_sl_owner" ]' "$F"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-subfetch-stale-lock.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/module" "$T/bin" "$T/state/subs"
cp -a "$ROOT/." "$T/module/"
printf '#!%s\n' "$(command -v sh)" > "$T/bin/curl"
cat >> "$T/bin/curl" <<'CURL'
out=
while [ "$#" -gt 0 ]; do
  if [ "$1" = '-o' ]; then shift; out=$1; fi
  shift
done
[ "$out" = '-' ] || [ -n "$out" ] || exit 2
if [ "$out" = '-' ]; then
  printf 'vless://123e4567-e89b-12d3-a456-426614174000@edge.example:443?encryption=none#test\n'
else
  printf 'vless://123e4567-e89b-12d3-a456-426614174000@edge.example:443?encryption=none#test\n' > "$out"
fi
CURL
printf '#!%s\n' "$(command -v sh)" > "$T/bin/timeout"
cat >> "$T/bin/timeout" <<'TIMEOUT'
shift
exec "$@"
TIMEOUT
chmod 755 "$T/bin/curl" "$T/bin/timeout"
export PATH="$T/bin:$PATH"
url='https://example.invalid/subscription'
key=$(printf '%s' "$url" | cksum | awk '{print $1}')
mkdir "$T/state/subs/.lock.$key"
printf '99999999\n' > "$T/state/subs/.lock.$key/pid"
PG="$T/state" MODDIR="$T/module" sh "$T/module/scripts/subfetch.sh" "$url" --force > "$T/out"
grep -Fq '"ok":1' "$T/out" || { cat "$T/out" >&2; exit 1; }
[ -s "$T/state/subs/$key.txt" ]
[ -s "$T/state/subs/$key.meta" ]
[ ! -d "$T/state/subs/.lock.$key" ]
echo 'PASS: stale lock is reclaimed without deleting an unverified owner'
