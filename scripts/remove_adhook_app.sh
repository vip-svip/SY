#!/system/bin/sh
# Remove only Hook packages with explicit FX ownership markers.
set -u
STATE_DIR=${2:-${FX_ADHOOK_STATE_DIR:-/data/adb/privacyguard}}
LOG=${FX_ADHOOK_LOG:-$STATE_DIR/adhook-install.log}
log_msg(){ _msg="$(date '+%m-%d %H:%M:%S' 2>/dev/null) remove_adhook_app: $*"; printf '%s\n' "$_msg" >> "$LOG" 2>/dev/null || :; }
[ -d "$STATE_DIR" ] || exit 0
command -v pm >/dev/null 2>&1 || exit 0
_result=0
for _pair in 'de.privacyguard.adhook fxunifiedhook' 'de.privacyguard.adhook fxunified' 'de.privacyguard.adhook fxadhook' 'de.privacyguard.hook privacyguardhook'; do
  set -- $_pair; _pkg=$1; _slug=$2
  _marker="$STATE_DIR/adhook-apk-$_slug.sha256"; _owned="$STATE_DIR/adhook-apk-$_slug.fx-owned"
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
