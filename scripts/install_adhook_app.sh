#!/system/bin/sh
# Install bundled LSPosed Hook APKs as ordinary /data/app packages.
# This avoids requiring a KernelSU metamodule merely to expose Hook APKs under /system/priv-app.
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
install_one() {
  _pkg=$1; _slug=$2; _apk=$3
  _marker="$STATE_DIR/adhook-apk-$_slug.sha256"
  _owned="$STATE_DIR/adhook-apk-$_slug.fx-owned"
  if [ ! -s "$_apk" ]; then log_msg "WARN: bundled APK missing: $_apk"; return 1; fi
  if ! command -v pm >/dev/null 2>&1; then log_msg "WARN: pm command unavailable; cannot install $_pkg yet"; return 1; fi
  _actual=$(sha256sum "$_apk" 2>/dev/null | awk 'NR==1 {print $1}')
  if [ -z "$_actual" ]; then log_msg "WARN: cannot compute APK digest for $_pkg"; return 1; fi
  if [ -s "$_apk.sha256" ]; then
    _expected=$(awk 'NR==1 {print $1}' "$_apk.sha256" 2>/dev/null)
    if [ -n "$_expected" ] && [ "$_actual" != "$_expected" ]; then log_msg "WARN: APK checksum mismatch for $_pkg; refusing install"; return 1; fi
  fi
  _prior=$(cat "$_marker" 2>/dev/null)
  _was_present=0
  package_present "$_pkg" && _was_present=1
  if [ "$_was_present" = 1 ] && [ "$_prior" = "$_actual" ]; then log_msg "already installed and unchanged: $_pkg"; return 0; fi
  _stage="$TMP_DIR/.fx-adhook-${_slug}-$$.apk"
  rm -f "$_stage" 2>/dev/null
  if ! cp "$_apk" "$_stage" 2>/dev/null; then log_msg "WARN: cannot stage APK for PackageManager: $_pkg"; return 1; fi
  chmod 0644 "$_stage" 2>/dev/null || :
  chown shell:shell "$_stage" 2>/dev/null || :
  if command -v restorecon >/dev/null 2>&1; then restorecon "$_stage" 2>/dev/null || :; fi
  if command -v chcon >/dev/null 2>&1; then chcon u:object_r:shell_data_file:s0 "$_stage" 2>/dev/null || :; fi
  _attempt=1; _installed=0
  while [ "$_attempt" -le 3 ]; do
    _log_lines=$(wc -l < "$LOG" 2>/dev/null || echo 0)
    if pm install -r "$_stage" >> "$LOG" 2>&1 && package_present "$_pkg"; then
      # Only claim package ownership when it did not exist before FX installed it.
      # Never let module removal uninstall an app package that predated FX.
      if [ "$_was_present" = 0 ]; then
        _owned_tmp="${_owned}.tmp.$$"
        (umask 077; printf 'fx-managed-v1\n' > "$_owned_tmp") && chmod 0600 "$_owned_tmp" 2>/dev/null && mv -f "$_owned_tmp" "$_owned" 2>/dev/null || log_msg "WARN: ownership marker could not be persisted for $_pkg"
      fi
      _marker_tmp="${_marker}.tmp.$$"
      (umask 077; printf '%s\n' "$_actual" > "$_marker_tmp") &&
        chmod 0600 "$_marker_tmp" 2>/dev/null && mv -f "$_marker_tmp" "$_marker" 2>/dev/null
      if [ -s "$_marker" ] && [ "$(cat "$_marker" 2>/dev/null)" = "$_actual" ]; then _installed=1; break; fi
      rm -f "$_marker_tmp" 2>/dev/null
      log_msg "WARN: package installed but state marker could not be persisted: $_pkg"
      _installed=1; break
    fi
    if tail -n "+$((_log_lines + 1))" "$LOG" 2>/dev/null | grep -Eqi 'INSTALL_FAILED_UPDATE_INCOMPATIBLE|signatures do not match|signing certificate'; then
      log_msg "ERROR: signing certificate differs for $_pkg; existing package and app data are preserved; no uninstall attempted"
      rm -f "$_stage" 2>/dev/null
      return 1
    fi
    log_msg "WARN: PackageManager install attempt $_attempt/3 failed for $_pkg"
    _attempt=$((_attempt+1))
    [ "$_attempt" -le 3 ] && sleep 2
  done
  rm -f "$_stage" 2>/dev/null
  if [ "$_installed" = 1 ]; then
    log_msg "installed as ordinary app; LSPosed activation requires its module/scope and a reboot: $_pkg"; return 0
  fi
  log_msg "ERROR: unable to install $_pkg; core FX installation continues, see $LOG"; return 1
}
_result=0
install_one de.privacyguard.hook privacyguardhook "$MODDIR/optional/PrivacyGuardHook.apk" || _result=1
install_one de.privacyguard.adhook fxadhook "$MODDIR/optional/FXAdHook.apk" || _result=1
exit "$_result"
