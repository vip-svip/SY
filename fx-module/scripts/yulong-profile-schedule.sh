#!/system/bin/sh
# Yulong ProtectionProfile periodic scheduler; separate from the ad-list timer.
set -u
ACTION=${1:-status}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" 2>/dev/null && pwd)
SCRIPT="$SCRIPT_DIR/yulong-profile-schedule.sh"
MP=${MP:-${SCRIPT_DIR%/scripts}}
PG=${PG:-/data/adb/privacyguard}
case "$ACTION" in watch|start|stop|evaluate)
  [ -z "${2:-}" ] || MP=$2
  [ -z "${3:-}" ] || PG=$3
  ;;
esac
[ -f "$MP/scripts/yulong-profiles.sh" ] || { echo "profile controller missing" >&2; exit 20; }
PIDFILE="$PG/yulong-profile-schedule.pid"
LOG="$PG/yulong-profile-schedule.log"
LOCK="$PG/yulong-profile-schedule.runtime.lock"
OWNER="$LOCK/owner"
HELD=0
SELF_PID=
SELF_START=
_yps_validate_parent_chain() {
  _yps_candidate=$1
  case "$_yps_candidate" in /*) : ;; *) return 1 ;; esac
  case "$_yps_candidate" in /|*/|*//* ) return 1 ;; esac
  _yps_final=${_yps_candidate##*/}
  case "$_yps_final" in ''|.|..) return 1 ;; esac
  _yps_parent=${_yps_candidate%/*}
  [ -n "$_yps_parent" ] || _yps_parent=/
  _yps_rest=${_yps_parent#/}
  _yps_walk=
  while [ -n "$_yps_rest" ]; do
    case "$_yps_rest" in
      */*) _yps_component=${_yps_rest%%/*}; _yps_rest=${_yps_rest#*/} ;;
      *) _yps_component=$_yps_rest; _yps_rest= ;;
    esac
    case "$_yps_component" in ''|.|..) return 1 ;; esac
    _yps_walk="$_yps_walk/$_yps_component"
    [ -d "$_yps_walk" ] && [ ! -L "$_yps_walk" ] || return 1
  done
  return 0
}
_yps_validate_parent_chain "$PG" || { echo "profile scheduler state parent is unsafe" >&2; exit 21; }
[ ! -L "$PG" ] || exit 21
if [ ! -e "$PG" ]; then mkdir "$PG" 2>/dev/null || exit 21; fi
[ -d "$PG" ] && [ ! -L "$PG" ] || exit 21
for _yps_path in "$PIDFILE" "$LOG" "$LOCK"; do
  [ ! -L "$_yps_path" ] || { echo "profile scheduler path is a symbolic link" >&2; exit 21; }
