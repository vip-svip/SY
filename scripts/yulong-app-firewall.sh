#!/system/bin/sh
# Yulong 7.0.1 per-app firewall, independent of FX VPN routing.
set -eu
MP=${MP:-}
if [ -z "$MP" ]; then
  for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do
    if [ -s "$d/module.prop" ] && grep -q '^id=privacyguard$' "$d/module.prop" 2>/dev/null; then MP="$d"; break; fi
  done
fi
[ -n "$MP" ] && [ -s "$MP/module.prop" ] || { echo "FX module is not installed" >&2; exit 20; }
PG=${PG:-/data/adb/privacyguard}
CONF=${CONF:-$PG/settings.conf}
ACTIVE=${ACTIVE:-$PG/yulong-firewall-active}
LOCK=${LOCK:-$PG/yulong-firewall.lock}
NET_CLASS=${NET_CLASS:-/sys/class/net}
_FW_TEMP=
_FW_BACKUP=
_FW_RESTORE=
mkdir -p "$PG"
[ -d "$PG" ] && [ ! -L "$PG" ] || { echo "FX firewall state directory is unsafe" >&2; exit 21; }
[ -f "$CONF" ] && [ ! -L "$CONF" ] || { echo "FX settings.conf is missing or unsafe" >&2; exit 21; }
[ ! -L "$ACTIVE" ] || { echo "FX firewall active marker is unsafe" >&2; exit 22; }

