#!/system/bin/sh
# Watch the live local recursive DNS chain and roll back redirection if an
# uncached query stops working. A successful listener check alone is insufficient.
set -u
case "$0" in
  */scripts/localdns-watchdog.sh) SELF=$0; MODDIR=${0%/scripts/localdns-watchdog.sh} ;;
  *) SELF=${SELF:-$0}; MODDIR=${MODDIR:-/data/adb/modules/privacyguard} ;;
esac
MODE=${1:-start}
[ "$#" -ge 2 ] && MODDIR=$2
PG=${3:-/data/adb/privacyguard}
PIDFILE="$PG/localdns-watchdog.pid"
LOG="$PG/localdns-watchdog.log"
SELF=$(readlink -f "$SELF" 2>/dev/null || printf '%s' "$SELF")

_log() { printf '[%s] localdns-watchdog: %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$LOG" 2>/dev/null || :; }
# A loop can lose ownership between its first PID check and a later exit path.
# Never unlink a replacement watchdog's PID marker merely because our own loop
# is exiting; the marker is shared state and must be checked at removal time.
_remove_owned_pidfile() {
  _owned_now=$(cat "$PIDFILE" 2>/dev/null)
  [ "$_owned_now" = "$$" ] || return 0
  rm -f "$PIDFILE" 2>/dev/null || :
}
_valid_pid() {
  _p=$1
  case "$_p" in ''|*[!0-9]*) return 1;; esac
  [ "$_p" -gt 1 ] 2>/dev/null || return 1
  [ -r "/proc/$_p/cmdline" ] || return 1
  # A terminated child may briefly remain as a zombie on some init systems.
  # kill -0 succeeds for zombies, so treating them as live makes stop retain a
  # stale PID marker even though the watchdog can no longer run or own work.
  _state=$(sed -n 's/.*) \([^ ]*\).*/\1/p' "/proc/$_p/stat" 2>/dev/null)
  case "$_state" in Z|X) return 1 ;; esac
  _cmd=$(tr '\000' ' ' < "/proc/$_p/cmdline" 2>/dev/null)
  case "$_cmd" in *"$SELF"*' loop '*) return 0;; *) return 1;; esac
}

if [ "$MODE" = stop ]; then
  _old=$(cat "$PIDFILE" 2>/dev/null)
  if _valid_pid "$_old"; then
    kill -TERM "$_old" 2>/dev/null || :
    _n=0
    while [ "$_n" -lt 20 ] && _valid_pid "$_old" && kill -0 "$_old" 2>/dev/null; do sleep 0.2; _n=$((_n+1)); done
    if _valid_pid "$_old" && kill -0 "$_old" 2>/dev/null; then
      # Recheck identity immediately before force termination to avoid PID reuse.
      _valid_pid "$_old" && kill -KILL "$_old" 2>/dev/null || :
    fi
    if _valid_pid "$_old" && kill -0 "$_old" 2>/dev/null; then
      _log "unable to stop watchdog pid=$_old; preserving marker"
      exit 1
    fi
  fi
  _cur=$(cat "$PIDFILE" 2>/dev/null)
  [ "$_cur" != "$_old" ] || rm -f "$PIDFILE" 2>/dev/null || :
  exit 0
fi

if [ "$MODE" = start ]; then
  mkdir -p "$PG" 2>/dev/null || exit 1
  _old=$(cat "$PIDFILE" 2>/dev/null)
  if _valid_pid "$_old"; then exit 0; fi
  rm -f "$PIDFILE" 2>/dev/null || :
  nohup sh "$SELF" loop "$MODDIR" "$PG" >> "$LOG" 2>&1 &
  _new=$!
  printf '%s\n' "$_new" > "$PIDFILE.tmp.$$" || { kill "$_new" 2>/dev/null || :; exit 1; }
  chmod 600 "$PIDFILE.tmp.$$" 2>/dev/null || :
  mv -f "$PIDFILE.tmp.$$" "$PIDFILE" || { rm -f "$PIDFILE.tmp.$$"; _valid_pid "$_new" && kill "$_new" 2>/dev/null || :; exit 1; }
  # The old implementation returned success as soon as it wrote the PID, even
  # if the child died immediately. That could leave DNS redirected to a dead
  # resolver with no watchdog to roll back. Require the exact child to prove its
  # command-line identity and remain alive before declaring start successful.
  _n=0
  while [ "$_n" -lt 20 ]; do
    _cur=$(cat "$PIDFILE" 2>/dev/null)
    if [ "$_cur" = "$_new" ] && _valid_pid "$_new" && kill -0 "$_new" 2>/dev/null; then
      _log "started and verified watcher pid=$_new"
      exit 0
    fi
    if ! kill -0 "$_new" 2>/dev/null; then break; fi
    sleep 0.1
    _n=$((_n+1))
  done
  _log "watchdog child could not prove liveness after PID publication (pid=$_new); refusing DNS interception"
  if _valid_pid "$_new"; then kill -TERM "$_new" 2>/dev/null || :; fi
  _cur=$(cat "$PIDFILE" 2>/dev/null)
  [ "$_cur" != "$_new" ] || rm -f "$PIDFILE" 2>/dev/null || :
  exit 1
