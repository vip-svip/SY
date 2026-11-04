#!/system/bin/sh
# Yulong Shield / Stellar authorization data manager.
set -eu
DIR=/data/local/tmp/stellar_guard
PKGS=$DIR/command_whitelist.txt
ALWAYS=$DIR/command_always_allow.txt
SCOPES=$DIR/scope_grants.txt
LOCK=$DIR/fx-stellar.lock
_STELLAR_TEMP=
if [ -e "$DIR" ] || [ -L "$DIR" ]; then
  [ -d "$DIR" ] && [ ! -L "$DIR" ] || { echo "Stellar data directory is not a safe directory" >&2; exit 40; }
else
  (umask 077; mkdir "$DIR") || { echo "cannot create Stellar data directory" >&2; exit 40; }
fi
chmod 0700 "$DIR"
secure_file(){
  path=$1
  [ ! -L "$path" ] || { echo "refusing symlinked Stellar state file: $path" >&2; return 1; }
  if [ -e "$path" ]; then
    [ -f "$path" ] || { echo "Stellar state path is not a regular file: $path" >&2; return 1; }
  else
    (umask 077; : > "$path") || return 1
  fi
  chmod 0600 "$path"
}
secure_file "$PKGS"
secure_file "$ALWAYS"
secure_file "$SCOPES"
secure_file "$DIR/action.log"
valid_pkg(){ printf '%s' "$1" | grep -Eq '^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$'; }
valid_scope(){ case "$1" in SHELL_ID_COMMAND|PACKAGE_LIST_COMMAND|PROCESS_LIST_COMMAND|PROPERTY_READ_COMMAND|SETTINGS_READ_COMMAND|SELINUX_STATUS_COMMAND|FILESYSTEM_READ_COMMAND|SERVICE_LIST_COMMAND|SECURE_SETTINGS_WRITE|APPOPS_MANAGE|RUNTIME_PERMISSION_MANAGE|TERMINAL_COMMAND) return 0 ;; *) return 1 ;; esac; }
valid_command(){
  # Commands are passed to sh -c below. Reject control characters before
  # matching the complete string so a valid first line cannot hide a second.
  if printf '%s' "$1" | LC_ALL=C grep -q '[[:cntrl:]]'; then return 1; fi
  case "$1" in
    getprop|id|id\ -u|whoami|ps|ps\ -A|ps\ -ef|getenforce|service\ list) return 0 ;;
  esac
  printf '%s' "$1" | LC_ALL=C grep -Eq '^(getprop [A-Za-z0-9_.-]{1,128}|pm list packages( -3|-s|-f|-U)?|cmd package list packages( -3|-s|-f|-U)?|dumpsys package [A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+|settings get (secure|global|system) [A-Za-z0-9_.-]{1,128}|cat /proc/(version|uptime)|cat /sys/fs/selinux/enforce|ls (/system|/product|/vendor|/apex|/proc|/sys)(/[A-Za-z0-9_.-]+)*)$'
}
with_lock(){
  n=0
  while ! mkdir "$LOCK" 2>/dev/null; do n=$((n+1)); [ "$n" -lt 20 ] || return 30; sleep 1; done
  cleanup_lock(){
    [ -z "$_STELLAR_TEMP" ] || rm -f "$_STELLAR_TEMP" 2>/dev/null || :
    _STELLAR_TEMP=
    rmdir "$LOCK" 2>/dev/null || :
  }
  # A signal must terminate into EXIT cleanup; do not release the lock and resume.
  trap cleanup_lock EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  "$@"
}
authorized_pkg(){ grep -Fxq "$1" "$PKGS"; }
has_scope(){ awk -F '\t' -v pkg="$1" -v scope="$2" '$1==pkg&&$2==scope{found=1} END{exit !found}' "$SCOPES"; }
has_always(){ awk -F '\t' -v pkg="$1" -v command="$2" '$1==pkg&&$2==command{found=1} END{exit !found}' "$ALWAYS"; }
valid_runtime_permission(){
  case "$1" in
    android.permission.CAMERA|android.permission.RECORD_AUDIO|android.permission.ACCESS_FINE_LOCATION|android.permission.ACCESS_COARSE_LOCATION|android.permission.ACCESS_BACKGROUND_LOCATION|android.permission.READ_CONTACTS|android.permission.WRITE_CONTACTS|android.permission.GET_ACCOUNTS|android.permission.READ_CALENDAR|android.permission.WRITE_CALENDAR|android.permission.READ_CALL_LOG|android.permission.WRITE_CALL_LOG|android.permission.CALL_PHONE|android.permission.READ_PHONE_STATE|android.permission.READ_PHONE_NUMBERS|android.permission.ANSWER_PHONE_CALLS|android.permission.ADD_VOICEMAIL|android.permission.USE_SIP|android.permission.BODY_SENSORS|android.permission.BODY_SENSORS_BACKGROUND|android.permission.SEND_SMS|android.permission.RECEIVE_SMS|android.permission.READ_SMS|android.permission.RECEIVE_WAP_PUSH|android.permission.RECEIVE_MMS|android.permission.POST_NOTIFICATIONS|android.permission.READ_MEDIA_IMAGES|android.permission.READ_MEDIA_VIDEO|android.permission.READ_MEDIA_AUDIO|android.permission.READ_MEDIA_VISUAL_USER_SELECTED|android.permission.NEARBY_WIFI_DEVICES|android.permission.BLUETOOTH_SCAN|android.permission.BLUETOOTH_CONNECT|android.permission.BLUETOOTH_ADVERTISE|android.permission.ACTIVITY_RECOGNITION|android.permission.ACCESS_MEDIA_LOCATION) return 0 ;;
    *) return 1 ;;
  esac
}
valid_appop(){
  case "$1" in
    CAMERA|RECORD_AUDIO|FINE_LOCATION|COARSE_LOCATION|BACKGROUND_LOCATION|READ_CONTACTS|WRITE_CONTACTS|READ_SMS|SEND_SMS|READ_CALL_LOG|CALL_PHONE|READ_PHONE_STATE|POST_NOTIFICATION|SYSTEM_ALERT_WINDOW|WRITE_SETTINGS|GET_USAGE_STATS|READ_CLIPBOARD|READ_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE|READ_MEDIA_IMAGES|READ_MEDIA_VIDEO|READ_MEDIA_AUDIO|NEARBY_WIFI_DEVICES|BLUETOOTH_SCAN|BLUETOOTH_CONNECT|BLUETOOTH_ADVERTISE) return 0 ;;
    *) return 1 ;;
  esac
}
valid_appop_mode(){ case "$1" in allow|ignore|deny|default|foreground) return 0 ;; *) return 1 ;; esac; }
append_action_log(){
  line=$1
  [ -f "$DIR/action.log" ] && [ ! -L "$DIR/action.log" ] || return 1
  tmp=$(mktemp "$DIR/action.log.XXXXXX") || return 1
  tail -n 499 "$DIR/action.log" > "$tmp" || { rm -f "$tmp"; return 1; }
  printf '%s\n' "$line" >> "$tmp" || { rm -f "$tmp"; return 1; }
  if [ -f "$tmp" ] && [ ! -L "$tmp" ] && chmod 0600 "$tmp" \
      && [ -f "$DIR/action.log" ] && [ ! -L "$DIR/action.log" ] \
      && mv -f "$tmp" "$DIR/action.log"; then return 0; fi
  rm -f "$tmp"; return 1
}
read_action_log(){
  [ -f "$DIR/action.log" ] && [ ! -L "$DIR/action.log" ] || { echo "Stellar action log is missing or unsafe" >&2; return 21; }
  [ -s "$DIR/action.log" ] || { echo FXSTELLARLOG_EMPTY; return 0; }
  echo FXSTELLARLOG1
  tail -n 200 "$DIR/action.log"
}
clear_action_log(){
  [ -f "$DIR/action.log" ] && [ ! -L "$DIR/action.log" ] || { echo "Stellar action log is missing or unsafe" >&2; return 21; }
  tmp=$(mktemp "$DIR/action.log.clear.XXXXXX") || return 1
  if [ -f "$tmp" ] && [ ! -L "$tmp" ] && chmod 0600 "$tmp" \
      && [ -f "$DIR/action.log" ] && [ ! -L "$DIR/action.log" ] \
      && mv -f "$tmp" "$DIR/action.log"; then echo "cleared=1"; return 0; fi
  rm -f "$tmp"; return 1
}
permission_action(){
  pkg=$1; action=$2; permission=$3
  valid_pkg "$pkg" && valid_runtime_permission "$permission" || { echo "permission or package is not in the safe runtime allowlist" >&2; return 2; }
  authorized_pkg "$pkg" || { echo "target app is not authorized in Stellar" >&2; return 3; }
  has_scope "$pkg" RUNTIME_PERMISSION_MANAGE || { echo "RUNTIME_PERMISSION_MANAGE scope is required" >&2; return 4; }
  case "$action" in grant|revoke) ;; *) return 2 ;; esac
  pm path "$pkg" >/dev/null 2>&1 || { echo "target package is not installed" >&2; return 5; }
  if [ "$action" = grant ]; then pm grant "$pkg" "$permission" || return $?; else pm revoke "$pkg" "$permission" || return $?; fi
  log_entry=$(printf '[%s] permission %s %s %s' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$action" "$pkg" "$permission")
  append_action_log "$log_entry" || echo "warning: operation succeeded but audit log update failed" >&2
  unset log_entry
  echo "success=1 action=$action package=$pkg permission=$permission"
}
appops_action(){
  pkg=$1; operation=$2; mode=$3
  valid_pkg "$pkg" && valid_appop "$operation" && valid_appop_mode "$mode" || { echo "AppOps request is not in the safe allowlist" >&2; return 2; }
  authorized_pkg "$pkg" || { echo "target app is not authorized in Stellar" >&2; return 3; }
  has_scope "$pkg" APPOPS_MANAGE || { echo "APPOPS_MANAGE scope is required" >&2; return 4; }
  pm path "$pkg" >/dev/null 2>&1 || { echo "target package is not installed" >&2; return 5; }
  if command -v cmd >/dev/null 2>&1; then cmd appops set "$pkg" "$operation" "$mode" || return $?
  elif command -v appops >/dev/null 2>&1; then appops set "$pkg" "$operation" "$mode" || return $?
  else echo "AppOps command is unavailable" >&2; return 6; fi
  log_entry=$(printf '[%s] appops %s %s %s' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$pkg" "$operation" "$mode")
  append_action_log "$log_entry" || echo "warning: operation succeeded but audit log update failed" >&2
  unset log_entry
  echo "success=1 package=$pkg appop=$operation mode=$mode"
}
restore_secure_setting(){
  _restore_key="$1"; _restore_value="$2"
  if [ "$_restore_value" = "null" ]; then
    settings delete secure "$_restore_key" >/dev/null 2>&1 || return 1
  else
    settings put secure "$_restore_key" "$_restore_value" >/dev/null 2>&1 || return 1
  fi
  _restored_value="$(settings get secure "$_restore_key" 2>/dev/null)" || return 1
  [ -n "$_restored_value" ] || _restored_value=null
  [ "$_restored_value" = "$_restore_value" ]
}
secure_setting_action(){
  pkg="$1"; key="$2"; value="$3"
  valid_pkg "$pkg" || { echo "invalid target package" >&2; return 2; }
  authorized_pkg "$pkg" || { echo "target app is not authorized in Stellar" >&2; return 3; }
  has_scope "$pkg" SECURE_SETTINGS_WRITE || { echo "SECURE_SETTINGS_WRITE scope is required" >&2; return 4; }
  case "$key:$value" in
    show_ime_with_hard_keyboard:0|show_ime_with_hard_keyboard:1|screensaver_enabled:0|screensaver_enabled:1) ;;
    long_press_timeout:*)
      case "$value" in ''|*[!0-9]*) echo "long_press_timeout must be numeric" >&2; return 2 ;; esac
      [ "$value" -ge 100 ] && [ "$value" -le 1000 ] || {
        echo "long_press_timeout must be between 100 and 1000 milliseconds" >&2; return 2;
      }
      ;;
    *)
      echo "secure setting is not in the fixed safe allowlist" >&2
      return 2
      ;;
  esac
  if ! previous="$(settings get secure "$key" 2>/dev/null)"; then
    echo "secure setting prior value could not be read; no write was attempted" >&2
    return 5
  fi
  [ -n "$previous" ] || previous=null

  if ! settings put secure "$key" "$value"; then
    if restore_secure_setting "$key" "$previous"; then
      echo "secure setting write failed; previous value was restored" >&2
      return 6
    fi
    echo "secure setting write failed and previous value rollback could not be verified" >&2
    return 8
  fi
  actual="$(settings get secure "$key" 2>/dev/null || true)"
  if [ "$actual" != "$value" ]; then
    if restore_secure_setting "$key" "$previous"; then
      echo "secure setting write could not be confirmed; previous value was restored" >&2
      return 7
    fi
    echo "secure setting write could not be confirmed and rollback failed" >&2
    return 8
  fi
  log_entry=$(printf '[%s] secure-setting %s=%s by %s' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$key" "$value" "$pkg")
  append_action_log "$log_entry" || echo "warning: operation succeeded but audit log update failed" >&2
  unset log_entry
  echo "success=1 package=$pkg secure_setting=$key value=$actual"
}
run_readonly(){
  pkg="$1"; scope="$2"; command="$3"
  valid_pkg "$pkg" && valid_scope "$scope" && valid_command "$command" || { echo "invalid read-only command or scope" >&2; return 2; }
  authorized_pkg "$pkg" || { echo "target app has not been authorized" >&2; return 3; }
  case "$scope" in SHELL_ID_COMMAND|PACKAGE_LIST_COMMAND|PROCESS_LIST_COMMAND|PROPERTY_READ_COMMAND|SETTINGS_READ_COMMAND|SELINUX_STATUS_COMMAND|FILESYSTEM_READ_COMMAND|SERVICE_LIST_COMMAND) ;; *) echo "scope is not a read-only query scope" >&2; return 4 ;; esac
  has_scope "$pkg" "$scope" || { echo "required Stellar capability is not granted" >&2; return 5; }
  has_always "$pkg" "$command" || { echo "command is not in this app's always-allow list" >&2; return 6; }
  sh -c "$command"
}
# Create an unpredictable same-directory file and retain it for the lock's
# EXIT cleanup. Re-check both paths immediately before the atomic rename.
begin_state_temp(){
  file=$1
  [ -f "$file" ] && [ ! -L "$file" ] || {
    echo "Stellar state file changed or became unsafe: $file" >&2
    return 1
  }
  _STELLAR_TEMP=$(mktemp "$file.fx.XXXXXX") || { _STELLAR_TEMP=; return 1; }
  [ -f "$_STELLAR_TEMP" ] && [ ! -L "$_STELLAR_TEMP" ] || {
    rm -f "$_STELLAR_TEMP"; _STELLAR_TEMP=; return 1;
  }
  chmod 0600 "$_STELLAR_TEMP" || {
    rm -f "$_STELLAR_TEMP"; _STELLAR_TEMP=; return 1;
  }
}
commit_state_temp(){
  file=$1
  tmp=$_STELLAR_TEMP
  [ -n "$tmp" ] && [ -f "$tmp" ] && [ ! -L "$tmp" ] \
    && [ -f "$file" ] && [ ! -L "$file" ] \
    && chmod 0600 "$tmp" && mv -f "$tmp" "$file" || {
      echo "Stellar atomic state replacement failed: $file" >&2
      return 1
    }
  _STELLAR_TEMP=
  return 0
}
mutate_file(){
  file=$1; mode=$2; pkg=$3; value=$4
  begin_state_temp "$file" || return 1
  awk -F '\t' -v OFS='\t' -v mode="$mode" -v pkg="$pkg" -v value="$value" '
    BEGIN{done=0}
    $1==pkg && (NF==1 || $2==value) {
      if(mode=="remove") next
      if(!done){print pkg,value;done=1}
      next
    }
    {print}
    END{if(mode=="add"&&!done)print pkg,value}
  ' "$file" > "$_STELLAR_TEMP" || return 1
  commit_state_temp "$file"
}
set_pkg(){
  pkg=$1; on=$2
  if [ "$on" = 1 ]; then
    if ! grep -Fxq "$pkg" "$PKGS"; then
      begin_state_temp "$PKGS" || return 1
      cat "$PKGS" > "$_STELLAR_TEMP" || return 1
      printf '%s\n' "$pkg" >> "$_STELLAR_TEMP" || return 1
      commit_state_temp "$PKGS" || return 1
    fi
  else
    # Drop dependent grants before removing package authorization. If an
    # intermediate write fails, the target is left with fewer privileges,
    # never with an authorized package whose old scopes can be revived later.
    for file in "$ALWAYS" "$SCOPES"; do
      begin_state_temp "$file" || return 1
      awk -F '\t' -v pkg="$pkg" '$1!=pkg{print}' "$file" > "$_STELLAR_TEMP" || return 1
      commit_state_temp "$file" || return 1
    done
    begin_state_temp "$PKGS" || return 1
    awk -v pkg="$pkg" '$0!=pkg{print}' "$PKGS" > "$_STELLAR_TEMP" || return 1
    commit_state_temp "$PKGS"
  fi
}
BOOT_SCRIPT=/data/adb/service.d/stellar.sh
FX_PACKAGE=de.privacyguard.adhook
DROP_PREFS_FILE=/data/user_de/0/de.privacyguard.adhook/shared_prefs/settings.xml