valid_package() {
  case "$1" in ''|*[!A-Za-z0-9_.-]*) return 1 ;; esac
  printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$'
}
valid_state() { [ "$1" = 0 ] || [ "$1" = 1 ]; }
valid_time() { printf '%s\n' "$1" | grep -Eq '^([01][0-9]|2[0-3]):[0-5][0-9]$'; }
to_minutes() {
  _value=$1
  _hour=$(printf '%s' "$_value" | cut -d: -f1)
  _minute=$(printf '%s' "$_value" | cut -d: -f2)
  _hour=$(printf '%s' "$_hour" | sed 's/^0//')
  _minute=$(printf '%s' "$_minute" | sed 's/^0//')
  [ -n "$_hour" ] || _hour=0
  [ -n "$_minute" ] || _minute=0
  printf '%s\n' "$((_hour * 60 + _minute))"
}
time_is_active() {
  _schedule=$1; _start=$2; _end=$3; _now=$4
  [ "$_schedule" = 0 ] && return 0
  valid_time "$_start" && valid_time "$_end" && valid_time "$_now" || return 1
  _now_m=$(to_minutes "$_now"); _start_m=$(to_minutes "$_start"); _end_m=$(to_minutes "$_end")
  # Original FirewallManager uses device-local Calendar minutes and includes both bounds.
  if [ "$_start_m" -le "$_end_m" ]; then
    [ "$_now_m" -ge "$_start_m" ] && [ "$_now_m" -le "$_end_m" ]
  else
    [ "$_now_m" -ge "$_start_m" ] || [ "$_now_m" -le "$_end_m" ]
  fi
}
read_master() {
  awk '
    $0=="[conf:yulong_app_firewall]" {insec=1; next}
    /^\[/ {insec=0}
    insec && /^enabled=/ {v=substr($0,9)}
    END {if(v=="1") print 1; else print 0}
  ' "$CONF"
}
list_rows() {
  awk -F'|' '
    function bit(v) { return v=="0" || v=="1" }
    function validtime(v) { return v ~ /^([01][0-9]|2[0-3]):[0-5][0-9]$/ }
    $0=="[list:yulong_app_firewall]" {inlist=1; next}
    /^\[/ {inlist=0}
    inlist && $1 ~ /^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$/ && $2 ~ /^[0-9]+$/ && bit($3) {
      if (NF==3) print $1 "|" $2 "|" $3 "|1|1|0|22:00|06:00"
      else if (NF>=8 && bit($4) && bit($5) && bit($6) && validtime($7) && validtime($8))
        print $1 "|" $2 "|" $3 "|" $4 "|" $5 "|" $6 "|" $7 "|" $8
    }
  ' "$CONF"
}
set_master_value() {
  wanted="$1"
  tmp=$(mktemp "$CONF.yulong-master.XXXXXX") || return 1
  _FW_TEMP=$tmp
  awk -v wanted="$wanted" '
    BEGIN {insec=0; seen=0; written=0}
    $0=="[conf:yulong_app_firewall]" {
      if(insec && !written){print "enabled=" wanted; written=1}
      insec=1; seen=1; print; next
    }
    /^\[/ {
      if(insec && !written){print "enabled=" wanted; written=1}
      insec=0; print; next
    }
    insec && /^enabled=/ {
      if(!written) print "enabled=" wanted
      written=1; next
    }
    {print}
    END {
      if(insec && !written) print "enabled=" wanted
      if(!seen) {print ""; print "[conf:yulong_app_firewall]"; print "enabled=" wanted}
    }
  ' "$CONF" > "$tmp" || { rm -f "$tmp"; _FW_TEMP=; return 1; }
  if [ -s "$tmp" ] && [ ! -L "$CONF" ] && chmod 600 "$tmp" && mv -f "$tmp" "$CONF"; then
    _FW_TEMP=
    return 0
  fi
  rm -f "$tmp"
  _FW_TEMP=
  return 1
}
set_rule_value() {
  pkg="$1"; uid="$2"; state="$3"; wifi="$4"; mobile="$5"; schedule="$6"; start="$7"; end="$8"
  tmp=$(mktemp "$CONF.yulong-list.XXXXXX") || return 1
  _FW_TEMP=$tmp
  awk -F'|' -v OFS='|' -v pkg="$pkg" -v uid="$uid" -v state="$state" \
      -v wifi="$wifi" -v mobile="$mobile" -v schedule="$schedule" -v start="$start" -v end="$end" '
    BEGIN {inlist=0; seen=0; inserted=0}
    $0=="[list:yulong_app_firewall]" {inlist=1; seen=1; print; next}
    /^\[/ {
      if(inlist && !inserted){print pkg,uid,state,wifi,mobile,schedule,start,end; inserted=1}
      inlist=0; print; next
    }
    inlist && $1==pkg {if(!inserted){print pkg,uid,state,wifi,mobile,schedule,start,end; inserted=1} next}
    {print}
    END {
      if(inlist && !inserted){print pkg,uid,state,wifi,mobile,schedule,start,end; inserted=1}
      if(!seen){print ""; print "[list:yulong_app_firewall]"; print pkg,uid,state,wifi,mobile,schedule,start,end}
    }
  ' "$CONF" > "$tmp" || { rm -f "$tmp"; _FW_TEMP=; return 1; }
  if [ -s "$tmp" ] && [ ! -L "$CONF" ] && chmod 600 "$tmp" && mv -f "$tmp" "$CONF"; then _FW_TEMP=; return 0; fi
  rm -f "$tmp"; _FW_TEMP=; return 1
}
remove_item_value() {
  pkg="$1"; tmp=$(mktemp "$CONF.yulong-remove.XXXXXX") || return 1
  _FW_TEMP=$tmp
  awk -F'|' -v pkg="$pkg" '
    $0=="[list:yulong_app_firewall]" {inlist=1; print; next}
    /^\[/ {inlist=0; print; next}
    inlist && $1==pkg {next}
    {print}
  ' "$CONF" > "$tmp" || { rm -f "$tmp"; _FW_TEMP=; return 1; }
  if [ -s "$tmp" ] && [ ! -L "$CONF" ] && chmod 600 "$tmp" && mv -f "$tmp" "$CONF"; then _FW_TEMP=; return 0; fi
  rm -f "$tmp"; _FW_TEMP=; return 1
}
set_item_value() {
  pkg="$1"; uid="$2"; state="$3"
  if [ "$state" = 0 ]; then remove_item_value "$pkg"; return $?; fi
  old=$(list_rows | awk -F'|' -v pkg="$pkg" '$1==pkg {print; exit}')
  if [ -n "$old" ]; then
    IFS='|' read -r _old_pkg _old_uid _old_state wifi mobile schedule start end <<EOF
$old
EOF
  else
    wifi=1; mobile=1; schedule=0; start=22:00; end=06:00
  fi
  set_rule_value "$pkg" "$uid" "$state" "$wifi" "$mobile" "$schedule" "$start" "$end"
}
resolve_uid() {
  pkg="$1"
  snapshot="$2"
  found="$(printf '%s\n' "$snapshot" | awk -v wanted="package:$pkg" '
    BEGIN {seen=0}
    $1==wanted {
      seen=1
      for(i=2;i<=NF;i++) if($i ~ /^uid:[0-9]+$/) {
        sub(/^uid:/,"",$i); print $i; exit
      }
    }
    END {if(!seen) print "__MISSING__"}
  ')"
  [ "$found" = "__MISSING__" ] && return 2
  case "$found" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$found"
}

remove_hook() {
  bin="$1"; chain="$2"
  while "$bin" -t filter -C OUTPUT -j "$chain" >/dev/null 2>&1; do
    "$bin" -t filter -D OUTPUT -j "$chain" >/dev/null 2>&1 || break
  done
}
clear_chain() {
  bin="$1"; chain="$2"
  remove_hook "$bin" "$chain" || :
  "$bin" -t filter -F "$chain" >/dev/null 2>&1 || :
  "$bin" -t filter -X "$chain" >/dev/null 2>&1 || :
}
clear_all() {
  for chain in FXYUL_A FXYUL_B; do
    clear_chain iptables "$chain"
    clear_chain ip6tables "$chain"
  done
  rm -f "$ACTIVE"
}
build_chain() {
  bin="$1"; chain="$2"; uids="$3"; now="$4"
  "$bin" -t filter -N "$chain" >/dev/null 2>&1 || "$bin" -t filter -F "$chain"
  [ -d "$NET_CLASS" ] || { echo "network interface inventory unavailable" >&2; return 1; }
  _FW_INTERFACE_COUNT=0
  for iface_path in "$NET_CLASS"/*; do
    [ -e "$iface_path" ] || continue
    iface=${iface_path##*/}
    case "$iface" in ''|lo|dummy*|ifb*) continue ;; esac
    _FW_INTERFACE_COUNT=$((_FW_INTERFACE_COUNT + 1))
  done
  [ "$_FW_INTERFACE_COUNT" -gt 0 ] || { echo "no usable network interfaces; keep previous firewall" >&2; return 1; }
  _FW_BLOCKED_COUNT=0
  while IFS='|' read -r pkg uid state block_wifi block_mobile schedule start end; do
    [ "$state" = 1 ] || continue
    time_is_active "$schedule" "$start" "$end" "$now" || continue
    [ "$block_wifi" = 1 ] || [ "$block_mobile" = 1 ] || continue
    rule_added=0
    for iface_path in "$NET_CLASS"/*; do
      [ -e "$iface_path" ] || continue
      iface=${iface_path##*/}
      case "$iface" in ''|lo|dummy*|ifb*) continue ;; esac
      case "$iface" in
        wlan*|wifi*|swlan*|p2p*|ap*) [ "$block_wifi" = 1 ] || continue ;;
        rmnet*|v4-rmnet*|ccmni*|ccemni*|ccmn*|pdp*|wwan*) [ "$block_mobile" = 1 ] || continue ;;
        *) [ "$block_wifi" = 1 ] || [ "$block_mobile" = 1 ] || continue ;;
      esac
      "$bin" -t filter -A "$chain" -o "$iface" -m owner --uid-owner "$uid" -j REJECT >/dev/null 2>&1 || return 1
      rule_added=1
    done
    [ "$rule_added" = 0 ] || _FW_BLOCKED_COUNT=$((_FW_BLOCKED_COUNT + 1))
  done <<EOF
