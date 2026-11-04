#!/system/bin/sh
# Yulong 7.0.1 application whitelist migrated into FX.
# Selected packages bypass FX ad/DNS filtering through the existing single
# sing-box TUN (exclude_uid) or the external-VPN Root DNS Proxy UID allowlist.
# Independent from FX's proxy route list and the network-blocking firewall.
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
LOCK=${LOCK:-$PG/yulong-app-whitelist.lock}
_YW_TEMP=
_YW_BACKUP=
_YW_RESTORE=
_YW_PID_TEMP=
umask 077
mkdir -p "$PG"
[ -d "$PG" ] && [ ! -L "$PG" ] || { echo "FX state directory is unsafe" >&2; exit 21; }
[ -f "$CONF" ] && [ ! -L "$CONF" ] || { echo "FX settings.conf missing or unsafe" >&2; exit 21; }
[ ! -L "$LOCK" ] || { echo "FX whitelist lock path is unsafe" >&2; exit 21; }

valid_package() {
  case "$1" in ''|*[!A-Za-z0-9_.-]*) return 1 ;; esac
  printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$'
}
read_rows() {
  awk -F'|' '
    $0=="[list:yulong_app_whitelist]" {inlist=1; next}
    /^\[/ {inlist=0}
    inlist && NF>=3 &&
      $1 ~ /^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$/ &&
      ($3=="0" || $3=="1") {print $1 "|" $2 "|" $3}
  ' "$CONF"
}
write_item() {
  pkg="$1"; enabled="$2"
  tmp=$(mktemp "$CONF.yulong-white.XXXXXX") || return 1
  _YW_TEMP=$tmp
  awk -F'|' -v OFS='|' -v pkg="$pkg" -v enabled="$enabled" '
    BEGIN {inlist=0; seen=0; inserted=0}
    $0=="[list:yulong_app_whitelist]" {
      if(inlist && !inserted && enabled=="1"){print pkg,pkg,enabled;inserted=1}
      inlist=1;seen=1;print;next
    }
    /^\[/ {
      if(inlist && !inserted && enabled=="1"){print pkg,pkg,enabled;inserted=1}
      inlist=0;print;next
    }
    inlist && $1==pkg {
      if(enabled=="1" && !inserted){print pkg,pkg,enabled;inserted=1}
      next
    }
    {print}
    END {
      if(inlist && !inserted && enabled=="1"){print pkg,pkg,enabled;inserted=1}
      if(!seen && enabled=="1"){print "";print "[list:yulong_app_whitelist]";print pkg,pkg,enabled}
    }
  ' "$CONF" > "$tmp" || { rm -f "$tmp"; _YW_TEMP=; return 1; }
  if [ -s "$tmp" ] && [ -f "$tmp" ] && [ ! -L "$tmp" ] \
      && [ -f "$CONF" ] && [ ! -L "$CONF" ] \
      && chmod 600 "$tmp" && mv -f "$tmp" "$CONF"; then
    _YW_TEMP=
    return 0
  fi
  rm -f "$tmp"
  _YW_TEMP=
  return 1
}
with_lock() {
  tries=0
  [ ! -L "$LOCK" ] || { echo "FX whitelist lock path is unsafe" >&2; return 10; }
  while ! mkdir "$LOCK" 2>/dev/null; do
    [ ! -L "$LOCK" ] && [ -d "$LOCK" ] || { echo "FX whitelist lock path is unsafe" >&2; return 10; }
    [ ! -L "$LOCK/pid" ] || { echo "FX whitelist lock PID path is unsafe" >&2; return 10; }
    if [ -e "$LOCK/pid" ] && [ ! -f "$LOCK/pid" ]; then
      echo "FX whitelist lock PID file is unsafe" >&2
      return 10
    fi
    owner="$(cat "$LOCK/pid" 2>/dev/null || true)"
    case "$owner" in
      ''|*[!0-9]*)
        # A process may be between mkdir and writing its PID. Give that short
        # critical section time to finish before treating a PID-less lock stale.
        if [ ! -e "$LOCK/pid" ] && [ "$tries" -ge 3 ]; then
          rmdir "$LOCK" 2>/dev/null || :
        fi
        ;;
      *)
        if ! kill -0 "$owner" 2>/dev/null; then
          rm -f "$LOCK/pid" 2>/dev/null || :
          rmdir "$LOCK" 2>/dev/null || :
        fi
        ;;
    esac
    tries=$((tries+1))
    [ "$tries" -lt 20 ] || { echo "app whitelist update is busy" >&2; return 10; }
    sleep 1
  done
  if [ -L "$LOCK/pid" ]; then
    rmdir "$LOCK" 2>/dev/null || :
    echo "FX whitelist lock PID path is unsafe" >&2
    return 10
  fi
  _YW_PID_TEMP=$(mktemp "$LOCK/pid.XXXXXX") || {
    rmdir "$LOCK" 2>/dev/null || :
    echo "cannot create private whitelist lock owner file" >&2
    return 10
  }
  if ! printf '%s\n' "$" > "$_YW_PID_TEMP" || ! chmod 600 "$_YW_PID_TEMP" \
      || [ -L "$LOCK/pid" ] || ! mv -f "$_YW_PID_TEMP" "$LOCK/pid"; then
    rm -f "$_YW_PID_TEMP"
    _YW_PID_TEMP=
    rmdir "$LOCK" 2>/dev/null || :
    echo "cannot record app whitelist lock owner" >&2
    return 10
  fi
  _YW_PID_TEMP=
  cleanup_lock() {
    [ -z "$_YW_TEMP" ] || rm -f "$_YW_TEMP" 2>/dev/null || :
    [ -z "$_YW_BACKUP" ] || rm -f "$_YW_BACKUP" 2>/dev/null || :
    [ -z "$_YW_RESTORE" ] || rm -f "$_YW_RESTORE" 2>/dev/null || :
    [ -z "$_YW_PID_TEMP" ] || rm -f "$_YW_PID_TEMP" 2>/dev/null || :
    [ -L "$LOCK/pid" ] || rm -f "$LOCK/pid" 2>/dev/null || :
    rmdir "$LOCK" 2>/dev/null || :
  }
  # Keep the lock until the transaction shell has actually exited. A signal
  # must not run cleanup and then resume mutation without owning the lock.
  trap cleanup_lock EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  "$@"
}
mutate_transaction() {
  enabled="$1"; pkg="$2"
  [ -f "$CONF" ] && [ ! -L "$CONF" ] || { echo "FX settings.conf missing or unsafe" >&2; return 21; }
  _YW_BACKUP=$(mktemp "$CONF.yulong-white-rollback.XXXXXX") || return 1
  backup=$_YW_BACKUP
  if ! cat "$CONF" > "$backup" || ! chmod 600 "$backup"; then
    rm -f "$backup"; _YW_BACKUP=; return 1
  fi
  if ! write_item "$pkg" "$enabled"; then
    rm -f "$backup"; _YW_BACKUP=; return 1
  fi
  if sh "$MP/scripts/apply.sh" fast; then
    rm -f "$backup"; _YW_BACKUP=
    echo "applied=1"
    return 0
  fi
  _YW_RESTORE=$(mktemp "$CONF.restore.XXXXXX") || {
    rm -f "$backup"; _YW_BACKUP=
    echo "unable to create private whitelist rollback file" >&2
    return 11
  }
  if cat "$backup" > "$_YW_RESTORE" && chmod 600 "$_YW_RESTORE" \
      && [ -f "$CONF" ] && [ ! -L "$CONF" ] \
      && [ -f "$_YW_RESTORE" ] && [ ! -L "$_YW_RESTORE" ] \
      && mv -f "$_YW_RESTORE" "$CONF"; then
    _YW_RESTORE=
  else
    rm -f "$_YW_RESTORE" "$backup"
    _YW_RESTORE=; _YW_BACKUP=
    echo "whitelist config rollback failed" >&2
    return 11
  fi
  sh "$MP/scripts/apply.sh" fast >/dev/null 2>&1 || echo "previous config restored; runtime reconcile failed" >&2
  rm -f "$backup"; _YW_BACKUP=
  echo "apply failed; previous whitelist restored" >&2
  return 1
}
cmd=${1:-list}
case "$cmd" in
  list)
    echo FXYULONGWHITE1
    read_rows
    ;;
  add)
    [ "$#" -eq 2 ] && valid_package "$2" || { echo "usage: $0 add PACKAGE" >&2; exit 2; }
    with_lock mutate_transaction 1 "$2"
    ;;
  remove)
    [ "$#" -eq 2 ] && valid_package "$2" || { echo "usage: $0 remove PACKAGE" >&2; exit 2; }
    with_lock mutate_transaction 0 "$2"
    ;;
  apply)
    sh "$MP/scripts/apply.sh" fast
    ;;
  *)
    echo "usage: $0 list|add PACKAGE|remove PACKAGE|apply" >&2
    exit 2
    ;;
esac