read_drop_privileges(){
  [ ! -L "$DROP_PREFS_FILE" ] || { echo "drop_privileges settings path is a symlink" >&2; return 34; }
  if [ ! -e "$DROP_PREFS_FILE" ]; then echo 0; return 0; fi
  [ -f "$DROP_PREFS_FILE" ] || { echo "drop_privileges settings path is not a regular file" >&2; return 34; }
  if grep -Fq 'name="drop_privileges"' "$DROP_PREFS_FILE"; then
    if grep -Eq '<boolean name="drop_privileges" value="true"[[:space:]]*/>' "$DROP_PREFS_FILE"; then echo 1; return 0; fi
    if grep -Eq '<boolean name="drop_privileges" value="false"[[:space:]]*/>' "$DROP_PREFS_FILE"; then echo 0; return 0; fi
    echo "drop_privileges setting is malformed; refusing launcher startup" >&2
    return 34
  else
    rc=$?
    [ "$rc" -eq 1 ] || { echo "cannot read drop_privileges settings" >&2; return 34; }
    echo 0
    return 0
  fi
}

find_native_helper(){
  wanted=$1
  result=""
  for candidate in "$apk_dir"/lib/*/"$wanted"; do
    [ -f "$candidate" ] && [ ! -L "$candidate" ] && [ -x "$candidate" ] || continue
    result="$candidate"
    break
  done
  [ -n "$result" ] || return 1
  printf '%s\n' "$result"
}

boot_script(){
  action="$1"
  case "$action" in
    status)
      drop_privileges=$(read_drop_privileges) || return $?
      if [ -f "$BOOT_SCRIPT" ] && [ ! -L "$BOOT_SCRIPT" ] && [ -x "$BOOT_SCRIPT" ] \
          && grep -Fq '# FX_STELLAR_BOOT_SCRIPT_V1' "$BOOT_SCRIPT"; then
        echo "success=1 boot_script=installed drop_privileges=$drop_privileges path=$BOOT_SCRIPT"
      elif [ -f "$BOOT_SCRIPT" ] && [ ! -L "$BOOT_SCRIPT" ] \
          && grep -Fq 'pm path com.youlong.hd' "$BOOT_SCRIPT"; then
        echo "success=1 boot_script=legacy drop_privileges=$drop_privileges path=$BOOT_SCRIPT"
      elif [ ! -e "$BOOT_SCRIPT" ]; then
        echo "success=1 boot_script=absent drop_privileges=$drop_privileges path=$BOOT_SCRIPT"
      else
        echo "boot script exists but is not recognized; refusing to treat it as FX-managed" >&2
        return 33
      fi
      ;;
    install)
      [ -d /data/adb ] || { echo "KernelSU/Magisk data directory is unavailable" >&2; return 20; }
      apk_path=$(pm path "$FX_PACKAGE" 2>/dev/null | sed -n '1s/^package://p')
      [ -n "$apk_path" ] && [ "${apk_path%/base.apk}" != "$apk_path" ] || {
        echo "FX Hook base APK was not found; boot script was not installed" >&2
        return 21
      }
      apk_dir=${apk_path%/base.apk}
      drop_privileges=$(read_drop_privileges) || return $?
      found=$(find_native_helper libstellar.so) || found=""
      [ -n "$found" ] || {
        echo "FX Hook libstellar.so is missing or not executable; boot script was not installed" >&2
        return 22
      }
      if [ "$drop_privileges" = 1 ]; then
        chid=$(find_native_helper libchid.so) || chid=""
        [ -n "$chid" ] || {
          echo "drop_privileges is enabled but FX Hook libchid.so is missing or not executable; boot script was not installed" >&2
          return 23
        }
      fi
      mkdir -p /data/adb/service.d || return 23
      [ ! -L /data/adb/service.d ] || {
        echo "service.d is a symlink; refusing to write boot script" >&2
        return 24
      }
      [ ! -L /data/adb ] && [ ! -L /data/adb/service.d ] || {
        echo "KernelSU/Magisk service.d path contains a symlink; refusing to write boot script" >&2
        return 24
      }
      if [ -e "$BOOT_SCRIPT" ] && ! grep -Fq '# FX_STELLAR_BOOT_SCRIPT_V1' "$BOOT_SCRIPT" \
          && ! grep -Fq 'pm path com.youlong.hd' "$BOOT_SCRIPT"; then
        echo "existing boot script is not FX-managed or a recognized legacy Stellar script; refusing to overwrite" >&2
        return 33
      fi
      boot_tmp=$(mktemp /data/adb/service.d/.stellar.sh.fx.XXXXXX) || return 25
      if ! cat > "$boot_tmp" <<'FX_STELLAR_BOOT_SCRIPT'
#!/system/bin/sh
# FX_STELLAR_BOOT_SCRIPT_V1
# Wait for Android's package manager and boot properties, but never block
# the service.d runner indefinitely if the boot sequence is incomplete.
DROP_PREFS_FILE=/data/user_de/0/de.privacyguard.adhook/shared_prefs/settings.xml
LOG=/data/local/tmp/fx_stellar_boot.log
exec >> "$LOG" 2>&1
echo "[FX Stellar] boot script started"
i=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
  i=$((i+1))
  [ "$i" -lt 100 ] || { echo "[FX Stellar] boot completion timeout"; exit 124; }
  sleep 3
done
APK_PATH=$(pm path de.privacyguard.adhook 2>/dev/null | sed -n '1s/^package://p')
[ -n "$APK_PATH" ] || { echo "[FX Stellar] FX Hook package is not installed"; exit 20; }
APK_DIR=${APK_PATH%/base.apk}
LIB=""
for CANDIDATE in "$APK_DIR"/lib/*/libstellar.so; do
  [ -f "$CANDIDATE" ] && [ ! -L "$CANDIDATE" ] && [ -x "$CANDIDATE" ] || continue
  LIB="$CANDIDATE"
  break
done
[ -n "$LIB" ] || { echo "[FX Stellar] executable libstellar.so was not found"; exit 21; }
DROP_PRIVILEGES=0
if [ -L "$DROP_PREFS_FILE" ]; then
  echo "[FX Stellar] drop_privileges settings path is a symlink; refusing startup"
  exit 34
elif [ -e "$DROP_PREFS_FILE" ]; then
  [ -f "$DROP_PREFS_FILE" ] || { echo "[FX Stellar] drop_privileges settings is not a regular file"; exit 34; }
  if grep -Fq 'name="drop_privileges"' "$DROP_PREFS_FILE"; then
    if grep -Eq '<boolean name="drop_privileges" value="true"[[:space:]]*/>' "$DROP_PREFS_FILE"; then
      DROP_PRIVILEGES=1
    elif grep -Eq '<boolean name="drop_privileges" value="false"[[:space:]]*/>' "$DROP_PREFS_FILE"; then
      DROP_PRIVILEGES=0
    else
      echo "[FX Stellar] drop_privileges setting is malformed; refusing startup"
      exit 34
    fi
  else
    rc=$?
    [ "$rc" -eq 1 ] || { echo "[FX Stellar] cannot read drop_privileges setting"; exit 34; }
  fi
fi
echo "[FX Stellar] launching $LIB drop_privileges=$DROP_PRIVILEGES"
if [ "$DROP_PRIVILEGES" = 1 ]; then
  CHID=""
  for CANDIDATE in "$APK_DIR"/lib/*/libchid.so; do
    [ -f "$CANDIDATE" ] && [ ! -L "$CANDIDATE" ] && [ -x "$CANDIDATE" ] || continue
    CHID="$CANDIDATE"
    break
  done
  [ -n "$CHID" ] || { echo "[FX Stellar] drop_privileges is enabled but libchid.so is missing; refusing root fallback"; exit 22; }
  "$CHID" 2000 "$LIB"
else
  "$LIB"
fi
RESULT=$?
echo "[FX Stellar] launcher exited with code $RESULT"
exit "$RESULT"
FX_STELLAR_BOOT_SCRIPT
      then
        rm -f "$boot_tmp"
        return 26
      fi
      chmod 0755 "$boot_tmp" || { rm -f "$boot_tmp"; return 27; }
      grep -Fq '# FX_STELLAR_BOOT_SCRIPT_V1' "$boot_tmp" || { rm -f "$boot_tmp"; return 28; }
      mv -f "$boot_tmp" "$BOOT_SCRIPT" || { rm -f "$boot_tmp"; return 29; }
      [ -x "$BOOT_SCRIPT" ] || return 30
      echo "success=1 boot_script=installed path=$BOOT_SCRIPT"
      ;;
    remove)
      [ ! -L "$BOOT_SCRIPT" ] || {
        echo "existing boot script path is a symlink; refusing to remove it" >&2
        return 24
      }
      if [ -e "$BOOT_SCRIPT" ] && ! grep -Fq '# FX_STELLAR_BOOT_SCRIPT_V1' "$BOOT_SCRIPT" \
          && ! grep -Fq 'pm path com.youlong.hd' "$BOOT_SCRIPT"; then
        echo "existing boot script is not FX-managed or a recognized legacy Stellar script; refusing to remove it" >&2
        return 33
      fi
      rm -f "$BOOT_SCRIPT" || return 31
      [ ! -e "$BOOT_SCRIPT" ] || return 32
      echo "success=1 boot_script=removed path=$BOOT_SCRIPT"
      ;;
    *)
      echo "unsupported boot-script operation" >&2
      return 2
      ;;
  esac
}

cmd="$1"
case "$cmd" in
  boot-script)
    [ "$#" -eq 2 ] || exit 2
    with_lock boot_script "$2"
    ;;
  logs)
    [ "$#" -eq 1 ] || exit 2
    with_lock read_action_log
    ;;
  clear-logs)
    [ "$#" -eq 1 ] || exit 2
    with_lock clear_action_log
    ;;
  list)
    echo STELLARFX1
    while IFS= read -r p; do [ -n "$p" ] && valid_pkg "$p" && echo "PKG|$p"; done < "$PKGS"
    while IFS="$(printf '\t')" read -r p v; do
      [ -n "$p" ] && [ -n "$v" ] && valid_pkg "$p" && valid_scope "$v" && echo "SCOPE|$p|$v"
    done < "$SCOPES"
    while IFS="$(printf '\t')" read -r p v; do
      [ -n "$p" ] && [ -n "$v" ] && valid_pkg "$p" && valid_command "$v" && echo "ALWAYS|$p|$v"
    done < "$ALWAYS"
    ;;
  pkg-set)
    [ "$#" -eq 3 ] && valid_pkg "$2" && { [ "$3" = 0 ] || [ "$3" = 1 ]; } || exit 2
    with_lock set_pkg "$2" "$3"
    ;;
  scope-set)
    [ "$#" -eq 4 ] && valid_pkg "$2" && valid_scope "$3" && { [ "$4" = 0 ] || { [ "$4" = 1 ] && [ "$3" != "TERMINAL_COMMAND" ]; }; } || exit 2
    if [ "$4" = 1 ]; then authorized_pkg "$2" || { echo "authorize package first" >&2; exit 3; }; fi
    with_lock mutate_file "$SCOPES" "$([ "$4" = 1 ] && echo add || echo remove)" "$2" "$3"
    ;;
  always-set)
    [ "$#" -eq 4 ] && valid_pkg "$2" && valid_command "$3" && { [ "$4" = 0 ] || [ "$4" = 1 ]; } || exit 2
    [ "$4" = 0 ] || authorized_pkg "$2" || { echo "authorize package first" >&2; exit 3; }
    with_lock mutate_file "$ALWAYS" "$([ "$4" = 1 ] && echo add || echo remove)" "$2" "$3"
    ;;
  permission)
    [ "$#" -eq 4 ] || exit 2
    with_lock permission_action "$2" "$3" "$4"
    ;;
  appops)
    [ "$#" -eq 4 ] || exit 2
    with_lock appops_action "$2" "$3" "$4"
    ;;
  secure-setting)
    [ "$#" -eq 4 ] || exit 2
    with_lock secure_setting_action "$2" "$3" "$4"
    ;;
  run)
    [ "$#" -eq 4 ] || exit 2
    run_readonly "$2" "$3" "$4"
    ;;
  *) exit 2 ;;
esac
