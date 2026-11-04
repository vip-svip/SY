#!/system/bin/sh
# Bounded hourly watcher for enabled QuickJS script subscriptions.
# The scheduler owns one atomic PID record; stop/status never signal a reused PID.
set -u

_d=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P)
MODDIR=$(CDPATH= cd -- "$_d/../.." 2>/dev/null && pwd -P)
[ -f "$MODDIR/module.prop" ] || { echo "FX module directory unavailable" >&2; exit 2; }

PG=${PG:-/data/adb/privacyguard}
STATE_DIR="$PG/jsruntime"
PIDFILE="$STATE_DIR/scheduler.pid"
SCRIPT_PATH="$MODDIR/scripts/jsruntime/scheduler.sh"
OWNED=0
OWN_RECORD=
OWNER_PID=
OWNER_START=
OWNER_SNAPSHOT=

reject_symlink_path() {
  _check_path=$1
  while [ -n "$_check_path" ] && [ "$_check_path" != "/" ]; do
    [ ! -L "$_check_path" ] || return 1
    _check_path=${_check_path%/*}
    [ -n "$_check_path" ] || _check_path="/"
  done
  return 0
}

pid_fields() {
  _pid=$1
  case "$_pid" in ''|*[!0-9]*) return 1 ;; esac
  [ -r "/proc/$_pid/stat" ] || return 1
  _tail=$(sed 's/^.*) //' "/proc/$_pid/stat" 2>/dev/null) || return 1
  _state=$(printf '%s\n' "$_tail" | awk '{print $1}')
  _start=$(printf '%s\n' "$_tail" | awk '{print $20}')
  case "$_start" in ''|*[!0-9]*) return 1 ;; esac
  case "$_state" in Z|X) return 1 ;; esac
  printf '%s|%s\n' "$_state" "$_start"
}

process_matches() {
  _candidate_pid=$1
  _expected_start=${2:-}
  kill -0 "$_candidate_pid" 2>/dev/null || return 1
  [ -r "/proc/$_candidate_pid/cmdline" ] || return 1
  _fields=$(pid_fields "$_candidate_pid") || return 1
  _live_start=${_fields#*|}
  [ -z "$_expected_start" ] || [ "$_live_start" = "$_expected_start" ] || return 1
  tr '\000' ' ' < "/proc/$_candidate_pid/cmdline" 2>/dev/null     | grep -F "$SCRIPT_PATH" >/dev/null 2>&1
}

read_owner() {
  [ ! -L "$PIDFILE" ] || return 2
  [ -f "$PIDFILE" ] || return 1
  OWNER_SNAPSHOT=$(cat "$PIDFILE" 2>/dev/null) || return 2
  OWNER_PID=$(printf '%s\n' "$OWNER_SNAPSHOT" | sed -n '1p')
  case "$OWNER_PID" in ''|*[!0-9]*) return 2 ;; esac

  _marker=$(printf '%s\n' "$OWNER_SNAPSHOT" | sed -n '2p')
  case "$_marker" in
    FXSCHED1)
      _owner_script=$(printf '%s\n' "$OWNER_SNAPSHOT" | sed -n '3p')
      OWNER_START=$(printf '%s\n' "$OWNER_SNAPSHOT" | sed -n '4p')
      [ "$_owner_script" = "$SCRIPT_PATH" ] || return 2
      case "$OWNER_START" in ''|*[!0-9]*) return 2 ;; esac
      kill -0 "$OWNER_PID" 2>/dev/null || return 1
      _fields=$(pid_fields "$OWNER_PID") || return 1
      _live_start=${_fields#*|}
      [ "$_live_start" = "$OWNER_START" ] || return 2
      process_matches "$OWNER_PID" "$OWNER_START" || return 2
      return 0
      ;;
    '')
      # Backward compatibility with the old PID-only scheduler.pid format.
      kill -0 "$OWNER_PID" 2>/dev/null || return 1
      process_matches "$OWNER_PID" "" || return 2
      _fields=$(pid_fields "$OWNER_PID") || return 1
      OWNER_START=${_fields#*|}
      return 0
      ;;
    *)
      return 2
      ;;
  esac
}

remove_snapshot() {
  _expected_record=$1
  [ ! -L "$PIDFILE" ] || return 1
  [ -f "$PIDFILE" ] || return 1
  [ "$(cat "$PIDFILE" 2>/dev/null)" = "$_expected_record" ] || return 1
  _release="$PIDFILE.release.$$"
  [ ! -e "$_release" ] && [ ! -L "$_release" ] || return 1
  mv "$PIDFILE" "$_release" 2>/dev/null || return 1
  _moved=$(cat "$_release" 2>/dev/null || true)
  if [ "$_moved" = "$_expected_record" ]; then
    rm -f "$_release"
    return 0
  fi
  if [ ! -e "$PIDFILE" ] && [ ! -L "$PIDFILE" ]; then
    mv "$_release" "$PIDFILE" 2>/dev/null || :
  fi
  return 1
}

stop_requested() {
  [ ! -L "$STOPFILE" ] || return 1
  [ -f "$STOPFILE" ] || return 1
  [ "$(cat "$STOPFILE" 2>/dev/null)" = "$OWN_RECORD" ]
}

cleanup_owner() {
  if [ "$OWNED" = 1 ]; then
    if [ -f "$STOPFILE" ] && [ ! -L "$STOPFILE" ] \
        && [ "$(cat "$STOPFILE" 2>/dev/null)" = "$OWN_RECORD" ]; then
      rm -f "$STOPFILE"
    fi
    remove_snapshot "$OWN_RECORD" || :
    OWNED=0
  fi
}

acquire_owner() {
  _tries=0
  while [ "$_tries" -lt 20 ]; do
    [ ! -L "$PIDFILE" ] || { echo "unsafe QuickJS scheduler PID symlink" >&2; return 22; }
    if [ -e "$PIDFILE" ]; then
      _owner_state=0
      read_owner || _owner_state=$?
      case "$_owner_state" in
        0)
          echo "running=1"
          return 10
          ;;
        1)
          remove_snapshot "$OWNER_SNAPSHOT" || :
          ;;
        *)
          echo "QuickJS scheduler PID belongs to an unrelated or malformed process" >&2
          return 10
          ;;
      esac
    fi

    _start=$(printf '%s\n' "$(pid_fields "$$" 2>/dev/null)" | awk -F'|' '{print $2}')
    case "$_start" in ''|*[!0-9]*) echo "unable to read scheduler process start time" >&2; return 1 ;; esac
    OWN_RECORD=$(printf '%s\n%s\n%s\n%s' "$$" FXSCHED1 "$SCRIPT_PATH" "$_start")
    _tmp=$(mktemp "$STATE_DIR/.scheduler.XXXXXX") || return 1
    if ! {
      printf '%s\n%s\n%s\n%s\n' "$$" FXSCHED1 "$SCRIPT_PATH" "$_start" > "$_tmp" &&
      chmod 600 "$_tmp"
    }; then
      rm -f "$_tmp"
      return 1
    fi
    if ln "$_tmp" "$PIDFILE" 2>/dev/null; then
      rm -f "$_tmp"
      if [ -f "$PIDFILE" ] && [ ! -L "$PIDFILE" ]           && [ "$(cat "$PIDFILE" 2>/dev/null)" = "$OWN_RECORD" ]; then
        OWNED=1
        return 0
      fi
      echo "unable to verify QuickJS scheduler ownership" >&2
      return 1
    fi
    rm -f "$_tmp"
    _tries=$((_tries+1))
    sleep 0.05
  done
  echo "QuickJS scheduler is busy; start request was not queued" >&2
  return 10
}

stop_scheduler() {
  [ ! -L "$PIDFILE" ] || { echo "unsafe QuickJS scheduler PID symlink" >&2; return 22; }
  [ ! -L "$STOPFILE" ] || { echo "unsafe QuickJS scheduler stop path" >&2; return 22; }
  [ -f "$PIDFILE" ] || { echo "running=0"; return 0; }
  _owner_state=0
  read_owner || _owner_state=$?
  case "$_owner_state" in
    1)
      remove_snapshot "$OWNER_SNAPSHOT" || :
      echo "running=0"
      return 0
      ;;
    2)
      echo "QuickJS scheduler PID belongs to an unrelated or malformed process; refusing to signal it" >&2
      return 10
      ;;
    0)
      _stop_snapshot=$OWNER_SNAPSHOT
      if [ -e "$STOPFILE" ]; then
        [ -f "$STOPFILE" ] && [ "$(cat "$STOPFILE" 2>/dev/null)" = "$_stop_snapshot" ] || {
          echo "QuickJS scheduler stop request belongs to another owner" >&2
          return 10
        }
      else
        _stop_tmp=$(mktemp "$STATE_DIR/.scheduler-stop.XXXXXX") || return 1
        if ! {
          printf '%s\\n' "$_stop_snapshot" > "$_stop_tmp" &&
          chmod 600 "$_stop_tmp"
        }; then
          rm -f "$_stop_tmp"
          return 1
        fi
        if ! ln "$_stop_tmp" "$STOPFILE" 2>/dev/null; then
          rm -f "$_stop_tmp"
          [ -f "$STOPFILE" ] && [ ! -L "$STOPFILE" ] \
            && [ "$(cat "$STOPFILE" 2>/dev/null)" = "$_stop_snapshot" ] || return 10
        else
          rm -f "$_stop_tmp"
        fi
      fi

      _wait=0
      while [ "$_wait" -lt 50 ]; do
        if [ ! -f "$PIDFILE" ] || [ "$(cat "$PIDFILE" 2>/dev/null)" != "$_stop_snapshot" ]; then
          if [ -f "$STOPFILE" ] && [ ! -L "$STOPFILE" ] \
              && [ "$(cat "$STOPFILE" 2>/dev/null)" = "$_stop_snapshot" ]; then
            rm -f "$STOPFILE"
          fi
          echo "running=0"
          return 0
        fi
        sleep 0.1
        _wait=$((_wait+1))
      done
      echo "QuickJS scheduler stop requested; it has not exited within 5 seconds" >&2
      return 10
      ;;
  esac
}

scheduler_loop() {
  while [ -f "$MODDIR/module.prop" ] && [ -f "$PG/settings.conf" ]; do
    stop_requested && return 0
    interval=$(grep -m1 '^script_auto_update_h=' "$PG/settings.conf" 2>/dev/null | cut -d= -f2- | tr -d ' ')
    interval=${interval:-24}
    case "$interval" in ''|*[!0-9]*) interval=24 ;; esac
    [ "$interval" -lt 1 ] && interval=1
    [ "$interval" -gt 168 ] && interval=168

    now=$(date +%s 2>/dev/null)
    case "$now" in ''|*[!0-9]*) now=0 ;; esac
    stamp="$STATE_DIR/sub-last"
    prev=0
    [ -f "$stamp" ] && prev=$(cat "$stamp" 2>/dev/null)
    case "$prev" in ''|*[!0-9]*) prev=0 ;; esac

    if [ $((now-prev)) -ge $((interval*3600)) ]; then
      if awk '/^\\[list:script\\]/{s=1;next} /^\\[/{s=0} s && /^https:\\/\\/[^|]+\\|[^|]*\\|1([[:space:]]*)?$/{found=1} END{exit !found}' "$PG/settings.conf" 2>/dev/null; then
        sh "$MODDIR/scripts/jsruntime/sync-subs.sh" >> "$STATE_DIR/scheduler.log" 2>&1
        rc=$?
        if [ "$rc" -eq 0 ]; then
          _stamp_tmp=$(mktemp "$stamp.tmp.XXXXXX") || _stamp_tmp=
          if [ -n "$_stamp_tmp" ]; then
            printf '%s\\n' "$now" > "$_stamp_tmp" && chmod 600 "$_stamp_tmp" && mv -f "$_stamp_tmp" "$stamp" || rm -f "$_stamp_tmp"
          fi
        else
          echo "[$(date '+%F %T')] refresh failed rc=$rc; retry next hour" >> "$STATE_DIR/scheduler.log"
        fi
      fi
    fi

    _slept=0
    while [ "$_slept" -lt 3600 ]; do
      stop_requested && return 0
      sleep 2
      _slept=$((_slept+2))
    done
  done
}

cmd=${1:-start}
case "$cmd" in
  start)
    for _path in /data /data/adb "$PG" "$STATE_DIR" "$PIDFILE" "$STOPFILE"; do
      reject_symlink_path "$_path" || { echo "unsafe QuickJS scheduler state path: $_path" >&2; exit 22; }
    done
    mkdir -p "$STATE_DIR" 2>/dev/null || exit 1
    [ -d "$STATE_DIR" ] && [ ! -L "$STATE_DIR" ] || exit 22
    _acquire_rc=0
    acquire_owner || _acquire_rc=$?
    [ "$_acquire_rc" -eq 10 ] && exit 0
    [ "$_acquire_rc" -eq 0 ] || exit "$_acquire_rc"
    trap cleanup_owner EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    scheduler_loop
    ;;
  stop|uninstall)
    reject_symlink_path "$PIDFILE" && reject_symlink_path "$STOPFILE" || { echo "unsafe QuickJS scheduler state path" >&2; exit 22; }
    stop_scheduler
    ;;
  status)
    reject_symlink_path "$PIDFILE" || { echo "unsafe QuickJS scheduler PID path" >&2; exit 22; }
    _owner_state=0
    read_owner || _owner_state=$?
    [ "$_owner_state" -eq 0 ] && { echo "running=1"; exit 0; }
    echo "running=0"
    ;;
  *)
    echo "usage: $0 start|stop|status" >&2
    exit 64
    ;;
esac
