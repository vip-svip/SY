#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
PATCHER="$ROOT/fx-patches/patch_native_script_scheduler.py"
SOURCE="$ROOT/fx-patches/native-script-scheduler.sh"
MOD=${1:-"$ROOT/fx-module"}
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$PATCHER" ] || fail "scheduler patcher missing"
[ -s "$SOURCE" ] || fail "scheduler source missing"
grep -Fq 'sync-subs.sh' "$PATCHER" || fail "scheduler patcher does not validate subscription synchronizer"
grep -Fq 'runner.sh' "$PATCHER" || fail "scheduler patcher does not validate QuickJS runner"
grep -Fq 'host.js' "$PATCHER" || fail "scheduler patcher does not validate HTTP host bridge"
[ -s "$MOD/scripts/jsruntime/scheduler.sh" ] || fail "staged scheduler missing"
cmp -s "$SOURCE" "$MOD/scripts/jsruntime/scheduler.sh" || fail "staged scheduler differs from reviewed source"
sh -n "$SOURCE" || fail "scheduler shell syntax invalid"
sh -n "$MOD/scripts/jsruntime/scheduler.sh" || fail "staged scheduler shell syntax invalid"
grep -Fqx '# FX_QUICKJS_SCHEDULER_STOP_BEGIN' "$MOD/uninstall.sh" || fail "module uninstall does not stop QuickJS scheduler"
grep -Fqx '# FX_QUICKJS_SCHEDULER_STOP_END' "$MOD/uninstall.sh" || fail "module uninstall stop block is incomplete"
[ "$(grep -Fc '# FX_QUICKJS_SCHEDULER_STOP_BEGIN' "$MOD/uninstall.sh")" -eq 1 ] || fail "uninstall stop hook is duplicated"

T=$(mktemp -d "${TMPDIR:-/tmp}/fx-qjs-scheduler.XXXXXX")
cleanup(){
  if [ -n "${START_PID:-}" ]; then
    PG="$PG" sh "$SCHED" stop >/dev/null 2>&1 || :
    wait "$START_PID" 2>/dev/null || :
  fi
  rm -rf "$T"
}
trap cleanup EXIT HUP INT TERM
FIX="$T/module"
PG="$T/state"
mkdir -p "$FIX/scripts/jsruntime" "$PG"
printf 'id=privacyguard\n' > "$FIX/module.prop"
cp "$SOURCE" "$FIX/scripts/jsruntime/scheduler.sh"
chmod 755 "$FIX/scripts/jsruntime/scheduler.sh"
SCHED="$FIX/scripts/jsruntime/scheduler.sh"
export PG SCHED
printf 'script_auto_update_h=24\n[list:script]\n' > "$PG/settings.conf"
[ "$(PG="$PG" sh "$SCHED" status)" = "running=0" ] || fail "fresh scheduler status is not stopped"
PG="$PG" sh "$SCHED" start >/dev/null 2>&1 &
START_PID=$!
ready=0
i=0
while [ "$i" -lt 50 ]; do
  if PG="$PG" sh "$SCHED" status 2>/dev/null | grep -qx 'running=1'; then ready=1; break; fi
  sleep 0.1
  i=$((i+1))
done
[ "$ready" -eq 1 ] || fail "scheduler did not acquire its owned PID record"
PG="$PG" sh "$SCHED" stop >/dev/null || fail "owned scheduler stop failed"
wait "$START_PID" 2>/dev/null || :
START_PID=
[ ! -e "$PG/jsruntime/scheduler.pid" ] || fail "owned PID record was not removed after stop"
[ "$(PG="$PG" sh "$SCHED" status)" = "running=0" ] || fail "scheduler still reports running after stop"

# An unrelated live PID must never be signalled merely because it appears in the PID file.
printf '%s\n' "$$" > "$PG/jsruntime/scheduler.pid"
if PG="$PG" sh "$SCHED" stop >/dev/null 2>&1; then fail "unrelated live PID was accepted as scheduler owner"; else rc=$?; [ "$rc" -eq 10 ] || fail "unrelated PID returned unexpected status $rc"; fi
kill -0 "$$" 2>/dev/null || fail "unrelated test process was signalled"
rm -f "$PG/jsruntime/scheduler.pid"

# Symlinked PID state is rejected rather than followed or removed.
printf 'sentinel\n' > "$T/sentinel"
ln -s "$T/sentinel" "$PG/jsruntime/scheduler.pid"
if PG="$PG" sh "$SCHED" status >/dev/null 2>&1; then fail "symlinked PID state was accepted"; else rc=$?; [ "$rc" -eq 22 ] || fail "symlink PID state returned unexpected status $rc"; fi
grep -qx 'sentinel' "$T/sentinel" || fail "symlink target was modified"