done
[ ! -e "$LOCK" ] || [ -d "$LOCK" ] || exit 21
log(){ printf '[%s] profile-schedule: %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$LOG" 2>/dev/null || :; }
proc_start(){
  _pid=$1
  case "$_pid" in ''|*[!0-9]*) return 1 ;; esac
  [ -r "/proc/$_pid/stat" ] || return 1
  _tail=$(sed 's/^.*) //' "/proc/$_pid/stat" 2>/dev/null) || return 1
  _state=$(printf '%s\n' "$_tail" | awk '{print $1}')
  _start=$(printf '%s\n' "$_tail" | awk '{print $20}')
  case "$_state" in Z|X|'') return 1 ;; esac
  case "$_start" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$_start"
}
process_running(){
  _live_start=$(proc_start "$1" 2>/dev/null) || return 1
  [ -n "$_live_start" ]
}
is_our_watcher(){
  _watch_pid=$1
  _expected_start=${2:-}
  process_running "$_watch_pid" || return 1
  _live_start=$(proc_start "$_watch_pid" 2>/dev/null) || return 1
  [ -z "$_expected_start" ] || [ "$_live_start" = "$_expected_start" ] || return 1
  [ -r "/proc/$_watch_pid/cmdline" ] || return 1
  tr '\000' '\n' < "/proc/$_watch_pid/cmdline" 2>/dev/null |
    awk -v script="$SCRIPT" '
      $0 == script { found=1; next }
      found && $0 == "watch" { exit 0 }
      END { if (!found) exit 1 }
    '
}
read_pid_record(){
  [ -f "$PIDFILE" ] && [ ! -L "$PIDFILE" ] || return 1
  _record=$(cat "$PIDFILE" 2>/dev/null) || return 1
  _record_pid=$(printf '%s\n' "$_record" | sed -n '1p')
  _record_start=$(printf '%s\n' "$_record" | sed -n '2p')
  case "$_record_pid" in ''|*[!0-9]*) return 2 ;; esac
  case "$_record_start" in ''|*[!0-9]*) _record_start= ;; esac
  [ -z "$(printf '%s\n' "$_record" | sed -n '3p')" ] || return 2
  printf '%s|%s\n' "$_record_pid" "$_record_start"
}
release_lock(){
  [ "$HELD" = 1 ] || return 0
  if [ -f "$OWNER" ] && [ ! -L "$OWNER" ]; then
    _record=$(cat "$OWNER" 2>/dev/null || :)
    _pid=$(printf '%s\n' "$_record" | awk '{print $1}')
    _start=$(printf '%s\n' "$_record" | awk '{print $2}')
    if [ "$_pid" = "$SELF_PID" ] && [ "$_start" = "$SELF_START" ]; then
      rm -f "$OWNER" 2>/dev/null || :
      rmdir "$LOCK" 2>/dev/null || :
    fi
  fi
  HELD=0
}
acquire_lock(){
  _stat=
  IFS= read -r _stat < /proc/self/stat || return 31
  SELF_PID=${_stat%% *}
  case "$SELF_PID" in ''|*[!0-9]*) return 31 ;; esac
  SELF_START=$(proc_start "$SELF_PID" 2>/dev/null || :)
  case "$SELF_START" in ''|*[!0-9]*) return 31 ;; esac
  _tries=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    if [ -d "$LOCK" ] && [ ! -L "$LOCK" ] && [ -s "$OWNER" ] && [ ! -L "$OWNER" ]; then
      _old=$(cat "$OWNER" 2>/dev/null || :)
      _pid=$(printf '%s\n' "$_old" | awk '{print $1}')
      _start=$(printf '%s\n' "$_old" | awk '{print $2}')
      _actual=
      case "$_pid:$_start" in *[!0-9:]*|:*) : ;; *) _actual=$(proc_start "$_pid" 2>/dev/null || :) ;; esac
      if [ "$_actual" != "$_start" ] && [ "$(cat "$OWNER" 2>/dev/null || :)" = "$_old" ]; then
        rm -f "$OWNER" 2>/dev/null || :
        rmdir "$LOCK" 2>/dev/null || :
      fi
    fi
    _tries=$((_tries+1))
    [ "$_tries" -lt 100 ] || return 30
    sleep 0.1
  done
  (umask 077; printf '%s %s\n' "$SELF_PID" "$SELF_START" > "$OWNER") || { rmdir "$LOCK" 2>/dev/null || :; return 31; }
  HELD=1
}
with_lock(){
  acquire_lock || return $?
  if "$@"; then _rc=0; else _rc=$?; fi
  release_lock
  return "$_rc"
}
write_pid(){
  _pid_to_write=$1
  _start_to_write=$(proc_start "$_pid_to_write" 2>/dev/null) || return 1
  _tmp=$(mktemp "$PG/yulong-profile-schedule.pid.XXXXXX") || return 1
  if (umask 077; printf '%s\n%s\n' "$_pid_to_write" "$_start_to_write" > "$_tmp" && chmod 600 "$_tmp" && mv -f "$_tmp" "$PIDFILE"); then return 0; fi
  rm -f "$_tmp" 2>/dev/null || :
  return 1
}
evaluate_locked(){
  MP="$MP" PG="$PG" sh "$MP/scripts/yulong-profiles.sh" evaluate >> "$LOG" 2>&1
}
watch(){
  log "watcher started"
  while :; do evaluate_locked || log "profile evaluation failed; will retry"; sleep 60; done
}
start_locked(){
  # Avoid a permanent poller when no profile schedules have been created.
  _count=$(awk -F'|' 'NR>1 && $5=="1" && NF>=6 {n++} END{print n+0}' "$PG/yulong-profile-schedules.tsv" 2>/dev/null || echo 0)
  if [ "$_count" -eq 0 ]; then
    stop_locked
    echo "no-profile-schedules"
    return 0
  fi
  if _old_record=$(read_pid_record); then
    _oldpid=${_old_record%%|*}
    _oldstart=${_old_record#*|}
    if [ -n "$_oldstart" ] && is_our_watcher "$_oldpid" "$_oldstart"; then
      echo "already-running pid=$_oldpid"; return 0
    fi
  elif [ -f "$PIDFILE" ] && [ ! -L "$PIDFILE" ]; then
    # Legacy PID-only records are accepted only when argv proves this exact watcher.
    _oldpid=$(sed -n '1p' "$PIDFILE" 2>/dev/null)
    case "$_oldpid" in ''|*[!0-9]*) _oldpid= ;; esac
    if [ -n "$_oldpid" ] && is_our_watcher "$_oldpid"; then
      _legacy_start=$(proc_start "$_oldpid" 2>/dev/null || :)
      [ -n "$_legacy_start" ] && write_pid "$_oldpid" || return 1
      echo "already-running pid=$_oldpid"; return 0
    fi
  fi
  rm -f "$PIDFILE"
  nohup sh "$SCRIPT" watch "$MP" "$PG" >> "$LOG" 2>&1 &
  _pid=$!
  write_pid "$_pid" || { is_our_watcher "$_pid" && kill -TERM "$_pid" 2>/dev/null || :; return 1; }
  evaluate_locked || log "initial evaluation failed"
  echo "started pid=$_pid"
}
start(){ with_lock start_locked; }
stop_locked(){
  if _record=$(read_pid_record); then
    _pid=${_record%%|*}
    _expected_start=${_record#*|}
    is_our_watcher "$_pid" "$_expected_start" || {
      log "watcher PID identity no longer matches its published record; refusing signal"
      return 1
    }
    kill -TERM "$_pid" 2>/dev/null || :
    _wait=0
    while [ "$_wait" -lt 15 ] && is_our_watcher "$_pid" "$_expected_start"; do sleep 0.2; _wait=$((_wait+1)); done
    if is_our_watcher "$_pid" "$_expected_start"; then
      is_our_watcher "$_pid" "$_expected_start" || { log "watcher PID changed identity; refusing SIGKILL"; return 1; }
      kill -KILL "$_pid" 2>/dev/null || :
    fi
    _wait=0
    while [ "$_wait" -lt 15 ] && is_our_watcher "$_pid" "$_expected_start"; do sleep 0.2; _wait=$((_wait+1)); done
    is_our_watcher "$_pid" "$_expected_start" && { log "watcher did not stop"; return 1; }
  elif [ -f "$PIDFILE" ] && [ ! -L "$PIDFILE" ]; then
    _legacy_pid=$(sed -n '1p' "$PIDFILE" 2>/dev/null)
    case "$_legacy_pid" in ''|*[!0-9]*) _legacy_pid= ;; esac
    if [ -n "$_legacy_pid" ] && is_our_watcher "$_legacy_pid"; then
      _legacy_start=$(proc_start "$_legacy_pid" 2>/dev/null) || return 1
      kill -TERM "$_legacy_pid" 2>/dev/null || :
      _wait=0
      while [ "$_wait" -lt 15 ] && is_our_watcher "$_legacy_pid" "$_legacy_start"; do sleep 0.2; _wait=$((_wait+1)); done
      is_our_watcher "$_legacy_pid" "$_legacy_start" && { log "legacy watcher did not stop"; return 1; }
    fi
  fi
  rm -f "$PIDFILE"
  echo stopped
}
stop(){ with_lock stop_locked; }
status(){
  _running=0
  if _record=$(read_pid_record); then
    _pid=${_record%%|*}
    _start=${_record#*|}
    if [ -n "$_start" ] && is_our_watcher "$_pid" "$_start"; then _running=1; fi
  elif [ -f "$PIDFILE" ] && [ ! -L "$PIDFILE" ]; then
    _pid=$(sed -n '1p' "$PIDFILE" 2>/dev/null)
    case "$_pid" in ''|*[!0-9]*) _pid= ;; esac
    if [ -n "$_pid" ] && is_our_watcher "$_pid"; then _running=1; fi
  fi
  echo "watcher=$_running"
  echo "schedules=$(awk -F'|' 'NR>1 && $5=="1" && NF>=6 {n++} END{print n+0}' "$PG/yulong-profile-schedules.tsv" 2>/dev/null)"
}
trap 'release_lock; exit 129' HUP
trap 'release_lock; exit 130' INT
trap 'release_lock; exit 143' TERM
case "$ACTION" in
  watch) watch ;;
  start) start ;;
  stop) stop ;;
  evaluate) evaluate_locked ;;
  status) status ;;
  *) echo "usage: $0 {start|watch|stop|evaluate|status}" >&2; exit 64 ;;
esac
