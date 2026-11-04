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
install_hook() {
  bin="$1"; chain="$2"
  if "$bin" -t filter -C OUTPUT -j "$chain" >/dev/null 2>&1; then return 0; fi
  "$bin" -t filter -I OUTPUT 1 -j "$chain" >/dev/null 2>&1 || return 1
  "$bin" -t filter -C OUTPUT -j "$chain" >/dev/null 2>&1
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
    if [ "$block_wifi" = 1 ]; then
      for iface in wlan+ wifi+ swlan+ p2p+ ap+; do
        "$bin" -t filter -A "$chain" -o "$iface" -m owner --uid-owner "$uid" -j REJECT >/dev/null 2>&1 || return 1
      done
      rule_added=1
    fi
    if [ "$block_mobile" = 1 ]; then
      for iface in rmnet+ v4-rmnet+ ccmni+ ccemni+ ccmn+ pdp+ wwan+; do
        "$bin" -t filter -A "$chain" -o "$iface" -m owner --uid-owner "$uid" -j REJECT >/dev/null 2>&1 || return 1
      done
      rule_added=1
    fi
    # For Ethernet, VPN, USB and other transports the original manager uses
    # the "either Wi-Fi or mobile restriction" fallback.
    for iface in eth+ en+ usb+ rndis+ tun+ wg+ ppp+ tap+ ipsec+; do
      "$bin" -t filter -A "$chain" -o "$iface" -m owner --uid-owner "$uid" -j REJECT >/dev/null 2>&1 || return 1
    done
    # Unknown/vendor-specific interfaces are deliberately fail-open.
    # Their transport class cannot be inferred safely from an interface name:
    # treating every unknown interface as blocked makes a Wi-Fi-only policy
    # silently block vendor mobile-data interfaces (and vice versa). Known
    # transports are covered by the explicit wildcard groups above. Add a
    # vendor prefix only after its transport has been verified on target devices.
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
  build_chain "$ipt" "$next" "$resolved" "$now" || {
    clear_chain "$ipt" "$next"
    echo "IPv4 firewall chain build failed; old firewall kept" >&2
    return 6
  }
  blocked_count=$_FW_BLOCKED_COUNT
  build_chain "$ip6t" "$next" "$resolved" "$now" || {
    clear_chain "$ipt" "$next"; clear_chain "$ip6t" "$next"
    echo "IPv6 firewall chain build failed; old firewall kept" >&2
    return 7
  }

  # Stage the marker before changing OUTPUT. Keep the old chain attached until
  # both protocol families have accepted the new chain.
  _FW_TEMP=$(mktemp "$ACTIVE.XXXXXX") || {
    clear_chain "$ipt" "$next"; clear_chain "$ip6t" "$next"
    echo "unable to create private firewall active marker; old firewall kept" >&2
    return 10
  }
  if ! printf '%s\n' "$next" > "$_FW_TEMP" || ! chmod 600 "$_FW_TEMP"; then
    rm -f "$_FW_TEMP"; _FW_TEMP=
    clear_chain "$ipt" "$next"; clear_chain "$ip6t" "$next"
    echo "unable to prepare firewall active marker; old firewall kept" >&2
    return 10
  fi

  if ! install_hook "$ipt" "$next"; then
    rm -f "$_FW_TEMP"; _FW_TEMP=
    clear_chain "$ipt" "$next"; clear_chain "$ip6t" "$next"
    echo "IPv4 OUTPUT activation failed; old firewall kept" >&2
    return 8
  fi
  if ! install_hook "$ip6t" "$next"; then
    rm -f "$_FW_TEMP"; _FW_TEMP=
    clear_chain "$ipt" "$next"; clear_chain "$ip6t" "$next"
    echo "IPv6 OUTPUT activation failed; IPv4 activation rolled back; old firewall kept" >&2
    return 9
  fi

  if [ ! -L "$ACTIVE" ] && mv -f "$_FW_TEMP" "$ACTIVE"; then
    _FW_TEMP=
  else
    rm -f "$_FW_TEMP"; _FW_TEMP=
    clear_chain "$ipt" "$next"; clear_chain "$ip6t" "$next"
    echo "unable to install firewall active marker; new OUTPUT hooks rolled back" >&2
    return 10
  fi

  remove_hook "$ipt" "$old"; remove_hook "$ip6t" "$old"
  clear_chain "$ipt" "$old"; clear_chain "$ip6t" "$old"
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
WATCH_LOCK="$PG/yulong-app-firewall-watch.lock"
WATCH_LOCK_OWNED=0
WATCH_LOCK_START=
SCRIPT_PATH="$MP/scripts/yulong-app-firewall.sh"
WATCH_INTERVAL=${WATCH_INTERVAL:-10}
case "$WATCH_INTERVAL" in ''|*[!0-9]*) WATCH_INTERVAL=10 ;; esac
[ "$WATCH_INTERVAL" -gt 0 ] || WATCH_INTERVAL=10
WATCH_LOCK_MAX_TRIES=${WATCH_LOCK_MAX_TRIES:-100}
case "$WATCH_LOCK_MAX_TRIES" in ''|*[!0-9]*) WATCH_LOCK_MAX_TRIES=100 ;; esac
[ "$WATCH_LOCK_MAX_TRIES" -gt 0 ] || WATCH_LOCK_MAX_TRIES=100
[ "$WATCH_LOCK_MAX_TRIES" -le 100 ] || WATCH_LOCK_MAX_TRIES=100
interface_snapshot() {
  [ -d "$NET_CLASS" ] || return 1
  for iface_path in "$NET_CLASS"/*; do
    [ -e "$iface_path" ] || continue
    iface=${iface_path##*/}
    case "$iface" in ''|lo|dummy*|ifb*) continue ;; esac
    printf '%s\n' "$iface"
  done | sort
}
has_enabled_rules() {
  list_rows | awk -F'|' '$3=="1" {found=1; exit} END {exit !found}'
}
has_scheduled_rules() {
  list_rows | awk -F'|' '$3=="1" && $6=="1" {found=1; exit} END {exit !found}'
}
watch_is_ours() {
  _watch_pid=$1
  watch_lock_pid_live "$_watch_pid" || return 1
  [ -r "/proc/$_watch_pid/cmdline" ] || return 1
  _watch_arg1=$(tr '\000' '\n' < "/proc/$_watch_pid/cmdline" 2>/dev/null | sed -n '2p') || return 1
  _watch_arg2=$(tr '\000' '\n' < "/proc/$_watch_pid/cmdline" 2>/dev/null | sed -n '3p') || return 1
  [ "$_watch_arg1" = "$SCRIPT_PATH" ] && [ "$_watch_arg2" = "watch-loop" ]
}
watch_loop() {
  _watch_sleep_pid=
  _watch_pid_tmp=
  cleanup_watch_loop() {
    [ -z "$_watch_sleep_pid" ] || kill "$_watch_sleep_pid" 2>/dev/null || :
    [ -z "$_watch_pid_tmp" ] || rm -f "$_watch_pid_tmp" 2>/dev/null || :
    if [ -f "$WATCH_PIDFILE" ] && [ ! -L "$WATCH_PIDFILE" ] \
        && [ "$(cat "$WATCH_PIDFILE" 2>/dev/null || true)" = "$$" ]; then
      rm -f "$WATCH_PIDFILE"
    fi
  }
  trap cleanup_watch_loop EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  # The watcher itself, not the spawning parent, publishes its PID after
  # entering this command. The parent holds the lifecycle lock until this
  # readiness marker is visible and the process identity is confirmed.
  [ ! -L "$WATCH_PIDFILE" ] && [ ! -e "$WATCH_PIDFILE" ] || exit 1
  _watch_pid_tmp=$(mktemp "$WATCH_PIDFILE.XXXXXX") || exit 1
  [ -f "$_watch_pid_tmp" ] && [ ! -L "$_watch_pid_tmp" ] || exit 1
  printf '%s\n' "$$" > "$_watch_pid_tmp"
  chmod 600 "$_watch_pid_tmp"
  mv -f "$_watch_pid_tmp" "$WATCH_PIDFILE"
  _watch_pid_tmp=
  last_interfaces=$(interface_snapshot 2>/dev/null || printf '__unavailable__')
  last_minute=$(date '+%H:%M' 2>/dev/null || true)
  while :; do
    sleep "$WATCH_INTERVAL" & _watch_sleep_pid=$!
    wait "$_watch_sleep_pid" || :; _watch_sleep_pid=
    [ ! -e "$MP/disable" ] && [ ! -e "$MP/remove" ] || exit 0
    [ "$(read_master)" = 1 ] || exit 0
    has_enabled_rules || exit 0
    current_interfaces=$(interface_snapshot 2>/dev/null || printf '__unavailable__')
    current_minute=$(date '+%H:%M' 2>/dev/null || true)
    reapply=0
    [ "$current_interfaces" = "$last_interfaces" ] || reapply=1
    if has_scheduled_rules && [ "$current_minute" != "$last_minute" ]; then reapply=1; fi
    if [ "$reapply" = 1 ]; then
      if sh "$SCRIPT_PATH" apply-event >> "$WATCH_LOG" 2>&1; then
        last_interfaces=$current_interfaces
        last_minute=$current_minute
      fi
    fi
  done
}
find_live_watchers() {
  _watch_found=
  for _watch_proc in /proc/[0-9]*; do
    [ -r "$_watch_proc/cmdline" ] || continue
    _watch_candidate=$(basename "$_watch_proc")
    case "$_watch_candidate" in ''|*[!0-9]*) continue ;; esac
    watch_is_ours "$_watch_candidate" || continue
    if [ -n "$_watch_found" ]; then
      _watch_found="$_watch_found $_watch_candidate"
    else
      _watch_found=$_watch_candidate
    fi
  done
  printf '%s\n' "$_watch_found"
}
publish_watch_pid() {
  _publish_pid=$1
  [ ! -L "$WATCH_PIDFILE" ] || return 1
  _publish_tmp=$(mktemp "$WATCH_PIDFILE.XXXXXX") || return 1
  if ! printf '%s\n' "$_publish_pid" > "$_publish_tmp" || ! chmod 600 "$_publish_tmp"; then
    rm -f "$_publish_tmp"
    return 1
  fi
  if ! mv -f "$_publish_tmp" "$WATCH_PIDFILE"; then
    rm -f "$_publish_tmp"
    return 1
  fi
}
start_watch_locked() {
  [ "$(read_master)" = 1 ] && has_enabled_rules || {
    echo "no enabled per-app firewall rules; watcher not started"
    return 0
  }
  [ ! -L "$WATCH_PIDFILE" ] || { echo "firewall watcher PID file is unsafe" >&2; return 1; }
  if [ -s "$WATCH_PIDFILE" ]; then
    old=$(cat "$WATCH_PIDFILE" 2>/dev/null || true)
    case "$old" in ''|*[!0-9]*) old= ;; esac
    if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
      watch_is_ours "$old" || { echo "firewall watcher PID belongs to another process" >&2; return 1; }
      echo "already-running pid=$old"
      return 0
    fi
    rm -f "$WATCH_PIDFILE"
  elif [ -e "$WATCH_PIDFILE" ]; then
    rm -f "$WATCH_PIDFILE"
  fi
  # Recover the exact watcher process if its marker was lost or removed during
  # an interrupted prior startup. A second start must not launch a duplicate.
  _watch_existing=$(find_live_watchers)
  if [ -n "$_watch_existing" ]; then
    _watch_primary=$(printf '%s\n' "$_watch_existing" | awk '{print $1}')
    case "$_watch_primary" in ''|*[!0-9]*) _watch_primary= ;; esac
    if [ -n "$_watch_primary" ] && kill -0 "$_watch_primary" 2>/dev/null \
        && watch_is_ours "$_watch_primary"; then
      for _watch_extra in $(printf '%s\n' "$_watch_existing" | awk '{for (i=2;i<=NF;i++) print $i}'); do
        if kill -0 "$_watch_extra" 2>/dev/null && watch_is_ours "$_watch_extra"; then
          kill -TERM "$_watch_extra" 2>/dev/null || :
        fi
      done
      publish_watch_pid "$_watch_primary" || {
        echo "unable to restore live watcher PID marker" >&2
        return 1
      }
      echo "already-running pid=$_watch_primary (recovered live process marker)"
      return 0
    fi
  fi
  nohup sh "$SCRIPT_PATH" watch-loop </dev/null >> "$WATCH_LOG" 2>&1 &
  pid=$!
  _watch_start_wait=0
  _watch_child_pid=
  while [ "$_watch_start_wait" -lt 50 ]; do
    if [ -s "$WATCH_PIDFILE" ] && [ ! -L "$WATCH_PIDFILE" ]; then
      _watch_child_pid=$(cat "$WATCH_PIDFILE" 2>/dev/null || true)
      case "$_watch_child_pid" in ''|*[!0-9]*) _watch_child_pid= ;; esac
      if [ -n "$_watch_child_pid" ] && kill -0 "$_watch_child_pid" 2>/dev/null \
          && watch_is_ours "$_watch_child_pid"; then
        echo "started pid=$_watch_child_pid"
        return 0
      fi
    fi
    # Some nohup implementations preserve their PID through exec; others
    # launch the command as a child. The watcher-owned PID marker is canonical.
    sleep 0.1
    _watch_start_wait=$((_watch_start_wait + 1))
  done
  if [ -s "$WATCH_PIDFILE" ] && [ ! -L "$WATCH_PIDFILE" ]; then
    _watch_child_pid=$(cat "$WATCH_PIDFILE" 2>/dev/null || true)
    case "$_watch_child_pid" in ''|*[!0-9]*) _watch_child_pid= ;; esac
    if [ -n "$_watch_child_pid" ] && kill -0 "$_watch_child_pid" 2>/dev/null \
        && watch_is_ours "$_watch_child_pid"; then
      kill -TERM "$_watch_child_pid" 2>/dev/null || :
    fi
    rm -f "$WATCH_PIDFILE"
  fi
  if kill -0 "$pid" 2>/dev/null && watch_is_ours "$pid"; then
    kill -TERM "$pid" 2>/dev/null || :
  fi
  echo "watcher failed to publish its live PID; lifecycle lock remains held until cleanup" >&2
  return 1
}
stop_watch_locked() {
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
  rm -f "$WATCH_PIDFILE"
  echo "stopped"
}
watch_lock_pid_live() {
  _watch_lock_pid=$1
  case "$_watch_lock_pid" in ''|*[!0-9]*) return 1 ;; esac
  [ -r "/proc/$_watch_lock_pid/stat" ] || return 1
  _watch_lock_state=$(sed 's/^.*) //' "/proc/$_watch_lock_pid/stat" 2>/dev/null | cut -d ' ' -f1 || :)
  case "$_watch_lock_state" in Z|X|x) return 1 ;; esac
  kill -0 "$_watch_lock_pid" 2>/dev/null
}
watch_lock_process_is_ours() {
  _lock_pid=$1
  watch_lock_pid_live "$_lock_pid" || return 1
  [ -r "/proc/$_lock_pid/cmdline" ] || return 1
  # Match the exact script argument anywhere in argv. Some Android shell
  # launchers add a wrapper argument before the script path, so argv[2] is
  # not a stable identity contract.
  _lock_cmdline=$(tr '\000' ' ' < "/proc/$_lock_pid/cmdline" 2>/dev/null) || return 1
  # Some su/shell launchers preserve the script path inside a command argument
  # rather than exposing it as a standalone argv element.
  case "$_lock_cmdline" in *"$SCRIPT_PATH"*) return 0 ;; esac
  # Emit the live owner's identity at the point of rejection. The caller may
  # observe an already-cleaned lock by the time a background race fails.
  echo "watcher lock owner identity mismatch: pid=$_lock_pid expected_script=$SCRIPT_PATH cmdline=$_lock_cmdline" >&2
  if [ -r "/proc/$_lock_pid/stat" ]; then
    ps -o pid=,ppid=,args= -p "$_lock_pid" >&2 || :
  fi
  return 1
}
watch_lock_pid_start_time() {
  _watch_start_pid=$1
  case "$_watch_start_pid" in ''|*[!0-9]*) return 1 ;; esac
  [ -r "/proc/$_watch_start_pid/stat" ] || return 1
  _watch_stat_tail=$(sed 's/^.*) //' "/proc/$_watch_start_pid/stat" 2>/dev/null) || return 1
  _watch_start_time=$(printf '%s\n' "$_watch_stat_tail" | awk '{print $20}')
  case "$_watch_start_time" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$_watch_start_time"
}
watch_lock_owner_is_ours() {
  _watch_owner_pid=$1
  # Return 0 for a live owner, 1 for a stale/reused PID (safe to reclaim if
  # the lock record has not changed), and 2 for an actual foreign/malformed
  # owner. Keep this as a single liveness/identity decision: checking kill -0
  # once in the caller and again here races with a starter exiting normally.
  watch_lock_pid_live "$_watch_owner_pid" || return 1
  _watch_owner_marker=$(sed -n '2p' "$WATCH_LOCK" 2>/dev/null || true)
  case "$_watch_owner_marker" in
    FXYWLOCK2)
      _watch_owner_script=$(sed -n '3p' "$WATCH_LOCK" 2>/dev/null || true)
      _watch_owner_start=$(sed -n '4p' "$WATCH_LOCK" 2>/dev/null || true)
      [ "$_watch_owner_script" = "$SCRIPT_PATH" ] || return 2
      case "$_watch_owner_start" in ''|*[!0-9]*) return 2 ;; esac
      _watch_live_start=$(watch_lock_pid_start_time "$_watch_owner_pid") || return 1
      [ "$_watch_live_start" = "$_watch_owner_start" ] || return 1
      return 0
      ;;
    '')
      # Backward compatibility for old PID-only locks. A live foreign process
      # is a hard conflict; an exited owner is an ordinary stale lock.
      if watch_lock_process_is_ours "$_watch_owner_pid"; then return 0; fi
      watch_lock_pid_live "$_watch_owner_pid" && return 2
      return 1
      ;;
    *)
      return 2
      ;;
  esac
}
watch_lock_acquire() {
  [ ! -L "$WATCH_LOCK" ] || {
    echo "firewall watcher lock path is unsafe" >&2
    return 1
  }
  _watch_lock_tries=0
  while :; do
    if [ -d "$WATCH_LOCK" ]; then
      # Upgrade path: an older FX version used a lock directory with owner.pid.
      [ ! -L "$WATCH_LOCK" ] || {
        echo "legacy firewall watcher lock path is unsafe" >&2
        return 1
      }
      _legacy_owner_file="$WATCH_LOCK/owner.pid"
      if [ -f "$_legacy_owner_file" ] && [ ! -L "$_legacy_owner_file" ]; then
        _legacy_owner=$(cat "$_legacy_owner_file" 2>/dev/null || true)
        case "$_legacy_owner" in
          '') : ;;
          *[!0-9]*)
            echo "legacy firewall watcher lock owner PID is malformed" >&2
            return 1
            ;;
          *)
            if watch_lock_pid_live "$_legacy_owner"; then
              watch_lock_process_is_ours "$_legacy_owner" || {
                echo "legacy firewall watcher lock belongs to an unrelated process" >&2
                return 1
              }
            elif [ "$(cat "$_legacy_owner_file" 2>/dev/null || true)" = "$_legacy_owner" ]; then
              rm -f "$_legacy_owner_file"
              rmdir "$WATCH_LOCK" 2>/dev/null || :
            fi
            ;;
        esac
      else
        # An ownerless legacy directory may be a live starter between mkdir
        # and owner publication. Never reclaim it solely because it is empty.
        :
      fi
    elif [ -e "$WATCH_LOCK" ]; then
      [ ! -L "$WATCH_LOCK" ] || {
        echo "firewall watcher lock path became unsafe" >&2
        return 1
      }
      [ -f "$WATCH_LOCK" ] || {
        echo "firewall watcher lock is not a regular file" >&2
        return 1
      }
      _watch_lock_record=$(cat "$WATCH_LOCK" 2>/dev/null || true)
      _watch_lock_owner=$(sed -n '1p' "$WATCH_LOCK" 2>/dev/null || true)
      case "$_watch_lock_owner" in
        '') : ;;
        *[!0-9]*)
          echo "firewall watcher lock owner PID is malformed" >&2
          return 1
          ;;
        *)
          _watch_owner_state=0
          watch_lock_owner_is_ours "$_watch_lock_owner" || _watch_owner_state=$?
          case "$_watch_owner_state" in
            0)
              # A live owner of this script holds the lifecycle lock.
              ;;
            1)
              # The PID exited or was reused between lock creation and this
              # check. Reclaim only the exact unchanged record we inspected.
              if [ "$(cat "$WATCH_LOCK" 2>/dev/null || true)" = "$_watch_lock_record" ]; then
                rm -f "$WATCH_LOCK"
              fi
              ;;
            *)
              # The exclusive lock path is visible before its four-line
              # ownership record is fully written. Settle an initially invalid
              # snapshot before classifying a live owner as foreign.
              sleep 0.02
              _watch_lock_settled=$(cat "$WATCH_LOCK" 2>/dev/null || true)
              if [ "$_watch_lock_settled" != "$_watch_lock_record" ]; then
                :
              else
                _watch_owner_state=0
                watch_lock_owner_is_ours "$_watch_lock_owner" || _watch_owner_state=$?
                case "$_watch_owner_state" in
                  0) : ;;
                  1)
                    if [ "$(cat "$WATCH_LOCK" 2>/dev/null || true)" = "$_watch_lock_settled" ]; then
                      rm -f "$WATCH_LOCK"
                    fi
                    ;;
                  *)
                    echo "firewall watcher lock belongs to an unrelated process (pid=$_watch_lock_owner)" >&2
                    return 1
                    ;;
                esac
              fi
              ;;
          esac
          ;;
      esac
    else
      # Prepare the complete ownership record under a unique private name,
      # then publish it with one same-directory hard link. A contender can
      # never observe a truncated/partially-written lock record.
      _watch_lock_start=$(watch_lock_pid_start_time "$") || {
        echo "unable to read current watcher lock owner start time" >&2
        return 1
      }
      _watch_lock_expected=$(printf '%s\n%s\n%s\n%s\n' "$$" FXYWLOCK2 "$SCRIPT_PATH" "$_watch_lock_start")
      _watch_lock_tmp=$(mktemp "$WATCH_LOCK.tmp.XXXXXX") || return 1
      if ! {
        printf '%s\n%s\n%s\n%s\n' "$$" FXYWLOCK2 "$SCRIPT_PATH" "$_watch_lock_start" > "$_watch_lock_tmp" &&
        chmod 600 "$_watch_lock_tmp"
      }; then
        rm -f "$_watch_lock_tmp"
        return 1
      fi
      if ln "$_watch_lock_tmp" "$WATCH_LOCK" 2>/dev/null; then
        rm -f "$_watch_lock_tmp"
        WATCH_LOCK_OWNED=1
        WATCH_LOCK_START=$_watch_lock_start
        if [ -f "$WATCH_LOCK" ] && [ ! -L "$WATCH_LOCK" ] \
            && [ "$(cat "$WATCH_LOCK" 2>/dev/null || true)" = "$_watch_lock_expected" ]; then
          trap 'watch_lock_signal_exit 129' HUP
          trap 'watch_lock_signal_exit 130' INT
          trap 'watch_lock_signal_exit 143' TERM
          return 0
        fi
        if [ -f "$WATCH_LOCK" ] && [ ! -L "$WATCH_LOCK" ] \
            && [ "$(cat "$WATCH_LOCK" 2>/dev/null || true)" = "$_watch_lock_expected" ]; then
          rm -f "$WATCH_LOCK"
        fi
        WATCH_LOCK_OWNED=0
        WATCH_LOCK_START=
        echo "unable to verify firewall watcher lock ownership" >&2
        return 1
      fi
      rm -f "$_watch_lock_tmp"
    fi
    _watch_lock_tries=$((_watch_lock_tries + 1))
    [ "$_watch_lock_tries" -lt "$WATCH_LOCK_MAX_TRIES" ] || {
      echo "firewall watcher lifecycle is busy; no change was made" >&2
      return 10
    }
    sleep 0.1
  done
}
watch_lock_release() {
  [ "$WATCH_LOCK_OWNED" = 1 ] || return 0
  _watch_lock_expected=$(printf '%s\n%s\n%s\n%s\n' "$$" FXYWLOCK2 "$SCRIPT_PATH" "$WATCH_LOCK_START")
  if [ -f "$WATCH_LOCK" ] && [ ! -L "$WATCH_LOCK" ] \
      && [ "$(cat "$WATCH_LOCK" 2>/dev/null || true)" = "$_watch_lock_expected" ]; then
    rm -f "$WATCH_LOCK"
  fi
  WATCH_LOCK_OWNED=0
  WATCH_LOCK_START=
}
watch_lock_signal_exit() {
  _watch_signal_status=$1
  watch_lock_release
  exit "$_watch_signal_status"
}
watch_lock_run() {
  watch_lock_acquire || return $?
  if "$@"; then
    _watch_lock_result=0
  else
    _watch_lock_result=$?
  fi
  watch_lock_release
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  return "$_watch_lock_result"
}
start_watch() { watch_lock_run start_watch_locked; }
stop_watch() { watch_lock_run stop_watch_locked; }

