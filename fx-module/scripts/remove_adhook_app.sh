#!/system/bin/sh
# Remove only Hook packages with explicit FX ownership markers.
set -u
STATE_DIR=${2:-${FX_ADHOOK_STATE_DIR:-/data/adb/privacyguard}}
LOG=${FX_ADHOOK_LOG:-$STATE_DIR/adhook-install.log}

# Uninstall runs as root. Never follow a redirected state/log path or read
# ownership markers through a symlink: doing so could turn stale metadata into
# authority to remove an unrelated PackageManager package.
path_components_are_safe() {
  _pc_path=$1
  case "$_pc_path" in /*) ;; *) return 1 ;; esac
  _pc_rest=${_pc_path#/}
  _pc_current=''
  while [ -n "$_pc_rest" ]; do
    case "$_pc_rest" in
      */*) _pc_part=${_pc_rest%%/*}; _pc_rest=${_pc_rest#*/} ;;
      *) _pc_part=$_pc_rest; _pc_rest='' ;;
    esac
    case "$_pc_part" in
      ''|.) continue ;;
      ..) return 1 ;;
    esac
    _pc_current="$_pc_current/$_pc_part"
    [ ! -L "$_pc_current" ] || return 1
  done
  return 0
}

if ! path_components_are_safe "$STATE_DIR"; then
  printf '%s\n' "ERROR: refusing Hook cleanup through an unsafe state path" >&2
  exit 1
fi
[ -d "$STATE_DIR" ] || exit 0
[ ! -L "$STATE_DIR" ] || {
  printf '%s\n' "ERROR: refusing Hook cleanup through a symlinked state directory" >&2
  exit 1
}
LOG_DIR=$(dirname "$LOG" 2>/dev/null) || exit 1
if ! path_components_are_safe "$LOG_DIR" || [ -L "$LOG" ] ||
   { [ -e "$LOG" ] && [ ! -f "$LOG" ]; }; then
  printf '%s\n' "ERROR: refusing Hook cleanup through an unsafe log path" >&2
  exit 1
fi
: >> "$LOG" 2>/dev/null || {
  printf '%s\n' "ERROR: cannot safely open Hook cleanup log" >&2
  exit 1
}
log_msg(){ _msg="$(date '+%m-%d %H:%M:%S' 2>/dev/null) remove_adhook_app: $*"; printf '%s\n' "$_msg" >> "$LOG" 2>/dev/null || :; }
command -v pm >/dev/null 2>&1 || exit 0
_result=0
for _pair in 'de.privacyguard.adhook fxunifiedhook' 'de.privacyguard.adhook fxunified' 'de.privacyguard.adhook fxadhook' 'de.privacyguard.hook privacyguardhook'; do
  set -- $_pair; _pkg=$1; _slug=$2
  _marker="$STATE_DIR/adhook-apk-$_slug.sha256"; _owned="$STATE_DIR/adhook-apk-$_slug.fx-owned"
  [ -e "$_marker" ] || [ -L "$_marker" ] || continue
  if [ -L "$_marker" ] || [ -L "$_owned" ] ||
     { [ -e "$_marker" ] && [ ! -f "$_marker" ]; } ||
     { [ -e "$_owned" ] && [ ! -f "$_owned" ]; }; then
    log_msg "leaving package untouched: unsafe FX ownership marker path: $_pkg"
    _result=1
    continue
  fi
  [ -s "$_marker" ] || continue
  if [ ! -s "$_owned" ]; then log_msg "leaving pre-existing or ownership-unknown package untouched: $_pkg"; rm -f "$_marker" "$_owned"; continue; fi
  _paths=$(pm path "$_pkg" 2>/dev/null)
  if [ -z "$_paths" ]; then rm -f "$_marker" "$_owned"; continue; fi
  case "$_paths" in
    *:/system/*|*:/product/*|*:/vendor/*) log_msg "system-overlay package will disappear with module unmount: $_pkg"; rm -f "$_marker" "$_owned";;
    *)
      # The ownership marker alone is not enough: the user may have removed
      # the FX-installed app and later installed another app with the same ID.
      # Verify the installed base.apk still matches the exact FX APK digest.
      _installed_apk=$(printf '%s\n' "$_paths" | awk 'NR==1 {sub(/^package:/, ""); print; exit}')
      _expected=$(awk 'NR==1 {print $1}' "$_marker" 2>/dev/null)
      _actual=$(sha256sum "$_installed_apk" 2>/dev/null | awk 'NR==1 {print $1}')
      if [ -z "$_expected" ] || [ -z "$_actual" ] || [ "$_actual" != "$_expected" ]; then
        log_msg "leaving package untouched: installed APK digest does not match FX ownership record: $_pkg"
        rm -f "$_marker" "$_owned"
        continue
      fi
      if pm uninstall "$_pkg" >> "$LOG" 2>&1; then
        log_msg "removed FX-managed Hook package: $_pkg"
        rm -f "$_marker" "$_owned"
      else
        log_msg "WARN: could not remove FX-managed package: $_pkg"
        _result=1
      fi
      ;;
  esac
done
exit "$_result"
