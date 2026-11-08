#!/system/bin/sh
# Verify the unified FX Hook system-app overlay; only overlay-less legacy modules use ordinary-app fallback.
set -u

# Do not let Root installer state or logs traverse attacker-controlled symlinks.
# Check every lexical path component before mkdir/open, then re-check after creation.
path_components_are_safe() {
  _pc_path=$1
  case "$_pc_path" in /*) : ;; *) return 1 ;; esac
  case "$_pc_path" in *//*|*/../*|*/..|*/./*|*/.) return 1 ;; esac
  _pc_rest=${_pc_path#/}
  _pc_current=
  while [ -n "$_pc_rest" ]; do
    case "$_pc_rest" in
      */*) _pc_part=${_pc_rest%%/*}; _pc_rest=${_pc_rest#*/} ;;
      *) _pc_part=$_pc_rest; _pc_rest= ;;
    esac
    case "$_pc_part" in ''|.|..) return 1 ;; esac
    _pc_current="$_pc_current/$_pc_part"
    [ ! -L "$_pc_current" ] || return 1
  done
  return 0
}
file_path_is_safe_or_absent() {
  _safe_file=$1
  path_components_are_safe "$_safe_file" || return 1
  [ ! -L "$_safe_file" ] || return 1
  [ ! -e "$_safe_file" ] || [ -f "$_safe_file" ]
}

MODDIR=${1:-}
if [ -z "$MODDIR" ]; then _d=$(dirname "$0" 2>/dev/null); MODDIR=$(cd "$_d/.." 2>/dev/null && pwd); fi
if ! path_components_are_safe "$MODDIR" || [ ! -d "$MODDIR" ] || [ -L "$MODDIR" ]; then
  printf "%s\\n" "ERROR: unsafe or missing FX module directory." >&2
  exit 1
fi
STATE_DIR=${FX_ADHOOK_STATE_DIR:-/data/adb/privacyguard}
TMP_DIR=${FX_ADHOOK_TMP_DIR:-/data/local/tmp}
LOG=${FX_ADHOOK_LOG:-$STATE_DIR/adhook-install.log}
if ! path_components_are_safe "$STATE_DIR" || ! path_components_are_safe "$TMP_DIR"; then
  printf '%s\n' "ERROR: installer state/temp path contains a symlink, relative component, or parent traversal; refusing Root installation." >&2
  exit 1
fi
umask 077
mkdir -p "$STATE_DIR" "$TMP_DIR" 2>/dev/null || {
  printf '%s\n' "ERROR: cannot prepare installer state/temp directories; refusing Root installation." >&2
  exit 1
}
if [ ! -d "$STATE_DIR" ] || [ -L "$STATE_DIR" ] ||
   [ ! -d "$TMP_DIR" ] || [ -L "$TMP_DIR" ] ||
   ! path_components_are_safe "$STATE_DIR" || ! path_components_are_safe "$TMP_DIR"; then
  printf '%s\n' "ERROR: installer state/temp directory changed or is not a real directory; refusing Root installation." >&2
  exit 1
fi
LOG_DIR=$(dirname "$LOG" 2>/dev/null) || exit 1
if ! path_components_are_safe "$LOG_DIR" || ! file_path_is_safe_or_absent "$LOG"; then
  printf '%s\n' "ERROR: installer log path is unsafe; refusing Root installation." >&2
  exit 1
