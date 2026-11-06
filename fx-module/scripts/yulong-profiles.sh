#!/system/bin/sh
# FX migration of Yulong 7.0.1 ProtectionProfile and ProfileSchedule.
set -u
ACTION=${1:-list}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" 2>/dev/null && pwd)
MP=${MP:-${SCRIPT_DIR%/scripts}}
PG=${PG:-/data/adb/privacyguard}
_yprof_validate_parent_chain() {
  _yprof_candidate=$1
  case "$_yprof_candidate" in /*) : ;; *) return 1 ;; esac
  case "$_yprof_candidate" in /|*/|*//* ) return 1 ;; esac
  _yprof_final=${_yprof_candidate##*/}
  case "$_yprof_final" in ''|.|..) return 1 ;; esac
  _yprof_parent=${_yprof_candidate%/*}
  [ -n "$_yprof_parent" ] || _yprof_parent=/
  _yprof_rest=${_yprof_parent#/}
  _yprof_walk=
  while [ -n "$_yprof_rest" ]; do
    case "$_yprof_rest" in
      */*) _yprof_component=${_yprof_rest%%/*}; _yprof_rest=${_yprof_rest#*/} ;;
      *) _yprof_component=$_yprof_rest; _yprof_rest= ;;
    esac
    case "$_yprof_component" in ''|.|..) return 1 ;; esac
    _yprof_walk="$_yprof_walk/$_yprof_component"
    [ -d "$_yprof_walk" ] && [ ! -L "$_yprof_walk" ] || return 1
  done
  return 0
}
_yprof_validate_parent_chain "$PG" || { echo "FX profile state parent is missing or unsafe" >&2; exit 21; }
[ -d "$PG" ] && [ ! -L "$PG" ] || { echo "FX profile state directory is unsafe" >&2; exit 21; }
[ -f "$MP/scripts/util.sh" ] || { echo "FX module utility library is missing" >&2; exit 20; }
[ -f "$PG/settings.conf" ] && [ ! -L "$PG/settings.conf" ] || { echo "FX settings.conf missing or unsafe" >&2; exit 21; }
CONF="$PG/settings.conf"
PROFILES="$PG/yulong-profiles.tsv"
SCHEDULES="$PG/yulong-profile-schedules.tsv"
LOCK="$PG/yulong-profile.lock"
for _yprof_path in "$PROFILES" "$SCHEDULES" "$LOCK"; do
  [ ! -L "$_yprof_path" ] || { echo "FX profile state file is a symbolic link" >&2; exit 21; }
