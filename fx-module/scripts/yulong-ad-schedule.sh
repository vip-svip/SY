#!/system/bin/sh
# Yulong 7.0.1 weekly ad-filter schedule migrated into FX.
# Weekday values: 1=Monday ... 7=Sunday.
set -u
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" 2>/dev/null && pwd)
SCRIPT="$SCRIPT_DIR/yulong-ad-schedule.sh"
MP=${MP:-}
PG=${PG:-/data/adb/privacyguard}
if [ "${1:-}" = "watch" ] && [ -n "${2:-}" ]; then MP=$2; fi
if [ -n "${3:-}" ]; then PG=$3; fi
for candidate in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do
  if [ -s "$candidate/module.prop" ] && grep -q '^id=privacyguard$' "$candidate/module.prop" 2>/dev/null; then MP=$candidate; break; fi
done
[ -n "$MP" ] && [ -f "$MP/scripts/util.sh" ] || exit 20
. "$MP/scripts/util.sh"
SCHEDULE="$PG/yulong-ad-schedule.conf"
PIDFILE="$PG/yulong-ad-schedule.pid"
LOG="$PG/yulong-ad-schedule.log"
RUNTIME_LOCK="$PG/yulong-ad-schedule.runtime.lock"
RUNTIME_OWNER="$RUNTIME_LOCK/owner"
RUNTIME_LOCK_HELD=0
RUNTIME_LOCK_START=
_yas_validate_parent_chain() {
  _yas_candidate=$1
  case "$_yas_candidate" in /*) : ;; *) return 1 ;; esac
  case "$_yas_candidate" in /|*/|*//* ) return 1 ;; esac
  _yas_final=${_yas_candidate##*/}
  case "$_yas_final" in ''|.|..) return 1 ;; esac
  _yas_parent=${_yas_candidate%/*}
  [ -n "$_yas_parent" ] || _yas_parent=/
  _yas_rest=${_yas_parent#/}
  _yas_walk=
  while [ -n "$_yas_rest" ]; do
    case "$_yas_rest" in
      */*) _yas_component=${_yas_rest%%/*}; _yas_rest=${_yas_rest#*/} ;;
      *) _yas_component=$_yas_rest; _yas_rest= ;;
    esac
    case "$_yas_component" in ''|.|..) return 1 ;; esac
    _yas_walk="$_yas_walk/$_yas_component"
    [ -d "$_yas_walk" ] && [ ! -L "$_yas_walk" ] || return 1
  done
  return 0
}
_yas_validate_parent_chain "$PG" || { echo "Yulong schedule state parent is unsafe" >&2; exit 21; }
[ ! -L "$PG" ] || exit 21
if [ ! -e "$PG" ]; then mkdir "$PG" 2>/dev/null || exit 21; fi
[ -d "$PG" ] && [ ! -L "$PG" ] || exit 21
for _yas_path in "$SCHEDULE" "$PIDFILE" "$LOG" "$RUNTIME_LOCK"; do
  [ ! -L "$_yas_path" ] || { echo "Yulong schedule state path is a symbolic link" >&2; exit 21; }
