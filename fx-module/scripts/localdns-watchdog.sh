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
SELF_RAW=$SELF

# Reject traversal and symlinked ancestors before touching root-owned state.
_path_safe() {
  _path=$1
  case "$_path" in /*) : ;; *) return 1 ;; esac
  case "$_path" in *//*|*/../*|*/..|*/./*|*/.) return 1 ;; esac
  _rest=${_path#/}
  _walk=
  while [ -n "$_rest" ]; do
    case "$_rest" in
      */*) _part=${_rest%%/*}; _rest=${_rest#*/} ;;
      *) _part=$_rest; _rest= ;;
    esac
    case "$_part" in ''|.|..) return 1 ;; esac
    _walk="$_walk/$_part"
    [ ! -L "$_walk" ] || return 1
  done
  return 0
}
_file_safe_or_absent() {
  _file=$1
  _path_safe "$_file" || return 1
  [ ! -L "$_file" ] || return 1
  [ ! -e "$_file" ] || [ -f "$_file" ]
}
_prepare_paths() {
  _path_safe "$MODDIR" && [ -d "$MODDIR" ] || return 1
  _path_safe "$PG" || return 1
  [ ! -e "$PG" ] || [ -d "$PG" ] || return 1
  _path_safe "$SELF_RAW" && [ -f "$SELF_RAW" ] && [ ! -L "$SELF_RAW" ] || return 1
  _file_safe_or_absent "$PIDFILE" && _file_safe_or_absent "$LOG" || return 1
}
_prepare_paths || { echo "unsafe local DNS watchdog path" >&2; exit 22; }
SELF=$(readlink -f "$SELF_RAW" 2>/dev/null || printf '%s' "$SELF_RAW")

_log() { _file_safe_or_absent "$LOG" || return 0; printf '[%s] localdns-watchdog: %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$LOG" 2>/dev/null || :; }
# A loop can lose ownership between its first PID check and a later exit path.
# Never unlink a replacement watchdog's PID marker merely because our own loop
# is exiting; the marker is shared state and must be checked at removal time.
_release_pid_if_matches() {
  _expected=$1
  _file_safe_or_absent "$PIDFILE" || return 1
  [ -f "$PIDFILE" ] || return 0
  _current=$(cat "$PIDFILE" 2>/dev/null) || return 1
  [ "$_current" = "$_expected" ] || return 0
  _release=$(umask 077; mktemp "$PIDFILE.release.XXXXXX") || return 1
  if ! chmod 600 "$_release" || ! mv -f "$PIDFILE" "$_release"; then
    rm -f "$_release" 2>/dev/null || :
    return 1
  fi
  _moved=$(cat "$_release" 2>/dev/null || :)
  if [ "$_moved" = "$_expected" ] && [ -f "$_release" ] && [ ! -L "$_release" ]; then
    rm -f "$_release" 2>/dev/null || return 1
    return 0
  fi
  if [ ! -e "$PIDFILE" ] && [ ! -L "$PIDFILE" ]; then
    mv "$_release" "$PIDFILE" 2>/dev/null || :
  fi
  return 1
}
_pid_is_zombie() {
  _p=$1
  _stat=$(cat "/proc/$_p/stat" 2>/dev/null) || return 1
  _stat_tail=${_stat##*) }
  _state=${_stat_tail%% *}
  case "$_state" in Z|X) return 0 ;; *) return 1 ;; esac
}
_read_pid() {
  _file_safe_or_absent "$PIDFILE" && [ -f "$PIDFILE" ] || return 1
  _p=$(cat "$PIDFILE" 2>/dev/null) || return 1
  case "$_p" in ''|*[!0-9]*) return 1 ;; esac
  [ "$_p" -gt 1 ] 2>/dev/null || return 1
  echo "$_p"
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
  _argv=$(tr '\000' '\n' < "/proc/$_p/cmdline" 2>/dev/null) || return 1
  printf '%s\n' "$_argv" | grep -Fqx -- "$SELF" || return 1
  printf '%s\n' "$_argv" | grep -Fqx -- "loop" || return 1
  printf '%s\n' "$_argv" | grep -Fqx -- "$MODDIR" || return 1
  printf '%s\n' "$_argv" | grep -Fqx -- "$PG" || return 1
  return 0
}

