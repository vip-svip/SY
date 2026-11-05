#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
PATCHER="$ROOT/fx-patches/patch_localdns_uninstall_shutdown.py"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$PATCHER" ] || fail "local DNS uninstall patcher missing"
python3 -m py_compile "$PATCHER" || fail "patcher Python syntax invalid"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-localdns-uninstall.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
MOD="$T/module"; PG="$T/state"
mkdir -p "$MOD/scripts" "$PG"
cat > "$MOD/uninstall.sh" <<'UNINSTALL'
#!/system/bin/sh
set -u
PG=${PG:-/data/adb/privacyguard}
MODDIR=${MODDIR:-/data/adb/modules/privacyguard}
PG_KEEP_DATA=0
_mitm_warn(){ printf '%s\n' "$*" >&2; }
if [ -x "$MODDIR/scripts/localdns-watchdog.sh" ]; then
  if ! sh "$MODDIR/scripts/localdns-watchdog.sh" stop "$MODDIR" "$PG"; then
    _mitm_warn "could not confirm stopping local DNS watchdog before firewall cleanup; preserving $PG and continuing best-effort cleanup"
  fi
elif [ -s "$PG/localdns-watchdog.pid" ]; then
  _wd_pid=$(cat "$PG/localdns-watchdog.pid" 2>/dev/null)
  case "$_wd_pid" in ''|*[!0-9]*|0|1) ;; *)
    if [ -r "/proc/$_wd_pid/cmdline" ]; then
      _wd_cmd=$(tr '\000' ' ' < "/proc/$_wd_pid/cmdline" 2>/dev/null)
      case "$_wd_cmd" in *"$MODDIR/scripts/localdns-watchdog.sh"*) kill -TERM "$_wd_pid" 2>/dev/null || : ;; esac
    fi ;;
  esac
fi
echo FIREWALL_CLEANUP
UNINSTALL
chmod 0755 "$MOD/uninstall.sh"
python3 "$PATCHER" "$MOD" >/dev/null || fail "patcher rejected canonical uninstall anchors"
python3 "$PATCHER" "$MOD" >/dev/null || fail "patcher is not idempotent"
sh -n "$MOD/uninstall.sh" || fail "patched uninstall shell syntax invalid"
grep -Fq 'cleared stale local DNS watchdog PID record' "$MOD/uninstall.sh" || fail "dead-PID cleanup path missing"
grep -Fq 'PID record is a symlink' "$MOD/uninstall.sh" || fail "symlink PID record must fail closed"

# An exited watchdog PID is stale state, not an active unknown owner.
printf '99999999\n' > "$PG/localdns-watchdog.pid"
PG="$PG" MODDIR="$MOD" sh "$MOD/uninstall.sh" > "$T/dead.out" 2>&1 || fail "dead watchdog PID blocked uninstall"
grep -Fq 'cleared stale local DNS watchdog PID record' "$T/dead.out" || fail "stale PID cleanup was not reported"
grep -Fq 'FIREWALL_CLEANUP' "$T/dead.out" || fail "firewall cleanup did not continue after stale PID removal"
[ ! -e "$PG/localdns-watchdog.pid" ] || fail "stale PID record was not removed"

# A live unrelated PID must never be signalled or mistaken for FX's watchdog.
printf '%s\n' "$$" > "$PG/localdns-watchdog.pid"
if PG="$PG" MODDIR="$MOD" sh "$MOD/uninstall.sh" > "$T/reused.out" 2>&1; then
  fail "live unrelated PID was accepted as the local DNS watchdog"
fi
grep -Fq 'process identity cannot be confirmed' "$T/reused.out" || fail "PID identity refusal was not explained"
! grep -Fq 'FIREWALL_CLEANUP' "$T/reused.out" || fail "firewall teardown continued with an unverified live PID"
kill -0 "$$" 2>/dev/null || fail "PID identity check signalled the test process"
[ -s "$PG/localdns-watchdog.pid" ] || fail "unverified PID record was discarded"

# A symlinked PID record is untrusted and must preserve module state.
rm -f "$PG/localdns-watchdog.pid"
printf '%s\n' "$$" > "$T/pid-target"
ln -s "$T/pid-target" "$PG/localdns-watchdog.pid"
if PG="$PG" MODDIR="$MOD" sh "$MOD/uninstall.sh" > "$T/symlink.out" 2>&1; then
  fail "symlink PID record was accepted"
fi
grep -Fq 'PID record is a symlink' "$T/symlink.out" || fail "symlink refusal was not explained"
! grep -Fq 'FIREWALL_CLEANUP' "$T/symlink.out" || fail "firewall teardown continued with a symlinked PID record"
grep -Fxq "$" "$T/pid-target" || fail "symlinked PID target was modified during refusal"

# The cooperative helper path also aborts cleanup when shutdown is unconfirmed.
rm -f "$PG/localdns-watchdog.pid"
cat > "$MOD/scripts/localdns-watchdog.sh" <<'WATCHDOG'
#!/bin/sh
exit 7
WATCHDOG
chmod 0755 "$MOD/scripts/localdns-watchdog.sh"
if PG="$PG" MODDIR="$MOD" sh "$MOD/uninstall.sh" > "$T/helper.out" 2>&1; then
  fail "failed cooperative watchdog shutdown did not abort uninstall"
fi
grep -Fq 'aborting uninstall before firewall cleanup' "$T/helper.out" || fail "helper shutdown failure did not report fail-closed behavior"
! grep -Fq 'FIREWALL_CLEANUP' "$T/helper.out" || fail "firewall teardown continued after helper shutdown failure"

echo "PASS: local DNS watchdog uninstall clears dead PID records, rejects reused/symlink PIDs, and aborts cleanup when a live owner cannot be stopped"
