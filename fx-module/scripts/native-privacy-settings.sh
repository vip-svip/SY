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


  show-target)
    _pkg=${2:-}
    case "$_pkg" in ''|*[!A-Za-z0-9_.-]*) echo "invalid package" >&2; exit 2 ;; esac
    pg_target_show_location "$_pkg"
    ;;
  clear-target)
    _pkg=${2:-}
    case "$_pkg" in ''|*[!A-Za-z0-9_.-]*) echo "invalid package" >&2; exit 2 ;; esac
    pg_target_clear_location "$_pkg" || { echo "failed to clear target coordinates" >&2; exit 1; }
    echo "cleared=1"
    ;;
  set-target)
    # set-target <package> <lat> <lon> [accuracy]
    # Coordinates are per-target target-list features, not global 0/1 settings: the
    # module's target row already carries location_lat/location_lon/location_accuracy.
    _pkg=${2:-}
    _lat=${3:-}
    _lon=${4:-}
    _acc=${5:-}
    case "$_pkg" in ''|*[!A-Za-z0-9_.-]*) echo "invalid package" >&2; exit 2 ;; esac
    _ok=$(
      awk -v p="$_pkg" -v lat="$_lat" -v lon="$_lon" -v acc="$_acc" '
        BEGIN {
          if (lat+0 != lat || lat < -90 || lat > 90) exit 1
          if (lon+0 != lon || lon < -180 || lon > 180) exit 1
          if (acc != "" && (acc+0 != acc || acc < 0 || acc > 1000)) exit 1
          print "ok"
        }'
    ) || { echo "invalid coordinate" >&2; exit 2; }
    [ "$_ok" = ok ] || { echo "invalid coordinate" >&2; exit 2; }
    if ! pg_target_set_location "$_pkg" "$_lat" "$_lon" "$_acc"; then
      echo "failed to persist target coordinates" >&2; exit 1
    fi
    echo "saved=1"
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
    _backup=$(umask 077; mktemp "$CONF.privacy-rollback.XXXXXX") || {
      echo "unable to stage privacy settings rollback" >&2; exit 1;
    }
    if ! cp -p "$CONF" "$_backup"; then
      rm -f "$_backup"
      echo "unable to snapshot privacy settings" >&2
      exit 1
    fi
    if ! pg_set "$key" "$value"; then
      rm -f "$_backup"
      echo "settings.conf write failed" >&2
      exit 1
    fi
    if sh "$MP/scripts/apply.sh" fast >> "$PG/apply.log" 2>&1; then
      rm -f "$_backup"
      printf '%s\\n' "saved=1 applied=1 key=$key value=$value"
      exit 0
    fi
    _restore=$(umask 077; mktemp "$CONF.privacy-restore.XXXXXX") || {
      echo "privacy settings apply failed; rollback backup retained at $_backup" >&2
      exit 11
    }
    if ! cp -p "$_backup" "$_restore" || ! chmod 600 "$_restore" ||
        ! mv -f "$_restore" "$CONF"; then
      rm -f "$_restore" 2>/dev/null || :
      echo "privacy settings apply failed and rollback could not be published; backup retained at $_backup" >&2
      exit 11
    fi
    rm -f "$_backup"
    if ! sh "$MP/scripts/apply.sh" fast >> "$PG/apply.log" 2>&1; then
      echo "previous privacy settings restored; runtime reconcile failed" >&2
      exit 12
    fi
    echo "privacy settings apply failed; previous settings restored" >&2
    exit 10
    ;;
  *)
    echo "usage: native-privacy-settings.sh set KEY 0|1" >&2
    exit 2
    ;;
esac
