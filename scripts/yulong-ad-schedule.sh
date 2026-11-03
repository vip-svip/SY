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
mkdir -p "$PG" 2>/dev/null || exit 21
log() { printf '[%s] yulong-ad-schedule: %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$LOG" 2>/dev/null || :; }
read_value() {
  key=$1
  if [ -f "$SCHEDULE" ] && [ ! -L "$SCHEDULE" ]; then
    awk -F= -v key="$key" '$1==key {print substr($0,index($0,"=")+1); exit}' "$SCHEDULE"
  fi
}
valid_time() { printf '%s\n' "$1" | awk -F: 'NF==2 && $1~/^[0-9][0-9]$/ && $2~/^[0-9][0-9]$/ && $1+0<=23 && $2+0<=59 {ok=1} END{exit !ok}'; }
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
evaluate() {
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
watch() { log "watcher started"; while :; do evaluate || :; sleep 60; done; }
start() {
  if [ -s "$PIDFILE" ]; then
    old=$(cat "$PIDFILE" 2>/dev/null); case "$old" in ''|*[!0-9]*) old= ;; esac
    if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then echo "already-running pid=$old"; return 0; fi
  fi
  nohup sh "$SCRIPT" watch "$MP" "$PG" >> "$LOG" 2>&1 &
  pid=$!; (umask 077; printf '%s\n' "$pid" > "$PIDFILE") || return 1
  evaluate || :; echo "started pid=$pid"
}
stop() {
  if [ -s "$PIDFILE" ]; then
    pid=$(cat "$PIDFILE" 2>/dev/null); case "$pid" in ''|*[!0-9]*) pid= ;; esac
    [ -z "$pid" ] || kill "$pid" 2>/dev/null || :
  fi
  rm -f "$PIDFILE"
  pg_set yulong_ad_schedule_active 1 >/dev/null 2>&1 || :
  sh "$MP/scripts/apply.sh" fast >> "$LOG" 2>&1 || :
  log "watcher stopped; Yulong manual master preference remains unchanged"
  echo stopped
}
cmd=${1:-status}
case "$cmd" in
  start) start ;;
  watch) watch ;;
  evaluate) evaluate ;;
  stop) stop ;;
  status) echo "enabled=$(read_value enabled)"; echo "start=$(read_value start)"; echo "end=$(read_value end)"; echo "days=$(read_value days)"; echo "active=$(pg_get yulong_ad_schedule_active 1)" ;;
  *) echo "usage: $0 {start|watch|evaluate|stop|status}" >&2; exit 64 ;;
esac
