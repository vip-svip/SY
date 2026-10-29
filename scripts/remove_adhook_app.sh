#!/system/bin/sh
# Remove only Hook APKs tracked as installed by FX's bundled-app installer.
set -u
STATE_DIR=${2:-${FX_ADHOOK_STATE_DIR:-/data/adb/privacyguard}}
LOG=${FX_ADHOOK_LOG:-$STATE_DIR/adhook-install.log}
log_msg() {
  _msg="$(date '+%m-%d %H:%M:%S' 2>/dev/null) remove_adhook_app: $*"
  printf '%s\n' "$_msg" >> "$LOG" 2>/dev/null || :
}
[ -d "$STATE_DIR" ] || exit 0
command -v pm >/dev/null 2>&1 || exit 0
_result=0
for _pair in 'de.privacyguard.hook privacyguardhook' 'de.privacyguard.adhook fxadhook'; do
  set -- $_pair
  _pkg=$1; _slug=$2
  _marker="$STATE_DIR/adhook-apk-$_slug.sha256"
  _owned="$STATE_DIR/adhook-apk-$_slug.fx-owned"
  [ -s "$_marker" ] || continue
  # A digest marker means FX observed/installed this APK; only the ownership
  # marker proves the package was absent before FX installed it.
  if [ ! -s "$_owned" ]; then
    log_msg "leaving pre-existing or ownership-unknown package untouched: $_pkg"
    rm -f "$_marker" 2>/dev/null
    continue
  fi
  _paths=$(pm path "$_pkg" 2>/dev/null)
  if [ -z "$_paths" ]; then rm -f "$_marker" 2>/dev/null; continue; fi
  case "$_paths" in
    *:/system/*|*:/product/*|*:/vendor/*)
      log_msg "system-overlay package will disappear with module unmount: $_pkg"
      rm -f "$_marker" "$_owned" 2>/dev/null
      ;;
    *)
      if pm uninstall "$_pkg" >> "$LOG" 2>&1; then
        log_msg "removed FX-managed app package: $_pkg"; rm -f "$_marker" "$_owned" 2>/dev/null
      else
        log_msg "WARN: could not remove FX-managed app package: $_pkg"; _result=1
      fi
      ;;
  esac
done
exit "$_result"