fi
: >> "$LOG" 2>/dev/null || {
  printf '%s\n' "ERROR: cannot safely open installer log; refusing Root installation." >&2
  exit 1
}
log_msg(){ _msg="$(date '+%m-%d %H:%M:%S' 2>/dev/null) install_adhook_app: $*"; printf '%s\n' "$_msg" >> "$LOG" 2>/dev/null || :; printf '%s\n' "$*"; }
package_present(){ pm path "$1" 2>/dev/null | grep -q '^package:'; }
package_is_system(){
  # Updated system apps may live under /data/app while PackageManager still
  # classifies them as system packages; check both the code path and -s list.
  pm list packages -s "$1" 2>/dev/null | grep -Fqx "package:$1"
}
retire_legacy_standalone(){
  # Retire only when both the FX owner token and the exact installed APK digest match.
  # -k intentionally preserves old package data for the user.
  _legacy_pkg=de.privacyguard.hook
  _legacy_marker="$STATE_DIR/adhook-apk-privacyguardhook.sha256"
  _legacy_owned="$STATE_DIR/adhook-apk-privacyguardhook.fx-owned"
  file_path_is_safe_or_absent "$_legacy_marker" && file_path_is_safe_or_absent "$_legacy_owned" || {
    log_msg "WARN: unsafe legacy Hook ownership metadata; preserving package and data"
    return 0
  }
  if ! package_present "$_legacy_pkg"; then rm -f "$_legacy_marker" "$_legacy_owned"; return 0; fi
  if [ ! -f "$_legacy_marker" ] || [ ! -f "$_legacy_owned" ]; then
    log_msg "WARN: legacy Hook package has no FX ownership proof; preserving package and data"
    return 0
  fi
  _legacy_owner=$(cat "$_legacy_owned" 2>/dev/null) || _legacy_owner=
  _legacy_path=$(pm path "$_legacy_pkg" 2>/dev/null | awk 'NR==1 {sub(/^package:/, ""); print; exit}')
  _legacy_expected=$(awk 'NR==1 {print $1}' "$_legacy_marker" 2>/dev/null)
  case "$_legacy_expected" in *[!0-9a-fA-F]*|'') _legacy_expected= ;; esac
  _legacy_actual=
  if file_path_is_safe_or_absent "$_legacy_path" && [ -f "$_legacy_path" ] && [ ! -L "$_legacy_path" ]; then
    _legacy_actual=$(sha256sum "$_legacy_path" 2>/dev/null | awk 'NR==1 {print $1}')
  fi
  if [ "$_legacy_owner" != "fx-managed-v1" ] || [ "${#_legacy_expected}" -ne 64 ] ||
     [ -z "$_legacy_actual" ] || [ "$_legacy_actual" != "$_legacy_expected" ]; then
    log_msg "WARN: legacy Hook ownership/digest proof does not match; preserving package and data"
    return 0
  fi
  if pm uninstall -k "$_legacy_pkg" >> "$LOG" 2>&1 && ! package_present "$_legacy_pkg"; then
    rm -f "$_legacy_marker" "$_legacy_owned"
    log_msg "retired FX-owned legacy Hook package with -k; legacy app data retained"
    return 0
  fi
  log_msg "ERROR: could not retire FX-owned legacy Hook package; legacy data retained"
  return 1
}
write_private_record() {
  _record_path=$1
  _record_value=$2
  file_path_is_safe_or_absent "$_record_path" || return 1
  _record_dir=$(dirname "$_record_path" 2>/dev/null) || return 1
  [ -d "$_record_dir" ] && [ ! -L "$_record_dir" ] && path_components_are_safe "$_record_dir" || return 1

  # mktemp creates the file exclusively. A PID-derived redirection path can
  # be pre-planted as a symlink by another process with write access to state.
  _record_tmp=$(umask 077; mktemp "${_record_path}.tmp.XXXXXX") || return 1
  if ! path_components_are_safe "$_record_tmp" || [ ! -f "$_record_tmp" ] || [ -L "$_record_tmp" ]; then
    [ -f "$_record_tmp" ] && [ ! -L "$_record_tmp" ] && rm -f "$_record_tmp" 2>/dev/null || :
    return 1
  fi
  if ! ( umask 077; printf '%s\n' "$_record_value" > "$_record_tmp" ) 2>/dev/null ||
     ! chmod 0600 "$_record_tmp" 2>/dev/null ||
     ! mv -f "$_record_tmp" "$_record_path" 2>/dev/null; then
    [ -f "$_record_tmp" ] && [ ! -L "$_record_tmp" ] && rm -f "$_record_tmp" 2>/dev/null || :
    return 1
  fi
  [ -f "$_record_path" ] && [ ! -L "$_record_path" ] &&
    [ "$(cat "$_record_path" 2>/dev/null)" = "$_record_value" ]
}