done
. "$MP/scripts/util.sh"
CONF="$PG/settings.conf"
PROFILES="$PG/yulong-profiles.tsv"
SCHEDULES="$PG/yulong-profile-schedules.tsv"
LOCK="$PG/yulong-profile.lock"
LOCK_HELD=0
LOCK_PID=
LOCK_START=
BACKUP_CONF=
BACKUP_PROFILES=
BACKUP_SCHEDULES=
TMP=
fail(){ echo "$*" >&2; return "${2:-1}"; }
valid_id(){ case "$1" in ''|*[!a-zA-Z0-9_-]*) return 1 ;; esac; [ "${#1}" -le 48 ]; }
valid_bool(){ [ "$1" = 0 ] || [ "$1" = 1 ]; }
valid_text(){
  [ -n "$1" ] || return 1
  case "$1" in *'|'*|*'
'*|*'
'*) return 1 ;; esac
}
valid_time(){ printf '%s\n' "$1" | awk -F: 'NF==2 && $1~/^[0-9][0-9]$/ && $2~/^[0-9][0-9]$/ && $1+0<=23 && $2+0<=59 {ok=1} END{exit !ok}'; }
valid_days(){ printf '%s\n' "$1" | awk -F, 'NF<1 || NF>7 {bad=1} {for(i=1;i<=NF;i++)if($i!~/^[0-6]$/||seen[$i]++)bad=1} END{exit bad?1:0}'; }
valid_profile_url(){
  case "$1" in
    https://*) printf '%s\n' "$1" | grep -Eq '^https://[A-Za-z0-9._~:/?#@!$&()*+,;=%-]+$' ;;
    builtin://*) printf '%s\n' "$1" | grep -Eq '^builtin://[A-Za-z0-9._-]+$' ;;
    *) return 1 ;;
  esac
  return 0
}
encode(){ printf '%s' "$1" | base64 | tr -d '\r\n'; }
decode(){ printf '%s' "$1" | base64 -d 2>/dev/null; }
to_minutes(){
  _h=${1%:*}; _m=${1#*:}
  # POSIX shell can treat leading-zero values as octal; normalize HH/MM first.
  _h=$(printf '%s\n' "$_h" | sed 's/^0*//')
  _m=$(printf '%s\n' "$_m" | sed 's/^0*//')
  [ -n "$_h" ] || _h=0
  [ -n "$_m" ] || _m=0
  printf '%s\n' "$((_h * 60 + _m))"
}
atomic_replace(){
  _dst=$1; _src=$2
  chmod 600 "$_src" 2>/dev/null || return 1
  mv -f "$_src" "$_dst" || return 1
}
release_lock(){
  [ "$LOCK_HELD" = 1 ] || return 0
  if [ -f "$LOCK/owner" ] && [ ! -L "$LOCK/owner" ]; then
    _owner=$(cat "$LOCK/owner" 2>/dev/null || :)
    _pid=$(printf '%s\n' "$_owner" | awk '{print $1}')
    _start=$(printf '%s\n' "$_owner" | awk '{print $2}')
    if [ "$_pid" = "$LOCK_PID" ] && [ "$_start" = "$LOCK_START" ]; then
      rm -f "$LOCK/owner" 2>/dev/null || :
      rmdir "$LOCK" 2>/dev/null || :
    fi
  fi
  LOCK_HELD=0; LOCK_PID=; LOCK_START=
}
cleanup(){
  [ -z "$TMP" ] || rm -f "$TMP" 2>/dev/null || :
  [ -z "$BACKUP_CONF" ] || rm -f "$BACKUP_CONF" 2>/dev/null || :
  [ -z "$BACKUP_PROFILES" ] || rm -f "$BACKUP_PROFILES" 2>/dev/null || :
  [ -z "$BACKUP_SCHEDULES" ] || rm -f "$BACKUP_SCHEDULES" 2>/dev/null || :
  release_lock
}
trap cleanup 0
trap 'cleanup; exit 129' HUP
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
acquire_lock(){
  [ -d "$PG" ] && [ ! -L "$PG" ] || return 1
  _tries=0
  _selfstat=
  IFS= read -r _selfstat < /proc/self/stat || return 31
  _selfpid=${_selfstat%% *}
  case "$_selfpid" in ''|*[!0-9]*) return 31 ;; esac
  _selfstart=$(awk '{print $22}' "/proc/$_selfpid/stat" 2>/dev/null || :)
  case "$_selfstart" in ''|*[!0-9]*) return 31 ;; esac
  while ! mkdir "$LOCK" 2>/dev/null; do
    if [ -d "$LOCK" ] && [ ! -L "$LOCK" ] && [ -s "$LOCK/owner" ] && [ ! -L "$LOCK/owner" ]; then
      _record=$(cat "$LOCK/owner" 2>/dev/null || :)
      _pid=$(printf '%s\n' "$_record" | awk '{print $1}')
      _start=$(printf '%s\n' "$_record" | awk '{print $2}')
      _actual=
      case "$_pid:$_start" in *[!0-9:]*|:*) : ;; *) _actual=$(awk '{print $22}' "/proc/$_pid/stat" 2>/dev/null || :) ;; esac
      if [ "$_actual" != "$_start" ] && [ "$(cat "$LOCK/owner" 2>/dev/null || :)" = "$_record" ]; then
        rm -f "$LOCK/owner" 2>/dev/null || :
        rmdir "$LOCK" 2>/dev/null || :
      fi
    fi
    _tries=$((_tries+1))
    [ "$_tries" -lt 100 ] || return 30
    sleep 0.1
  done
  (umask 077; printf '%s %s\n' "$_selfpid" "$_selfstart" > "$LOCK/owner") || { rmdir "$LOCK" 2>/dev/null || :; return 31; }
  LOCK_HELD=1; LOCK_PID=$_selfpid; LOCK_START=$_selfstart
}
with_lock(){
  acquire_lock || return $?
  if "$@"; then _rc=0; else _rc=$?; fi
  release_lock
  return "$_rc"
}
profile_row(){ awk -F'|' -v id="$1" '$1==id {print; exit}' "$PROFILES" 2>/dev/null; }
replace_profile_row(){
  _row=$1; _id=${_row%%|*}
  _tmp=$(mktemp "$PROFILES.tmp.XXXXXX") || return 1
  awk -F'|' -v id="$_id" -v row="$_row" '
    BEGIN{done=0}
    NR==1 && $0=="FXYULONGPROFILES1" {print;next}
    $1==id {if(!done)print row;done=1;next}
    {print}
    END{if(!done)print row}
  ' "$PROFILES" > "$_tmp" || { rm -f "$_tmp"; return 1; }
  atomic_replace "$PROFILES" "$_tmp"
}
ensure_store(){
  [ -d "$PG" ] && [ ! -L "$PG" ] && [ ! -L "$PROFILES" ] && [ ! -L "$SCHEDULES" ] || return 1
  if [ ! -s "$PROFILES" ]; then
    _current_urls=$(pg_list rule | awk -F'|' '$1 ~ /^https:\/\// && $3=="1" {print $1}' | LC_ALL=C sort -u)
    _current_b64=$(encode "$_current_urls")
    _safe=$(pg_get yulong_safe_search_enabled 0); valid_bool "$_safe" || _safe=0
    _yt=$(pg_get yulong_youtube_restricted_mode 0); valid_bool "$_yt" || _yt=0
    _def=$(encode "Default"); _strict=$(encode "Strict"); _family=$(encode "Family")
    _gaming=$(encode "Gaming"); _strictfamily=$(encode "Strict Family")
    _strict_urls=$(printf '%s\n' \
      'https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts' \
      'https://easylist.to/easylist/easylist.txt' \
      'https://easylist.to/easylist/easyprivacy.txt' \
      'https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt' \
      'https://pgl.yoyo.org/adservers/serverlist.php?hostformat=adblockplus&showintro=1&mimetype=plaintext' \
      'https://filters.adtidy.org/extension/ublock/filters/2.txt' \
      'https://filters.adtidy.org/extension/ublock/filters/11.txt')
    _family_urls=$(printf '%s\n' \
      'https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts' \
      'https://easylist.to/easylist/easylist.txt' \
      'https://easylist.to/easylist/easyprivacy.txt' \
      'https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn-only/hosts' \
      'https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling-only/hosts')
    _gaming_urls=$(printf '%s\n' \
      'https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts' \
      'https://easylist.to/easylist/easylist.txt')
    _strict_b64=$(encode "$_strict_urls"); _family_b64=$(encode "$_family_urls")
    _gaming_b64=$(encode "$_gaming_urls")
    _strictfamily_b64=$(encode "$(printf '%s\n' "$_strict_urls" "$_family_urls" | LC_ALL=C sort -u)")
    _tmp=$(mktemp "$PG/yulong-profiles.init.XXXXXX") || return 1
    {
      echo FXYULONGPROFILES1
      printf 'default|%s|DEFAULT|%s|%s|%s\n' "$_def" "$_current_b64" "$_safe" "$_yt"
      printf 'strict|%s|STRICT|%s|0|0\n' "$_strict" "$_strict_b64"
      printf 'family|%s|FAMILY|%s|1|1\n' "$_family" "$_family_b64"
      printf 'gaming|%s|GAMING|%s|0|0\n' "$_gaming" "$_gaming_b64"
      printf 'strict_family|%s|STRICT_FAMILY|%s|1|1\n' "$_strictfamily" "$_strictfamily_b64"
    } > "$_tmp" || { rm -f "$_tmp"; return 1; }
    atomic_replace "$PROFILES" "$_tmp" || return 1
    if [ -z "$(pg_get yulong_active_profile "")" ]; then pg_set yulong_active_profile default || return 1; fi
  fi
  if [ ! -s "$SCHEDULES" ]; then
    _tmp=$(mktemp "$PG/yulong-profile-schedules.init.XXXXXX") || return 1
    printf 'FXYULONGPROFILESCHEDULE1\n' > "$_tmp"
    atomic_replace "$SCHEDULES" "$_tmp" || return 1
  fi
  [ -f "$PROFILES" ] && [ -f "$SCHEDULES" ]
}
profile_list_locked(){
  ensure_store || return 1
  _active=$(pg_get yulong_active_profile default)
  echo FXYULONGPROFILE1
  while IFS='|' read -r _id _name _kind _urls _safe _yt; do
    [ "$_id" = "FXYULONGPROFILES1" ] && continue
    [ -n "$_id" ] || continue
    _is_active=0; [ "$_id" = "$_active" ] && _is_active=1
    printf 'PROFILE|%s|%s|%s|%s|%s|%s\n' "$_id" "$_name" "$_kind" "$_safe" "$_yt" "$_is_active"
  done < "$PROFILES"
  while IFS='|' read -r _sid _pid _start _end _enabled _days; do
    [ "$_sid" = "FXYULONGPROFILESCHEDULE1" ] && continue
    [ -n "$_sid" ] || continue
    printf 'SCHEDULE|%s|%s|%s|%s|%s|%s\n' "$_sid" "$_pid" "$_start" "$_end" "$_enabled" "$_days"
  done < "$SCHEDULES"
}
current_urls_file(){
  pg_list rule | awk -F'|' '$1 ~ /^https:\/\// && $3=="1" {print $1}' | LC_ALL=C sort -u > "$1"
}
rollback_profile_state(){
  _restore_conf=$(mktemp "$CONF.profile-restore.XXXXXX") || { BACKUP_CONF=; BACKUP_PROFILES=; return 34; }
  _restore_profiles=$(mktemp "$PROFILES.profile-restore.XXXXXX") || { rm -f "$_restore_conf"; BACKUP_CONF=; BACKUP_PROFILES=; return 34; }
  if cp -p "$BACKUP_CONF" "$_restore_conf" && cp -p "$BACKUP_PROFILES" "$_restore_profiles" && mv -f "$_restore_conf" "$CONF" && mv -f "$_restore_profiles" "$PROFILES"; then
    if sh "$MP/scripts/apply.sh" fast >/dev/null 2>&1; then
      rm -f "$BACKUP_CONF" "$BACKUP_PROFILES" "$TMP"
      BACKUP_CONF=; BACKUP_PROFILES=; TMP=
      return 0
    fi
    echo "profile rollback restored files but runtime re-apply failed; retained backups: $BACKUP_CONF $BACKUP_PROFILES" >&2
    [ -z "$TMP" ] || rm -f "$TMP" 2>/dev/null || :
    BACKUP_CONF=; BACKUP_PROFILES=; TMP=
    return 35
  fi
  rm -f "$_restore_conf" "$_restore_profiles" 2>/dev/null || :
  echo "profile rollback failed; preserved backup files: $BACKUP_CONF $BACKUP_PROFILES" >&2
  BACKUP_CONF=; BACKUP_PROFILES=
  return 34
}
refresh_schedule_worker(){
  if [ -x "$MP/scripts/yulong-profile-schedule.sh" ]; then
    PG="$PG" MP="$MP" sh "$MP/scripts/yulong-profile-schedule.sh" start "$MP" "$PG" >/dev/null 2>&1 || echo "profile_schedule_watcher=deferred" >&2
  fi
}
apply_profile_locked(){
  ensure_store || return 1
  _target=$1; valid_id "$_target" || { echo "invalid profile id" >&2; return 2; }
  _row=$(profile_row "$_target"); [ -n "$_row" ] || { echo "profile not found: $_target" >&2; return 3; }
  _target_name=$(printf '%s\n' "$_row" | cut -d'|' -f2)
  _target_kind=$(printf '%s\n' "$_row" | cut -d'|' -f3)
  _target_urls_b64=$(printf '%s\n' "$_row" | cut -d'|' -f4)
  _target_safe=$(printf '%s\n' "$_row" | cut -d'|' -f5)
  _target_yt=$(printf '%s\n' "$_row" | cut -d'|' -f6)
  valid_bool "$_target_safe" && valid_bool "$_target_yt" || { echo "profile flags corrupt" >&2; return 31; }
  BACKUP_CONF=$(mktemp "$CONF.profile-backup.XXXXXX") || return 1
  BACKUP_PROFILES=$(mktemp "$PROFILES.profile-backup.XXXXXX") || return 1
  cp -p "$CONF" "$BACKUP_CONF" && cp -p "$PROFILES" "$BACKUP_PROFILES" || return 1
  TMP=$(mktemp "$PG/profile-target-urls.XXXXXX") || return 1
  decode "$_target_urls_b64" > "$TMP" || { echo "profile URL data corrupt" >&2; return 31; }
  _valid_urls=0
  while IFS= read -r _url; do
    [ -n "$_url" ] || continue
    valid_profile_url "$_url" || { echo "profile contains an invalid filter source: $_url" >&2; return 31; }
    _valid_urls=$((_valid_urls+1))
  done < "$TMP"
  sort -u "$TMP" > "$TMP.sorted" || return 1
  mv -f "$TMP.sorted" "$TMP" || return 1
  _active=$(pg_get yulong_active_profile default)
  _active_row=$(profile_row "$_active")
  if [ -n "$_active_row" ]; then
    _active_name=$(printf '%s\n' "$_active_row" | cut -d'|' -f2)
    _active_kind=$(printf '%s\n' "$_active_row" | cut -d'|' -f3)
    _active_safe=$(pg_get yulong_safe_search_enabled 0); valid_bool "$_active_safe" || _active_safe=0
    _active_yt=$(pg_get yulong_youtube_restricted_mode 0); valid_bool "$_active_yt" || _active_yt=0
    _current_file=$(mktemp "$PG/profile-current-urls.XXXXXX") || return 1
    current_urls_file "$_current_file" || { rm -f "$_current_file"; return 1; }
    _current_b64=$(base64 < "$_current_file" | tr -d '\r\n')
    rm -f "$_current_file"
    replace_profile_row "$_active|$_active_name|$_active_kind|$_current_b64|$_active_safe|$_active_yt" || { rollback_profile_state || :; return 1; }
  fi
  _existing=$(mktemp "$PG/profile-existing-urls.XXXXXX") || { rollback_profile_state || :; return 1; }
  pg_list rule | awk -F'|' '$1!="" {print $1}' | LC_ALL=C sort -u > "$_existing"
  _missing=0
  while IFS= read -r _url; do
    [ -n "$_url" ] || continue
    case "$_url" in
      https://*)
        if ! grep -F -x "$_url" "$_existing" >/dev/null 2>&1; then _missing=$((_missing+1)); fi
        ;;
      builtin://*)
        grep -F -x "$_url" "$_existing" >/dev/null 2>&1 || {
          echo "profile references an unavailable FX built-in source: $_url" >&2
          rm -f "$_existing"
          rollback_profile_state || :
          return 31
        }
        ;;
    esac
  done < "$TMP"
  _missing_file=$(mktemp "$PG/profile-missing-urls.XXXXXX") || { rm -f "$_existing"; rollback_profile_state || :; return 1; }
  while IFS= read -r _url; do
    [ -n "$_url" ] || continue
    case "$_url" in
      https://*)
        grep -F -x "$_url" "$_existing" >/dev/null 2>&1 || printf '%s\n' "$_url" >> "$_missing_file"
        ;;
    esac
  done < "$TMP"
  rm -f "$_existing"
  _rules_tmp=$(mktemp "$CONF.profile-rules.XXXXXX") || { rm -f "$_missing_file"; rollback_profile_state || :; return 1; }
  awk -F'|' -v OFS='|' -v wanted="$TMP" -v missing="$_missing_file" '
    function emit_missing(    u) {
      while((getline u < missing)>0) if(u!="") print u,"Yulong ProtectionProfile source",1
      close(missing); emitted=1
    }
    BEGIN {
      while((getline u < wanted)>0) if(u!="") selected[u]=1
      close(wanted); inside=0; found=0; emitted=0
    }
    $0=="[list:rule]" {
      inside=1; found=1; print
      emit_missing()
      next
    }
    /^\[/ {
      if(inside && !emitted) emit_missing()
      inside=0; print; next
    }
    inside && $0 !~ /^[[:space:]]*#/ && NF>=3 && $1!="" {
      # This profile owns remote filter-list URLs. Keep FX-native non-URL rows intact.
      if($1 ~ /^https:\/\//) $3=($1 in selected)?"1":"0"
      print; next
    }
    {print}
    END {
      if(inside && !emitted) emit_missing()
      if(!found) {print ""; print "[list:rule]"; if(!emitted) emit_missing()}
    }
  ' "$CONF" > "$_rules_tmp" || { rm -f "$_rules_tmp" "$_missing_file"; rollback_profile_state || :; return 1; }
  rm -f "$_missing_file"
  chmod 600 "$_rules_tmp" && mv -f "$_rules_tmp" "$CONF" || { rm -f "$_rules_tmp"; rollback_profile_state || :; return 1; }
  pg_set yulong_active_profile "$_target" || { rollback_profile_state || :; return 1; }
  pg_set yulong_safe_search_enabled "$_target_safe" || { rollback_profile_state || :; return 1; }
  pg_set yulong_youtube_restricted_mode "$_target_yt" || { rollback_profile_state || :; return 1; }
  if sh "$MP/scripts/apply.sh" fast; then
    rm -f "$BACKUP_CONF" "$BACKUP_PROFILES" "$TMP"
    BACKUP_CONF=; BACKUP_PROFILES=; TMP=
    echo "switched=$_target missing_sources=$_missing safe_search=$_target_safe youtube_restricted=$_target_yt"
    return 0
  fi
  echo "profile apply failed; restoring previous state" >&2
  rollback_profile_state || return 34
  return 35
}
profile_create_locked(){
  ensure_store || return 1
  _name=$1; _safe=$2; _yt=$3
  valid_text "$_name" && valid_bool "$_safe" && valid_bool "$_yt" || { echo "usage: profile-create NAME SAFE(0|1) YOUTUBE(0|1)" >&2; return 2; }
  _file=$(mktemp "$PG/profile-create-urls.XXXXXX") || return 1
  current_urls_file "$_file" || { rm -f "$_file"; return 1; }
  _urls_b64=$(base64 < "$_file" | tr -d '\r\n'); rm -f "$_file"
  _id="custom_$(date +%s)_$$"
  _name_b64=$(encode "$_name")
  _tmp=$(mktemp "$PROFILES.tmp.XXXXXX") || return 1
  cat "$PROFILES" > "$_tmp" && printf '%s|%s|CUSTOM|%s|%s|%s\n' "$_id" "$_name_b64" "$_urls_b64" "$_safe" "$_yt" >> "$_tmp" || { rm -f "$_tmp"; return 1; }
  atomic_replace "$PROFILES" "$_tmp" || return 1
  echo "created=$_id"
}
profile_delete_locked(){
  ensure_store || return 1
  _id=$1; valid_id "$_id" || return 2
  [ "$_id" != default ] || { echo "Default profile cannot be deleted" >&2; return 2; }
  _row=$(profile_row "$_id"); [ -n "$_row" ] || return 3
  _kind=$(printf '%s\n' "$_row" | cut -d'|' -f3)
  [ "$_kind" = CUSTOM ] || { echo "built-in profiles cannot be deleted" >&2; return 2; }
  [ "$(pg_get yulong_active_profile default)" != "$_id" ] || { echo "switch away from the active profile first" >&2; return 2; }
  # Profile records and their weekly schedules form one logical object. Keep
  # rollback copies until both candidate files have been atomically replaced.
  BACKUP_PROFILES=$(mktemp "$PROFILES.delete-backup.XXXXXX") || return 1
  BACKUP_SCHEDULES=$(mktemp "$SCHEDULES.delete-backup.XXXXXX") || return 1
  cp -p "$PROFILES" "$BACKUP_PROFILES" && cp -p "$SCHEDULES" "$BACKUP_SCHEDULES" || return 1
  _tmp=$(mktemp "$PROFILES.delete-candidate.XXXXXX") || return 1
  _stmp=$(mktemp "$SCHEDULES.delete-candidate.XXXXXX") || { rm -f "$_tmp"; return 1; }
  awk -F'|' -v id="$_id" '$1!=id {print}' "$PROFILES" > "$_tmp" || { rm -f "$_tmp" "$_stmp"; return 1; }
  awk -F'|' -v id="$_id" 'NR==1 || $2!=id {print}' "$SCHEDULES" > "$_stmp" || { rm -f "$_tmp" "$_stmp"; return 1; }
  chmod 600 "$_tmp" "$_stmp" || { rm -f "$_tmp" "$_stmp"; return 1; }
  if ! mv -f "$_tmp" "$PROFILES"; then
    rm -f "$_tmp" "$_stmp"
    return 1
  fi
  if ! mv -f "$_stmp" "$SCHEDULES"; then
    rm -f "$_stmp"
    _restore_profile=$(mktemp "$PROFILES.delete-restore.XXXXXX") || {
      echo "profile table changed but schedule deletion failed; preserved backup: $BACKUP_PROFILES" >&2
      BACKUP_PROFILES=
      return 34
    }
    if cp -p "$BACKUP_PROFILES" "$_restore_profile" && chmod 600 "$_restore_profile" && mv -f "$_restore_profile" "$PROFILES"; then
      rm -f "$BACKUP_PROFILES" "$BACKUP_SCHEDULES"
      BACKUP_PROFILES=; BACKUP_SCHEDULES=
      echo "profile delete aborted; original profile and schedules restored" >&2
      return 1
    fi
    rm -f "$_restore_profile" 2>/dev/null || :
    echo "profile delete rollback failed; preserved backups: $BACKUP_PROFILES $BACKUP_SCHEDULES" >&2
    BACKUP_PROFILES=; BACKUP_SCHEDULES=
    return 34
  fi
  rm -f "$BACKUP_PROFILES" "$BACKUP_SCHEDULES"
  BACKUP_PROFILES=; BACKUP_SCHEDULES=
  echo "deleted=$_id"
}
schedule_add_locked(){
  ensure_store || return 1
  _profile=$1; _start=$2; _end=$3; _days=$4
  valid_id "$_profile" && [ -n "$(profile_row "$_profile")" ] || { echo "profile not found" >&2; return 2; }
  valid_time "$_start" && valid_time "$_end" && valid_days "$_days" || { echo "invalid schedule" >&2; return 2; }
  _id="schedule_$(date +%s)_$$"
  _tmp=$(mktemp "$SCHEDULES.tmp.XXXXXX") || return 1
  cat "$SCHEDULES" > "$_tmp" && printf '%s|%s|%s|%s|1|%s\n' "$_id" "$_profile" "$_start" "$_end" "$_days" >> "$_tmp" || { rm -f "$_tmp"; return 1; }
  atomic_replace "$SCHEDULES" "$_tmp" || return 1
  echo "created=$_id"
}
schedule_set_locked(){
  ensure_store || return 1
  _id=$1; _enabled=$2; _start=$3; _end=$4; _days=$5
  valid_id "$_id" && valid_bool "$_enabled" && valid_time "$_start" && valid_time "$_end" && valid_days "$_days" || return 2
  _tmp=$(mktemp "$SCHEDULES.tmp.XXXXXX") || return 1
  awk -F'|' -v OFS='|' -v id="$_id" -v enabled="$_enabled" -v start="$_start" -v end="$_end" -v days="$_days" '
    BEGIN{found=0}
    NR==1 {print;next}
    $1==id {$3=start;$4=end;$5=enabled;$6=days;found=1}
    {print}
    END{if(!found)exit 3}
  ' "$SCHEDULES" > "$_tmp" || { rm -f "$_tmp"; return 3; }
  atomic_replace "$SCHEDULES" "$_tmp" || return 1
  echo "updated=$_id"
}
schedule_remove_locked(){
  ensure_store || return 1
  _id=$1; valid_id "$_id" || return 2
  awk -F'|' -v id="$_id" '$1==id {found=1} END{exit !found}' "$SCHEDULES" || { echo "schedule not found: $_id" >&2; return 3; }
  _tmp=$(mktemp "$SCHEDULES.tmp.XXXXXX") || return 1
  awk -F'|' -v id="$_id" 'NR==1 || $1!=id {print}' "$SCHEDULES" > "$_tmp" || { rm -f "$_tmp"; return 1; }
  atomic_replace "$SCHEDULES" "$_tmp"
}
profile_evaluate_locked(){
  ensure_store || return 1
  # The original worker stores Calendar weekday minus one: Sunday=0 ... Saturday=6.
  _day=$(date '+%w' 2>/dev/null); _now=$(date '+%H:%M' 2>/dev/null)
  case "$_day" in 0|1|2|3|4|5|6) ;; *) return 0 ;; esac
  valid_time "$_now" || return 0
  _now_m=$(to_minutes "$_now")
  while IFS='|' read -r _sid _profile _start _end _enabled _days; do
    [ "$_sid" = "FXYULONGPROFILESCHEDULE1" ] && continue
    [ "$_enabled" = 1 ] && [ -n "$_profile" ] || continue
    case ",$_days," in *,"$_day",*) ;; *) continue ;; esac
    valid_time "$_start" && valid_time "$_end" || continue
    _start_m=$(to_minutes "$_start"); _end_m=$(to_minutes "$_end")
    if [ "$_start_m" -lt "$_end_m" ]; then
      [ "$_now_m" -ge "$_start_m" ] && [ "$_now_m" -lt "$_end_m" ] || continue
    elif [ "$_start_m" -gt "$_end_m" ]; then
      [ "$_now_m" -lt "$_end_m" ] || [ "$_now_m" -ge "$_start_m" ] || continue
    else
      # Equal start/end is an empty interval in the original implementation.
      continue
    fi
    _active=$(pg_get yulong_active_profile default)
    [ "$_active" = "$_profile" ] && { echo "already_active=$_profile schedule=$_sid"; return 0; }
    apply_profile_locked "$_profile"
    return $?
  done < "$SCHEDULES"
  echo "no_matching_profile_schedule"
}
case "$ACTION" in
  list) with_lock profile_list_locked ;;
  profile-create) [ "$#" -eq 4 ] || fail "usage: $0 profile-create NAME SAFE YOUTUBE" 2; with_lock profile_create_locked "$2" "$3" "$4" ;;
  profile-switch) [ "$#" -eq 2 ] || fail "usage: $0 profile-switch ID" 2; with_lock apply_profile_locked "$2" ;;
  profile-delete) [ "$#" -eq 2 ] || fail "usage: $0 profile-delete ID" 2; with_lock profile_delete_locked "$2"; _rc=$?; [ "$_rc" -ne 0 ] || refresh_schedule_worker; exit "$_rc" ;;
  schedule-add) [ "$#" -eq 5 ] || fail "usage: $0 schedule-add PROFILE HH:MM HH:MM DAYS" 2; with_lock schedule_add_locked "$2" "$3" "$4" "$5"; _rc=$?; [ "$_rc" -ne 0 ] || refresh_schedule_worker; exit "$_rc" ;;
  schedule-set) [ "$#" -eq 6 ] || fail "usage: $0 schedule-set ID ENABLED HH:MM HH:MM DAYS" 2; with_lock schedule_set_locked "$2" "$3" "$4" "$5" "$6"; _rc=$?; [ "$_rc" -ne 0 ] || refresh_schedule_worker; exit "$_rc" ;;
  schedule-remove) [ "$#" -eq 2 ] || fail "usage: $0 schedule-remove ID" 2; with_lock schedule_remove_locked "$2"; _rc=$?; [ "$_rc" -ne 0 ] || refresh_schedule_worker; exit "$_rc" ;;
  evaluate) with_lock profile_evaluate_locked ;;
  *) fail "unsupported profile operation" 2 ;;
esac
