#!/system/bin/sh
# Trusted Wi-Fi auto-pause for Yulong rules only; FX Hosts/96110/VPN stay independent.
set +u
MP="$MP"; PG="$PG"; CMD="$1"; A1="$2"; A2="$3"
set -u
LOCK_HELD=0
[ -n "$PG" ] || PG=/data/adb/privacyguard
[ -n "$CMD" ] || CMD=status
DIR=$(CDPATH= cd -- "$(dirname "$0")" 2>/dev/null && pwd)
SCRIPT="$DIR/yulong-trusted-network.sh"
if [ "$CMD" = watch ]; then MP=$A1; PG=$A2; fi
if [ -z "$MP" ]; then
 for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do
  if [ -s "$d/module.prop" ] && grep -q '^id=privacyguard$' "$d/module.prop" 2>/dev/null; then MP=$d; break; fi
 done
fi
[ -n "$MP" ] && [ -f "$MP/scripts/util.sh" ] || { echo "FX module missing" >&2; exit 20; }
. "$MP/scripts/util.sh"
CONF="$PG/yulong-trusted-network.conf"; LIST="$PG/yulong-trusted-ssids.conf"
MARK="$PG/yulong-trusted-paused"; PID="$PG/yulong-trusted-network.pid"
LOCK="$PG/yulong-trusted-network.lock"; LOG="$PG/yulong-trusted-network.log"
mkdir -p "$PG" 2>/dev/null || exit 21
[ -d "$PG" ] && [ ! -L "$PG" ] || exit 21
INTERVAL=10
log(){ printf '[%s] trusted-network: %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$1" >> "$LOG" 2>/dev/null || :; }
valid(){ v=$1; case "$v" in ''|*'|'*) return 1 ;; esac; n=$(printf '%s' "$v"|wc -c|tr -d ' '); [ "$n" -ge 1 ] && [ "$n" -le 32 ] || return 1; printf '%s' "$v"|LC_ALL=C grep -q '[[:cntrl:]]' && return 1; case "$v" in '<unknown ssid>'|'0x'|'null') return 1 ;; esac; }
is_enabled(){ [ -f "$CONF" ] && [ ! -L "$CONF" ] || { echo 0; return; }; awk -F= '$1=="enabled"{v=$2} END{print(v=="1"?1:0)}' "$CONF"; }
write_enabled(){ [ "$1" = 0 ] || [ "$1" = 1 ] || return 2; [ ! -L "$CONF" ] || return 21; t=$(mktemp "$CONF.tmp.XXXXXX") || return 31; if printf 'enabled=%s\n' "$1" > "$t" && chmod 600 "$t" && mv -f "$t" "$CONF"; then return 0; fi; rm -f "$t"; return 31; }
ssid(){
 line=$(dumpsys wifi 2>/dev/null|grep -m 1 -E 'mWifiInfo.*SSID:|WifiInfo.*SSID:' || true)
 [ -n "$line" ] || { command -v cmd >/dev/null 2>&1 && line=$(cmd wifi status 2>/dev/null|grep -m 1 'SSID:' || true); }
 [ -n "$line" ] || return 1
 v=$(printf '%s\n' "$line"|sed -n 's/.*SSID:[[:space:]]*"\([^"]*\)".*/\1/p')
 [ -n "$v" ] || v=$(printf '%s\n' "$line"|sed 's/.*SSID:[[:space:]]*//'|sed 's/[,;][[:space:]].*$//'|sed 's/^[[:space:]]*//'|sed 's/[[:space:]]*$//')
 valid "$v" || return 1; printf '%s\n' "$v"
}
contains(){ [ -f "$LIST" ] && [ ! -L "$LIST" ] || return 1; while IFS= read -r row || [ -n "$row" ]; do [ "$row" = "$1" ] && return 0; done < "$LIST"; return 1; }
master(){ [ "$(pg_get yulong_ad_filter_enabled 1 2>/dev/null || echo 1)" != 0 ]; }
schedule(){ [ "$(pg_get yulong_ad_schedule_active 1 2>/dev/null || echo 1)" != 0 ]; }
gate(){ [ "$(pg_get yulong_ad_trusted_active 1 2>/dev/null || echo 1)" != 0 ]; }
apply(){ sh "$MP/scripts/apply.sh" fast >> "$LOG" 2>&1; }
set_gate(){
 want=$1; old=$(pg_get yulong_ad_trusted_active 1 2>/dev/null || echo 1)
 [ "$want" = 0 ] || [ "$want" = 1 ] || return 2; [ "$old" = "$want" ] && return 0
 pg_set yulong_ad_trusted_active "$want" || return 1
 if apply; then return 0; fi
 pg_set yulong_ad_trusted_active "$old" >/dev/null 2>&1 || :; apply || :
 log "apply failed; previous gate restored"; return 1
}
marked(){ [ -f "$MARK" ] && [ ! -L "$MARK" ]; }
mark(){ [ ! -L "$MARK" ] || return 1; t=$(mktemp "$MARK.tmp.XXXXXX") || return 1; if printf 'version=1\nowner=yulong-trusted-network\n' > "$t" && chmod 600 "$t" && mv -f "$t" "$MARK"; then return 0; fi; rm -f "$t"; return 1; }
unmark(){ [ ! -L "$MARK" ] || return 1; [ ! -e "$MARK" ] || rm -f "$MARK"; }
evaluate(){
 e=$(is_enabled); s=$(ssid 2>/dev/null || true); match=0
 [ "$e" = 1 ] && [ -n "$s" ] && contains "$s" && match=1
 if [ "$match" = 1 ] && master && schedule; then
  if ! marked; then [ ! -L "$MARK" ] || return 1; mark || return 1; fi
  if gate; then set_gate 0 || { unmark || :; return 1; }; fi
  echo 'trusted=1'; echo 'paused_by_trusted=1'; return 0
 fi
 if marked; then set_gate 1 || return 1; unmark || return 1; log "trusted pause ended; restored owned Yulong rule gate"
 elif [ -L "$MARK" ]; then log "unsafe pause marker symlink; state unchanged"; return 1; fi
 echo "trusted=$match"; echo 'paused_by_trusted=0'
}
ours(){
 p=$1; case "$p" in ''|*[!0-9]*) return 1 ;; esac; [ -r "/proc/$p/cmdline" ] || return 1
 a2=$(tr '\000' '\n' < "/proc/$p/cmdline" 2>/dev/null|sed -n '2p'); a3=$(tr '\000' '\n' < "/proc/$p/cmdline" 2>/dev/null|sed -n '3p')
 a4=$(tr '\000' '\n' < "/proc/$p/cmdline" 2>/dev/null|sed -n '4p'); a5=$(tr '\000' '\n' < "/proc/$p/cmdline" 2>/dev/null|sed -n '5p')
 [ "$a2" = "$SCRIPT" ] && [ "$a3" = watch ] && [ "$a4" = "$MP" ] && [ "$a5" = "$PG" ]
}
lock_acquire(){
 i=0
 while [ "$i" -lt 30 ]; do
  if [ ! -L "$LOCK" ] && mkdir "$LOCK" 2>/dev/null; then
   LOCK_HELD=1; printf '%s\n' "$$" > "$LOCK/owner.tmp.$$" && chmod 600 "$LOCK/owner.tmp.$$" && mv "$LOCK/owner.tmp.$$" "$LOCK/owner" && return 0
   rm -f "$LOCK/owner.tmp.$$"; rmdir "$LOCK" 2>/dev/null || :; LOCK_HELD=0; return 1
  fi
  [ ! -L "$LOCK" ] && [ -d "$LOCK" ] || return 1
  p=$(cat "$LOCK/owner" 2>/dev/null || true); case "$p" in ''|*[!0-9]*) p= ;; esac
  if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then sleep 0.2
  else
   if [ "$i" -ge 10 ]; then
    stale="$LOCK.stale.$$.$i"
    if [ ! -e "$stale" ] && [ ! -L "$stale" ] && mv "$LOCK" "$stale" 2>/dev/null; then
     moved=$(cat "$stale/owner" 2>/dev/null || true)
     if [ -z "$moved" ] || { [ "$moved" = "$p" ] && ! kill -0 "$moved" 2>/dev/null; }; then rm -f "$stale/owner" 2>/dev/null || :; rmdir "$stale" 2>/dev/null || :
     elif [ ! -e "$LOCK" ] && [ ! -L "$LOCK" ]; then mv "$stale" "$LOCK" 2>/dev/null || :; fi
    fi
   fi
   sleep 0.2
  fi
  i=$((i+1))
 done
 return 1
}
lock_release(){
 [ "$LOCK_HELD" = 1 ] || return 0
 if [ ! -L "$LOCK" ] && [ -d "$LOCK" ] && [ ! -L "$LOCK/owner" ] && [ "$(cat "$LOCK/owner" 2>/dev/null || true)" = "$$" ]; then
  r="$LOCK.release.$$"
  if [ ! -e "$r" ] && [ ! -L "$r" ] && mv "$LOCK" "$r" 2>/dev/null; then
   if [ "$(cat "$r/owner" 2>/dev/null || true)" = "$$" ]; then rm -f "$r/owner" 2>/dev/null || :; rmdir "$r" 2>/dev/null || :
   elif [ ! -e "$LOCK" ] && [ ! -L "$LOCK" ]; then mv "$r" "$LOCK" 2>/dev/null || :; fi
  fi
 fi
 LOCK_HELD=0
}
publish(){ [ ! -L "$PID" ] || return 1; t=$(mktemp "$PID.tmp.XXXXXX") || return 1; if printf '%s\n' "$$" > "$t" && chmod 600 "$t" && mv -f "$t" "$PID"; then return 0; fi; rm -f "$t"; return 1; }
watch_loop(){
 [ ! -L "$PID" ] || exit 1
 if [ -s "$PID" ]; then old=$(cat "$PID" 2>/dev/null || true); [ "$old" = "$$" ] || { ours "$old" && exit 0; }; fi
 publish || exit 1
 cleanup(){ [ ! -L "$PID" ] && [ "$(cat "$PID" 2>/dev/null || true)" = "$$" ] && rm -f "$PID" 2>/dev/null || :; }
 trap cleanup EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
 log "watcher started"
 while :; do evaluate >/dev/null 2>&1 || log "evaluation failed; recovery will retry"; sleep "$INTERVAL" || :; done
}
start(){
 LOCK_HELD=0; lock_acquire || return 1
 if [ "$(is_enabled)" != 1 ] || [ ! -s "$LIST" ]; then lock_release; evaluate || :; echo watcher=disabled; return 0; fi
 if [ -s "$PID" ]; then p=$(cat "$PID" 2>/dev/null || true); if ours "$p" && kill -0 "$p" 2>/dev/null; then lock_release; evaluate || :; echo watcher=running; return 0; fi; [ ! -L "$PID" ] && rm -f "$PID" 2>/dev/null || :; fi
 [ ! -L "$PID" ] || { lock_release; return 1; }
 nohup sh "$SCRIPT" watch "$MP" "$PG" >> "$LOG" 2>&1 &
 child=$!; ready=0; i=0
 while [ "$i" -lt 30 ]; do
  if [ "$(cat "$PID" 2>/dev/null || true)" = "$child" ] && ours "$child"; then ready=1; break; fi
  kill -0 "$child" 2>/dev/null || break; sleep 0.1; i=$((i+1))
 done
 lock_release; [ "$ready" = 1 ] || { log "watcher PID was not verifiable"; return 1; }
 evaluate || :; echo watcher=started
}
stop(){
 uninstall=$1; LOCK_HELD=0; lock_acquire || return 1
 [ ! -L "$PID" ] || { lock_release; return 1; }
 p=$(cat "$PID" 2>/dev/null || true); case "$p" in ''|*[!0-9]*) p= ;; esac
 if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
  ours "$p" || { lock_release; return 1; }; kill -TERM "$p" 2>/dev/null || :; i=0
  while [ "$i" -lt 20 ] && kill -0 "$p" 2>/dev/null; do sleep 0.2; i=$((i+1)); done
  if kill -0 "$p" 2>/dev/null; then ours "$p" || { lock_release; return 1; }; kill -KILL "$p" 2>/dev/null || :; fi
  kill -0 "$p" 2>/dev/null && { lock_release; return 1; }
 fi
 [ ! -L "$PID" ] && [ "$(cat "$PID" 2>/dev/null || true)" = "$p" ] && rm -f "$PID" 2>/dev/null || :
 lock_release
 if [ "$uninstall" = 1 ]; then pg_set yulong_ad_trusted_active 1 >/dev/null 2>&1 || :; unmark || :; log "watcher stopped for uninstall"; return 0; fi
 evaluate
}
status(){
 e=$(is_enabled); s=$(ssid 2>/dev/null || true); match=0; [ -n "$s" ] && contains "$s" && match=1
 paused=0; marked && paused=1; watcher=0
 if [ -s "$PID" ]; then p=$(cat "$PID" 2>/dev/null || true); ours "$p" && kill -0 "$p" 2>/dev/null && watcher=1; fi
 echo FXYULONGTRUSTED1; echo "pause_enabled=$e"; echo "current_ssid=$s"; echo "trusted_match=$match"; echo "paused_by_trusted=$paused"
 echo "trusted_gate=$(pg_get yulong_ad_trusted_active 1 2>/dev/null || echo 1)"; echo "watcher=$watcher"
 if [ -f "$LIST" ] && [ ! -L "$LIST" ]; then while IFS= read -r row || [ -n "$row" ]; do valid "$row" && printf 'SSID|%s\n' "$row"; done < "$LIST"; fi
}
mutate(){
 mode=$1; value=$2; valid "$value" || return 2; [ ! -L "$LIST" ] || return 21
 t=$(mktemp "$LIST.tmp.XXXXXX") || return 31; found=0
 if [ -f "$LIST" ]; then while IFS= read -r row || [ -n "$row" ]; do [ "$row" = "$value" ] && found=1; if [ "$mode" = add ] || [ "$row" != "$value" ]; then printf '%s\n' "$row" >> "$t"; fi; done < "$LIST"; fi
 [ "$mode" != add ] || [ "$found" = 1 ] || printf '%s\n' "$value" >> "$t"
 if ! chmod 600 "$t" || ! mv -f "$t" "$LIST"; then rm -f "$t"; return 31; fi
 if [ "$(is_enabled)" = 1 ]; then start; else evaluate; fi
}
pause_set(){
 old=$(is_enabled); write_enabled "$1" || return $?
 if [ "$1" = 1 ]; then start && return 0; else stop 0 && return 0; fi
 write_enabled "$old" || :; if [ "$old" = 1 ]; then start || :; else stop 0 || :; fi; return 1
}
case "$CMD" in
 watch) watch_loop ;;
 start) start ;;
 stop) stop 0 ;;
 uninstall) stop 1 ;;
 status) status ;;
 evaluate) evaluate ;;
 add) [ -n "$A1" ] || exit 2; mutate add "$A1" ;;
 remove) [ -n "$A1" ] || exit 2; mutate remove "$A1" ;;
 pause-set) [ "$A1" = 0 ] || [ "$A1" = 1 ] || exit 2; pause_set "$A1" ;;
 *) echo "usage: $0 {status|evaluate|add SSID|remove SSID|pause-set 0|1|start|stop|uninstall}" >&2; exit 64 ;;
esac
