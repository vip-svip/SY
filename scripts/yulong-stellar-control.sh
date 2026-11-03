#!/system/bin/sh
# Yulong Shield / Stellar authorization data manager.
set -eu
DIR=/data/local/tmp/stellar_guard
PKGS=$DIR/command_whitelist.txt
ALWAYS=$DIR/command_always_allow.txt
SCOPES=$DIR/scope_grants.txt
LOCK=$DIR/fx-stellar.lock
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
  # Commands are later passed to sh -c. Never let grep's per-line matching
  # accept a valid first line while hiding injected commands on later lines.
  # The fixed command grammar needs no control characters (including tabs).
  if printf '%s' "$1" | LC_ALL=C grep -q '[[:cntrl:]]'; then return 1; fi
  case "$1" in
    getprop|id|id\ -u|whoami|ps|ps\ -A|ps\ -ef|getenforce|service\ list) return 0 ;;
  esac
  printf '%s' "$1" | LC_ALL=C grep -Eq '^(getprop [A-Za-z0-9_.-]{1,128}|pm list packages( -3|-s|-f|-U)?|cmd package list packages( -3|-s|-f|-U)?|dumpsys package [A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+|settings get (secure|global|system) [A-Za-z0-9_.-]{1,128}|cat /proc/(version|uptime)|cat /sys/fs/selinux/enforce|ls (/system|/product|/vendor|/apex|/proc|/sys)(/[A-Za-z0-9_.-]+)*)