# Read-only watchdog status uses exact PID/argument identity matching.
if [ "$MODE" = status ]; then
  if [ -L "$PIDFILE" ]; then echo unsafe; exit 22; fi
  if [ ! -e "$PIDFILE" ]; then echo stopped; exit 1; fi
  _old=$(cat "$PIDFILE" 2>/dev/null) || { echo invalid; exit 22; }
  case "$_old" in ''|*[!0-9]*) echo invalid; exit 22 ;; esac
  [ "$_old" -gt 1 ] 2>/dev/null || { echo invalid; exit 22; }
  if _valid_pid "$_old"; then
    echo "running pid=$_old"
    exit 0
  fi
  if kill -0 "$_old" 2>/dev/null && ! _pid_is_zombie "$_old"; then
    echo "identity_unknown pid=$_old"
    exit 23
  fi
  echo "stopped stale-pid=$_old"
  exit 1
fi

# Manual repair always enters the serialized apply transaction. This script
# never edits IPv4/IPv6 firewall rules or engine PID markers directly.
if [ "$MODE" = repair ]; then
  _apply="$MODDIR/scripts/apply.sh"
  if ! _path_safe "$_apply" || [ ! -f "$_apply" ] || [ -L "$_apply" ]; then
    echo "unsafe or missing FX apply transaction" >&2
    exit 22
  fi
  _log "manual DNS recovery requested; invoking serialized apply transaction"
  sh "$_apply" fast >> "$LOG" 2>&1
  _apply_rc=$?
  if [ "$_apply_rc" -eq 0 ]; then
    _log "manual DNS recovery completed by apply transaction"
    echo "dns_repair=applied"
    exit 0
  fi
  _log "manual DNS recovery failed through apply transaction rc=$_apply_rc"
  echo "dns_repair=failed"
  echo "reason=apply_exit_$_apply_rc"
  exit 1
fi

if [ "$MODE" = stop ]; then
  [ ! -e "$PIDFILE" ] && [ ! -L "$PIDFILE" ] && { echo stopped; exit 0; }
  _old=$(_read_pid 2>/dev/null) || {
    echo "local DNS watchdog PID record is malformed or unsafe" >&2
    exit 22
  }
  if ! _valid_pid "$_old"; then
    if kill -0 "$_old" 2>/dev/null && ! _pid_is_zombie "$_old"; then
      _log "refusing to stop live PID $_old because watchdog identity cannot be confirmed"
      echo "identity_unknown pid=$_old" >&2
      exit 23
    fi
    _release_pid_if_matches "$_old" || {
      echo "unable to clear stale local DNS watchdog PID record" >&2
      exit 1
    }
    echo "stopped stale-pid=$_old"
    exit 0
  fi

  # Revalidate exact process identity before every signal. A PID reused by an
  # unrelated process is never signalled or silently treated as a clean stop.
  _valid_pid "$_old" || { echo "watchdog identity changed before TERM" >&2; exit 23; }
  kill -TERM "$_old" 2>/dev/null || :
  _n=0
  while [ "$_n" -lt 20 ]; do
    if _valid_pid "$_old"; then
      sleep 0.2
      _n=$((_n+1))
      continue
    fi
    if kill -0 "$_old" 2>/dev/null && ! _pid_is_zombie "$_old"; then
      _log "watchdog PID $_old changed identity during TERM wait; preserving marker"
      echo "identity_unknown pid=$_old" >&2
      exit 23
    fi
    break
  done
  if _valid_pid "$_old" && kill -0 "$_old" 2>/dev/null; then
    _valid_pid "$_old" || { echo "watchdog identity changed before KILL" >&2; exit 23; }
    kill -KILL "$_old" 2>/dev/null || :
  fi
  _n=0
  while [ "$_n" -lt 10 ] && _valid_pid "$_old" && kill -0 "$_old" 2>/dev/null; do
    sleep 0.2
    _n=$((_n+1))
  done
  if _valid_pid "$_old" && kill -0 "$_old" 2>/dev/null; then
    _log "unable to stop watchdog pid=$_old; preserving marker"
    exit 1
  fi
  if kill -0 "$_old" 2>/dev/null && ! _pid_is_zombie "$_old"; then
    _log "watchdog PID $_old is live with unknown identity after stop; preserving marker"
    echo "identity_unknown pid=$_old" >&2
    exit 23
  fi
  _release_pid_if_matches "$_old" || {
    echo "unable to release stopped watchdog PID record" >&2
    exit 1
  }
  echo "stopped pid=$_old"
  exit 0
