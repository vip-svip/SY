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
valid_scope(){ case "$1" in shell_basic|settings_secure) return 0 ;; *) return 1 ;; esac; }
valid_command(){
  tick=$(printf '\140')
  case "$1" in *';'*|*'|'*|*'&'*|*'>'*|*'<'*|*'$'*|*"$tick"*|*'('*|*')'*|*'\\'*|*'
'*) return 1 ;; esac
  case "$1" in
    getprop|pm\ list\ packages*|dumpsys\ package*|settings\ get*|cmd\ package\ list*) return 0 ;;
    *) return 1 ;;
  esac
}
with_lock(){
  n=0
  while ! mkdir "$LOCK" 2>/dev/null; do n=$((n+1)); [ "$n" -lt 20 ] || return 30; sleep 1; done
  trap 'rmdir "$LOCK" 2>/dev/null || :' EXIT HUP INT TERM
  "$@"
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
    [ "$#" -eq 4 ] && valid_pkg "$2" && valid_scope "$3" && { [ "$4" = 0 ] || [ "$4" = 1 ]; } || exit 2
    with_lock mutate_file "$SCOPES" "$([ "$4" = 1 ] && echo add || echo remove)" "$2" "$3"
    ;;
  always-set)
    [ "$#" -eq 4 ] && valid_pkg "$2" && valid_command "$3" && { [ "$4" = 0 ] || [ "$4" = 1 ]; } || exit 2
    with_lock mutate_file "$ALWAYS" "$([ "$4" = 1 ] && echo add || echo remove)" "$2" "$3"
    ;;
  *) exit 2 ;;
esac
