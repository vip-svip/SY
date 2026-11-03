#!/system/bin/sh
# Yulong Shield / Stellar authorization data manager.
set -eu
DIR=/data/local/tmp/stellar_guard
PKGS=$DIR/command_whitelist.txt
ALWAYS=$DIR/command_always_allow.txt
SCOPES=$DIR/scope_grants.txt
LOCK=$DIR/fx-stellar.lock
mkdir -p "$DIR"
touch "$PKGS" "$ALWAYS" "$SCOPES"
chmod 0600 "$PKGS" "$ALWAYS" "$SCOPES"
valid_pkg(){ printf '%s' "$1" | grep -Eq '^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$'; }
valid_scope(){ case "$1" in SHELL_ID_COMMAND|PACKAGE_LIST_COMMAND|PROCESS_LIST_COMMAND|PROPERTY_READ_COMMAND|SETTINGS_READ_COMMAND|SELINUX_STATUS_COMMAND|FILESYSTEM_READ_COMMAND|SERVICE_LIST_COMMAND|SECURE_SETTINGS_WRITE|APPOPS_MANAGE|RUNTIME_PERMISSION_MANAGE|TERMINAL_COMMAND) return 0 ;; *) return 1 ;; esac; }
valid_command(){
  case "$1" in
    getprop|id|id\\ -u|whoami|ps|ps\\ -A|ps\\ -ef|getenforce|service\\ list) return 0 ;;
  esac
  printf '%s\\n' "$1" | grep -Eq '^(getprop [A-Za-z0-9_.-]{1,128}|pm list packages( -3|-s|-f|-U)?|cmd package list packages( -3|-s|-f|-U)?|dumpsys package [A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+|settings get (secure|global|system) [A-Za-z0-9_.-]{1,128}|cat /proc/(version|uptime)|cat /sys/fs/selinux/enforce|ls (/system|/product|/vendor|/apex|/proc|/sys)(/[A-Za-z0-9_.-]+)*)$'
}
with_lock(){
  n=0
  while ! mkdir "$LOCK" 2>/dev/null; do n=$((n+1)); [ "$n" -lt 20 ] || return 30; sleep 1; done
  trap 'rmdir "$LOCK" 2>/dev/null || :' EXIT HUP INT TERM
  "$@"
}
authorized_pkg(){ grep -Fxq "$1" "$PKGS"; }
has_scope(){ awk -F '\\t' -v pkg="$1" -v scope="$2" '$1==pkg&&$2==scope{found=1} END{exit !found}' "$SCOPES"; }
has_always(){ awk -F '\\t' -v pkg="$1" -v command="$2" '$1==pkg&&$2==command{found=1} END{exit !found}' "$ALWAYS"; }
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
  run)
    [ "$#" -eq 4 ] || exit 2
    run_readonly "$2" "$3" "$4"
    ;;
  *) exit 2 ;;
esac