$uids
EOF
}
apply_rules() {
  master="$(read_master)"
  if [ "$master" != 1 ]; then clear_all; echo "firewall=0"; return 0; fi
  rows="$(list_rows | awk -F'|' '$3=="1" {print}')"
  if [ -z "$rows" ]; then clear_all; echo "firewall=0"; echo "no enabled app rules; per-app firewall is disabled"; return 0; fi
  ipt="$(command -v iptables 2>/dev/null || true)"
  ip6t="$(command -v ip6tables 2>/dev/null || true)"
  [ -n "$ipt" ] && [ -n "$ip6t" ] || { echo "IPv4/IPv6 iptables tools are both required; no firewall rules were changed" >&2; return 4; }
  now="$(date '+%H:%M' 2>/dev/null || true)"
  valid_time "$now" || { echo "device local clock is unavailable; last known-good firewall kept" >&2; return 5; }
  uid_snapshot="$(cmd package list packages -U 2>/dev/null)" || { echo "cannot read installed package UID snapshot; old firewall kept" >&2; return 5; }
  [ -n "$uid_snapshot" ] || { echo "installed package UID snapshot is empty; old firewall kept" >&2; return 5; }
  current="$(cat "$ACTIVE" 2>/dev/null || echo FXYUL_A)"
  case "$current" in FXYUL_A) next=FXYUL_B; old=FXYUL_A ;; FXYUL_B) next=FXYUL_A; old=FXYUL_B ;; *) clear_all; next=FXYUL_A; old=FXYUL_B ;; esac
  resolved=""
  while IFS='|' read -r pkg stored_uid state block_wifi block_mobile schedule start end; do
    [ "$state" = 1 ] || continue
    uid_rc=0
    uid="$(resolve_uid "$pkg" "$uid_snapshot")" || uid_rc=$?
    if [ "$uid_rc" -eq 2 ]; then echo "selected package is no longer installed; stale UID excluded: $pkg" >&2; continue
    elif [ "$uid_rc" -ne 0 ]; then echo "cannot resolve current UID for $pkg; old firewall kept" >&2; return 5; fi
    [ -n "$resolved" ] && resolved="$resolved
