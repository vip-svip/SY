#!/system/bin/sh
# Verify and label the FX systemless APK overlay before PackageManager scans
# system applications. FX is a system app, not a privileged app.
set -u
APP_DIR=/system/app/FX
APK_PATH="$APP_DIR/FX.apk"
SUM_PATH="$APP_DIR/FX.apk.sha256"
STATE_DIR=/data/adb/privacyguard
LOG_DIR="$STATE_DIR/logs"
LOG_FILE="$LOG_DIR/system-app-overlay.log"
DEPLOYMENT_MARKER="$STATE_DIR/system-app-apk.sha256"
RETRY_MARKER="$STATE_DIR/system-app-retry"

log(){ mkdir -p "$LOG_DIR" 2>/dev/null || :; chmod 0700 "$LOG_DIR" 2>/dev/null || :; printf '%s\n' "$*" >> "$LOG_FILE" 2>/dev/null || :; }
retry(){ 
  log "RETRY: $*"
  mkdir -p "$STATE_DIR" 2>/dev/null || :
  ( umask 077; printf '%s\n' "$(date '+%m-%d %H:%M:%S' 2>/dev/null)" > "$RETRY_MARKER.tmp.$$" ) 2>/dev/null &&
    mv -f "$RETRY_MARKER.tmp.$$" "$RETRY_MARKER" 2>/dev/null || rm -f "$RETRY_MARKER.tmp.$$" 2>/dev/null || :
  exit 0
}

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
mkdir -p "$STATE_DIR" 2>/dev/null || retry "cannot create deployment state directory"
[ ! -L "$STATE_DIR" ] && [ ! -L "$DEPLOYMENT_MARKER" ] || retry "deployment state path is a symlink"
if [ -s "$DEPLOYMENT_MARKER" ]; then
  _recorded=$(awk 'NR==1 {print $1}' "$DEPLOYMENT_MARKER" 2>/dev/null)
  [ "$_recorded" = "$_actual" ] || retry "deployment marker does not match the mounted overlay"
else
  ( umask 077; printf '%s\n' "$_actual" > "$DEPLOYMENT_MARKER.tmp.$$" ) 2>/dev/null &&
    chmod 0600 "$DEPLOYMENT_MARKER.tmp.$$" 2>/dev/null &&
    mv -f "$DEPLOYMENT_MARKER.tmp.$$" "$DEPLOYMENT_MARKER" 2>/dev/null ||
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
