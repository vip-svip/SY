#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
PATCHER="$ROOT/fx-patches/patch_native_script_scheduler.py"
SOURCE="$ROOT/fx-patches/native-script-scheduler.sh"
MOD=${1:-"$ROOT/fx-module"}
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$PATCHER" ] || fail "scheduler patcher missing"
[ -s "$SOURCE" ] || fail "scheduler source missing"
[ -s "$MOD/scripts/jsruntime/scheduler.sh" ] || fail "staged scheduler missing"
cmp -s "$SOURCE" "$MOD/scripts/jsruntime/scheduler.sh" || fail "staged scheduler differs from reviewed source"
sh -n "$SOURCE" || fail "scheduler shell syntax invalid"
sh -n "$MOD/scripts/jsruntime/scheduler.sh" || fail "staged scheduler shell syntax invalid"
grep -Fqx '# FX_QUICKJS_SCHEDULER_STOP_BEGIN' "$MOD/uninstall.sh" || fail "module uninstall does not stop QuickJS scheduler"
grep -Fqx '# FX_QUICKJS_SCHEDULER_STOP_END' "$MOD/uninstall.sh" || fail "module uninstall stop block is incomplete"
[ "$(grep -Fc 'scripts/jsruntime/scheduler.sh' "$MOD/uninstall.sh")" -eq 1 ] || fail "uninstall stop hook is duplicated"

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
printf '#!/system/bin/sh\nMODDIR=/tmp/fx\nSTATE_DIR=/data/adb/privacyguard\nexit 0\n' > "$FIXTURE/uninstall.sh"
python3 "$PATCHER" "$FIXTURE" >/dev/null || fail "first staging patch failed"
first=$(sha256sum "$FIXTURE/scripts/jsruntime/scheduler.sh" "$FIXTURE/uninstall.sh")
python3 "$PATCHER" "$FIXTURE" >/dev/null || fail "second staging patch failed"
second=$(sha256sum "$FIXTURE/scripts/jsruntime/scheduler.sh" "$FIXTURE/uninstall.sh")
[ "$first" = "$second" ] || fail "scheduler patch is not idempotent"
[ "$(grep -Fc 'scripts/jsruntime/scheduler.sh' "$FIXTURE/uninstall.sh")" -eq 1 ] || fail "patcher duplicated uninstall hook"
sh -n "$FIXTURE/uninstall.sh" || fail "patched uninstall shell syntax invalid"
echo "PASS: QuickJS scheduler staging, ownership lifecycle, unrelated-PID refusal, symlink rejection and uninstall cleanup"
