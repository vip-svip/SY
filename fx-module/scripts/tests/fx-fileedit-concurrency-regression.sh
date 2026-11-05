#!/bin/sh
set -eu
SOURCE=${1:?usage: fx-fileedit-concurrency-regression.sh path/to/fileedit.sh}
SOURCE_DIR=$(CDPATH= cd -- "$(dirname "$SOURCE")" && pwd)
[ -s "$SOURCE" ] || { echo "FAIL: fileedit source missing" >&2; exit 1; }
[ -s "$SOURCE_DIR/util.sh" ] || { echo "FAIL: matching util.sh missing" >&2; exit 1; }
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-fileedit-lock.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/module/scripts" "$T/module" "$T/pg/local" "$T/pg/cache"
printf 'id=FX\n' > "$T/module/module.prop"
cp "$SOURCE" "$T/module/scripts/fileedit.sh"
cp "$SOURCE_DIR/util.sh" "$T/module/scripts/util.sh"
BE="$T/module/scripts/fileedit.sh"
PGDIR="$T/pg"
run() { PG="$PGDIR" sh "$BE" "$@"; }
printf 'seed.example\n' > "$PGDIR/local/hosts"
mkdir -p "$PGDIR/fileedit-locks" "$T/bin"
REAL_AWK=$(command -v awk)
cat > "$T/bin/awk" <<'AWK'
#!/bin/sh
last=
for arg do last=$arg; done
if [ -n "$FX_TEST_DELAY_FILE" ] && [ "$last" = "$FX_TEST_DELAY_FILE" ]; then sleep 0.6; fi
exec "$FX_TEST_REAL_AWK" "$@"
AWK
chmod 700 "$T/bin/awk"
printf 'alpha.example\n' > "$T/alpha"
printf 'beta.example\n' > "$T/beta"
PG="$PGDIR" PATH="$T/bin:$PATH" FX_TEST_REAL_AWK="$REAL_AWK" FX_TEST_DELAY_FILE="$PGDIR/local/hosts" sh "$BE" ins hosts 2 "$T/alpha" > "$T/first.out" &
P1=$!
PG="$PGDIR" PATH="$T/bin:$PATH" FX_TEST_REAL_AWK="$REAL_AWK" FX_TEST_DELAY_FILE="$PGDIR/local/hosts" sh "$BE" ins hosts 2 "$T/beta" > "$T/second.out" &
P2=$!
wait "$P1"; wait "$P2"
grep -qx 'seed.example' "$PGDIR/local/hosts" || { echo "FAIL: seed line lost" >&2; exit 1; }
grep -qx 'alpha.example' "$PGDIR/local/hosts" || { echo "FAIL: first concurrent edit lost" >&2; exit 1; }
grep -qx 'beta.example' "$PGDIR/local/hosts" || { echo "FAIL: second concurrent edit lost" >&2; exit 1; }
[ ! -e "$PGDIR/fileedit-locks/hosts.lock" ] || { echo "FAIL: successful edit left lock" >&2; exit 1; }
printf '99999999\n' > "$PGDIR/fileedit-locks/hosts.lock"
printf 'stale.example\n' > "$T/stale"
out=$(run ins hosts 1 "$T/stale")
printf '%s' "$out" | grep -Fq '"ok":1' || { echo "FAIL: stale lock not recovered: $out" >&2; exit 1; }
grep -qx 'stale.example' "$PGDIR/local/hosts" || { echo "FAIL: write after stale recovery missing" >&2; exit 1; }
TEST_PID=$PPID
printf '%s\n' "$TEST_PID" > "$PGDIR/fileedit-locks/hosts.lock"
before=$(sha256sum "$PGDIR/local/hosts" | awk '{print $1}')
printf 'blocked.example\n' > "$T/blocked"
out=$(PG="$PGDIR" FX_FILEEDIT_LOCK_RETRIES=1 sh "$BE" ins hosts 1 "$T/blocked")
printf '%s' "$out" | grep -Fq '"ok":0' || { echo "FAIL: live lock not rejected: $out" >&2; exit 1; }
[ "$(cat "$PGDIR/fileedit-locks/hosts.lock")" = "$TEST_PID" ] || { echo "FAIL: live lock owner changed" >&2; exit 1; }
after=$(sha256sum "$PGDIR/local/hosts" | awk '{print $1}')
[ "$before" = "$after" ] || { echo "FAIL: blocked write modified hosts" >&2; exit 1; }
rm -f "$PGDIR/fileedit-locks/hosts.lock"
printf 'outside lock data\n' > "$T/outside"
ln -s "$T/outside" "$PGDIR/fileedit-locks/hosts.lock"
out=$(run ins hosts 1 "$T/blocked")
printf '%s' "$out" | grep -Fq 'symbolic link' || { echo "FAIL: lock symlink not rejected: $out" >&2; exit 1; }
[ -L "$PGDIR/fileedit-locks/hosts.lock" ] || { echo "FAIL: lock symlink replaced" >&2; exit 1; }
[ "$(cat "$T/outside")" = 'outside lock data' ] || { echo "FAIL: lock symlink target modified" >&2; exit 1; }
rm -f "$PGDIR/fileedit-locks/hosts.lock"
python3 - "$BE" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text(encoding="utf-8")
guard = 'case "$op" in\n  edit|ins|del|put|replacepage|reset|import-external)\n    fe_lock_acquire || exit 0'
assert guard in s, "mutating operations not guarded before source processing"
assert 'sha256sum' in s and 'source-' in s, "non-host source lock key must be bounded by source hash"
print("PASS: all editor mutation entry points share one per-source transaction lock")
PY
echo 'PASS: file editor serializes concurrent writes, reclaims stale locks and refuses live/symlink locks'
