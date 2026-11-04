#!/system/bin/sh
# FX per-app VPN route manager. This controls the existing FX tunnel only.
set -eu

MP=${MP:-}
if [ -z "$MP" ]; then
  for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do
    if [ -f "$d/module.prop" ]; then MP="$d"; break; fi
  done
fi
[ -n "$MP" ] && [ -f "$MP/scripts/util.sh" ] || {
  echo "FX module is not installed" >&2
  exit 20
}
. "$MP/scripts/util.sh"

LOCK="$CONF.vpn-apps.lock"
_VPN_TEMP=
_VPN_BACKUP=
_VPN_RESTORE=

require_safe_config() {
  [ -n "$CONF" ] && [ -f "$CONF" ] && [ ! -L "$CONF" ] || {
    echo "VPN app settings.conf is missing or unsafe" >&2
    return 1
  }
  [ ! -L "$LOCK" ] || {
    echo "VPN app settings lock path is unsafe" >&2
    return 1
  }
}

cleanup_vpn_apps_lock() {
  [ -z "$_VPN_TEMP" ] || rm -f "$_VPN_TEMP" 2>/dev/null || :
  [ -z "$_VPN_BACKUP" ] || rm -f "$_VPN_BACKUP" 2>/dev/null || :
  [ -z "$_VPN_RESTORE" ] || rm -f "$_VPN_RESTORE" 2>/dev/null || :
  rmdir "$LOCK" 2>/dev/null || :
}

with_lock() {
  require_safe_config || return 1
  _tries=0
  _max_tries=50
  while ! mkdir "$LOCK" 2>/dev/null; do
    [ ! -L "$LOCK" ] || {
      echo "VPN app settings lock path is unsafe" >&2
      return 1
    }
    _tries=$((_tries + 1))
    [ "$_tries" -lt "$_max_tries" ] || {
      echo "VPN app settings are busy; no changes were made" >&2
      return 10
    }
    sleep 0.1
  done
  trap cleanup_vpn_apps_lock EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  "$@"
}


valid_package() {
  case "$1" in
    ''|*[!A-Za-z0-9_.-]*) return 1 ;;
  esac
  printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$'
}

valid_enabled() {
  [ "$1" = "0" ] || [ "$1" = "1" ]
}

read_mode() {
  _mode=$(pg_conf vpn | awk -F= '$1=="app_mode" {value=$2} END {print value}')
  case "$_mode" in only|proxy) echo only ;; bypass) echo bypass ;; *) echo bypass ;; esac
}

atomic_list_update() {
  _op="$1" _pkg="$2" _enabled="${3:-}"
  valid_package "$_pkg" || { echo "invalid package name" >&2; return 2; }
  if [ "$_op" = "set" ]; then
    valid_enabled "$_enabled" || { echo "invalid enabled state" >&2; return 2; }
  fi
  require_safe_config || return 1
  _tmp=$(mktemp "$CONF.vpn-apps.XXXXXX") || {
    echo "unable to create private VPN app-list candidate" >&2
    return 1
  }
  _VPN_TEMP=$_tmp
  if ! awk -F'|' -v OFS='|' -v op="$_op" -v pkg="$_pkg" -v enabled="$_enabled" '
    BEGIN { inlist=0; seen=0; inserted=0 }
    $0=="[list:vpn_app]" { seen=1; inlist=1; print; next }
    /^\[/ {
      if (inlist && op=="set" && !inserted) {
        print pkg, pkg, enabled
        inserted=1
      }
      inlist=0
      print
      next
    }
    inlist && $1==pkg {
      if (op=="set" && !inserted) {
        print pkg, pkg, enabled
        inserted=1
      }
      next
    }
    { print }
    END {
      if (inlist && op=="set" && !inserted) {
        print pkg, pkg, enabled
        inserted=1
      }
      if (!seen && op=="set") {
        print ""
        print "[list:vpn_app]"
        print pkg, pkg, enabled
      }
    }
  ' "$CONF" > "$_tmp" 2>/dev/null; then
    rm -f "$_tmp" 2>/dev/null || :
    _VPN_TEMP=
    echo "unable to build VPN app list candidate" >&2
    return 1
  fi
  [ -s "$_tmp" ] && [ ! -L "$CONF" ] || {
    rm -f "$_tmp"; _VPN_TEMP=; return 1;
  }
  chmod 600 "$_tmp" || { rm -f "$_tmp"; _VPN_TEMP=; return 1; }
  [ ! -L "$CONF" ] && mv -f "$_tmp" "$CONF" || {
    rm -f "$_tmp"; _VPN_TEMP=; return 1;
  }
  _VPN_TEMP=
}

set_mode() {
  _want="$1"
  case "$_want" in only|proxy) _want=only ;; bypass) : ;; *) echo "mode must be only or bypass" >&2; return 2 ;; esac
  require_safe_config || return 1
  _tmp=$(mktemp "$CONF.vpn-mode.XXXXXX") || {
    echo "unable to create private VPN mode candidate" >&2
    return 1
  }
  _VPN_TEMP=$_tmp
  if ! awk -v mode="$_want" '
    BEGIN { in_vpn=0; seen=0; updated=0 }
    $0=="[conf:vpn]" {
      if (in_vpn && !updated) { print "app_mode=" mode; updated=1 }
      in_vpn=1; seen=1; print; next
    }
    /^\[/ {
      if (in_vpn && !updated) { print "app_mode=" mode; updated=1 }
      in_vpn=0; print; next
    }
    in_vpn && /^app_mode=/ {
      if (!updated) print "app_mode=" mode
      updated=1; next
    }
    { print }
    END {
      if (in_vpn && !updated) print "app_mode=" mode
      if (!seen) { print ""; print "[conf:vpn]"; print "app_mode=" mode }
    }
  ' "$CONF" > "$_tmp" 2>/dev/null; then
    rm -f "$_tmp" 2>/dev/null || :
    _VPN_TEMP=
    return 1
  fi
  [ -s "$_tmp" ] && [ ! -L "$CONF" ] || {
    rm -f "$_tmp"; _VPN_TEMP=; return 1;
  }
  chmod 600 "$_tmp" || { rm -f "$_tmp"; _VPN_TEMP=; return 1; }
  [ ! -L "$CONF" ] && mv -f "$_tmp" "$CONF" || {
    rm -f "$_tmp"; _VPN_TEMP=; return 1;
  }
  _VPN_TEMP=
}

