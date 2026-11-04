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
mkdir -p "$PG" 2>/dev/null || exit 21
log(){ printf '[%s] profile-schedule: %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$LOG" 2>/dev/null || :; }
proc_start(){ [ -r "/proc/$1/stat" ] || return 1; awk '{print $22}' "/proc/$1/stat" 2>/dev/null; }
process_running(){
  kill -0 "$1" 2>/dev/null || return 1
  _state=$(awk '{print $3}' "/proc/$1/stat" 2>/dev/null || :)
  [ "$_state" != Z ]
}
is_our_watcher(){
  [ -r "/proc/$1/cmdline" ] || return 1
  _cmd=$(tr '\000' ' ' < "/proc/$1/cmdline" 2>/dev/null) || return 1
  case "$_cmd" in *"$SCRIPT"*' watch '*) return 0 ;; esac
  return 1
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
  _tmp=$(mktemp "$PG/yulong-profile-schedule.pid.XXXXXX") || return 1
  if (umask 077; printf '%s\n' "$1" > "$_tmp" && chmod 600 "$_tmp" && mv -f "$_tmp" "$PIDFILE"); then return 0; fi
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
  _count=$(awk 'NR>1 && $5=="1" && NF>=6 {n++} END{print n+0}' "$PG/yulong-profile-schedules.tsv" 2>/dev/null || echo 0)
  if [ "$_count" -eq 0 ]; then
    stop_locked
    echo "no-profile-schedules"
    return 0
  fi
  if [ -f "$PIDFILE" ] && [ ! -L "$PIDFILE" ]; then
    _oldpid=$(cat "$PIDFILE" 2>/dev/null)
    case "$_oldpid" in ''|*[!0-9]*) _oldpid= ;; esac
    if [ -n "$_oldpid" ] && process_running "$_oldpid" && is_our_watcher "$_oldpid"; then
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
  if [ -f "$PIDFILE" ] && [ ! -L "$PIDFILE" ]; then
    _pid=$(cat "$PIDFILE" 2>/dev/null)
    case "$_pid" in ''|*[!0-9]*) _pid= ;; esac
    if [ -n "$_pid" ] && process_running "$_pid" && is_our_watcher "$_pid"; then
      kill -TERM "$_pid" 2>/dev/null || :
      _wait=0
      while [ "$_wait" -lt 15 ] && process_running "$_pid"; do sleep 0.2; _wait=$((_wait+1)); done
      if process_running "$_pid"; then
        is_our_watcher "$_pid" || { log "watcher PID changed identity; refusing SIGKILL"; return 1; }
        kill -KILL "$_pid" 2>/dev/null || :
      fi
      _wait=0
      while [ "$_wait" -lt 15 ] && process_running "$_pid"; do sleep 0.2; _wait=$((_wait+1)); done
      process_running "$_pid" && { log "watcher did not stop"; return 1; }
    fi
  fi
  rm -f "$PIDFILE"
  echo stopped
}
stop(){ with_lock stop_locked; }
status(){
  _running=0
  if [ -f "$PIDFILE" ] && [ ! -L "$PIDFILE" ]; then
    _pid=$(cat "$PIDFILE" 2>/dev/null)
    case "$_pid" in ''|*[!0-9]*) _pid= ;; esac
    if [ -n "$_pid" ] && process_running "$_pid" && is_our_watcher "$_pid"; then _running=1; fi
  fi
  echo "watcher=$_running"
  echo "schedules=$(awk 'NR>1 && $5=="1" && NF>=6 {n++} END{print n+0}' "$PG/yulong-profile-schedules.tsv" 2>/dev/null)"
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
