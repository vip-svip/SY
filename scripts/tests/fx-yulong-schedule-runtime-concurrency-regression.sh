#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SOURCE="$ROOT/scripts/yulong-ad-schedule.sh"
CONTROL="$ROOT/scripts/yulong-ad-control.sh"
[ -s "$SOURCE" ] || { echo "FAIL: Yulong schedule runtime missing" >&2; exit 1; }
sh -n "$SOURCE" || { echo "FAIL: Yulong schedule script has invalid shell syntax" >&2; exit 1; }
[ -s "$CONTROL" ] || { echo "FAIL: Yulong control backend missing" >&2; exit 1; }
TMP=$(mktemp -d "/tmp/fx-yulong-schedule-lock.XXXXXX")
MOD="$TMP/module"
PG="$TMP/state"
SCHEDULE="$MOD/scripts/yulong-ad-schedule.sh"
SLEEP_PID=
mkdir -p "$MOD/scripts" "$PG"
cleanup() {
  if [ -s "$PG/yulong-ad-schedule.pid" ] && [ ! -L "$PG/yulong-ad-schedule.pid" ]; then
    p=$(cat "$PG/yulong-ad-schedule.pid" 2>/dev/null || :)
    case "$p" in ''|*[!0-9]*) p= ;; esac
    if [ -n "$p" ] && [ -r "/proc/$p/cmdline" ]; then
      cmd=$(tr '\000' ' ' < "/proc/$p/cmdline" 2>/dev/null || :)
      case "$cmd" in *"$SCHEDULE"*' watch '*) kill -TERM "$p" 2>/dev/null || : ;; esac
    fi
  fi
  if [ -n "$SLEEP_PID" ]; then kill "$SLEEP_PID" 2>/dev/null || :; fi
  rm -rf "$TMP"
}
trap cleanup EXIT HUP INT TERM
cp "$SOURCE" "$SCHEDULE"
chmod 700 "$SCHEDULE"
cat > "$MOD/scripts/util.sh" <<'EOF'
pg_get() {
  key=$1
  default=
  [ "$#" -lt 2 ] || default=$2
  value=$(awk -F= -v key="$key" '$1==key {print substr($0,index($0,"=")+1); exit}' "$PG/state" 2>/dev/null || :)
  [ -n "$value" ] || value=$default
  printf '%s\n' "$value"
}
pg_set() {
  key=$1
  value=$2
  tmp="$PG/state.tmp.$$"
  awk -F= -v key="$key" -v value="$value" '
    BEGIN {done=0}
    $1==key {if(!done) print key "=" value; done=1; next}
    {print}
    END {if(!done) print key "=" value}
  ' "$PG/state" > "$tmp" && mv "$tmp" "$PG/state"
}
EOF
cat > "$MOD/scripts/apply.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$$" >> "$PG/apply.calls"
sleep 0.02
EOF
chmod 700 "$MOD/scripts/apply.sh"
cat > "$PG/yulong-ad-schedule.conf" <<'EOF'
enabled=1
start=00:00
end=00:00
days=1,2,3,4,5,6,7
EOF
printf 'yulong_ad_schedule_active=0\n' > "$PG/state"
MP="$MOD"
export MP PG
. "$MOD/scripts/util.sh"
# Force a long pause between successful mkdir and owner-file publication.
# Old code could delete this live lock after five 200ms polls and start duplicates.
REAL_MKDIR=$(command -v mkdir)
mkdir -p "$TMP/bin"
cat > "$TMP/bin/mkdir" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "${FX_TEST_RUNTIME_LOCK:-}" ]; then
  "$FX_TEST_REAL_MKDIR" "$@" || exit $?
  sleep "${FX_TEST_LOCK_PUBLISH_DELAY:-1.5}"
  exit 0
fi
exec "$FX_TEST_REAL_MKDIR" "$@"
EOF
chmod 700 "$TMP/bin/mkdir"
FX_TEST_REAL_MKDIR=$REAL_MKDIR
FX_TEST_RUNTIME_LOCK=$PG/yulong-ad-schedule.runtime.lock
FX_TEST_LOCK_PUBLISH_DELAY=1.5
ORIGINAL_PATH=$PATH
export FX_TEST_REAL_MKDIR FX_TEST_RUNTIME_LOCK FX_TEST_LOCK_PUBLISH_DELAY
PATH="$TMP/bin:$PATH"
export PATH
i=0
while [ "$i" -lt 8 ]; do
  (sh "$SCHEDULE" start > "$TMP/start.$i.log" 2>&1) &
  i=$((i + 1))
done
wait
PATH=$ORIGINAL_PATH
export PATH
unset FX_TEST_REAL_MKDIR FX_TEST_RUNTIME_LOCK FX_TEST_LOCK_PUBLISH_DELAY
watchers=$(ps -eo pid=,args= | awk -v script="$SCHEDULE" 'index($0,script) && index($0," watch ") && $0 !~ /awk/ {n++} END{print n+0}')
[ "$watchers" -eq 1 ] || {
  echo "FAIL: concurrent starts created $watchers watcher processes (expected 1)" >&2
  cat "$TMP"/start.*.log >&2
  exit 1
}
pid=$(cat "$PG/yulong-ad-schedule.pid")
case "$pid" in ''|*[!0-9]*) echo "FAIL: PID file is not a numeric PID" >&2; exit 1 ;; esac
{
  grep -Fq "started pid=$pid" "$TMP"/start.*.log 2>/dev/null ||
  grep -Fq "already-running pid=$pid" "$TMP"/start.*.log 2>/dev/null
} || {
  echo "FAIL: serialized start did not report the persisted watcher PID" >&2
  cat "$TMP"/start.*.log >&2
  exit 1
}
i=0
while [ "$i" -lt 8 ]; do
  (sh "$SCHEDULE" evaluate > "$TMP/evaluate.$i.log" 2>&1) &
  i=$((i + 1))
