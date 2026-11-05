#!/system/bin/sh
# Apply Android's path-derived system_file label to the systemless FX APK before
# PackageManager scans system applications. This app is not a privileged app.
set -u
APP_DIR=/system/app/FX
APK_PATH="$APP_DIR/FX.apk"
LOG_DIR=/data/adb/privacyguard/logs
LOG_FILE="$LOG_DIR/system-app-overlay.log"
log(){ mkdir -p "$LOG_DIR" 2>/dev/null || :; chmod 0700 "$LOG_DIR" 2>/dev/null || :; printf '%s\n' "$*" >> "$LOG_FILE" 2>/dev/null || :; }
[ -d "$APP_DIR" ] && [ ! -L "$APP_DIR" ] || exit 0
[ -f "$APK_PATH" ] && [ ! -L "$APK_PATH" ] || exit 0

chown 0:0 "$APP_DIR" "$APK_PATH" 2>/dev/null || log "WARN: could not normalize system-app overlay ownership"
chmod 0755 "$APP_DIR" 2>/dev/null || log "WARN: could not normalize system-app directory mode"
chmod 0644 "$APK_PATH" 2>/dev/null || log "WARN: could not normalize APK mode"

if command -v restorecon >/dev/null 2>&1; then
  restorecon -RF "$APP_DIR" >/dev/null 2>&1 || log "WARN: restorecon could not label /system/app/FX"
fi

# Some recovery/KernelSU builds omit restorecon; use the standard Android
# system_file type as a best-effort fallback, never changing the device policy.
if command -v ls >/dev/null 2>&1; then
  _fx_context=$(ls -Zd "$APK_PATH" 2>/dev/null | awk '{print $1}')
  case "$_fx_context" in
    u:object_r:system_file:s0) ;;
    *)
      if command -v chcon >/dev/null 2>&1; then
        chcon u:object_r:system_file:s0 "$APP_DIR" "$APK_PATH" 2>/dev/null \
          || log "WARN: SELinux system_file context could not be applied"
      else
        log "WARN: neither restorecon nor chcon could apply system_file context"
      fi
      ;;
  esac
fi

_fx_context=$(ls -Zd "$APK_PATH" 2>/dev/null | awk '{print $1}')
if [ "$_fx_context" = "u:object_r:system_file:s0" ]; then
  log "OK: system app overlay ownership, mode and SELinux context verified"
else
  log "WARN: system app overlay context remains ${_fx_context:-unknown}; PackageManager visibility may require device-specific policy"
fi
exit 0
