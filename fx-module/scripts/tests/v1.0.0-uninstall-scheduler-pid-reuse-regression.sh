#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
U="$ROOT/uninstall.sh"
SCHED="$ROOT/scripts/jsruntime/scheduler.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$U" ] || fail "FX module uninstall.sh missing"
[ -s "$SCHED" ] || fail "owned QuickJS scheduler missing"
grep -Fq 'sh "$MODDIR/scripts/jsruntime/scheduler.sh" uninstall' "$U" || fail "uninstall must request cooperative scheduler shutdown"
grep -Fq 'pid_fields "$$" 2>/dev/null' "$SCHED" || fail "scheduler must bind its PID to the live /proc start time"
grep -Fq 'process_matches "$OWNER_PID" "$OWNER_START"' "$SCHED" || fail "owner validation must compare PID, command path and start time"
grep -Fq 'STOPFILE="$STATE_DIR/scheduler.stop"' "$SCHED" || fail "scheduler stop must use its owner-bound stop marker"
grep -Fq 'stop_requested()' "$SCHED" || fail "scheduler loop must observe cooperative stop requests"
if grep -Eq 'kill[[:space:]]+(-9|-KILL|-TERM)[[:space:]].*(sched|_stop_pid)' "$SCHED"; then fail "scheduler stop must not signal a PID that may have been reused"; fi
if grep -Eq 'kill[[:space:]]+(-9|-KILL|-TERM)[[:space:]].*sched' "$U"; then fail "uninstall must not directly signal a scheduler PID"; fi
sh -n "$SCHED" || fail "scheduler shell syntax invalid"
sh -n "$U" || fail "uninstall shell syntax invalid"

T=$(mktemp -d "${TMPDIR:-/tmp}/fx-scheduler-pid-reuse.XXXXXX")
MOD="$T/module"
PG="$T/state"
SCHED_PID=
cleanup(){
  if [ -n "${SCHED_PID:-}" ] && kill -0 "$SCHED_PID" 2>/dev/null; then
    if [ -s "$T/owner.valid" ]; then
      mkdir -p "$PG/jsruntime"
      cp "$T/owner.valid" "$PG/jsruntime/scheduler.pid" 2>/dev/null || :
      chmod 600 "$PG/jsruntime/scheduler.pid" 2>/dev/null || :
    fi
    PG="$PG" sh "$MOD/scripts/jsruntime/scheduler.sh" stop >/dev/null 2>&1 || :
    wait "$SCHED_PID" 2>/dev/null || :
  fi
  rm -rf "$T"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$MOD/scripts/jsruntime" "$PG/jsruntime"
printf 'id=privacyguard\\nversion=1.0.0\\n' > "$MOD/module.prop"
cp "$SCHED" "$MOD/scripts/jsruntime/scheduler.sh"
chmod 755 "$MOD/scripts/jsruntime/scheduler.sh"
printf '[list:script]\\n' > "$PG/settings.conf"
TEST_SCHED="$MOD/scripts/jsruntime/scheduler.sh"
PG="$PG" sh "$TEST_SCHED" start > "$T/start.log" 2>&1 &
SCHED_PID=$!
ready=0
i=0
while [ "$i" -lt 60 ]; do
  if PG="$PG" sh "$TEST_SCHED" status 2>/dev/null | grep -qx 'running=1'; then ready=1; break; fi
  if ! kill -0 "$SCHED_PID" 2>/dev/null; then break; fi
  sleep 0.1
  i=$((i+1))
done
[ "$ready" -eq 1 ] || { cat "$T/start.log" >&2; fail "test scheduler did not acquire an owner record"; }
PIDFILE="$PG/jsruntime/scheduler.pid"
STOPFILE="$PG/jsruntime/scheduler.stop"
[ -s "$PIDFILE" ] && [ ! -L "$PIDFILE" ] || fail "scheduler owner record missing or unsafe"
cp "$PIDFILE" "$T/owner.valid"
owner_pid=$(sed -n '1p' "$T/owner.valid")
owner_start=$(sed -n '4p' "$T/owner.valid")
[ "$owner_pid" = "$SCHED_PID" ] || fail "scheduler PID record does not identify the launched scheduler"
case "$owner_start" in ''|*[!0-9]*) fail "scheduler start time is not numeric" ;; esac
if [ "$owner_start" = 0 ]; then reused_start=1; else reused_start=0; fi
awk -v reused="$reused_start" 'NR==4{$0=reused} {print}' "$PIDFILE" > "$T/pid.reused"
chmod 600 "$T/pid.reused"
mv "$T/pid.reused" "$PIDFILE"
if PG="$PG" sh "$TEST_SCHED" stop > "$T/reused-stop.log" 2>&1; then
  fail "PID reuse simulation was accepted as the original scheduler owner"
else
  stop_rc=$?
  [ "$stop_rc" -eq 10 ] || { cat "$T/reused-stop.log" >&2; fail "PID reuse must return refusal status 10, got $stop_rc"; }
fi
grep -Fq 'unrelated or malformed process' "$T/reused-stop.log" || fail "PID reuse refusal was not explained"
kill -0 "$SCHED_PID" 2>/dev/null || fail "PID reuse check signalled the still-live scheduler process"
[ "$(sed -n '4p' "$PIDFILE")" = "$reused_start" ] || fail "PID reuse refusal unexpectedly rewrote the owner record"
[ ! -e "$STOPFILE" ] && [ ! -L "$STOPFILE" ] || fail "PID reuse refusal must not create a stop marker for an unverified owner"

# Restore the real owner snapshot. Only then may uninstall request cooperative exit.
cp "$T/owner.valid" "$PIDFILE"
chmod 600 "$PIDFILE"
PG="$PG" sh "$TEST_SCHED" stop > "$T/valid-stop.log" 2>&1 || { cat "$T/valid-stop.log" >&2; fail "verified owner could not be stopped cooperatively"; }
wait "$SCHED_PID" 2>/dev/null || :
SCHED_PID=
[ ! -e "$PIDFILE" ] && [ ! -L "$PIDFILE" ] || fail "cooperative stop left the scheduler owner record behind"
[ ! -e "$STOPFILE" ] && [ ! -L "$STOPFILE" ] || fail "cooperative stop left its owner stop marker behind"

# A legacy PID-only record must not let a reused live PID be mistaken for FX's scheduler.
printf '%s\\n' "$$" > "$PIDFILE"
if PG="$PG" sh "$TEST_SCHED" stop > "$T/legacy-stop.log" 2>&1; then
  fail "legacy PID-only record pointing at an unrelated live shell was accepted"
else
  legacy_rc=$?
  [ "$legacy_rc" -eq 10 ] || { cat "$T/legacy-stop.log" >&2; fail "legacy PID-only refusal returned $legacy_rc"; }
fi
kill -0 "$$" 2>/dev/null || fail "legacy PID-only check signalled the test process"
[ -s "$PIDFILE" ] || fail "legacy PID-only refusal deleted the unrelated owner record"
echo 'PASS: scheduler PID reuse is rejected by start-time ownership; verified owners stop only through the cooperative marker'