# The staging patch is repeatable and does not duplicate the uninstall hook.
FIXTURE="$T/patch-fixture"
mkdir -p "$FIXTURE"
printf 'id=privacyguard\n' > "$FIXTURE/module.prop"
mkdir -p "$FIXTURE/scripts/jsruntime"
cat > "$FIXTURE/uninstall.sh" <<'LEGACY_RELEASE'
#!/system/bin/sh
MODDIR=/tmp/fx
PG=/data/adb/privacyguard
# Stop the background script-subscription scheduler before user data is removed.
_pg_sched_pid=$(cat "$PG/jsruntime/scheduler.pid" 2>/dev/null)
if [ -n "$_pg_sched_pid" ]; then kill "$_pg_sched_pid" 2>/dev/null || :; fi
rm -f "$PG/jsruntime/scheduler.pid" 2>/dev/null || :
exit 0
LEGACY_RELEASE
printf '#!/system/bin/sh\nexit 0\n' > "$FIXTURE/scripts/jsruntime/sync-subs.sh"
printf '#!/system/bin/sh\nexit 0\n' > "$FIXTURE/scripts/jsruntime/runner.sh"
printf '/* fixture host bridge */\n' > "$FIXTURE/scripts/jsruntime/host.js"
python3 "$PATCHER" "$FIXTURE" >/dev/null || fail "first staging patch failed"
first=$(sha256sum "$FIXTURE/scripts/jsruntime/scheduler.sh" "$FIXTURE/uninstall.sh")
python3 "$PATCHER" "$FIXTURE" >/dev/null || fail "second staging patch failed"
second=$(sha256sum "$FIXTURE/scripts/jsruntime/scheduler.sh" "$FIXTURE/uninstall.sh")
[ "$first" = "$second" ] || fail "scheduler patch is not idempotent"
[ "$(grep -Fc '# FX_QUICKJS_SCHEDULER_STOP_BEGIN' "$FIXTURE/uninstall.sh")" -eq 1 ] || fail "patcher duplicated uninstall hook"
sh -n "$FIXTURE/uninstall.sh" || fail "patched uninstall shell syntax invalid"
grep -Fq 'preserving state and aborting cleanup' "$FIXTURE/uninstall.sh" || fail "uninstall does not fail closed when scheduler stop fails"
if grep -Fq 'kill "$_pg_sched_pid"' "$FIXTURE/uninstall.sh"; then fail "legacy PID-only scheduler kill remains after patch"; fi
if grep -Fq 'rm -f "$PG/jsruntime/scheduler.pid"' "$FIXTURE/uninstall.sh"; then fail "legacy PID-only scheduler record deletion remains after patch"; fi

# Upgrade the earlier FX marker form too; never leave the previous best-effort stop hook in place.
OLD_FIXTURE="$T/old-marker-fixture"
mkdir -p "$OLD_FIXTURE/scripts/jsruntime"
printf 'id=privacyguard\n' > "$OLD_FIXTURE/module.prop"
cp "$FIXTURE/scripts/jsruntime/sync-subs.sh" "$OLD_FIXTURE/scripts/jsruntime/sync-subs.sh"
cp "$FIXTURE/scripts/jsruntime/runner.sh" "$OLD_FIXTURE/scripts/jsruntime/runner.sh"
cp "$FIXTURE/scripts/jsruntime/host.js" "$OLD_FIXTURE/scripts/jsruntime/host.js"
cat > "$OLD_FIXTURE/uninstall.sh" <<'OLD_MARKER'
#!/system/bin/sh
MODDIR=/tmp/fx
STATE_DIR=/data/adb/privacyguard
# FX_QUICKJS_SCHEDULER_STOP_BEGIN
if [ -f "$MODDIR/scripts/jsruntime/scheduler.sh" ]; then
  sh "$MODDIR/scripts/jsruntime/scheduler.sh" uninstall >> "$STATE_DIR/jsruntime/scheduler.log" 2>&1 || :
fi
# FX_QUICKJS_SCHEDULER_STOP_END
exit 0
OLD_MARKER
python3 "$PATCHER" "$OLD_FIXTURE" >/dev/null || fail "upgrading the previous marked uninstall hook failed"
grep -Fq 'preserving state and aborting cleanup' "$OLD_FIXTURE/uninstall.sh" || fail "previous marked hook was not hardened"
python3 "$PATCHER" "$OLD_FIXTURE" >/dev/null || fail "second previous-marker patch failed"

grep -Fq 'STOPFILE="$STATE_DIR/scheduler.stop"' "$SOURCE" || fail "cooperative stop marker is missing"
grep -Fq 'pid_fields "$$" 2>/dev/null' "$SOURCE" || fail "scheduler does not capture its own PID start time"
grep -Fq "awk '{print \$20}'" "$SOURCE" || fail "scheduler does not capture Linux proc starttime field 22"
grep -Fq 'stop_requested()' "$SOURCE" || fail "scheduler does not poll owned stop requests"
if grep -Fq 'kill -TERM "$_stop_pid"' "$SOURCE"; then fail "scheduler stop still signals a PID"; fi
echo "PASS: QuickJS scheduler staging, cooperative ownership lifecycle, unrelated-PID refusal, symlink rejection and uninstall cleanup"