reconcile_watch_lifecycle() {
  if [ "$(read_master)" = 1 ] && has_enabled_rules; then
    start_watch || echo "firewall watcher did not start; re-evaluation is pending" >&2
  else
    stop_watch || echo "firewall watcher stop is pending" >&2
  fi
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
    reconcile_watch_lifecycle
    ;;
  set)
    [ "$#" -eq 4 ] && valid_package "$2" && [ "$3" -gt 0 ] 2>/dev/null && valid_state "$4" \
      || { echo "usage: $0 set package uid 0|1" >&2; exit 2; }
    with_lock mutate_transaction set_item_value "$2" "$3" "$4"
    reconcile_watch_lifecycle
    ;;
  rule)
    [ "$#" -eq 9 ] && valid_package "$2" && [ "$3" -gt 0 ] 2>/dev/null \
      && valid_state "$4" && valid_state "$5" && valid_state "$6" && valid_state "$7" \
      && valid_time "$8" && valid_time "$9" \
      || { echo "usage: $0 rule package uid enabled block_wifi block_mobile schedule_enabled HH:MM HH:MM" >&2; exit 2; }
    with_lock mutate_transaction set_rule_value "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
    reconcile_watch_lifecycle
    ;;
  remove)
    [ "$#" -eq 2 ] && valid_package "$2" || { echo "usage: $0 remove package" >&2; exit 2; }
    with_lock mutate_transaction remove_item_value "$2"
    reconcile_watch_lifecycle
    ;;
  apply) with_lock apply_rules ;;
  apply-event) with_lock --event apply_rules ;;
  start-watch) start_watch ;;
  watch-loop) watch_loop ;;
  stop-watch) stop_watch ;;
  uninstall) stop_watch || :; with_lock clear_all ;;
  *) echo "unknown command: $cmd" >&2; exit 2 ;;
esac
