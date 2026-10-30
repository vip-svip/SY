#!/system/bin/sh
# Remove only Hook packages proven to have been installed and owned by FX.
set -u
STATE_DIR=${2:-${FX_ADHOOK_STATE_DIR:-/data/adb/privacyguard}}
LOG=${FX_ADHOOK_LOG:-$STATE_DIR/adhook-install.log}
log_msg() {
  _msg="$(date '+%m-%d %H:%M:%S' 2>/dev/null) remove_adhook_app: $*"
  printf '%s\n' "$_msg" >> "$LOG" 2>/dev/null || :
}
[ -d "$STATE_DIR" ] || exit 0
command -v pm >/dev/null 2>&1 || exit 0
RESULT=0
for PAIR in 'de.privacyguard.adhook fxadhook' 'de.privacyguard.hook privacyguardhook'; do
  set -- $PAIR
  PKG=$1
  SLUG=$2
  MARKER="$STATE_DIR/adhook-apk-$SLUG.sha256"
  OWNED="$STATE_DIR/adhook-apk-$SLUG.fx-owned"
  [ -s "$MARKER" ] || continue
  if [ ! -s "$OWNED" ]; then
    log_msg "leaving pre-existing or ownership-unknown package untouched: $PKG"
    rm -f "$MARKER" 2>/dev/null
    continue
  fi
  PATHS=$(pm path "$PKG" 2>/dev/null)
  if [ -z "$PATHS" ]; then rm -f "$MARKER" "$OWNED" 2>/dev/null; continue; fi
  case "$PATHS" in
    *:/system/*|*:/product/*|*:/vendor/*)
      log_msg "system-overlay package will disappear with module unmount: $PKG"
      rm -f "$MARKER" "$OWNED" 2>/dev/null
      ;;
    *)
      if pm uninstall "$PKG" >> "$LOG" 2>&1; then
        log_msg "removed FX-managed package: $PKG"
        rm -f "$MARKER" "$OWNED" 2>/dev/null
      else
        log_msg "WARN: could not remove FX-managed package: $PKG"
        RESULT=1
      fi
      ;;
  esac
done
exit "$RESULT"
