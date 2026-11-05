#!/system/bin/sh
# Verify the unified FX Hook system-app overlay; only overlay-less legacy modules use ordinary-app fallback.
set -u
MODDIR=${1:-}
if [ -z "$MODDIR" ]; then _d=$(dirname "$0" 2>/dev/null); MODDIR=$(cd "$_d/.." 2>/dev/null && pwd); fi
STATE_DIR=${FX_ADHOOK_STATE_DIR:-/data/adb/privacyguard}
TMP_DIR=${FX_ADHOOK_TMP_DIR:-/data/local/tmp}
LOG=${FX_ADHOOK_LOG:-$STATE_DIR/adhook-install.log}
mkdir -p "$STATE_DIR" "$TMP_DIR" 2>/dev/null || :
: >> "$LOG" 2>/dev/null || LOG=/dev/null
log_msg(){ _msg="$(date '+%m-%d %H:%M:%S' 2>/dev/null) install_adhook_app: $*"; printf '%s\n' "$_msg" >> "$LOG" 2>/dev/null || :; printf '%s\n' "$*"; }
package_present(){ pm path "$1" 2>/dev/null | grep -q '^package:'; }
package_is_system(){
  # Updated system apps may live under /data/app while PackageManager still
  # classifies them as system packages; check both the code path and -s list.
  pm list packages -s "$1" 2>/dev/null | grep -Fqx "package:$1"
}
retire_legacy_standalone(){
  # Remove the legacy app only when FX ownership and the exact installed APK
  # digest prove it is the old FX-managed package. Never uninstall a user app.
  _legacy_pkg=de.privacyguard.hook
  _legacy_marker="$STATE_DIR/adhook-apk-privacyguardhook.sha256"
  _legacy_owned="$STATE_DIR/adhook-apk-privacyguardhook.fx-owned"
  if ! package_present "$_legacy_pkg"; then
    rm -f "$_legacy_marker" "$_legacy_owned"
    return 0
  fi
  if [ ! -s "$_legacy_marker" ] || [ ! -s "$_legacy_owned" ]; then
    log_msg "WARN: legacy Hook package has no FX ownership proof; preserving it. Remove it manually if it is an old FX copy."
    return 0
  fi
  _legacy_path=$(pm path "$_legacy_pkg" 2>/dev/null | awk 'NR==1 {sub(/^package:/, ""); print; exit}')
  _legacy_expected=$(awk 'NR==1 {print $1}' "$_legacy_marker" 2>/dev/null)
  _legacy_actual=$(sha256sum "$_legacy_path" 2>/dev/null | awk 'NR==1 {print $1}')
  if [ -z "$_legacy_path" ] || [ -z "$_legacy_expected" ] ||
     [ -z "$_legacy_actual" ] || [ "$_legacy_actual" != "$_legacy_expected" ]; then
    log_msg "WARN: legacy Hook digest does not prove FX ownership; preserving package"
    return 0
  fi
  if pm uninstall "$_legacy_pkg" >> "$LOG" 2>&1; then
    rm -f "$_legacy_marker" "$_legacy_owned"
    log_msg "removed FX-managed legacy standalone Hook; FX Hook is the only FX app"
  else
    log_msg "ERROR: could not remove FX-managed legacy Hook package"
    return 1
  fi
  return 0
}
force_replace_signature_mismatch(){
  _pkg=$1; _new_apk=$2; _log_lines=$3
  _backup_dir="$TMP_DIR/.fx-hook-rollback-$$"
  rm -rf "$_backup_dir" 2>/dev/null
  mkdir -p "$_backup_dir" || {
    log_msg "ERROR: cannot create rollback directory; preserving old installation"
    return 1
  }
  _paths=$(pm path "$_pkg" 2>/dev/null | sed -n 's/^package://p')
  [ -n "$_paths" ] || {
    log_msg "ERROR: signature conflict but installed APK paths are unavailable; preserving old installation"
    rm -rf "$_backup_dir"
    return 1
  }
  _count=0
  printf '%s\n' "$_paths" | while IFS= read -r _path; do
    [ -s "$_path" ] || exit 1
    cp "$_path" "$_backup_dir/$(basename "$_path")" || exit 1
  done || {
    log_msg "ERROR: cannot back up all installed APK splits; preserving old installation"
    rm -rf "$_backup_dir"
    return 1
  }
  set -- "$_backup_dir"/*.apk
  [ -s "$1" ] || {
    log_msg "ERROR: rollback APK set is incomplete; preserving old installation"
    rm -rf "$_backup_dir"
    return 1
  }
  chmod 0600 "$@" 2>/dev/null || :
  if ! pm uninstall -k "$_pkg" >> "$LOG" 2>&1 || package_present "$_pkg"; then
    log_msg "ERROR: Android refused data-preserving uninstall; old FX Hook remains"
    rm -rf "$_backup_dir"
    return 1
  fi
  if pm install -r "$_new_apk" >> "$LOG" 2>&1 && package_present "$_pkg"; then
    log_msg "signature changed: replaced FX Hook with new signing identity using uninstall -k; app data retained by PackageManager"
    rm -rf "$_backup_dir"
    return 0
  fi
  log_msg "ERROR: new FX Hook install failed after signature migration; restoring previous APK set"
  if pm install-multiple -r "$@" >> "$LOG" 2>&1 && package_present "$_pkg"; then
    log_msg "ROLLBACK: previous FX Hook APK set restored; retained app data remains available"
  else
    log_msg "CRITICAL: automatic rollback failed; previous APK set retained at $_backup_dir"
    return 2
  fi
  rm -rf "$_backup_dir"
  return 1
}
install_one(){
  _pkg=de.privacyguard.adhook; _slug=fxunifiedhook
  # New module archives carry a systemless /system/app overlay. The optional
  # payload is only a compatibility fallback for legacy archives without it.
  _overlay_apk="$MODDIR/system/app/FX/FX.apk"
  if [ -s "$_overlay_apk" ]; then _apk="$_overlay_apk"; else _apk="$MODDIR/optional/FXUnifiedHook.apk"; fi
  _marker="$STATE_DIR/adhook-apk-$_slug.sha256"; _owned="$STATE_DIR/adhook-apk-$_slug.fx-owned"
  [ -s "$_apk" ] || { log_msg "ERROR: unified Hook APK missing: $_apk"; return 1; }
  command -v pm >/dev/null 2>&1 || { log_msg "WARN: pm unavailable; defer Hook installation"; return 1; }
  _actual=$(sha256sum "$_apk" 2>/dev/null | awk 'NR==1 {print $1}')
  [ -n "$_actual" ] || { log_msg "ERROR: cannot calculate unified APK digest"; return 1; }
  # The system-app overlay is a release payload: require its checksum sidecar.
  # Legacy optional APK payloads remain compatible with older module archives.
  if [ -s "$_overlay_apk" ] && [ ! -s "$_apk.sha256" ]; then
    log_msg "ERROR: system-app overlay checksum sidecar is missing; refusing deployment"
    return 1
  fi
  if [ -s "$_apk.sha256" ]; then
    _expected=$(awk 'NR==1 {print $1}' "$_apk.sha256")
    case "$_expected" in *[!0-9a-fA-F]*|'') log_msg "ERROR: invalid unified APK checksum format"; return 1 ;; esac
    [ "${#_expected}" -eq 64 ] || { log_msg "ERROR: invalid unified APK checksum length"; return 1; }
    [ "$_expected" = "$_actual" ] || { log_msg "ERROR: unified APK checksum mismatch; refusing install"; return 1; }
  fi
  _is_system_app=0
  if package_present "$_pkg"; then
    _paths=$(pm path "$_pkg" 2>/dev/null | sed -n 's/^package://p')
    _system_path=$(printf '%s\n' "$_paths" | awk '/^\/system\// || /^\/product\// || /^\/vendor\// {print; exit}')
    if [ -n "$_system_path" ] || package_is_system "$_pkg"; then
      _is_system_app=1
      _system_installed_path=$(printf '%s\n' "$_paths" | awk 'NR==1 {print; exit}')
      _installed_digest=$(sha256sum "$_system_installed_path" 2>/dev/null | awk 'NR==1 {print $1}')
      if [ -n "$_installed_digest" ] && [ "$_installed_digest" = "$_actual" ]; then
        log_msg "verified FX Hook system app and module APK digest; no PackageManager reinstall required"
        retire_legacy_standalone || return 1
        return 0
      fi
      if [ -n "$_system_path" ]; then
        log_msg "ERROR: system FX Hook path does not match the module APK digest; refusing an unsafe overwrite"
        return 1
      fi
      # An updated system app can be stored under /data/app. Keep PackageManager's
      # system classification and update that data-side package in place below.
      log_msg "FX Hook is an updated system app under /data/app; module APK digest changed"
    fi
  fi
  # A packaged systemless overlay must be recognized by PackageManager as a
  # system app before any update/install is attempted. If the overlay mount or
  # SELinux labeling failed, never silently downgrade the required deployment
  # to an ordinary /data/app install.
  if [ -s "$_overlay_apk" ] && [ "$_is_system_app" != 1 ]; then
    log_msg "ERROR: FX system-app overlay is present but PackageManager does not classify the package as a system app; refusing ordinary-app fallback. Check KernelSU overlay mount, post-fs-data SELinux labeling and reboot."
    return 1
  fi
  _prior=$(cat "$_marker" 2>/dev/null); _was_present=0; package_present "$_pkg" && _was_present=1
  if [ "$_was_present" = 1 ] && [ "$_prior" = "$_actual" ]; then
    retire_legacy_standalone || return 1
    log_msg "FX Hook already installed and unchanged; obsolete standalone app removed"
    return 0
  fi
  _stage="$TMP_DIR/.fx-unified-hook-$$.apk"; rm -f "$_stage" 2>/dev/null
  cp "$_apk" "$_stage" 2>/dev/null || { log_msg "ERROR: cannot stage unified APK"; return 1; }
  # Never mark a package as FX-owned before PackageManager confirms installation.
  # Otherwise a failed first install can leave a stale marker that later removes
  # an unrelated user-installed package with the same applicationId.
  if [ "$_was_present" = 0 ]; then
    rm -f "$_marker" "$_owned" "$_marker.tmp.$$" "$_owned.tmp.$$" 2>/dev/null
  fi
  chmod 0644 "$_stage" 2>/dev/null || :; chown shell:shell "$_stage" 2>/dev/null || :
  command -v restorecon >/dev/null 2>&1 && restorecon "$_stage" 2>/dev/null || :
  _attempt=1; _installed=0
  while [ "$_attempt" -le 3 ]; do
    _log_lines=$(wc -l < "$LOG" 2>/dev/null || echo 0)
    if pm install -r "$_stage" >> "$LOG" 2>&1 && package_present "$_pkg"; then
      if ! (umask 077; printf '%s\n' "$_actual" > "$_marker.tmp.$$") ||
         ! chmod 0600 "$_marker.tmp.$$" 2>/dev/null ||
         ! mv -f "$_marker.tmp.$$" "$_marker" 2>/dev/null ||
         [ "$(cat "$_marker" 2>/dev/null)" != "$_actual" ]; then
        rm -f "$_marker.tmp.$$" "$_stage" 2>/dev/null
        log_msg "ERROR: APK installed but its digest ownership record could not be committed"
        return 1
      fi
      if [ "$_was_present" = 0 ]; then
        if ! (umask 077; printf 'fx-managed-v1\n' > "$_owned.tmp.$$") ||
           ! chmod 0600 "$_owned.tmp.$$" 2>/dev/null ||
           ! mv -f "$_owned.tmp.$$" "$_owned" 2>/dev/null ||
           [ "$(cat "$_owned" 2>/dev/null)" != "fx-managed-v1" ]; then
          rm -f "$_owned.tmp.$$" "$_marker" "$_stage" 2>/dev/null
          log_msg "ERROR: APK installed but FX ownership record could not be committed; leaving package untouched"
          return 1
        fi
      fi
      _installed=1
      break
    fi
    if tail -n "+$((_log_lines+1))" "$LOG" 2>/dev/null | grep -Eqi 'INSTALL_FAILED_UPDATE_INCOMPATIBLE|signatures do not match|signing certificate'; then
      if [ "$_is_system_app" = 1 ]; then
        log_msg "ERROR: signing certificate changed for a system app; refusing uninstall/migration to protect the system package and app data. Build with the stable FX signing identity."
        rm -f "$_stage"
        return 1
      fi
      log_msg "WARN: Android rejected in-place update because the APK signing certificate changed; attempting data-preserving migration"
      if force_replace_signature_mismatch "$_pkg" "$_stage" "$_log_lines"; then
        _installed=1
        break
      else
        _migration_rc=$?
        [ "$_migration_rc" -eq 2 ] && log_msg "CRITICAL: rollback APK is retained; inspect $LOG before retrying"
        rm -f "$_stage"
        return 1
      fi
    fi
    log_msg "WARN: PackageManager attempt $_attempt/3 failed"; _attempt=$((_attempt+1)); [ "$_attempt" -le 3 ] && sleep 2
  done
  rm -f "$_stage" 2>/dev/null
  [ "$_installed" = 1 ] || { log_msg "ERROR: unable to install unified Hook; core FX installation continues"; return 1; }
  if [ -s "$_overlay_apk" ]; then
    log_msg "WARN: systemless overlay is not visible to PackageManager; installed compatibility copy as an ordinary app"
  else
    log_msg "installed unified Hook APK from legacy optional payload as an ordinary app"
  fi
  log_msg "configure LSPosed module and target scope, then reboot"
  retire_legacy_standalone || return 1
  return 0
}
install_one
exit $?