done
wait
[ ! -e "$PG/yulong-ad-schedule.runtime.lock" ] || {
  echo "FAIL: runtime lock remained after concurrent evaluate calls" >&2
  exit 1
}
[ "$(pg_get yulong_ad_schedule_active 0)" = 1 ] || {
  echo "FAIL: schedule did not reconcile active state" >&2
  exit 1
}
sh "$SCHEDULE" stop >/dev/null
i=0
while [ "$i" -lt 20 ]; do
  watchers=$(ps -eo pid=,args= | awk -v script="$SCHEDULE" 'index($0,script) && index($0," watch ") && $0 !~ /awk/ {n++} END{print n+0}')
  [ "$watchers" -eq 0 ] && break
  sleep 0.1
  i=$((i + 1))
done
[ "$watchers" -eq 0 ] || { echo "FAIL: stop left a watcher running" >&2; exit 1; }
[ ! -e "$PG/yulong-ad-schedule.pid" ] || { echo "FAIL: stop left a PID file" >&2; exit 1; }
sleep 30 &
SLEEP_PID=$!
printf '%s\n' "$SLEEP_PID" > "$PG/yulong-ad-schedule.pid"
sh "$SCHEDULE" stop >/dev/null
kill -0 "$SLEEP_PID" 2>/dev/null || {
  echo "FAIL: stale PID cleanup signalled an unrelated process" >&2
  exit 1
}
[ ! -e "$PG/yulong-ad-schedule.pid" ] || { echo "FAIL: stale PID pointer was not cleared" >&2; exit 1; }
mkdir "$PG/yulong-ad-schedule.runtime.lock"
printf '99999999 1\n' > "$PG/yulong-ad-schedule.runtime.lock/owner"
sh "$SCHEDULE" evaluate >/dev/null
[ ! -e "$PG/yulong-ad-schedule.runtime.lock" ] || {
  echo "FAIL: stale runtime lock was not reclaimed" >&2
  exit 1
}
mkdir "$PG/yulong-ad-schedule.runtime.lock"
if FX_YULONG_SCHEDULE_LOCK_RETRIES=3 sh "$SCHEDULE" evaluate > "$TMP/ownerless.log" 2>&1; then
  echo "FAIL: ownerless legacy lock was stolen" >&2
  exit 1
else
  ownerless_rc=$?
fi
[ "$ownerless_rc" -eq 30 ] || {
  echo "FAIL: ambiguous ownerless lock should fail closed (rc=$ownerless_rc)" >&2
  exit 1
}
[ -d "$PG/yulong-ad-schedule.runtime.lock" ] &&
[ ! -e "$PG/yulong-ad-schedule.runtime.lock/owner" ] || {
  echo "FAIL: ownerless legacy lock was removed or modified" >&2
  exit 1
}
rmdir "$PG/yulong-ad-schedule.runtime.lock"
cat > "$PG/yulong-ad-schedule.conf" <<'EOF'
enabled=1
start=00:00
end=00:00
days=1,1
EOF
pg_set yulong_ad_schedule_active 0
sh "$SCHEDULE" evaluate >/dev/null
[ "$(pg_get yulong_ad_schedule_active 0)" = 1 ] || {
  echo "FAIL: malformed weekday data did not fail open to active filtering" >&2
  exit 1
}
python3 - "$SOURCE" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
assert "IFS= read -r _lock_self_stat < /proc/self/stat" in source, "lock must read its own PID from procfs"
assert "lock_self_pid=" + chr(36) + "{_lock_self_stat%% *}" in source, "current PID extraction must be valid shell parameter expansion"
assert "lock_retry_limit=" + chr(36) + "{FX_YULONG_SCHEDULE_LOCK_RETRIES:-300}" in source, "retry override must be expanded by POSIX shell"
assert '"$RUNTIME_LOCK/owner.$_lock_self_pid"' in source, "temporary lock owner must be scoped to current PID"
assert 'printf \'%s %s\\n\' "$_lock_self_pid"' in source, "owner record must store current PID"
assert '"$_release_pid" = "$_lock_self_pid"' in source, "release must confirm owner PID and process start time"
assert '$_lock_missing' not in source, "ownerless lock cleanup must not use a short time threshold"
assert 'FX_YULONG_SCHEDULE_LOCK_RETRIES' in source, "bounded retry override must support deterministic fail-closed tests"
assert 'ownerless legacy scheduler lock remains' in source, "ownerless compatibility lock must fail closed"
print("PASS: scheduler lock owner uses the live process PID and start time")
PY
python3 - "$CONTROL" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
start = source.index("schedule_get() {")
end = source.index("\nschedule_set() {", start)
body = source[start:end]
assert '"/proc/$pid/cmdline"' in body, "schedule status must verify watcher command identity"
assert "' watch '" in body, "schedule status must distinguish the actual watcher"
assert '&& [ ! -L "$pidfile" ]' in body, "schedule status must reject a symlinked PID file"
print("PASS: schedule status verifies PID identity before reporting watcher=1")
PY
echo "PASS: Yulong scheduler serializes concurrent lifecycle/evaluation, keeps one watcher, reaps stale state safely and fails open"