transaction() {
  require_safe_config || return 1
  _VPN_BACKUP=$(mktemp "$CONF.vpn-apps.rollback.XXXXXX") || {
    echo "unable to create private VPN rollback snapshot" >&2
    return 1
  }
  _backup=$_VPN_BACKUP
  if ! cp -p "$CONF" "$_backup" || ! chmod 600 "$_backup"; then
    rm -f "$_backup"; _VPN_BACKUP=
    echo "unable to save VPN app settings rollback snapshot" >&2
    return 1
  fi
  if ! "$@"; then
    rm -f "$_backup"; _VPN_BACKUP=
    return 1
  fi
  if sh "$MP/scripts/apply.sh" fast; then
    rm -f "$_backup"; _VPN_BACKUP=
    return 0
  fi
  _VPN_RESTORE=$(mktemp "$CONF.vpn-apps.restore.XXXXXX") || {
    echo "apply failed; unable to create private VPN rollback restore file" >&2
    return 1
  }
  _restore=$_VPN_RESTORE
  if cp -p "$_backup" "$_restore" && chmod 600 "$_restore"
      && [ ! -L "$CONF" ] && mv -f "$_restore" "$CONF"; then
    _VPN_RESTORE=
    if sh "$MP/scripts/apply.sh" fast; then
      echo "apply failed; previous VPN app-list configuration restored" >&2
    else
      echo "apply failed; previous config restored but runtime reconciliation also failed" >&2
    fi
  else
    echo "apply failed and config rollback could not be verified; inspect settings.conf.vpn-apps.rollback file" >&2
  fi
  rm -f "$_backup" "$_restore" 2>/dev/null || :
  _VPN_BACKUP=
  _VPN_RESTORE=
  return 1
}

mutate_master() {
  _state="$1"
  if [ "$_state" = "1" ] && [ -z "$(pg_list_enabled vpn_app)" ]; then
    echo "per-app VPN routing needs at least one selected app" >&2
    return 3
  fi
  pg_set vpn_app_proxy "$_state"
}

mutate_mode() { set_mode "$1"; }
mutate_item() { atomic_list_update set "$1" "$2"; }
mutate_remove() { atomic_list_update remove "$1"; }

cmd="${1:-list}"
case "$cmd" in
  list)
    echo "FXVPNAPP1"
    echo "master=$(pg_get vpn_app_proxy 0)"
    echo "mode=$(read_mode)"
    pg_list vpn_app | awk -F'|' '
      /^[[:space:]]*#/ || NF<3 {next}
      $1 !~ /^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$/ {next}
      $3!="0" && $3!="1" {next}
      {print $1 "|" $2 "|" $3}
    '
    ;;
  master)
    [ "$#" -eq 2 ] && valid_enabled "$2" || { echo "usage: $0 master 0|1" >&2; exit 2; }
    with_lock mutate_master "$2"
    ;;
  mode)
    [ "$#" -eq 2 ] || { echo "usage: $0 mode only|bypass" >&2; exit 2; }
    with_lock set_mode "$2"
    ;;
  set-item)
    [ "$#" -eq 3 ] && valid_enabled "$3" || { echo "usage: $0 set-item PACKAGE 0|1" >&2; exit 2; }
    with_lock atomic_list_update set "$2" "$3"
    ;;
  remove)
    [ "$#" -eq 2 ] || { echo "usage: $0 remove PACKAGE" >&2; exit 2; }
    with_lock atomic_list_update remove "$2"
    ;;
  apply-item)
    [ "$#" -eq 3 ] && valid_enabled "$3" || { echo "usage: $0 apply-item PACKAGE 0|1" >&2; exit 2; }
    with_lock transaction mutate_item "$2" "$3"
    ;;
  apply-master)
    [ "$#" -eq 2 ] && valid_enabled "$2" || { echo "usage: $0 apply-master 0|1" >&2; exit 2; }
    with_lock transaction mutate_master "$2"
    ;;
  apply-mode)
    [ "$#" -eq 2 ] || { echo "usage: $0 apply-mode only|bypass" >&2; exit 2; }
    with_lock transaction mutate_mode "$2"
    ;;
  apply-remove)
    [ "$#" -eq 2 ] || { echo "usage: $0 apply-remove PACKAGE" >&2; exit 2; }
    with_lock transaction mutate_remove "$2"
    ;;
  apply)
    # Avoid a nested lock if apply.sh re-enters this manager.
    sh "$MP/scripts/apply.sh" fast
    ;;
  *)
    echo "usage: $0 list|master 0|1|mode only|bypass|set-item PACKAGE 0|1|remove PACKAGE|apply-item PACKAGE 0|1|apply-master 0|1|apply-mode only|bypass|apply-remove PACKAGE|apply" >&2
    exit 2
    ;;
esac
