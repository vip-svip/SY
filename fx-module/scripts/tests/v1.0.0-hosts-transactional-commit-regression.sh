#!/system/bin/sh
# Host-runnable rollback test for the exact transactional hosts commit helper.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-host-txn.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/pg/cache" "$T/bin"
export PG="$T/pg" CONF="$T/settings.conf"
: > "$CONF"
printf '127.0.0.1 old.example\n0.0.0.0 old-block.example\n' > "$PG/hosts"
printf 'first.example\nsecond.example\nthird.example\n' > "$PG/cache/hosts.tmp"
REAL_MV=$(command -v mv); export REAL_MV
cat > "$T/bin/mv" <<'MV'
#!/bin/sh
if [ "${FX_CORRUPT_CANDIDATE:-0}" = 1 ] && [ "$1" = "$PG/cache/hosts.tmp" ] && [ "$2" = "$PG/hosts" ]; then
  "$REAL_MV" "$@" || exit $?
  # Simulate a lower-level write/filesystem failure after the rename reports success.
  printf 'truncated.example\n' > "$PG/hosts"
  exit 0
fi
exec "$REAL_MV" "$@"
MV
chmod +x "$T/bin/mv"
PATH="$T/bin:$PATH"; export PATH
. "$ROOT/scripts/util.sh"
# Mock only the bind-mount query/unmount. The helper must unmount before moving
# the source inode; the apply caller will attempt to bind the final file afterward.
mount() {
  if [ -f "$PG/cache/mock-mounted" ]; then
    # Match the actual mount(8) source-on-target shape consumed by
    # pg_hosts_mount_state(): module source on /system/etc/hosts.
    printf '%s on /system/etc/hosts type none (rw,bind)\n' "$PG/hosts"
  fi
  return 0
}
umount() { rm -f "$PG/cache/mock-mounted"; return 0; }
printf x > "$PG/cache/mock-mounted"
export FX_CORRUPT_CANDIDATE=1
if pg_commit_hosts_candidate "$PG/cache/hosts.tmp"; then
  echo 'FAIL: corrupted candidate unexpectedly committed' >&2
  exit 1
fi
unset FX_CORRUPT_CANDIDATE
grep -Fxq '127.0.0.1 old.example' "$PG/hosts"
grep -Fxq '0.0.0.0 old-block.example' "$PG/hosts"
! grep -Fxq 'truncated.example' "$PG/hosts"
test ! -e "$PG/cache/hosts.precommit.$$"
# Normal valid candidate must replace the old file and remove its recovery inode.
printf 'new-one.example\nnew-two.example\n' > "$PG/cache/hosts.tmp"
pg_commit_hosts_candidate "$PG/cache/hosts.tmp"
grep -Fxq 'new-one.example' "$PG/hosts"
grep -Fxq 'new-two.example' "$PG/hosts"
! grep -Fxq '127.0.0.1 old.example' "$PG/hosts"
test "$(find "$PG/cache" -maxdepth 1 -name 'hosts.precommit.*' | wc -l | tr -d ' ')" -eq 0
echo 'FX hosts transactional commit regression: PASS (failure rollback + successful commit)'
