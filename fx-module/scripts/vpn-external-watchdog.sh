#!/system/bin/sh
# Reconcile FX's existing Root Proxy binding while a third-party Android VPN
# changes interfaces/routes. This watcher never creates a VpnService or claims
# to discover/own another app's VPN session.
set -u
MODDIR=${2:-${MODDIR:-/data/adb/modules/privacyguard}}
PG=${3:-${PG:-/data/adb/privacyguard}}
PROXY="$MODDIR/scripts/yulong-root-proxy.sh"
PIDFILE="$PG/vpn-external-watchdog.pid"
LOG="$PG/vpn-external-watchdog.log"
INTERVAL=${FX_VPN_WATCHDOG_INTERVAL:-15}
log(){ mkdir -p "$PG" 2>/dev/null || :; printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo unknown)" "$*" >> "$LOG"; }
valid_pid(){ case "$1" in ''|*[!0-9]*|0|1) return 1;; *) return 0;; esac; }
pid_matches(){
  _pid=$1
  valid_pid "$_pid" || return 1
  [ -r "/proc/$_pid/cmdline" ] || return 1
  _cmd=$(tr '\000' ' ' < "/proc/$_pid/cmdline" 2>/dev/null) || return 1
  case "$_cmd" in *"$MODDIR/scripts/vpn-external-watchdog.sh"*" _watch "*) return 0;; esac
  return 1
}
read_pid(){
  [ -f "$PIDFILE" ] && [ ! -L "$PIDFILE" ] || return 1
  IFS= read -r _pid < "$PIDFILE" || return 1
  valid_pid "$_pid" || return 1
  printf '%s\n' "$_pid"
}
snapshot(){
  mkdir -p "$PG" || return 1
  _tmp="$PG/.vpn-external-watchdog.snapshot.$$"
  (umask 077; {
    printf 'format=FXVPNWATCH1\n'
    printf 'proxy_enabled=%s\n' "$(awk -F= '$1=="vpn_external_dns_proxy"{gsub(/[[:space:]]/,"",$2);print $2;found=1} END{if(!found)print 1}' "$PG/settings.conf" 2>/dev/null)"
    printf 'captured_at=%s\n' "$(date +%s 2>/dev/null || echo 0)"
  } > "$_tmp") || { rm -f "$_tmp"; return 1; }
  mv -f "$_tmp" "$PG/vpn-external-watchdog.snapshot"
}
reconcile(){
  [ -f "$PROXY" ] || { log "Root Proxy helper missing; watcher cannot reconcile"; return 1; }
  MP="$MODDIR" PG="$PG" CONF="$PG/settings.conf" sh "$PROXY" reconcile
}
watch_loop(){
  trap 'exit 0' HUP INT TERM
  log "watch loop started interval=$INTERVAL"
  while :; do
    reconcile >> "$LOG" 2>&1 || log "reconcile failed; Root Proxy remains fail-open where cleanup is provable"
    sleep "$INTERVAL"
  done
}
cmd=${1:-status}
case "$cmd" in
  snapshot)
    MODDIR=${2:-$MODDIR}; PG=${3:-$PG}; PROXY="$MODDIR/scripts/yulong-root-proxy.sh"; PIDFILE="$PG/vpn-external-watchdog.pid"; LOG="$PG/vpn-external-watchdog.log"
    snapshot
    ;;
  mark-applied)
    MODDIR=${2:-$MODDIR}; PG=${3:-$PG}; PIDFILE="$PG/vpn-external-watchdog.pid"; LOG="$PG/vpn-external-watchdog.log"
    snapshot && log "FX apply completed; watcher baseline refreshed"
    ;;
  start)
    MODDIR=${2:-$MODDIR}; PG=${3:-$PG}; PROXY="$MODDIR/scripts/yulong-root-proxy.sh"; PIDFILE="$PG/vpn-external-watchdog.pid"; LOG="$PG/vpn-external-watchdog.log"
    [ -f "$PROXY" ] || { log "cannot start: Root Proxy helper missing"; exit 1; }
    mkdir -p "$PG" || exit 1
    [ ! -L "$PIDFILE" ] || { log "refusing symlink PID record"; exit 1; }
    if _old=$(read_pid) && pid_matches "$_old"; then log "watcher already running pid=$_old"; exit 0; fi
    rm -f "$PIDFILE" || exit 1
    nohup sh "$MODDIR/scripts/vpn-external-watchdog.sh" _watch "$MODDIR" "$PG" </dev/null >> "$LOG" 2>&1 &
    _new=$!
    valid_pid "$_new" || { log "failed to launch watcher"; exit 1; }
    (umask 077; printf '%s\n' "$_new" > "$PIDFILE") || { kill "$_new" 2>/dev/null || :; exit 1; }
    sleep 1
    pid_matches "$_new" || { rm -f "$PIDFILE"; log "watcher process identity could not be confirmed"; exit 1; }
    log "watcher started pid=$_new"
    ;;
  stop|uninstall)
    MODDIR=${2:-$MODDIR}; PG=${3:-$PG}; PROXY="$MODDIR/scripts/yulong-root-proxy.sh"; PIDFILE="$PG/vpn-external-watchdog.pid"; LOG="$PG/vpn-external-watchdog.log"
    [ ! -L "$PIDFILE" ] || { log "refusing symlink PID record"; exit 1; }
    if [ -e "$PIDFILE" ]; then
      _old=$(read_pid) || { log "invalid watcher PID record; preserving state"; exit 1; }
      if pid_matches "$_old"; then
        kill -TERM "$_old" 2>/dev/null || { log "could not signal watcher"; exit 1; }
        _wait=0
        while pid_matches "$_old" && [ "$_wait" -lt 5 ]; do sleep 1; _wait=$((_wait + 1)); done
        pid_matches "$_old" && { log "watcher did not stop; preserving PID record"; exit 1; }
      fi
      rm -f "$PIDFILE" || exit 1
    fi
    if [ -f "$PROXY" ]; then MP="$MODDIR" PG="$PG" CONF="$PG/settings.conf" sh "$PROXY" stop || { log "Root Proxy stop failed"; exit 1; }
    elif [ -e "$PG/yulong-root-proxy-active" ] || [ -e "$PG/yulong-root-proxy-active.meta" ] || [ -e "$PG/unbound-vpn-egress-ip" ]; then
      log "Root Proxy helper missing while active state remains"; exit 1
    fi
    log "watcher stopped and Root Proxy cleanup requested"
    ;;
  status)
    if _old=$(read_pid) && pid_matches "$_old"; then echo "running=1"; echo "pid=$_old"; else echo "running=0"; fi
    [ -f "$PROXY" ] && MP="$MODDIR" PG="$PG" CONF="$PG/settings.conf" sh "$PROXY" status
    ;;
  _watch)
    MODDIR=${2:-$MODDIR}; PG=${3:-$PG}; PROXY="$MODDIR/scripts/yulong-root-proxy.sh"; PIDFILE="$PG/vpn-external-watchdog.pid"; LOG="$PG/vpn-external-watchdog.log"
    watch_loop
    ;;
  *) echo "usage: $0 {snapshot|mark-applied|start|stop|uninstall|status}" >&2; exit 64 ;;
esac