with_lock(){
  n=0
  while ! mkdir "$LOCK" 2>/dev/null; do n=$((n+1)); [ "$n" -lt 20 ] || return 30; sleep 1; done
  cleanup_lock(){ rmdir "$LOCK" 2>/dev/null || :; }
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
permission_action(){
  pkg=$1; action=$2; permission=$3
  valid_pkg "$pkg" && valid_runtime_permission "$permission" || { echo "permission or package is not in the safe runtime allowlist" >&2; return 2; }
  authorized_pkg "$pkg" || { echo "target app is not authorized in Stellar" >&2; return 3; }
  has_scope "$pkg" RUNTIME_PERMISSION_MANAGE || { echo "RUNTIME_PERMISSION_MANAGE scope is required" >&2; return 4; }
  case "$action" in grant|revoke) ;; *) return 2 ;; esac
  pm path "$pkg" >/dev/null 2>&1 || { echo "target package is not installed" >&2; return 5; }
  if [ "$action" = grant ]; then pm grant "$pkg" "$permission" || return $?; else pm revoke "$pkg" "$permission" || return $?; fi
  printf '[%s] permission %s %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$action" "$pkg" "$permission" >> "$DIR/action.log"
  chmod 0600 "$DIR/action.log" 2>/dev/null || :
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
  printf '[%s] appops %s %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$pkg" "$operation" "$mode" >> "$DIR/action.log"
  chmod 0600 "$DIR/action.log" 2>/dev/null || :
  echo "success=1 package=$pkg appop=$operation mode=$mode"
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
  settings put secure "$key" "$value" || return $?
  actual="$(settings get secure "$key" 2>/dev/null || true)"
  [ "$actual" = "$value" ] || { echo "secure setting write could not be confirmed" >&2; return 7; }
  printf '[%s] secure-setting %s=%s by %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$key" "$value" "$pkg" >> "$DIR/action.log"
  chmod 0600 "$DIR/action.log" 2>/dev/null || :
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
mutate_file(){
  file=$1; mode=$2; pkg=$3; value=$4; tmp=$file.tmp.$$
  awk -F '\t' -v OFS='\t' -v mode="$mode" -v pkg="$pkg" -v value="$value" '
    BEGIN{done=0}
    $1==pkg && (NF==1 || $2==value) {
      if(mode=="remove") next
      if(!done){print pkg,value;done=1}
      next
    }
    {print}
    END{if(mode=="add"&&!done)print pkg,value}
  ' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 0600 "$tmp" && mv -f "$tmp" "$file"
}
set_pkg(){
  pkg=$1; on=$2; tmp=$PKGS.tmp.$$
  if [ "$on" = 1 ]; then
    grep -Fxq "$pkg" "$PKGS" || { cat "$PKGS" > "$tmp"; printf '%s\n' "$pkg" >> "$tmp"; chmod 0600 "$tmp"; mv -f "$tmp" "$PKGS"; }
  else
    grep -Fxv "$pkg" "$PKGS" > "$tmp" || :
    chmod 0600 "$tmp"; mv -f "$tmp" "$PKGS"
    for file in "$ALWAYS" "$SCOPES"; do
      tmp2=$file.tmp.$$
      awk -F '\t' -v pkg="$pkg" '$1!=pkg{print}' "$file" > "$tmp2"
      chmod 0600 "$tmp2"; mv -f "$tmp2" "$file"
    done
  fi
}
cmd="$1"
case "$cmd" in
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

}
with_lock(){
  n=0
  while ! mkdir "$LOCK" 2>/dev/null; do n=$((n+1)); [ "$n" -lt 20 ] || return 30; sleep 1; done
  cleanup_lock(){ rmdir "$LOCK" 2>/dev/null || :; }
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
permission_action(){
  pkg=$1; action=$2; permission=$3
  valid_pkg "$pkg" && valid_runtime_permission "$permission" || { echo "permission or package is not in the safe runtime allowlist" >&2; return 2; }
  authorized_pkg "$pkg" || { echo "target app is not authorized in Stellar" >&2; return 3; }
  has_scope "$pkg" RUNTIME_PERMISSION_MANAGE || { echo "RUNTIME_PERMISSION_MANAGE scope is required" >&2; return 4; }
  case "$action" in grant|revoke) ;; *) return 2 ;; esac
  pm path "$pkg" >/dev/null 2>&1 || { echo "target package is not installed" >&2; return 5; }
  if [ "$action" = grant ]; then pm grant "$pkg" "$permission" || return $?; else pm revoke "$pkg" "$permission" || return $?; fi
  printf '[%s] permission %s %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$action" "$pkg" "$permission" >> "$DIR/action.log"
  chmod 0600 "$DIR/action.log" 2>/dev/null || :
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
  printf '[%s] appops %s %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$pkg" "$operation" "$mode" >> "$DIR/action.log"
  chmod 0600 "$DIR/action.log" 2>/dev/null || :
  echo "success=1 package=$pkg appop=$operation mode=$mode"
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
  settings put secure "$key" "$value" || return $?
  actual="$(settings get secure "$key" 2>/dev/null || true)"
  [ "$actual" = "$value" ] || { echo "secure setting write could not be confirmed" >&2; return 7; }
  printf '[%s] secure-setting %s=%s by %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$key" "$value" "$pkg" >> "$DIR/action.log"
  chmod 0600 "$DIR/action.log" 2>/dev/null || :
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
mutate_file(){
  file=$1; mode=$2; pkg=$3; value=$4; tmp=$file.tmp.$$
  awk -F '\t' -v OFS='\t' -v mode="$mode" -v pkg="$pkg" -v value="$value" '
    BEGIN{done=0}
    $1==pkg && (NF==1 || $2==value) {
      if(mode=="remove") next
      if(!done){print pkg,value;done=1}
      next
    }
    {print}
    END{if(mode=="add"&&!done)print pkg,value}
  ' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 0600 "$tmp" && mv -f "$tmp" "$file"
}
set_pkg(){
  pkg=$1; on=$2; tmp=$PKGS.tmp.$$
  if [ "$on" = 1 ]; then
    grep -Fxq "$pkg" "$PKGS" || { cat "$PKGS" > "$tmp"; printf '%s\n' "$pkg" >> "$tmp"; chmod 0600 "$tmp"; mv -f "$tmp" "$PKGS"; }
  else
    grep -Fxv "$pkg" "$PKGS" > "$tmp" || :
    chmod 0600 "$tmp"; mv -f "$tmp" "$PKGS"
    for file in "$ALWAYS" "$SCOPES"; do
      tmp2=$file.tmp.$$
      awk -F '\t' -v pkg="$pkg" '$1!=pkg{print}' "$file" > "$tmp2"
      chmod 0600 "$tmp2"; mv -f "$tmp2" "$file"
    done
  fi
}
cmd="$1"
case "$cmd" in
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
