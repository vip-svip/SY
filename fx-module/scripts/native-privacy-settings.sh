#!/system/bin/sh
# Native FX privacy settings writer. Reads/writes only allowlisted top-level flags.
set -eu
PG=${PG:-/data/adb/privacyguard}
MP=${MP:-}
[ -n "$MP" ] || {
  for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do
    [ -f "$d/module.prop" ] && { MP="$d"; break; }
  done
}
[ -n "$MP" ] && [ -f "$MP/module.prop" ] || { echo "FX module not found" >&2; exit 20; }
CONF="$PG/settings.conf"
export MP PG CONF
# This helper runs as Root. Do not read or mutate settings through a symlinked
# state path, including an ancestor of /data/adb/privacyguard.
fx_privacy_path_is_safe() {
  _fx_path=$1
  case "$_fx_path" in /*) ;; *) return 1 ;; esac
  case "$_fx_path" in *//*|*/../*|*/..|*/./*|*/.) return 1 ;; esac
  _fx_rest=${_fx_path#/}
  _fx_current=
  while [ -n "$_fx_rest" ]; do
    case "$_fx_rest" in
      */*) _fx_part=${_fx_rest%%/*}; _fx_rest=${_fx_rest#*/} ;;
      *) _fx_part=$_fx_rest; _fx_rest= ;;
    esac
    case "$_fx_part" in ''|.|..) return 1 ;; esac
    _fx_current="$_fx_current/$_fx_part"
    [ ! -L "$_fx_current" ] || return 1
  done
  return 0
}
fx_privacy_path_is_safe "$PG" || { echo "unsafe FX state path" >&2; exit 21; }
[ -f "$CONF" ] && [ ! -L "$CONF" ] && [ -r "$CONF" ] || { echo "settings.conf unavailable" >&2; exit 21; }
case "${1:-}" in
  list)
    # Return only top-level boolean flags; never expose subscriptions or script bodies to the app.
    awk 'BEGIN{FS="="} /^\[/ {exit} /^[A-Za-z0-9_.-]+=[01]$/ {print}' "$CONF"
    ;;
  set)
    key=${2:-}; value=${3:-}
    case "$key" in ''|*[!A-Za-z0-9_.-]*) echo "invalid setting key" >&2; exit 2 ;; esac
    case "$value" in 0|1) ;; *) echo "setting value must be 0 or 1" >&2; exit 2 ;; esac
    if ! awk -v key="$key" 'BEGIN{FS="="} /^\[/ {exit} $1==key && $2 ~ /^[01]$/ {ok=1} END{exit !ok}' "$MP/scripts/default.conf" 2>/dev/null; then
      echo "setting key is not a declared top-level boolean flag" >&2
      exit 2
    fi
    # Never race an in-progress WebUI transaction or overwrite a damaged transaction.
    for marker in "$CONF.tmp" "$CONF.tmp."* "$CONF.txn" "$CONF.txn.tmp" "$CONF.bak" "$CONF.bak.tmp" "$CONF.recover" "$CONF.tmp3"; do
      [ ! -e "$marker" ] || { echo "settings.conf transaction busy; retry" >&2; exit 75; }
    done
    . "$MP/scripts/util.sh"
    pg_set "$key" "$value" || { echo "settings.conf write failed" >&2; exit 1; }
    if sh "$MP/scripts/apply.sh" fast >> "$PG/apply.log" 2>&1; then
      printf '%s\n' "saved=1 applied=1 key=$key value=$value"
      exit 0
    fi
    printf '%s\n' "saved=1 applied=0 key=$key value=$value"
    exit 10
    ;;
  *)
    echo "usage: native-privacy-settings.sh set KEY 0|1" >&2
    exit 2
    ;;
esac
