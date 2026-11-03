#!/system/bin/sh
# Yulong 7.0.1 application whitelist migrated into FX.
# Selected packages bypass FX ad/DNS filtering through the existing single
# sing-box TUN (exclude_uid) or the external-VPN Root DNS Proxy UID allowlist.
# Independent from FX's proxy route list and the network-blocking firewall.
set -eu

MP=\${MP:-}
if [ -z "$MP" ]; then
  for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do
    if [ -s "$d/module.prop" ] && grep -q '^id=privacyguard$' "$d/module.prop" 2>/dev/null; then MP="$d"; break; fi
  done
fi
[ -n "$MP" ] && [ -s "$MP/module.prop" ] || { echo "FX module is not installed" >&2; exit 20; }
PG=\${PG:-/data/adb/privacyguard}
CONF=\${CONF:-$PG/settings.conf}
LOCK=\${LOCK:-$PG/yulong-app-whitelist.lock}
mkdir -p "$PG"
[ -f "$CONF" ] && [ ! -L "$CONF" ] || { echo "FX settings.conf missing or unsafe" >&2; exit 21; }

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
  pkg="$1"; enabled="$2"; tmp="$CONF.yulong-white.$$"
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
  ' "$CONF" > "$tmp" || { rm -f "$tmp"; return 1; }
  [ -s "$tmp" ] || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" && mv -f "$tmp" "$CONF"
}
with_lock() {
  tries=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    tries=$((tries+1))
    [ "$tries" -lt 20 ] || { echo "app whitelist update is busy" >&2; return 10; }
    sleep 1
  done
  trap 'rmdir "$LOCK" 2>/dev/null || :' EXIT HUP INT TERM
  "$@"
}
mutate_transaction() {
  enabled="$1"; pkg="$2"
  backup="$CONF.yulong-white-rollback.$$"
  cp -p "$CONF" "$backup" || return 1
  if ! write_item "$pkg" "$enabled"; then rm -f "$backup"; return 1; fi
  if sh "$MP/scripts/apply.sh" fast; then
    rm -f "$backup"
    echo "applied=1"
    return 0
  fi
  cp -p "$backup" "$CONF.restore.$$" && chmod 600 "$CONF.restore.$$" \
    && mv -f "$CONF.restore.$$" "$CONF" || {
      rm -f "$backup"; echo "whitelist config rollback failed" >&2; return 11;
    }
  sh "$MP/scripts/apply.sh" fast >/dev/null 2>&1 || echo "previous config restored; runtime reconcile failed" >&2
  rm -f "$backup"
  echo "apply failed; previous whitelist restored" >&2
  return 1
}
cmd=\${1:-list}
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