fi

[ "$MODE" = loop ] || { echo 'usage: localdns-watchdog.sh {start|loop|stop} [module_dir] [data_dir]' >&2; exit 64; }
_watch_sleep_pid=
_watchdog_exit() {
  # The polling sleep is a child process. Terminate and reap it on shutdown so
  # repeated start/stop cycles do not leave orphaned 30-second sleepers.
  if [ -n "${_watch_sleep_pid:-}" ]; then
    kill "$_watch_sleep_pid" 2>/dev/null || :
    wait "$_watch_sleep_pid" 2>/dev/null || :
    _watch_sleep_pid=
  fi
  _remove_owned_pidfile
  exit 0
}
trap '_watchdog_exit' HUP INT TERM
# The child can execute before the parent has published its PID. Wait briefly
# for the atomic PID-file rename instead of exiting spuriously on this race.
_readywait=0
while [ "$_readywait" -lt 30 ]; do
  _cur=$(cat "$PIDFILE" 2>/dev/null)
  [ "$_cur" = "$$" ] && break
  sleep 0.1
  _readywait=$((_readywait + 1))
done
_cur=$(cat "$PIDFILE" 2>/dev/null)
if [ "$_cur" != "$$" ]; then _log 'PID ownership was not published in time; exiting safely'; exit 0; fi
while :; do
  _cur=$(cat "$PIDFILE" 2>/dev/null)
  if [ "$_cur" != "$$" ]; then _log 'PID ownership changed; exiting'; exit 0; fi
  # A missing engine marker does NOT prove that DNS redirection has already been
  # rolled back: an engine may have crashed or been killed outside apply.sh.
  # Re-enter the normal apply transaction so it can restart a healthy chain or
  # detach its IPv4/IPv6 hooks and restore fail-open. Never edit firewall rules here.
  if [ ! -s "$PG/adguardhome/managed.pid" ] || [ ! -s "$PG/unbound/managed.pid" ]; then
    _log 'engine PID marker absent while watchdog active; invoking apply transaction to recover or roll back DNS interception'
    sh "$MODDIR/scripts/apply.sh" fast >> "$LOG" 2>&1
    _apply_rc=$?
    if [ ! -s "$PG/adguardhome/managed.pid" ] || [ ! -s "$PG/unbound/managed.pid" ]; then
      # apply may return 75 when another transaction owns apply.lock. In that
      # case, exiting here would abandon monitoring while stale PGNAT hooks may
      # still exist. Never claim rollback unless apply actually proves recovery;
      # keep the watcher alive and retry through the normal serialized transaction.
      if [ "$_apply_rc" -ne 0 ]; then
        _log "apply transaction failed rc=$_apply_rc and DNS engine markers remain absent; retaining watcher and retrying instead of assuming fail-open"
      else
        _log 'apply returned success but DNS engine markers remain absent; retaining watcher and retrying recovery'
      fi
      sleep 2
      continue
    fi
    _log 'DNS engine markers re-established by apply; continue full-chain health checks'
  fi
  # Check the whole chain, not Unbound alone. A dead AdGuard Home process can
  # leave its stale PID marker while Unbound remains healthy; the previous
  # resolver-only probe missed that black-hole and kept redirects installed.
  if ! sh "$MODDIR/scripts/adguardhome.sh" status "$MODDIR" "$PG" >/dev/null 2>&1; then
    _log 'AdGuard Home filtering front-end or uncached Unbound recursive probe failed while redirects were active; invoking normal apply rollback'
    sh "$MODDIR/scripts/apply.sh" fast >> "$LOG" 2>&1
    _apply_rc=$?
    # apply.sh owns netfilter transactions and lifecycle rollback. A lock
    # contention (rc=75) must not turn into a 30-second blind window with stale
    # engine PID markers and potentially live PGNAT hooks. Retry quickly through
    # the serialized apply path; never mutate firewall rules in this watchdog.
    if [ "$_apply_rc" -ne 0 ]; then
      _log "apply recovery/rollback failed rc=$_apply_rc after DNS health probe failure; retaining watcher and retrying in 2s"
      sleep 2
      continue
    fi
    if [ ! -s "$PG/adguardhome/managed.pid" ] || [ ! -s "$PG/unbound/managed.pid" ]; then
      _log 'local DNS chain stopped by successful apply transaction; watcher exiting'
      _remove_owned_pidfile
      exit 0
    fi
    _log 'apply returned success but engine markers remain; rechecking DNS health promptly instead of waiting the normal interval'
    sleep 2
    continue
  fi
  # Recover from a dead resolver promptly; a 90-second blind window can
  # leave redirected DNS black-holed for too long after a runtime failure.
  # Run the long polling delay as a child and wait explicitly. A TERM sent to
  # this shell while it is blocked in a foreground sleep may not run the trap
  # until the full 30 seconds elapse; that makes stop appear hung and can exceed
  # the regression runner timeout. wait is interruptible when the shell receives
  # TERM, so cleanup can remove only this watchdog's PID marker promptly.
  sleep 30 &
  _watch_sleep_pid=$!
  wait "$_watch_sleep_pid" || :
done
