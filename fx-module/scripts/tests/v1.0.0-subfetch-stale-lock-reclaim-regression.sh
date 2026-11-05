#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
F="$ROOT/scripts/subfetch.sh"
sh -n "$F"
# Stale lock reclamation must rename the contested directory atomically.
grep -Fq '_sl_stale="$SUBDIR/.stale-lock.$_key.$$.$_sl_try"' "$F"
grep -Fq '&& mv "$LOCK" "$_sl_stale" 2>/dev/null; then' "$F"
grep -Fq '_sl_moved_owner=$(cat "$_sl_stale/pid"' "$F"
grep -Fq '[ "$_sl_moved_owner" = "$_sl_owner" ]' "$F"
# Never use a check-then-mv to restore an unverified quarantine into LOCK:
# another process can create LOCK between the check and mv, causing nesting.
if sed -n '/Recheck ownership, then atomically move/,/fi ;;/p' "$F" | grep -Fq 'mv "$_sl_stale" "$LOCK"'; then
  echo 'FAIL: quarantine restore can race with creation of a replacement lock' >&2
  exit 1
fi
# The stale-owner branch must not unlink the PID and directory separately.
block=$(sed -n '/Recheck ownership, then atomically move/,/fi ;;/p' "$F")
[ -n "$block" ]
if printf '%s\n' "$block" | grep -Eq 'rm -f "\$LOCK/pid"|rmdir "\$LOCK"'; then
  echo 'FAIL: stale-lock reaper can delete a replacement lock' >&2
  exit 1
fi
# Exercise the real script against a dead-owner lock in isolated state.
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-stale-lock.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/state/subs" "$T/bin"
key=$(printf '%s' 'https://example.invalid/reclaim' | cksum | awk '{print $1}')
mkdir "$T/state/subs/.lock.$key"
printf '99999999\n' > "$T/state/subs/.lock.$key/pid"
printf '#!%s\n' "$(command -v sh)" > "$T/bin/curl"
cat >> "$T/bin/curl" <<'CURL'

out=''
while [ "$#" -gt 0 ]; do case "$1" in -o) shift; out=$1 ;; esac; shift; done
if [ "$out" = '-' ]; then
  printf 'vless://123e4567-e89b-12d3-a456-426614174000@edge.example:443?encryption=none#test\n'
else
  printf 'vless://123e4567-e89b-12d3-a456-426614174000@edge.example:443?encryption=none#test\n' > "$out"
fi
CURL
chmod 755 "$T/bin/curl"
PATH="$T/bin:$PATH" PG="$T/state" MODDIR="$ROOT" sh "$F" 'https://example.invalid/reclaim' --force > "$T/out"
grep -q '"ok":1' "$T/out"
[ -s "$T/state/subs/$key.txt" ]
[ -s "$T/state/subs/$key.meta" ]
[ ! -d "$T/state/subs/.lock.$key" ]
echo 'PASS: stale subscription lock is reclaimed by atomic rename without deleting a replacement lock'
