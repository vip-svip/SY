#!/system/bin/sh
# Install bundled LSPosed Hook APKs as ordinary /data/app packages.
set -u
MODDIR=${1:-}
if [ -z "$MODDIR" ]; then _d=$(dirname "$0" 2>/dev/null); MODDIR=$(cd "$_d/.." 2>/dev/null && pwd); fi
STATE_DIR=${FX_ADHOOK_STATE_DIR:-/data/adb/privacyguard}
TMP_DIR=${FX_ADHOOK_TMP_DIR:-/data/local/tmp}
LOG=${FX_ADHOOK_LOG:-$STATE_DIR/adhook-install.log}
mkdir -p "$STATE_DIR" "$TMP_DIR" 2>/dev/null || :
log_msg() { _msg="$(date '+%m-%d %H:%M:%S' 2>/dev/null) install_adhook_app: $*"; printf '%s\n' "$_msg" >> "$LOG" 2>/dev/null || :; printf '%s\n' "$*"; }
package_present() { pm path "$1" 2>/dev/null | grep -q '^package:'; }
install_one() {
  _pkg=$1; _slug=$2; _apk=$3; _marker="$STATE_DIR/adhook-apk-$_slug.sha256"
  [ -s "$_apk" ] || { log_msg "WARN: bundled APK missing: $_apk"; return 1; }
  command -v pm >/dev/null 2>&1 || { log_msg "WARN: pm unavailable for $_pkg"; return 1; }
  _actual=$(sha256sum "$_apk" 2>/dev/null | awk 'NR==1 {print $1}')
  [ -n "$_actual" ] || { log_msg "WARN: cannot hash APK $_pkg"; return 1; }
  if [ -s "$_apk.sha256" ]; then _expected=$(awk 'NR==1 {print $1}' "$_apk.sha256" 2>/dev/null); [ -z "$_expected" ] || [ "$_actual" = "$_expected" ] || { log_msg "WARN: checksum mismatch; refusing $_pkg"; return 1; }; fi
  _prior=$(cat "$_marker" 2>/dev/null)
  if package_present "$_pkg" && [ "$_prior" = "$_actual" ]; then log_msg "already installed and unchanged: $_pkg"; return 0; fi
  _stage="$TMP_DIR/.fx-adhook-${_slug}-$$.apk"; rm -f "$_stage" 2>/dev/null
  cp "$_apk" "$_stage" 2>/dev/null || { log_msg "WARN: cannot stage APK $_pkg"; return 1; }
  chmod 0644 "$_stage" 2>/dev/null || :; chown shell:shell "$_stage" 2>/dev/null || :
  command -v restorecon >/dev/null 2>&1 && restorecon "$_stage" 2>/dev/null || :
  command -v chcon >/dev/null 2>&1 && chcon u:object_r:shell_data_file:s0 "$_stage" 2>/dev/null || :
  _attempt=1; _installed=0
  while [ "$_attempt" -le 3 ]; do
    if pm install -r "$_stage" >> "$LOG" 2>&1 && package_present "$_pkg"; then
      _marker_tmp="$_marker.tmp.$$"
      (umask 077; printf '%s\n' "$_actual" > "$_marker_tmp") && chmod 0600 "$_marker_tmp" 2>/dev/null && mv -f "$_marker_tmp" "$_marker" 2>/dev/null
      _installed=1; break
    fi
    log_msg "WARN: install attempt $_attempt/3 failed for $_pkg"; _attempt=$((_attempt+1)); [ "$_attempt" -le 3 ] && sleep 2
  done
  rm -f "$_stage" 2>/dev/null
  [ "$_installed" = 1 ] && { log_msg "installed; LSPosed module/scope and reboot still required: $_pkg"; return 0; }
  log_msg "ERROR: install failed for $_pkg; main FX startup continues"; return 1
}
_result=0
install_one de.privacyguard.hook privacyguardhook "$MODDIR/optional/PrivacyGuardHook.apk" || _result=1
install_one de.privacyguard.adhook fxadhook "$MODDIR/optional/FXAdHook.apk" || _result=1
exit "$_result"
