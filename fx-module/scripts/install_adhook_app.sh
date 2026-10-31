#!/system/bin/sh
# Install the unified dual-entry FX Hook APK as one ordinary /data/app package.
set -u
MODDIR=${1:-}
if [ -z "$MODDIR" ]; then _d=$(dirname "$0" 2>/dev/null); MODDIR=$(cd "$_d/.." 2>/dev/null && pwd); fi
STATE_DIR=${FX_ADHOOK_STATE_DIR:-/data/adb/privacyguard}
TMP_DIR=${FX_ADHOOK_TMP_DIR:-/data/local/tmp}
LOG=${FX_ADHOOK_LOG:-$STATE_DIR/adhook-install.log}
mkdir -p "$STATE_DIR" "$TMP_DIR" 2>/dev/null || :
log_msg(){ _msg="$(date '+%m-%d %H:%M:%S' 2>/dev/null) install_adhook_app: $*"; printf '%s\n' "$_msg" >> "$LOG" 2>/dev/null || :; printf '%s\n' "$*"; }
package_present(){ pm path "$1" 2>/dev/null | grep -q '^package:'; }
install_one(){
  _pkg=de.privacyguard.adhook; _slug=fxunifiedhook; _apk="$MODDIR/optional/FXUnifiedHook.apk"
  _marker="$STATE_DIR/adhook-apk-$_slug.sha256"; _owned="$STATE_DIR/adhook-apk-$_slug.fx-owned"
  [ -s "$_apk" ] || { log_msg "ERROR: unified Hook APK missing: $_apk"; return 1; }
  command -v pm >/dev/null 2>&1 || { log_msg "WARN: pm unavailable; defer Hook installation"; return 1; }
  _actual=$(sha256sum "$_apk" 2>/dev/null | awk 'NR==1 {print $1}')
  [ -n "$_actual" ] || { log_msg "ERROR: cannot calculate unified APK digest"; return 1; }
  if [ -s "$_apk.sha256" ]; then _expected=$(awk 'NR==1 {print $1}' "$_apk.sha256"); [ "$_expected" = "$_actual" ] || { log_msg "ERROR: unified APK checksum mismatch; refusing install"; return 1; }; fi
  _prior=$(cat "$_marker" 2>/dev/null); _was_present=0; package_present "$_pkg" && _was_present=1
  if [ "$_was_present" = 1 ] && [ "$_prior" = "$_actual" ]; then log_msg "unified Hook already installed and unchanged"; return 0; fi
  _stage="$TMP_DIR/.fx-unified-hook-$$.apk"; rm -f "$_stage" 2>/dev/null
  cp "$_apk" "$_stage" 2>/dev/null || { log_msg "ERROR: cannot stage unified APK"; return 1; }
  chmod 0644 "$_stage" 2>/dev/null || :; chown shell:shell "$_stage" 2>/dev/null || :
  command -v restorecon >/dev/null 2>&1 && restorecon "$_stage" 2>/dev/null || :
  _attempt=1; _installed=0
  while [ "$_attempt" -le 3 ]; do
    _log_lines=$(wc -l < "$LOG" 2>/dev/null || echo 0)
    if pm install -r "$_stage" >> "$LOG" 2>&1 && package_present "$_pkg"; then
      if [ "$_was_present" = 0 ]; then (umask 077; printf 'fx-managed-v1\n' > "$_owned.tmp.$$") && chmod 0600 "$_owned.tmp.$$" 2>/dev/null && mv -f "$_owned.tmp.$$" "$_owned" 2>/dev/null || log_msg "WARN: ownership marker not persisted"; fi
      (umask 077; printf '%s\n' "$_actual" > "$_marker.tmp.$$") && chmod 0600 "$_marker.tmp.$$" 2>/dev/null && mv -f "$_marker.tmp.$$" "$_marker" 2>/dev/null
      [ "$(cat "$_marker" 2>/dev/null)" = "$_actual" ] && _installed=1
      break
    fi
    if tail -n "+$((_log_lines+1))" "$LOG" 2>/dev/null | grep -Eqi 'INSTALL_FAILED_UPDATE_INCOMPATIBLE|signatures do not match|signing certificate'; then log_msg "ERROR: signing certificate mismatch for $_pkg; preserving existing package and data"; rm -f "$_stage"; return 1; fi
    log_msg "WARN: PackageManager attempt $_attempt/3 failed"; _attempt=$((_attempt+1)); [ "$_attempt" -le 3 ] && sleep 2
  done
  rm -f "$_stage" 2>/dev/null
  [ "$_installed" = 1 ] || { log_msg "ERROR: unable to install unified Hook; core FX installation continues"; return 1; }
  log_msg "installed unified dual-entry Hook APK; configure LSPosed module and target scope, then reboot"
  # Retire only the legacy standalone package if its FX ownership marker proves
  # FX installed it. Never uninstall a pre-existing user package.
  _legacy_marker="$STATE_DIR/adhook-apk-privacyguardhook.sha256"; _legacy_owned="$STATE_DIR/adhook-apk-privacyguardhook.fx-owned"
  if [ -s "$_legacy_owned" ] && package_present de.privacyguard.hook; then
    pm uninstall de.privacyguard.hook >> "$LOG" 2>&1 && { rm -f "$_legacy_marker" "$_legacy_owned"; log_msg "retired FX-managed standalone legacy Hook after unified install"; } || log_msg "WARN: could not retire old FX-managed standalone Hook"
  fi
  return 0
}
install_one
exit $?
