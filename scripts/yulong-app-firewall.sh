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
    $0=="[list:yulong_app_firewall]" {inlist=1; next}
    /^\[/ {inlist=0}
    inlist && NF>=3 &&
      $1 ~ /^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$/ &&
      $2 ~ /^[0-9]+$/ && ($3=="0" || $3=="1") {
        print $1 "|" $2 "|" $3
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
set_item_value() {
  pkg="$1"; uid="$2"; state="$3"
  tmp=$(mktemp "$CONF.yulong-list.XXXXXX") || return 1
  _FW_TEMP=$tmp
  awk -F'|' -v OFS='|' -v pkg="$pkg" -v uid="$uid" -v state="$state" '
    BEGIN {inlist=0; seen=0; inserted=0}
    $0=="[list:yulong_app_firewall]" {
      if(inlist && !inserted && state=="1"){print pkg,uid,state; inserted=1}
      inlist=1; seen=1; print; next
    }
    /^\[/ {
      if(inlist && !inserted && state=="1"){print pkg,uid,state; inserted=1}
      inlist=0; print; next
    }
    inlist && $1==pkg {if(state=="1" && !inserted){print pkg,uid,state; inserted=1} next}
    {print}
    END {
      if(inlist && !inserted && state=="1"){print pkg,uid,state; inserted=1}
      if(!seen && state=="1"){print ""; print "[list:yulong_app_firewall]"; print pkg,uid,state}
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
resolve_uid() {
  pkg="$1"
  found="$(cmd package list packages -U 2>/dev/null | awk -v wanted="package:$pkg" '
    $1==wanted {
      for(i=2;i<=NF;i++) if($i ~ /^uid:[0-9]+$/) {
        sub(/^uid:/,"",$i); print $i; exit
      }
    }')"
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
  bin="$1"; chain="$2"; uids="$3"
  "$bin" -t filter -N "$chain" >/dev/null 2>&1 || "$bin" -t filter -F "$chain"
  while IFS='|' read -r pkg uid state; do
    [ "$state" = 1 ] || continue
    "$bin" -t filter -A "$chain" -m owner --uid-owner "$uid" -j REJECT >/dev/null 2>&1 || return 1
  done <<EOF
$uids
EOF
}
apply_rules() {
  master="$(read_master)"
  if [ "$master" != 1 ]; then clear_all; echo "firewall=0"; return 0; fi
  rows="$(list_rows | awk -F'|' '$3=="1" {print}')"
  [ -n "$rows" ] || { echo "no selected apps; firewall remains disabled" >&2; return 3; }

  ipt="$(command -v iptables 2>/dev/null || true)"
  ip6t="$(command -v ip6tables 2>/dev/null || true)"
  [ -n "$ipt" ] && [ -n "$ip6t" ] || {
    echo "IPv4/IPv6 iptables tools are both required; no firewall rules were changed" >&2; return 4;
  }

  current="$(cat "$ACTIVE" 2>/dev/null || echo FXYUL_A)"
  case "$current" in FXYUL_A) next=FXYUL_B; old=FXYUL_A ;; FXYUL_B) next=FXYUL_A; old=FXYUL_B ;; *) clear_all; next=FXYUL_A; old=FXYUL_B ;; esac
  resolved=""
  while IFS='|' read -r pkg stored_uid state; do
    [ "$state" = 1 ] || continue
    uid="$(resolve_uid "$pkg")" || { echo "cannot resolve current UID for $pkg; old firewall kept" >&2; return 5; }
    [ -n "$resolved" ] && resolved="$resolved
"
    resolved="${resolved}${pkg}|${uid}|1"
  done <<EOF
$rows
EOF
  [ -n "$resolved" ] || { echo "no installed selected apps; old firewall kept" >&2; return 5; }

  build_chain "$ipt" "$next" "$resolved" || {
    clear_chain "$ipt" "$next"; echo "IPv4 firewall chain build failed; old firewall kept" >&2; return 6;
  }
  build_chain "$ip6t" "$next" "$resolved" || {
    clear_chain "$ipt" "$next"; clear_chain "$ip6t" "$next"
    echo "IPv6 firewall chain build failed; old firewall kept" >&2; return 7;
  }
  "$ipt" -t filter -I OUTPUT 1 -j "$next" >/dev/null 2>&1 || {
    clear_chain "$ipt" "$next"; clear_chain "$ip6t" "$next"
    echo "IPv4 firewall activation failed; old firewall kept" >&2; return 8;
  }
  "$ip6t" -t filter -I OUTPUT 1 -j "$next" >/dev/null 2>&1 || {
    remove_hook "$ipt" "$next"; clear_chain "$ipt" "$next"; clear_chain "$ip6t" "$next"
    echo "IPv6 firewall activation failed; old firewall kept" >&2; return 9;
  }
  remove_hook "$ipt" "$old"; remove_hook "$ip6t" "$old"
  clear_chain "$ipt" "$old"; clear_chain "$ip6t" "$old"
  _FW_TEMP=$(mktemp "$ACTIVE.XXXXXX") || {
    echo "unable to create private firewall active marker" >&2; return 10;
  }
  printf '%s\n' "$next" > "$_FW_TEMP" || {
    rm -f "$_FW_TEMP"; _FW_TEMP=; echo "unable to write firewall active marker" >&2; return 10;
  }
  if [ ! -L "$ACTIVE" ] && chmod 600 "$_FW_TEMP" && mv -f "$_FW_TEMP" "$ACTIVE"; then
    _FW_TEMP=
  else
    rm -f "$_FW_TEMP"; _FW_TEMP=; echo "unable to install firewall active marker" >&2; return 10
  fi
  echo "firewall=1"
  echo "blocked_packages=$(printf '%s\n' "$resolved" | wc -l | tr -d ' ')"
}
with_lock() {
  tries=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -lt 20 ] || { echo "firewall update is busy" >&2; return 10; }
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
cmd="${1:-list}"
case "$cmd" in
  list)
    echo "FXYULONGFW1"
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
  remove)
    [ "$#" -eq 2 ] && valid_package "$2" || { echo "usage: $0 remove package" >&2; exit 2; }
    with_lock mutate_transaction set_item_value "$2" 0 0
    ;;
  apply) with_lock apply_rules ;;
  uninstall) clear_all ;;
  *) echo "unknown command: $cmd" >&2; exit 2 ;;
esac