"
    resolved="${resolved}${pkg}|${uid}|${state}|${block_wifi}|${block_mobile}|${schedule}|${start}|${end}"
  done <<EOF
$rows
EOF
  if [ -z "$resolved" ]; then
    clear_all; echo "firewall=1"; echo "blocked_packages=0"
    echo "no selected package is currently installed; saved selections retained"
    return 0
  fi
  build_chain "$ipt" "$next" "$resolved" "$now" || { clear_chain "$ipt" "$next"; echo "IPv4 firewall chain build failed; old firewall kept" >&2; return 6; }
  blocked_count=$_FW_BLOCKED_COUNT
  build_chain "$ip6t" "$next" "$resolved" "$now" || { clear_chain "$ipt" "$next"; clear_chain "$ip6t" "$next"; echo "IPv6 firewall chain build failed; old firewall kept" >&2; return 7; }
  remove_hook "$ipt" "$old"; remove_hook "$ip6t" "$old"
  clear_chain "$ipt" "$old"; clear_chain "$ip6t" "$old"
  _FW_TEMP=$(mktemp "$ACTIVE.XXXXXX") || { echo "unable to create private firewall active marker" >&2; return 10; }
  printf '%s\n' "$next" > "$_FW_TEMP" || { rm -f "$_FW_TEMP"; _FW_TEMP=; echo "unable to write firewall active marker" >&2; return 10; }
  if [ ! -L "$ACTIVE" ] && chmod 600 "$_FW_TEMP" && mv -f "$_FW_TEMP" "$ACTIVE"; then _FW_TEMP=
  else rm -f "$_FW_TEMP"; _FW_TEMP=; echo "unable to install firewall active marker" >&2; return 10
  fi
  echo "firewall=1"; echo "blocked_packages=$blocked_count"; echo "evaluated_at=$now"
}
with_lock() {
  tries=0
  max_tries=20
  if [ "${1:-}" = "--event" ]; then
    max_tries=5
    shift
  fi
  while ! mkdir "$LOCK" 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -lt "$max_tries" ] || { echo "firewall update is busy" >&2; return 10; }
    sleep 1
  done
  cleanup_lock() {
    [ -z "$_FW_TEMP" ] || rm -f "$_FW_TEMP" 2>/dev/null || :
    [ -z "$_FW_BACKUP" ] || rm -f "$_FW_BACKUP" 2>/dev/null || :
    [ -z "$_FW_RESTORE" ] || rm -f "$_FW_RESTORE" 2>/dev/null || :
    rmdir "$LOCK" 2>/dev/null || :
  }
  trap cleanup_lock EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  "$@"
}
mutate_transaction() {
  op="$1"; shift
  _FW_BACKUP=$(mktemp "$CONF.yulong-rollback.XXXXXX") || return 1
  backup="$_FW_BACKUP"
  if ! cp -p "$CONF" "$backup" || ! chmod 600 "$backup"; then
    rm -f "$backup"; _FW_BACKUP=; return 1
  fi
  if ! "$op" "$@"; then
    rm -f "$backup"; _FW_BACKUP=; return 1
  fi
  if apply_rules; then
    rm -f "$backup"; _FW_BACKUP=; return 0
  fi
  _FW_RESTORE=$(mktemp "$CONF.restore.XXXXXX") || {
    rm -f "$backup"; _FW_BACKUP=; echo "unable to create private firewall restore temp" >&2; return 11;
  }
  if cp -p "$backup" "$_FW_RESTORE" && chmod 600 "$_FW_RESTORE" \
      && [ ! -L "$CONF" ] && mv -f "$_FW_RESTORE" "$CONF"; then
    _FW_RESTORE=
  else
    rm -f "$_FW_RESTORE" "$backup"; _FW_RESTORE=; _FW_BACKUP=
    echo "firewall config rollback failed" >&2
    return 11
  fi
  apply_rules >/dev/null 2>&1 || echo "previous config restored; firewall reconcile failed" >&2
  rm -f "$backup"
  _FW_BACKUP=
  return 1
}
WATCH_PIDFILE="$PG/yulong-app-firewall.pid"
WATCH_LOG="$PG/yulong-app-firewall.log"
SCRIPT_PATH="$MP/scripts/yulong-app-firewall.sh"
watch_is_ours() {
  _watch_pid=$1
  [ -r "/proc/$_watch_pid/cmdline" ] || return 1
  _watch_cmd=$(tr '\\000' ' ' < "/proc/$_watch_pid/cmdline" 2>/dev/null) || return 1
  case "$_watch_cmd" in *"$SCRIPT_PATH"*' watch-loop'*) return 0 ;; esac
  return 1
}
watch_loop() {
  _watch_sleep_pid=
  cleanup_watch_loop() { [ -z "$_watch_sleep_pid" ] || kill "$_watch_sleep_pid" 2>/dev/null || :; exit 0; }
  trap cleanup_watch_loop HUP INT TERM
  while :; do
    sleep 10 & _watch_sleep_pid=$!
    wait "$_watch_sleep_pid" || :; _watch_sleep_pid=
    [ ! -e "$MP/disable" ] && [ ! -e "$MP/remove" ] || exit 0
    [ "$(read_master)" = 1 ] || continue
    if list_rows | awk -F'|' '$3=="1" && $6=="1" {found=1; exit} END {exit !found}'; then
      sh "$SCRIPT_PATH" apply-event >> "$WATCH_LOG" 2>&1 || :
    fi
  done
}
start_watch() {
  [ ! -L "$WATCH_PIDFILE" ] || { echo "firewall watcher PID file is unsafe" >&2; return 1; }
  if [ -s "$WATCH_PIDFILE" ]; then
    old=$(cat "$WATCH_PIDFILE" 2>/dev/null || true)
    case "$old" in ''|*[!0-9]*) old= ;; esac
    if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
      watch_is_ours "$old" || { echo "firewall watcher PID belongs to another process" >&2; return 1; }
      echo "already-running pid=$old"; return 0
    fi
    rm -f "$WATCH_PIDFILE"
  fi
  if ! list_rows | awk -F'|' '$3=="1" && $6=="1" {found=1; exit} END {exit !found}'; then
    echo "no enabled scheduled rules"; return 0
  fi
  nohup sh "$SCRIPT_PATH" watch-loop </dev/null >> "$WATCH_LOG" 2>&1 &
  pid=$!
  tmp=$(mktemp "$WATCH_PIDFILE.XXXXXX") || { kill "$pid" 2>/dev/null || :; return 1; }
  printf '%s
