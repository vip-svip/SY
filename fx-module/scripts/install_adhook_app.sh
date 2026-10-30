#!/system/bin/sh
# Install the one unified libxposed API-101 FX Hook package.
set -u
MODDIR=${1:-}
if [ -z "$MODDIR" ]; then
  _d=$(dirname "$0" 2>/dev/null)
  MODDIR=$(cd "$_d/.." 2>/dev/null && pwd)
fi
STATE_DIR=${FX_ADHOOK_STATE_DIR:-/data/adb/privacyguard}
TMP_DIR=${FX_ADHOOK_TMP_DIR:-/data/local/tmp}
LOG=${FX_ADHOOK_LOG:-$STATE_DIR/adhook-install.log}
mkdir -p "$STATE_DIR" "$TMP_DIR" 2>/dev/null || :
log_msg() {
  _msg="$(date '+%m-%d %H:%M:%S' 2>/dev/null) install_adhook_app: $*"
  printf '%s\n' "$_msg" >> "$LOG" 2>/dev/null || :
  printf '%s\n' "$*"
}
package_present() { pm path "$1" 2>/dev/null | grep -q '^package:'; }
remove_legacy_if_fx_owned() {
  _pkg=de.privacyguard.hook
  _marker="$STATE_DIR/adhook-apk-privacyguardhook.sha256"
  _owned="$STATE_DIR/adhook-apk-privacyguardhook.fx-owned"
  [ -s "$_marker" ] || return 0
  if [ ! -s "$_owned" ]; then
    log_msg "legacy package ownership is unproven; preserving it: $_pkg"
    rm -f "$_marker" 2>/dev/null
    return 0
  fi
  if package_present "$_pkg"; then
    if pm uninstall "$_pkg" >> "$LOG" 2>&1; then
      log_msg "removed retired FX-owned API-82 package after API-101 install: $_pkg"
    else
      log_msg "WARN: could not remove retired FX-owned API-82 package: $_pkg"
      return 1
    fi
  fi
  rm -f "$_marker" "$_owned" 2>/dev/null
  return 0
}
APK="$MODDIR/optional/FXAdHook.apk"
PKG=de.privacyguard.adhook
SLUG=fxadhook
MARKER="$STATE_DIR/adhook-apk-$SLUG.sha256"
OWNED="$STATE_DIR/adhook-apk-$SLUG.fx-owned"
if [ ! -s "$APK" ]; then log_msg "ERROR: unified FX Hook APK missing: $APK"; exit 1; fi
if ! command -v pm >/dev/null 2>&1; then log_msg "WARN: pm command unavailable; cannot install $PKG"; exit 1; fi
ACTUAL=$(sha256sum "$APK" 2>/dev/null | awk 'NR==1 {print $1}')
if [ -z "$ACTUAL" ]; then log_msg "ERROR: cannot compute APK digest"; exit 1; fi
if [ -s "$APK.sha256" ]; then
  EXPECTED=$(awk 'NR==1 {print $1}' "$APK.sha256" 2>/dev/null)
  if [ -n "$EXPECTED" ] && [ "$ACTUAL" != "$EXPECTED" ]; then
    log_msg "ERROR: unified APK checksum mismatch; refusing install"; exit 1
  fi
fi
PRIOR=$(cat "$MARKER" 2>/dev/null)
WAS_PRESENT=0
package_present "$PKG" && WAS_PRESENT=1
if [ "$WAS_PRESENT" = 1 ] && [ "$PRIOR" = "$ACTUAL" ]; then
  log_msg "unified FX Hook already installed and unchanged"
  remove_legacy_if_fx_owned || exit 1
  exit 0
fi
STAGE="$TMP_DIR/.fx-unified-hook-$$.apk"
rm -f "$STAGE" 2>/dev/null
if ! cp "$APK" "$STAGE" 2>/dev/null; then log_msg "ERROR: cannot stage unified APK"; exit 1; fi
chmod 0644 "$STAGE" 2>/dev/null || :
chown shell:shell "$STAGE" 2>/dev/null || :
command -v restorecon >/dev/null 2>&1 && restorecon "$STAGE" 2>/dev/null || :
command -v chcon >/dev/null 2>&1 && chcon u:object_r:shell_data_file:s0 "$STAGE" 2>/dev/null || :
ATTEMPT=1
INSTALLED=0
while [ "$ATTEMPT" -le 3 ]; do
  if [ -f "$LOG" ]; then LOG_LINES=$(wc -l < "$LOG" 2>/dev/null || echo 0); else LOG_LINES=0; fi
  if pm install -r "$STAGE" >> "$LOG" 2>&1 && package_present "$PKG"; then
    if [ "$WAS_PRESENT" = 0 ]; then
      OWNED_TMP="$OWNED.tmp.$$"
      (umask 077; printf 'fx-managed-v1\n' > "$OWNED_TMP") &&
        chmod 0600 "$OWNED_TMP" 2>/dev/null && mv -f "$OWNED_TMP" "$OWNED" 2>/dev/null ||
        log_msg "WARN: ownership marker could not be persisted for $PKG"
    fi
    MARKER_TMP="$MARKER.tmp.$$"
    (umask 077; printf '%s\n' "$ACTUAL" > "$MARKER_TMP") &&
      chmod 0600 "$MARKER_TMP" 2>/dev/null && mv -f "$MARKER_TMP" "$MARKER" 2>/dev/null
    INSTALLED=1
    break
  fi
  if tail -n "+$((LOG_LINES + 1))" "$LOG" 2>/dev/null | grep -Eqi 'INSTALL_FAILED_UPDATE_INCOMPATIBLE|signatures do not match|signing certificate'; then
    log_msg "ERROR: unified APK signing certificate differs; existing package and data preserved"
    rm -f "$STAGE" 2>/dev/null
    exit 1
  fi
  log_msg "WARN: PackageManager install attempt $ATTEMPT/3 failed for $PKG"
  ATTEMPT=$((ATTEMPT + 1))
  [ "$ATTEMPT" -le 3 ] && sleep 2
done
rm -f "$STAGE" 2>/dev/null
[ "$INSTALLED" = 1 ] || { log_msg "ERROR: unable to install unified FX Hook"; exit 1; }
if [ ! -s "$MARKER" ] || [ "$(cat "$MARKER" 2>/dev/null)" != "$ACTUAL" ]; then
  log_msg "WARN: installed unified APK but checksum state marker could not be persisted"
fi
remove_legacy_if_fx_owned || exit 1
log_msg "unified FX Hook installed; enable its single LSPosed module/scope and reboot"
exit 0