force_replace_signature_mismatch(){
  _pkg=$1; _new_apk=$2; _log_lines=$3
  _backup_dir=$(umask 077; mktemp -d "$TMP_DIR/.fx-hook-rollback.XXXXXX") || _backup_dir=
  if [ -z "$_backup_dir" ] || [ ! -d "$_backup_dir" ] || [ -L "$_backup_dir" ] || ! path_components_are_safe "$_backup_dir"; then
    log_msg "ERROR: cannot create rollback directory; preserving old installation"
    return 1
  fi
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
  # A present-but-damaged overlay must never be treated as an overlay-less legacy archive.
  _overlay_apk="$MODDIR/system/app/FX/FX.apk"
  file_path_is_safe_or_absent "$_overlay_apk" || { log_msg "ERROR: unsafe FX system-app overlay path; refusing fallback"; return 1; }
  # A pending overlay retry means the systemless mount or its SELinux label is still
  # unresolved; falling back to /data/app here would silently ship an ordinary app
  # where the module promised a recognized system app.
  _retry_marker="$STATE_DIR/system-app-retry"
  if ! file_path_is_safe_or_absent "$_retry_marker"; then
    log_msg "ERROR: unsafe system-app retry marker; refusing ordinary-app fallback"
    return 1
  fi
  if [ ! -e "$_overlay_apk" ] && [ -s "$_retry_marker" ]; then
    log_msg "ERROR: system-app overlay deployment is still pending retry; refusing ordinary-app fallback"
    return 1
  fi
  _is_overlay=0
  if [ -e "$_overlay_apk" ]; then
    [ -f "$_overlay_apk" ] && [ -s "$_overlay_apk" ] && [ ! -L "$_overlay_apk" ] || { log_msg "ERROR: system-app overlay exists but is empty or non-regular; refusing ordinary-app fallback"; return 1; }
    _apk="$_overlay_apk"; _is_overlay=1
  else
    _apk="$MODDIR/optional/FXUnifiedHook.apk"
  fi
  _marker="$STATE_DIR/adhook-apk-$_slug.sha256"; _owned="$STATE_DIR/adhook-apk-$_slug.fx-owned"
  if ! file_path_is_safe_or_absent "$_apk" || [ ! -f "$_apk" ] || [ ! -s "$_apk" ] || [ -L "$_apk" ] ||
     ! file_path_is_safe_or_absent "$_apk.sha256" || [ ! -f "$_apk.sha256" ] || [ ! -s "$_apk.sha256" ] || [ -L "$_apk.sha256" ]; then
    log_msg "ERROR: unified Hook APK or required SHA-256 sidecar is missing or unsafe"
    return 1
  fi
  [ -s "$_apk" ] || { log_msg "ERROR: unified Hook APK missing: $_apk"; return 1; }
  command -v pm >/dev/null 2>&1 || { log_msg "WARN: pm unavailable; defer Hook installation"; return 1; }
  _actual=$(sha256sum "$_apk" 2>/dev/null | awk 'NR==1 {print $1}')
  [ -n "$_actual" ] || { log_msg "ERROR: cannot calculate unified APK digest"; return 1; }
  if ! file_path_is_safe_or_absent "$_apk" || [ ! -f "$_apk" ] || [ ! -s "$_apk" ] || [ -L "$_apk" ] ||
     ! file_path_is_safe_or_absent "$_apk.sha256" || [ ! -f "$_apk.sha256" ] || [ ! -s "$_apk.sha256" ] || [ -L "$_apk.sha256" ]; then
    log_msg "ERROR: unified Hook APK or required SHA-256 sidecar is missing or unsafe"
    return 1
  fi
  _actual=$(sha256sum "$_apk" 2>/dev/null | awk 'NR==1 {print $1}')
  _expected=$(awk 'NR==1 {print $1}' "$_apk.sha256" 2>/dev/null)
  case "$_expected" in *[!0-9a-fA-F]*|'') _expected= ;; esac
  [ "${#_actual}" -eq 64 ] && [ "${#_expected}" -eq 64 ] && [ "$_expected" = "$_actual" ] || {
    log_msg "ERROR: unified APK SHA-256 sidecar is invalid or does not match; refusing install"
    return 1
  }
  if [ "$_is_overlay" = 1 ]; then
    _build_info="$MODDIR/optional/FXUnifiedHook-BUILD-INFO.txt"
    if ! file_path_is_safe_or_absent "$_build_info" || [ ! -f "$_build_info" ] || [ -L "$_build_info" ] ||
       ! grep -Fqx "Deployment: systemless /system/app/FX/FX.apk overlay; PackageManager fallback only when overlay is unavailable" "$_build_info"; then
      log_msg "ERROR: FX system-app build provenance is missing or inconsistent; refusing deployment"
      return 1
    fi
  fi
  if ! file_path_is_safe_or_absent "$_marker" || ! file_path_is_safe_or_absent "$_owned"; then
    log_msg "ERROR: Hook ownership state path is unsafe"
    return 1
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
  _prior=; _was_present=0; _was_fx_owned=0; _installed_path=; _installed_digest=
  if package_present "$_pkg"; then
    _was_present=1
    _installed_path=$(pm path "$_pkg" 2>/dev/null | sed -n "s/^package://p" | awk "NR==1 {print; exit}")
    if file_path_is_safe_or_absent "$_installed_path" && [ -f "$_installed_path" ] && [ ! -L "$_installed_path" ]; then
      _installed_digest=$(sha256sum "$_installed_path" 2>/dev/null | awk 'NR==1 {print $1}')
    fi
    _prior=$(cat "$_marker" 2>/dev/null) || _prior=
    _owner_value=$(cat "$_owned" 2>/dev/null) || _owner_value=
    case "$_prior" in *[!0-9a-fA-F]*|'') _prior= ;; esac
    if [ "$_owner_value" = "fx-managed-v1" ] && [ "${#_prior}" -eq 64 ] &&
       [ -n "$_installed_digest" ] && [ "$_installed_digest" = "$_prior" ]; then
      _was_fx_owned=1
    else
      # Stale ownership records are not authority over the current installed app.
      rm -f "$_marker" "$_owned"
      _prior=
    fi
    if [ "$_installed_digest" = "$_actual" ]; then
      log_msg "verified existing FX Hook APK digest; PackageManager reinstall not required"
      retire_legacy_standalone || return 1
      return 0
    fi
  else
    rm -f "$_marker" "$_owned"
  fi
  # /data/local/tmp is shared and writable by other apps. Use an atomically
  # created private directory rather than a predictable staging-file path.
  _stage_dir=$(mktemp -d "$TMP_DIR/.fx-unified-hook.XXXXXX" 2>/dev/null) || _stage_dir=''
  if [ -z "$_stage_dir" ]; then
    log_msg "ERROR: cannot create a private Hook staging directory; refusing installation"
    return 1
  fi
  if [ ! -d "$_stage_dir" ] || [ -L "$_stage_dir" ] ||
     ! path_components_are_safe "$_stage_dir" ||
     ! chmod 0700 "$_stage_dir" 2>/dev/null; then
    log_msg "ERROR: private Hook staging directory is unsafe; refusing installation"
    [ -d "$_stage_dir" ] && [ ! -L "$_stage_dir" ] && rmdir "$_stage_dir" 2>/dev/null || :
    return 1
  fi
  _stage="$_stage_dir/FXUnifiedHook.apk"
  cleanup_stage() {
    # Never recursively remove a path that may have been replaced.
    if [ -d "$_stage_dir" ] && [ ! -L "$_stage_dir" ]; then
      [ ! -L "$_stage" ] && rm -f "$_stage" 2>/dev/null || :
      rmdir "$_stage_dir" 2>/dev/null || :
    fi
  }
  cp "$_apk" "$_stage" 2>/dev/null || {
    cleanup_stage
    log_msg "ERROR: cannot stage unified APK"
    return 1
  }
  # Never mark a package as FX-owned before PackageManager confirms installation.
  # Otherwise a failed first install can leave a stale marker that later removes
  # an unrelated user-installed package with the same applicationId.
  if [ "$_was_present" = 0 ]; then
    rm -f "$_marker" "$_owned" 2>/dev/null
  fi
  chmod 0644 "$_stage" 2>/dev/null || :; chown shell:shell "$_stage" 2>/dev/null || :
  command -v restorecon >/dev/null 2>&1 && restorecon "$_stage" 2>/dev/null || :
  _attempt=1; _installed=0
  while [ "$_attempt" -le 3 ]; do
    _log_lines=$(wc -l < "$LOG" 2>/dev/null || echo 0)
    if pm install -r "$_stage" >> "$LOG" 2>&1 && package_present "$_pkg"; then
      if ! write_private_record "$_marker" "$_actual"; then
        cleanup_stage
        log_msg "ERROR: APK installed but its digest ownership record could not be committed"
        return 1
      fi
      if [ "$_was_present" = 0 ]; then
        if ! write_private_record "$_owned" "fx-managed-v1"; then
          rm -f "$_marker" 2>/dev/null
          cleanup_stage
          log_msg "ERROR: APK installed but FX ownership record could not be committed; leaving package untouched"
          return 1
        fi
      fi
      _installed=1
      break
    fi
    if tail -n "+$((_log_lines+1))" "$LOG" 2>/dev/null | grep -Eqi 'INSTALL_FAILED_UPDATE_INCOMPATIBLE|signatures do not match|signing certificate'; then
      if [ "$_is_system_app" = 1 ]; then
        log_msg "ERROR: signing certificate changed for a system app; refusing uninstall/migration to protect the system package and app data."
        cleanup_stage
        return 1
      fi
      if [ "$_was_fx_owned" != 1 ]; then
        log_msg "ERROR: signing certificate differs for a package not proven FX-owned; preserving the existing app and its data."
        cleanup_stage
        return 1
      fi
      log_msg "WARN: Android rejected in-place update for an FX-owned ordinary Hook; attempting data-preserving migration"
      if force_replace_signature_mismatch "$_pkg" "$_stage" "$_log_lines"; then
        _installed=1
        break
      else
        _migration_rc=$?
        [ "$_migration_rc" -eq 2 ] && log_msg "CRITICAL: rollback APK is retained; inspect $LOG before retrying"
        cleanup_stage
        return 1
      fi
    fi
    log_msg "WARN: PackageManager attempt $_attempt/3 failed"; _attempt=$((_attempt+1)); [ "$_attempt" -le 3 ] && sleep 2
  done
  cleanup_stage
  [ "$_installed" = 1 ] || { log_msg "ERROR: unable to install unified Hook; core FX installation continues"; return 1; }
  _post_paths=$(pm path "$_pkg" 2>/dev/null | sed -n 's/^package://p')
  _post_system_path=$(printf '%s\n' "$_post_paths" | awk '/^\/system\// || /^\/product\// || /^\/vendor\// {print; exit}')
  _post_pm_system=0
  package_is_system "$_pkg" && _post_pm_system=1
  if [ "$_is_overlay" = 1 ]; then
    if [ -z "$_post_system_path" ] && [ "$_post_pm_system" != 1 ]; then
      log_msg "ERROR: PackageManager did not retain system-app classification after the overlay update; refusing success"
      return 1
    fi
    log_msg "verified FX Hook remains a PackageManager system app after the systemless overlay update"
  elif [ -n "$_post_system_path" ] || [ "$_post_pm_system" = 1 ]; then
    log_msg "updated an existing Android system app from an overlay-less legacy archive; PackageManager system classification is preserved"
  else
    log_msg "installed unified Hook APK from an overlay-less legacy archive as an ordinary /data/app compatibility app"
  fi
  log_msg "configure LSPosed module and target scope, then reboot"
  retire_legacy_standalone || return 1
  return 0
}
install_one
exit $?