' "$pid" > "$tmp"
  if [ ! -f "$tmp" ] || [ -L "$tmp" ] || ! chmod 600 "$tmp" || ! mv -f "$tmp" "$WATCH_PIDFILE"; then
    rm -f "$tmp"; kill "$pid" 2>/dev/null || :; return 1
  fi
  sleep 0.1
  if ! kill -0 "$pid" 2>/dev/null || ! watch_is_ours "$pid"; then
    rm -f "$WATCH_PIDFILE"; kill "$pid" 2>/dev/null || :; echo "watcher failed to start" >&2; return 1
  fi
  echo "started pid=$pid"
}
stop_watch() {
  [ ! -L "$WATCH_PIDFILE" ] || { echo "firewall watcher PID file is unsafe" >&2; return 1; }
  if [ -s "$WATCH_PIDFILE" ]; then
    pid=$(cat "$WATCH_PIDFILE" 2>/dev/null || true)
    case "$pid" in ''|*[!0-9]*) pid= ;; esac
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      watch_is_ours "$pid" || { echo "refusing to signal unrelated PID $pid" >&2; return 1; }
      kill -TERM "$pid" 2>/dev/null || :
      _stop_wait=0
      while [ "$_stop_wait" -lt 20 ] && kill -0 "$pid" 2>/dev/null; do sleep 0.1; _stop_wait=$((_stop_wait+1)); done
      if kill -0 "$pid" 2>/dev/null; then
        watch_is_ours "$pid" || { echo "watcher PID changed identity; refusing SIGKILL" >&2; return 1; }
        kill -KILL "$pid" 2>/dev/null || :
        _stop_wait=0
        while [ "$_stop_wait" -lt 20 ] && kill -0 "$pid" 2>/dev/null; do sleep 0.1; _stop_wait=$((_stop_wait+1)); done
      fi
      kill -0 "$pid" 2>/dev/null && { echo "could not confirm watcher stopped" >&2; return 1; }
    fi
  fi
  rm -f "$WATCH_PIDFILE"; echo "stopped"
}
cmd="${1:-list}"
case "$cmd" in
  list)
    echo "FXYULONGFW2"
    echo "master=$(read_master)"
    list_rows
    ;;
  master)
    [ "$#" -eq 2 ] && valid_state "$2" || { echo "usage: $0 master 0|1" >&2; exit 2; }
    with_lock mutate_transaction set_master_value "$2"
    ;;
  set)
    [ "$#" -eq 4 ] && valid_package "$2" && [ "$3" -gt 0 ] 2>/dev/null && valid_state "$4" \
      || { echo "usage: $0 set package uid 0|1" >&2; exit 2; }
    with_lock mutate_transaction set_item_value "$2" "$3" "$4"
    ;;
  rule)
    [ "$#" -eq 9 ] && valid_package "$2" && [ "$3" -gt 0 ] 2>/dev/null \
      && valid_state "$4" && valid_state "$5" && valid_state "$6" && valid_state "$7" \
      && valid_time "$8" && valid_time "$9" \
      || { echo "usage: $0 rule package uid enabled block_wifi block_mobile schedule_enabled HH:MM HH:MM" >&2; exit 2; }
    with_lock mutate_transaction set_rule_value "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
    ;;
  remove)
    [ "$#" -eq 2 ] && valid_package "$2" || { echo "usage: $0 remove package" >&2; exit 2; }
    with_lock mutate_transaction remove_item_value "$2"
    ;;
  apply) with_lock apply_rules ;;
  apply-event) with_lock --event apply_rules ;;
  start-watch) start_watch ;;
  watch-loop) watch_loop ;;
  stop-watch) stop_watch ;;
  uninstall) stop_watch || :; with_lock clear_all ;;
  *) echo "unknown command: $cmd" >&2; exit 2 ;;
esac