done
[ ! -e "$RUNTIME_LOCK" ] || [ -d "$RUNTIME_LOCK" ] || exit 21
log() { printf '[%s] yulong-ad-schedule: %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$LOG" 2>/dev/null || :; }
proc_start_time() {
  [ -r "/proc/$1/stat" ] || return 1
  awk '$3 != "Z" {print $22}' "/proc/$1/stat" 2>/dev/null
}
acquire_runtime_lock() {
  _lock_tries=0
  _lock_self_stat=
  IFS= read -r _lock_self_stat < /proc/self/stat || { log "cannot read current process identity"; return 31; }
  _lock_self_pid=${_lock_self_stat%% *}
  case "$_lock_self_pid" in ''|*[!0-9]*) log "cannot parse current process PID"; return 31 ;; esac
  _lock_self_start=$(proc_start_time "$_lock_self_pid" 2>/dev/null || :)
  case "$_lock_self_start" in ''|*[!0-9]*) log "cannot establish process identity for scheduler lock"; return 31 ;; esac
  _lock_retry_limit=${FX_YULONG_SCHEDULE_LOCK_RETRIES:-300}
  case "$_lock_retry_limit" in ''|*[!0-9]*|0) _lock_retry_limit=300 ;; esac
  [ "$_lock_retry_limit" -le 300 ] 2>/dev/null || _lock_retry_limit=300

  while :; do
    if [ -L "$RUNTIME_LOCK" ]; then
      log "scheduler runtime lock path is a symbolic link; refusing to follow it"
      return 31
    fi
    if mkdir "$RUNTIME_LOCK" 2>/dev/null; then
      break
    fi

    if [ -d "$RUNTIME_LOCK" ] && [ ! -L "$RUNTIME_LOCK" ] &&
       [ -s "$RUNTIME_OWNER" ] && [ ! -L "$RUNTIME_OWNER" ]; then
      _lock_record=$(cat "$RUNTIME_OWNER" 2>/dev/null || :)
      _lock_pid=$(printf '%s\n' "$_lock_record" | awk '{print $1}')
      _lock_start=$(printf '%s\n' "$_lock_record" | awk '{print $2}')
      case "$_lock_pid" in ''|*[!0-9]*) _lock_pid= ;; esac
      case "$_lock_start" in ''|*[!0-9]*) _lock_start= ;; esac
      if [ -n "$_lock_pid" ] && [ -n "$_lock_start" ]; then
        _lock_actual=$(proc_start_time "$_lock_pid" 2>/dev/null || :)
        if [ "$_lock_actual" != "$_lock_start" ] &&
           [ "$(cat "$RUNTIME_OWNER" 2>/dev/null || :)" = "$_lock_record" ]; then
          rm -f "$RUNTIME_OWNER" 2>/dev/null || :
          rmdir "$RUNTIME_LOCK" 2>/dev/null || :
        fi
      fi
    fi

    _lock_tries=$((_lock_tries + 1))
    if [ "$_lock_tries" -ge "$_lock_retry_limit" ]; then
      if [ -d "$RUNTIME_LOCK" ] && [ ! -s "$RUNTIME_OWNER" ]; then
        log "ownerless legacy scheduler lock remains; refusing unsafe automatic removal"
      else
        log "scheduler runtime lock remained busy or had no verifiable owner; operation was not applied"
      fi
      return 30
    fi
    sleep 0.2
  done

  _lock_owner_tmp="$RUNTIME_LOCK/owner.$_lock_self_pid"
  # Publish the owner record with a same-directory rename. Other starters
  # keep waiting while only owner.$PID exists; they may trust the lock only
  # after the complete PID + process-start identity becomes visible at owner.
  if (umask 077; printf '%s %s\n' "$_lock_self_pid" "$_lock_self_start" > "$_lock_owner_tmp" &&
      chmod 600 "$_lock_owner_tmp" && mv -f "$_lock_owner_tmp" "$RUNTIME_OWNER"); then
    _lock_published=$(cat "$RUNTIME_OWNER" 2>/dev/null || :)
    if [ ! -L "$RUNTIME_OWNER" ] &&
       [ "$_lock_published" = "$_lock_self_pid $_lock_self_start" ]; then
      RUNTIME_LOCK_HELD=1
      RUNTIME_LOCK_START=$_lock_self_start
      return 0
    fi
  fi
  rm -f "$_lock_owner_tmp" "$RUNTIME_OWNER" 2>/dev/null || :
  rmdir "$RUNTIME_LOCK" 2>/dev/null || :
  log "could not atomically publish and verify scheduler lock owner"
  return 31
}
release_runtime_lock() {
  [ "$RUNTIME_LOCK_HELD" = 1 ] || return 0
  if [ -f "$RUNTIME_OWNER" ] && [ ! -L "$RUNTIME_OWNER" ]; then
    _release_record=$(cat "$RUNTIME_OWNER" 2>/dev/null || :)
    _release_pid=$(printf '%s\n' "$_release_record" | awk '{print $1}')
    _release_start=$(printf '%s\n' "$_release_record" | awk '{print $2}')
    if [ "$_release_pid" = "$_lock_self_pid" ] && [ "$_release_start" = "$RUNTIME_LOCK_START" ]; then
      rm -f "$RUNTIME_OWNER" 2>/dev/null || :
      rmdir "$RUNTIME_LOCK" 2>/dev/null || :
    fi
  fi
  RUNTIME_LOCK_HELD=0
  RUNTIME_LOCK_START=
}
with_runtime_lock() {
  acquire_runtime_lock || return $?
  if "$@"; then
    _lock_rc=0
  else
    _lock_rc=$?
  fi
  release_runtime_lock
  return "$_lock_rc"
}
trap 'release_runtime_lock; exit 129' HUP
trap 'release_runtime_lock; exit 130' INT
trap 'release_runtime_lock; exit 143' TERM
read_value() {
  key=$1
  if [ -f "$SCHEDULE" ] && [ ! -L "$SCHEDULE" ]; then
    awk -F= -v key="$key" '$1==key {print substr($0,index($0,"=")+1); exit}' "$SCHEDULE"
  fi
}
valid_time() { printf '%s\n' "$1" | awk -F: 'NF==2 && $1~/^[0-9][0-9]$/ && $2~/^[0-9][0-9]$/ && $1+0<=23 && $2+0<=59 {ok=1} END{exit !ok}'; }
valid_days() { printf '%s\n' "$1" | awk -F, 'NF<1 || NF>7 {bad=1} {for(i=1;i<=NF;i++)if($i!~/^[1-7]$/||seen[$i]++)bad=1} END{exit bad?1:0}'; }
to_minutes() {
  h=${1%:*}; m=${1#*:}
  h=${h#0}; m=${m#0}
  [ -n "$h" ] || h=0
  [ -n "$m" ] || m=0
  printf '%s\n' "$((h * 60 + m))"
}
has_day() { case ",$1," in *,"$2",*) return 0 ;; *) return 1 ;; esac; }
calculate() {
  enabled=$(read_value enabled)
  [ "$enabled" = 1 ] || { echo 1; return 0; }
  start=$(read_value start); end=$(read_value end); days=$(read_value days)
  valid_time "$start" && valid_time "$end" || { echo 1; return 0; }
  [ -n "$days" ] || days=1,2,3,4,5,6,7
  valid_days "$days" || { log "invalid schedule weekdays; failing open to active ad filtering"; echo 1; return 0; }
  day=$(date '+%u' 2>/dev/null); now_hm=$(date '+%H:%M' 2>/dev/null)
  case "$day" in 1|2|3|4|5|6|7) ;; *) echo 1; return 0 ;; esac
  valid_time "$now_hm" || { echo 1; return 0; }
  now=$(to_minutes "$now_hm"); begin=$(to_minutes "$start"); finish=$(to_minutes "$end")
  previous=$((day - 1)); [ "$previous" -gt 0 ] || previous=7
  if [ "$begin" -eq "$finish" ]; then
    if has_day "$days" "$day"; then echo 1; else echo 0; fi
  elif [ "$begin" -lt "$finish" ]; then
    if has_day "$days" "$day" && [ "$now" -ge "$begin" ] && [ "$now" -lt "$finish" ]; then echo 1; else echo 0; fi
  elif [ "$now" -ge "$begin" ]; then
    if has_day "$days" "$day"; then echo 1; else echo 0; fi
  elif [ "$now" -lt "$finish" ]; then
    if has_day "$days" "$previous"; then echo 1; else echo 0; fi
  else
    echo 0
  fi
}
evaluate_locked() {
  desired=$(calculate)
  current=$(pg_get yulong_ad_schedule_active 1 2>/dev/null)
  case "$current" in 0|1) ;; *) current=1 ;; esac
  [ "$desired" = "$current" ] && { echo "active=$desired"; return 0; }
  if ! pg_set yulong_ad_schedule_active "$desired"; then log "failed to persist active=$desired"; return 1; fi
  if sh "$MP/scripts/apply.sh" fast >> "$LOG" 2>&1; then
    log "schedule state changed $current -> $desired; only Yulong ad rules are affected"
    echo "active=$desired"; return 0
  fi
  pg_set yulong_ad_schedule_active "$current" >/dev/null 2>&1 || :
  sh "$MP/scripts/apply.sh" fast >> "$LOG" 2>&1 || :
  log "apply failed; restored previous active state $current"; return 1
}
evaluate() { with_runtime_lock evaluate_locked; }
watch() { log "watcher started"; while :; do evaluate || :; sleep 60; done; }
process_start_time() {
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
process_running() { process_start_time "$1" >/dev/null 2>&1; }
is_our_watcher() {
  _watch_pid=$1
  _expected_start=${2:-}
  _live_start=$(process_start_time "$_watch_pid" 2>/dev/null) || return 1
  [ -z "$_expected_start" ] || [ "$_live_start" = "$_expected_start" ] || return 1
  [ -r "/proc/$_watch_pid/cmdline" ] || return 1
  tr '\000' '\n' < "/proc/$_watch_pid/cmdline" 2>/dev/null |
    awk -v script="$SCRIPT" '
      $0 == script { found=1; next }
      found && $0 == "watch" { exit 0 }
      END { if (!found) exit 1 }
    '
}
read_watcher_record() {
  [ -f "$PIDFILE" ] && [ ! -L "$PIDFILE" ] || return 1
  _record=$(cat "$PIDFILE" 2>/dev/null) || return 1
  _record_pid=$(printf '%s\n' "$_record" | sed -n '1p')
  _record_start=$(printf '%s\n' "$_record" | sed -n '2p')
  case "$_record_pid" in ''|*[!0-9]*) return 2 ;; esac
  case "$_record_start" in ''|*[!0-9]*) return 2 ;; esac
  [ -z "$(printf '%s\n' "$_record" | sed -n '3p')" ] || return 2
  printf '%s|%s\n' "$_record_pid" "$_record_start"
}
write_pidfile() {
  _pid_to_write=$1
  _start_to_write=$(process_start_time "$_pid_to_write" 2>/dev/null) || return 1
  _pid_tmp=$(mktemp "$PG/yulong-ad-schedule.pid.XXXXXX") || return 1
  if (umask 077; printf '%s\n%s\n' "$_pid_to_write" "$_start_to_write" > "$_pid_tmp" && chmod 600 "$_pid_tmp" && mv -f "$_pid_tmp" "$PIDFILE"); then
    return 0
  fi
  rm -f "$_pid_tmp" 2>/dev/null || :
  return 1
}
start_locked() {
  if [ "$(read_value enabled)" != 1 ]; then
    stop_locked "$@" || return 1
    echo "schedule-disabled"
    return 0
  fi
  if _old_record=$(read_watcher_record); then
    old=${_old_record%%|*}
    _old_start=${_old_record#*|}
    if is_our_watcher "$old" "$_old_start"; then
      echo "already-running pid=$old"
      return 0
    fi
  elif [ -f "$PIDFILE" ] && [ ! -L "$PIDFILE" ]; then
    # Upgrade a legacy PID-only pointer only after exact argv identity is known.
    old=$(sed -n '1p' "$PIDFILE" 2>/dev/null)
    case "$old" in ''|*[!0-9]*) old= ;; esac
    if [ -n "$old" ] && is_our_watcher "$old"; then
      write_pidfile "$old" || return 1
      echo "already-running pid=$old"
      return 0
    fi
  fi
  rm -f "$PIDFILE"
  nohup sh "$SCRIPT" watch "$MP" "$PG" >> "$LOG" 2>&1 &
  pid=$!
  if ! write_pidfile "$pid"; then
    if is_our_watcher "$pid"; then kill -TERM "$pid" 2>/dev/null || :; fi
    log "failed to persist watcher PID; spawned watcher was asked to stop"
    return 1
  fi
  evaluate_locked || log "watcher started; immediate evaluate failed and will retry on the next interval"
  echo "started pid=$pid"
}
start() { with_runtime_lock start_locked "$@"; }
stop_locked() {
  _uninstall_mode=
  [ "$#" -lt 4 ] || _uninstall_mode=$4
  if _record=$(read_watcher_record); then
    pid=${_record%%|*}
    _expected_start=${_record#*|}
    is_our_watcher "$pid" "$_expected_start" || {
      log "watcher PID identity no longer matches its published record; refusing signal"
      return 1
    }
    kill -TERM "$pid" 2>/dev/null || :
    _stop_wait=0
    while [ "$_stop_wait" -lt 10 ] && is_our_watcher "$pid" "$_expected_start"; do
      sleep 0.2; _stop_wait=$((_stop_wait + 1))
    done
    if is_our_watcher "$pid" "$_expected_start"; then
      is_our_watcher "$pid" "$_expected_start" || { log "PID $pid changed identity; refusing SIGKILL"; return 1; }
      kill -KILL "$pid" 2>/dev/null || :
      _stop_wait=0
      while [ "$_stop_wait" -lt 10 ] && is_our_watcher "$pid" "$_expected_start"; do
        sleep 0.2; _stop_wait=$((_stop_wait + 1))
      done
    fi
    is_our_watcher "$pid" "$_expected_start" && { log "could not confirm watcher PID $pid stopped"; return 1; }
  elif [ -f "$PIDFILE" ] && [ ! -L "$PIDFILE" ]; then
    pid=$(sed -n '1p' "$PIDFILE" 2>/dev/null)
    case "$pid" in ''|*[!0-9]*) pid= ;; esac
    if [ -n "$pid" ] && is_our_watcher "$pid"; then
      _legacy_start=$(process_start_time "$pid" 2>/dev/null) || return 1
      kill -TERM "$pid" 2>/dev/null || :
      _stop_wait=0
      while [ "$_stop_wait" -lt 10 ] && is_our_watcher "$pid" "$_legacy_start"; do
        sleep 0.2; _stop_wait=$((_stop_wait + 1))
      done
      is_our_watcher "$pid" "$_legacy_start" && { log "legacy watcher did not stop"; return 1; }
    fi
  fi
  rm -f "$PIDFILE"
  if [ "$_uninstall_mode" = "uninstall" ]; then
    log "watcher stopped for uninstall; skipping rule re-apply"
    echo stopped
    return 0
  fi
  if ! pg_set yulong_ad_schedule_active 1 >/dev/null 2>&1; then
    log "watcher stopped but could not restore active=1"
    return 1
  fi
  if ! sh "$MP/scripts/apply.sh" fast >> "$LOG" 2>&1; then
    log "watcher stopped but failed to re-apply manual Yulong rule state"
    return 1
  fi
  log "watcher stopped; Yulong manual master preference remains unchanged"
  echo stopped
}
stop() { with_runtime_lock stop_locked "$@"; }
status() {
  echo "enabled=$(read_value enabled)"
  echo "start=$(read_value start)"
  echo "end=$(read_value end)"
  echo "days=$(read_value days)"
  echo "active=$(pg_get yulong_ad_schedule_active 1)"
  watcher=0
  if _record=$(read_watcher_record); then
    pid=${_record%%|*}
    _start=${_record#*|}
    if is_our_watcher "$pid" "$_start"; then watcher=1; fi
  elif [ -f "$PIDFILE" ] && [ ! -L "$PIDFILE" ]; then
    pid=$(sed -n '1p' "$PIDFILE" 2>/dev/null)
    case "$pid" in ''|*[!0-9]*) pid= ;; esac
    if [ -n "$pid" ] && is_our_watcher "$pid"; then watcher=1; fi
  fi
  echo "watcher=$watcher"
}
cmd=${1:-status}
case "$cmd" in
  start) start "$@" ;;
  watch) watch ;;
  evaluate) with_runtime_lock evaluate_locked ;;
  stop) stop "$@" ;;
  status) status ;;
  *) echo "usage: $0 {start|watch|evaluate|stop|status}" >&2; exit 64 ;;
esac