fi

if [ "$MODE" = start ]; then
  mkdir -p "$PG" 2>/dev/null || exit 1
  if [ -e "$PIDFILE" ] || [ -L "$PIDFILE" ]; then
    _old=$(_read_pid 2>/dev/null) || {
      echo "local DNS watchdog PID record is malformed or unsafe; refusing replacement" >&2
      exit 22
    }
    if _valid_pid "$_old"; then
      echo "running pid=$_old"
      exit 0
    fi
    if kill -0 "$_old" 2>/dev/null && ! _pid_is_zombie "$_old"; then
      _log "refusing to replace live PID $_old because watchdog identity cannot be confirmed"
      echo "identity_unknown pid=$_old" >&2
      exit 23
    fi
    _release_pid_if_matches "$_old" || {
      echo "unable to clear stale local DNS watchdog PID record" >&2
      exit 1
    }
  fi
  nohup sh "$SELF" loop "$MODDIR" "$PG" >> "$LOG" 2>&1 &
  _new=$!
  _tmp=$(umask 077; mktemp "$PG/localdns-watchdog.pid.tmp.XXXXXX") || { kill "$_new" 2>/dev/null || :; exit 1; }
  if ! echo "$_new" > "$_tmp" || ! chmod 600 "$_tmp" || ! mv -f "$_tmp" "$PIDFILE"; then
    rm -f "$_tmp" 2>/dev/null || :
    kill "$_new" 2>/dev/null || :
    exit 1
  fi
  # Do not report success until the exact child has published a verifiable
  # command line and is still alive.
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
  _release_pid_if_matches "$_new" || :
  exit 1
fi

[ "$MODE" = loop ] || { echo 'usage: localdns-watchdog.sh {start|loop|stop|status|repair} [module_dir] [data_dir]' >&2; exit 64; }
_watch_sleep_pid=
_watchdog_exit() {
  # The start/stop caller owns PID-marker release. The watcher never removes
  # shared state during exit, so it cannot delete a replacement process marker.
  if [ -n "${_watch_sleep_pid:-}" ]; then
    kill "$_watch_sleep_pid" 2>/dev/null || :
    wait "$_watch_sleep_pid" 2>/dev/null || :
    _watch_sleep_pid=
  fi
  _log "watch loop exiting; PID marker cleanup is handled by the owning start/stop transaction"
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
  if [ ! -s "$PG/dns/fxdns.pid" ]; then
    _log 'engine PID marker absent while watchdog active; invoking apply transaction to recover or roll back DNS interception'
    sh "$MODDIR/scripts/apply.sh" fast >> "$LOG" 2>&1
    _apply_rc=$?
    if [ ! -s "$PG/dns/fxdns.pid" ]; then
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
  if ! sh "$MODDIR/scripts/fxdns.sh" status "$MODDIR" "$PG" >/dev/null 2>&1; then
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
    if [ ! -s "$PG/dns/fxdns.pid" ]; then
      _log 'local DNS chain stopped by successful apply transaction; watcher exiting'
      _release_pid_if_matches "$$" || :
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
  # TERM, allowing the stop caller to verify process exit and release only the
  # PID marker whose recorded owner still matches the stopped watchdog.
  sleep 30 &
  _watch_sleep_pid=$!
  wait "$_watch_sleep_pid" || :
done
