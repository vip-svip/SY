#!/system/bin/sh
# >>> fx-system-app-overlay-verify (managed by fx-patches/patch_system_app_install_stage.py)
# Verify and label the FX systemless APK overlay before PackageManager scans
# system applications. FX is a system app, not a privileged app.
set -u
APP_DIR=${FX_SYSTEM_APP_DIR:-/system/app/FX}
APK_PATH="$APP_DIR/FX.apk"
SUM_PATH="$APP_DIR/FX.apk.sha256"
STATE_DIR=${FX_SYSTEM_APP_STATE_DIR:-/data/adb/privacyguard}
LOG_DIR="$STATE_DIR/logs"
LOG_FILE="$LOG_DIR/system-app-overlay.log"
DEPLOYMENT_MARKER="$STATE_DIR/system-app-apk.sha256"
RETRY_MARKER="$STATE_DIR/system-app-retry"

path_components_are_safe(){
  _pc_path=$1
  case "$_pc_path" in /*) ;; *) return 1 ;; esac
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

log(){
  path_components_are_safe "$STATE_DIR" || return 0
  mkdir -p "$LOG_DIR" 2>/dev/null || return 0
  path_components_are_safe "$LOG_DIR" && [ -d "$LOG_DIR" ] && [ ! -L "$LOG_DIR" ] &&
    [ ! -L "$LOG_FILE" ] && { [ ! -e "$LOG_FILE" ] || [ -f "$LOG_FILE" ]; } || return 0
  chmod 0700 "$LOG_DIR" 2>/dev/null || :
  printf '%s\n' "$*" >> "$LOG_FILE" 2>/dev/null || :
}
retry(){
  log "RETRY: $*"
  path_components_are_safe "$STATE_DIR" || exit 0
  [ ! -L "$STATE_DIR" ] || exit 0
  mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
  path_components_are_safe "$STATE_DIR" && [ -d "$STATE_DIR" ] &&
    [ ! -L "$RETRY_MARKER" ] &&
    { [ ! -e "$RETRY_MARKER" ] || [ -f "$RETRY_MARKER" ]; } || exit 0
  _retry_tmp="$RETRY_MARKER.tmp.$$"
  [ ! -e "$_retry_tmp" ] && [ ! -L "$_retry_tmp" ] || exit 0
  ( umask 077; set -C; printf '%s\n' "$(date '+%m-%d %H:%M:%S' 2>/dev/null)" > "$_retry_tmp" ) 2>/dev/null || exit 0
  chmod 0600 "$_retry_tmp" 2>/dev/null &&
    mv -f "$_retry_tmp" "$RETRY_MARKER" 2>/dev/null || {
      [ -f "$_retry_tmp" ] && [ ! -L "$_retry_tmp" ] && rm -f "$_retry_tmp" 2>/dev/null || :
    }
  exit 0
}

path_components_are_safe "$APP_DIR" || exit 0
[ -d "$APP_DIR" ] && [ ! -L "$APP_DIR" ] || exit 0
[ -f "$APK_PATH" ] && [ ! -L "$APK_PATH" ] || exit 0
[ -f "$SUM_PATH" ] && [ ! -L "$SUM_PATH" ] || retry "overlay checksum sidecar is missing or unsafe"
command -v sha256sum >/dev/null 2>&1 || retry "sha256sum is unavailable; overlay digest cannot be verified"

_expected=$(awk 'NR==1 {print $1}' "$SUM_PATH" 2>/dev/null)
case "$_expected" in *[!0-9a-fA-F]*|'') retry "overlay checksum sidecar is malformed" ;; esac
[ "${#_expected}" -eq 64 ] || retry "overlay checksum sidecar has an invalid digest length"
_actual=$(sha256sum "$APK_PATH" 2>/dev/null | awk 'NR==1 {print $1}')
[ -n "$_actual" ] && [ "$_actual" = "$_expected" ] || retry "overlay APK digest does not match its checksum sidecar"

# The install hook writes this marker. If it could not (for example, recovery
# storage was temporarily unavailable), reconstruct it only from the verified
# APK and its packaged checksum; never trust an old or symlinked marker.
path_components_are_safe "$STATE_DIR" || retry "deployment state path contains a symlink"
mkdir -p "$STATE_DIR" 2>/dev/null || retry "cannot create deployment state directory"
path_components_are_safe "$STATE_DIR" && [ -d "$STATE_DIR" ] &&
  [ ! -L "$DEPLOYMENT_MARKER" ] &&
  { [ ! -e "$DEPLOYMENT_MARKER" ] || [ -f "$DEPLOYMENT_MARKER" ]; } ||
  retry "deployment state path is unsafe"
if [ -s "$DEPLOYMENT_MARKER" ]; then
  _recorded=$(awk 'NR==1 {print $1}' "$DEPLOYMENT_MARKER" 2>/dev/null)
  [ "$_recorded" = "$_actual" ] || retry "deployment marker does not match the mounted overlay"
else
  _marker_tmp="$DEPLOYMENT_MARKER.tmp.$$"
  [ ! -e "$_marker_tmp" ] && [ ! -L "$_marker_tmp" ] ||
    retry "deployment marker temporary path already exists or is unsafe"
  ( umask 077; set -C; printf '%s\n' "$_actual" > "$_marker_tmp" ) 2>/dev/null &&
    chmod 0600 "$_marker_tmp" 2>/dev/null &&
    mv -f "$_marker_tmp" "$DEPLOYMENT_MARKER" 2>/dev/null ||
    retry "cannot commit verified deployment marker"
fi

chown 0:0 "$APP_DIR" "$APK_PATH" 2>/dev/null || log "WARN: could not normalize system-app overlay ownership"
chmod 0755 "$APP_DIR" 2>/dev/null || log "WARN: could not normalize system-app directory mode"
chmod 0644 "$APK_PATH" "$SUM_PATH" 2>/dev/null || log "WARN: could not normalize APK/checksum mode"

if command -v restorecon >/dev/null 2>&1; then
  restorecon -RF "$APP_DIR" >/dev/null 2>&1 || log "WARN: restorecon could not label /system/app/FX"
fi

# Some recovery/KernelSU builds omit restorecon; use Android's standard
# system_file type as a best-effort fallback, never changing device policy.
_fx_context=$(ls -Zd "$APK_PATH" 2>/dev/null | awk '{print $1}')
case "$_fx_context" in
  u:object_r:system_file:s0) ;;
  *)
    if command -v chcon >/dev/null 2>&1; then
      chcon u:object_r:system_file:s0 "$APP_DIR" "$APK_PATH" 2>/dev/null ||
        log "WARN: SELinux system_file context could not be applied"
    else
      log "WARN: neither restorecon nor chcon could apply system_file context"
    fi
    ;;
esac

_fx_context=$(ls -Zd "$APK_PATH" 2>/dev/null | awk '{print $1}')
if [ "$_fx_context" = "u:object_r:system_file:s0" ]; then
  rm -f "$RETRY_MARKER" "$RETRY_MARKER.tmp."* 2>/dev/null || :
  log "OK: verified APK digest, deployment marker, ownership, mode and SELinux context"
else
  retry "system_file SELinux context is not active (context=${_fx_context:-unknown})"
fi
exit 0
# <<< fx-system-app-overlay-verify
