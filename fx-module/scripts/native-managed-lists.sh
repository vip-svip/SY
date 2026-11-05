#!/system/bin/sh
# Native Android UI backend for FX Hosts/Ad managed lists.
# Only the three fixed IDs below are writable from the application UI.
set -eu
umask 077

MP=${MP:-}
if [ -z "$MP" ]; then
  for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do
    if [ -s "$d/module.prop" ] && grep -q '^id=privacyguard$' "$d/module.prop" 2>/dev/null; then MP="$d"; break; fi
  done
fi
[ -n "$MP" ] && [ -s "$MP/module.prop" ] && grep -q '^id=privacyguard$' "$MP/module.prop" 2>/dev/null || {
  echo "FX module is not installed" >&2; exit 20;
}
PG=${PG:-/data/adb/privacyguard}
CONF=${CONF:-$PG/settings.conf}
LOCK=${LOCK:-$PG/native-managed-lists.lock}

# Validate each existing ancestor before touching the module state directory.
# Never mkdir -p through a symlink: the settings file and lock must remain
# direct children of the private FX state directory.
_nl_validate_parent_chain() {
  _nl_candidate=$1
  case "$_nl_candidate" in /*) : ;; *) return 1 ;; esac
  case "$_nl_candidate" in /|*/|*//* ) return 1 ;; esac
  _nl_final=${_nl_candidate##*/}
  case "$_nl_final" in ''|.|..) return 1 ;; esac
  _nl_parent=${_nl_candidate%/*}
  [ -n "$_nl_parent" ] || _nl_parent=/
  _nl_rest=${_nl_parent#/}
  _nl_walk=
  while [ -n "$_nl_rest" ]; do
    case "$_nl_rest" in
      */*) _nl_component=${_nl_rest%%/*}; _nl_rest=${_nl_rest#*/} ;;
      *) _nl_component=$_nl_rest; _nl_rest= ;;
    esac
    case "$_nl_component" in ''|.|..) return 1 ;; esac
    _nl_walk="$_nl_walk/$_nl_component"
    [ -d "$_nl_walk" ] && [ ! -L "$_nl_walk" ] || return 1
  done
  return 0
}

_nl_validate_parent_chain "$PG" || {
  echo "FX state directory has a missing or unsafe parent" >&2
  exit 21
}
[ ! -L "$PG" ] || { echo "FX state directory must not be a symbolic link" >&2; exit 21; }
if [ ! -e "$PG" ]; then mkdir "$PG" || { echo "cannot create FX state directory" >&2; exit 21; }; fi
[ -d "$PG" ] && [ ! -L "$PG" ] || { echo "FX state directory missing or unsafe" >&2; exit 21; }
[ "$CONF" = "$PG/settings.conf" ] || { echo "FX settings path must be the module state file" >&2; exit 21; }
[ "$LOCK" = "$PG/native-managed-lists.lock" ] || { echo "FX list lock path must be inside the module state directory" >&2; exit 21; }
[ -f "$CONF" ] && [ ! -L "$CONF" ] || { echo "FX settings.conf missing or unsafe" >&2; exit 21; }

TMP_FILE=
BACKUP_FILE=
RESTORE_FILE=
LOCK_HELD=0
cleanup() {
  [ -z "$TMP_FILE" ] || rm -f "$TMP_FILE" 2>/dev/null || :
  [ -z "$BACKUP_FILE" ] || rm -f "$BACKUP_FILE" 2>/dev/null || :
  [ -z "$RESTORE_FILE" ] || rm -f "$RESTORE_FILE" 2>/dev/null || :
  _nl_unlock || :
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

resolve_section() {
  case "$1" in
    ruleList) echo rule ;;
    domainList) echo domain ;;
    blockList) echo block ;;
    *) return 2 ;;
  esac
}
valid_field() {
  [ -n "$1" ] || return 1
  [ "${#1}" -le 4096 ] || return 1
  case "$1" in *'|'*|*'\'*) return 1 ;; esac
  lines=$(printf '%s' "$1" | wc -l | tr -d '[:space:]')
  [ "${lines:-0}" -eq 0 ] || return 1
  if printf '%s' "$1" | LC_ALL=C grep -q '[[:cntrl:]]'; then return 1; fi
  return 0
}
valid_note() {
  [ "${#1}" -le 180 ] || return 1
  case "$1" in *'|'*|*'\'*) return 1 ;; esac
  lines=$(printf '%s' "$1" | wc -l | tr -d '[:space:]')
  [ "${lines:-0}" -eq 0 ] || return 1
  if printf '%s' "$1" | LC_ALL=C grep -q '[[:cntrl:]]'; then return 1; fi
  return 0
}
normalize_domain() {
  d=$(printf '%s' "$1" | tr 'A-Z' 'a-z' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  case "$d" in ''|.*|*.|*..*|*[!a-z0-9.-]*) return 1 ;; esac
  printf '%s\n' "$d" | awk '{
    if(length($0)<1 || length($0)>253) exit 1
    n=split($0,a,".")
    for(i=1;i<=n;i++)
      if(length(a[i])<1 || length(a[i])>63 || a[i]!~/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/) exit 1
    print $0
  }'
}
normalize_value() {
  kind="$1"; raw="$2"
  case "$kind" in
    rule)
      valid_field "$raw" || return 1
      printf '%s\n' "$raw" | grep -Eq '^https?://[A-Za-z0-9._~:/?#@!$&()*+,;=%-]+$' || return 1
      printf '%s\n' "$raw"
      ;;
    domain|block)
      valid_field "$raw" || return 1
      normalize_domain "$raw"
      ;;
    *) return 1 ;;
  esac
}
list_rows() {
  section="$1"
  awk -F'|' -v target="[list:$section]" '
    BEGIN { rownum=0; inlist=0 }
    $0==target {inlist=1; next}
    /^\[/ {inlist=0}
    inlist && NF>=2 && $1!="" && $1 !~ /^[[:space:]]*#/ {
      note=$2
      enabled=(NF>=3 && $3=="0" ? 0 : 1)
      printf "%d|%s|%s|%d\n", rownum++, $1, note, enabled
    }
  ' "$CONF"
}
value_exists() {
  section="$1"; wanted="$2"; ignore_case="$3"; excluded="${4:--1}"
  awk -F'|' -v target="[list:$section]" -v wanted="$wanted" \
      -v ignore_case="$ignore_case" -v excluded="$excluded" '
    BEGIN {inlist=0; rownum=0; found=0}
    $0==target {inlist=1; next}
    /^\[/ {inlist=0}
    inlist && NF>=2 && $1!="" && $1 !~ /^[[:space:]]*#/ {
      same=(ignore_case=="1" ? tolower($1)==tolower(wanted) : $1==wanted)
      if(same && rownum!=excluded) found=1
      rownum++
    }
    END {exit(found ? 0 : 1)}
  ' "$CONF"
}
append_row() {
  section="$1"; value="$2"; note="$3"
  ignore_case=0
  [ "$section" = rule ] || ignore_case=1
  if value_exists "$section" "$value" "$ignore_case" -1; then
    echo "duplicate list entry" >&2
    return 3
  fi
  TMP_FILE=$(mktemp "$CONF.native-list.XXXXXX") || return 1
  # Legacy append-only builds may have repeated section headers. Add once,
  # to the last matching section, while preserving every existing row.
  awk -F'|' -v OFS='|' -v target="[list:$section]" -v value="$value" -v note="$note" '
    {
      lines[NR]=$0
      if($0==target) {
        last_header=NR
        last_end=NR
        in_target=1
      } else if(in_target && /^\[/) {
        last_end=NR-1
        in_target=0
      }
    }
    END {
      if(in_target) last_end=NR
      if(!last_header) {
        for(i=1;i<=NR;i++) print lines[i]
        if(NR>0) print ""
        print target
        print value,note,1
        exit
      }
      for(i=1;i<=NR;i++) {
        print lines[i]
        if(i==last_end) print value,note,1
      }
    }
  ' "$CONF" > "$TMP_FILE" || return 1
  [ -s "$TMP_FILE" ] || return 1
  chmod 600 "$TMP_FILE" && mv -f "$TMP_FILE" "$CONF" || return 1
  TMP_FILE=
}
update_row() {
  section="$1"; wanted="$2"; action="$3"; value="$4"; note="$5"; enabled="$6"
  TMP_FILE=$(mktemp "$CONF.native-list.XXXXXX") || return 1
  awk -F'|' -v OFS='|' -v target="[list:$section]" \
      -v wanted="$wanted" -v action="$action" -v value="$value" \
      -v note="$note" -v enabled="$enabled" '
    BEGIN {inlist=0; rownum=0; found=0}
    $0==target {inlist=1; print; next}
    /^\[/ {inlist=0; print; next}
    inlist && NF>=2 && $1!="" && $1 !~ /^[[:space:]]*#/ {
      if(rownum==wanted) {
        found=1
        if(action=="delete") {rownum++; next}
        if(action=="toggle") {print $1,$2,enabled; rownum++; next}
        if(action=="edit") {print value,note,enabled; rownum++; next}
      }
      rownum++
      print
      next
    }
    {print}
    END {if(!found) exit 4}
  ' "$CONF" > "$TMP_FILE" || { rm -f "$TMP_FILE"; TMP_FILE=; echo "list item not found" >&2; return 4; }
  [ -s "$TMP_FILE" ] || return 1
  chmod 600 "$TMP_FILE" && mv -f "$TMP_FILE" "$CONF" || return 1
  TMP_FILE=
}
# Read a lock owner without following symlinks. The directory form is
# accepted only for compatibility with a legacy PID-bearing lock.
_nl_read_lock_owner() {
  _nl_path=$1
  [ ! -L "$_nl_path" ] || return 1
  if [ -d "$_nl_path" ]; then
    [ ! -L "$_nl_path/pid" ] && [ -f "$_nl_path/pid" ] || return 1
    cat "$_nl_path/pid" 2>/dev/null
  elif [ -f "$_nl_path" ]; then
    cat "$_nl_path" 2>/dev/null
  else
    return 1
  fi
}

_nl_remove_lock_path() {
  _nl_path=$1
  [ ! -L "$_nl_path" ] || return 1
  if [ -d "$_nl_path" ]; then
    rm -rf "$_nl_path" 2>/dev/null
  elif [ -f "$_nl_path" ]; then
    rm -f "$_nl_path" 2>/dev/null
  else
    return 1
  fi
}

_nl_unlock() {
  [ "$LOCK_HELD" = 1 ] || return 0
  _nl_owner=$(_nl_read_lock_owner "$LOCK" 2>/dev/null || :)
  if [ "$_nl_owner" = "$_nl_lock_pid" ]; then
    _nl_release="$LOCK.release.$_nl_lock_pid"
    _nl_release_try=0
    while { [ -e "$_nl_release" ] || [ -L "$_nl_release" ]; } && [ "$_nl_release_try" -lt 20 ]; do
      _nl_release_try=$((_nl_release_try + 1))
      _nl_release="$LOCK.release.$_nl_lock_pid.$_nl_release_try"
    done
    if [ ! -e "$_nl_release" ] && [ ! -L "$_nl_release" ] &&
       mv "$LOCK" "$_nl_release" 2>/dev/null; then
      _nl_release_owner=$(_nl_read_lock_owner "$_nl_release" 2>/dev/null || :)
      if [ "$_nl_release_owner" = "$_nl_lock_pid" ]; then
        _nl_remove_lock_path "$_nl_release" || :
      elif [ ! -e "$LOCK" ] && [ ! -L "$LOCK" ]; then
        mv "$_nl_release" "$LOCK" 2>/dev/null || :
      fi
    fi
  fi
  LOCK_HELD=0
  return 0
}

_nl_acquire_lock() {
  # A builtin read of /proc/self/stat obtains this shell's PID directly;
  # command substitution would report a short-lived subshell PID instead.
  _nl_lock_pid=
  _nl_rest=
  IFS=' ' read -r _nl_lock_pid _nl_rest < /proc/self/stat || {
    echo "cannot determine managed-list lock owner PID" >&2
    return 10
  }
  case "$_nl_lock_pid" in ''|0|*[!0-9]*)
    echo "cannot determine managed-list lock owner PID" >&2
    return 10
    ;;
  esac

  _nl_tries=0
  _nl_retries=${FX_MANAGED_LIST_LOCK_RETRIES:-20}
  case "$_nl_retries" in ''|*[!0-9]*|0) _nl_retries=20 ;; esac
  [ "$_nl_retries" -le 120 ] 2>/dev/null || _nl_retries=120

  while :; do
    if [ -L "$LOCK" ]; then
      echo "managed-list lock path is a symbolic link; refusing to follow it" >&2
      return 10
    fi

    if [ ! -e "$LOCK" ]; then
      if ( umask 077; set -C; printf '%s\n' "$_nl_lock_pid" > "$LOCK" ) 2>/dev/null; then
        LOCK_HELD=1
        return 0
      fi
    else
      _nl_owner=$(_nl_read_lock_owner "$LOCK" 2>/dev/null || :)
      case "$_nl_owner" in
        ''|0|*[!0-9]*)
          # Do not remove an ownerless legacy mkdir lock. It may still belong
          # to an older process which has not yet written any PID metadata.
          ;;
        *)
          if ! kill -0 "$_nl_owner" 2>/dev/null; then
            _nl_owner2=$(_nl_read_lock_owner "$LOCK" 2>/dev/null || :)
            if [ "$_nl_owner2" = "$_nl_owner" ] &&
               ! kill -0 "$_nl_owner2" 2>/dev/null; then
              _nl_stale="$LOCK.stale.$_nl_lock_pid.$_nl_tries"
              if [ ! -e "$_nl_stale" ] && [ ! -L "$_nl_stale" ] &&
                 mv "$LOCK" "$_nl_stale" 2>/dev/null; then
                _nl_moved_owner=$(_nl_read_lock_owner "$_nl_stale" 2>/dev/null || :)
                if [ "$_nl_moved_owner" = "$_nl_owner" ] &&
                   ! kill -0 "$_nl_moved_owner" 2>/dev/null; then
                  _nl_remove_lock_path "$_nl_stale" || :
                elif [ ! -e "$LOCK" ] && [ ! -L "$LOCK" ]; then
                  # The lock changed between the last read and rename. Restore
                  # it instead of deleting a potentially live owner's lock.
                  mv "$_nl_stale" "$LOCK" 2>/dev/null || :
                fi
              fi
              continue
            fi
          fi
          ;;
      esac
    fi

    _nl_tries=$((_nl_tries + 1))
    if [ "$_nl_tries" -ge "$_nl_retries" ]; then
      if [ -d "$LOCK" ]; then
        echo "legacy ownerless managed-list lock remains; refusing unsafe automatic removal" >&2
      else
        echo "managed-list update is busy or has no verifiable owner" >&2
      fi
      return 10
    fi
    sleep 1
  done
}
with_lock() {
  _nl_acquire_lock || return $?
  if "$@"; then rc=0; else rc=$?; fi
  _nl_unlock
  return "$rc"
}
mutate_transaction() {
  action="$1"; section="$2"; index="$3"; value="$4"; note="$5"; enabled="$6"
  BACKUP_FILE=$(mktemp "$CONF.native-list-rollback.XXXXXX") || return 1
  cp -p "$CONF" "$BACKUP_FILE" || return 1
  case "$action" in
    add) append_row "$section" "$value" "$note" || { rc=$?; return "$rc"; } ;;
    edit)
      # The caller's early duplicate check is only a UI fast-fail. Recheck
      # under the transaction lock so concurrent writers cannot create
      # duplicate entries between validation and commit.
      _nl_ignore_case=0
      [ "$section" = rule ] || _nl_ignore_case=1
      if value_exists "$section" "$value" "$_nl_ignore_case" "$index"; then
        echo "duplicate list value" >&2
        return 3
      fi
      update_row "$section" "$index" "$action" "$value" "$note" "$enabled" || { rc=$?; return "$rc"; } ;;
    toggle|delete)
      update_row "$section" "$index" "$action" "$value" "$note" "$enabled" || { rc=$?; return "$rc"; } ;;
    *) return 2 ;;
  esac
  if [ "$section" = rule ]; then apply_mode=full; else apply_mode=fast; fi
  export MP PG MODDIR="$MP"
  if sh "$MP/scripts/apply.sh" "$apply_mode"; then
    rm -f "$BACKUP_FILE"; BACKUP_FILE=
    echo "applied=1"
    return 0
  fi
  RESTORE_FILE=$(mktemp "$CONF.restore.XXXXXX") || {
    echo "managed-list rollback temp creation failed; backup remains for recovery" >&2
    return 11
  }
  cp -p "$BACKUP_FILE" "$RESTORE_FILE" && chmod 600 "$RESTORE_FILE" \
    && mv -f "$RESTORE_FILE" "$CONF" || {
      echo "managed-list rollback failed; backup remains for recovery" >&2
      return 11
    }
  RESTORE_FILE=
  sh "$MP/scripts/apply.sh" "$apply_mode" >/dev/null 2>&1 || echo "previous list restored; apply reconciliation failed" >&2
  rm -f "$BACKUP_FILE"; BACKUP_FILE=
  echo "apply failed; previous list restored" >&2
  return 1
}

cmd=${1:-list}
if [ "$cmd" = apply ]; then
  [ "$#" -le 2 ] || { echo "usage: $0 apply [full|fast]" >&2; exit 2; }
  apply_mode=${2:-full}
  case "$apply_mode" in full|fast) : ;; *) echo "invalid apply mode" >&2; exit 2 ;; esac
  export MP PG MODDIR="$MP"
  sh "$MP/scripts/apply.sh" "$apply_mode"
  exit $?
fi
[ "$#" -ge 2 ] || { echo "usage: $0 list|add|edit|toggle|delete LIST_ID ... | apply [full|fast]" >&2; exit 2; }
section=$(resolve_section "$2") || { echo "unknown managed list: $2" >&2; exit 2; }

case "$cmd" in
  list)
    [ "$#" -eq 2 ] || exit 2
    echo FXLIST1
    list_rows "$section"
    ;;
  add)
    [ "$#" -eq 4 ] || { echo "usage: $0 add LIST_ID VALUE NOTE" >&2; exit 2; }
    value=$(normalize_value "$section" "$3") || { echo "invalid list value" >&2; exit 2; }
    valid_note "$4" || { echo "invalid note" >&2; exit 2; }
    with_lock mutate_transaction add "$section" -1 "$value" "$4" 1
    ;;
  edit)
    [ "$#" -eq 6 ] || { echo "usage: $0 edit LIST_ID INDEX VALUE NOTE ENABLED" >&2; exit 2; }
    case "$3" in ''|*[!0-9]*) exit 2 ;; esac
    value=$(normalize_value "$section" "$4") || { echo "invalid list value" >&2; exit 2; }
    valid_note "$5" || { echo "invalid note" >&2; exit 2; }
    case "$6" in 0|1) : ;; *) exit 2 ;; esac
    ignore_case=0; [ "$section" = rule ] || ignore_case=1
    if value_exists "$section" "$value" "$ignore_case" "$3"; then
      echo "duplicate list value" >&2; exit 3
    fi
    with_lock mutate_transaction edit "$section" "$3" "$value" "$5" "$6"
    ;;
  toggle)
    [ "$#" -eq 4 ] || { echo "usage: $0 toggle LIST_ID INDEX ENABLED" >&2; exit 2; }
    case "$3" in ''|*[!0-9]*) exit 2 ;; esac
    case "$4" in 0|1) : ;; *) exit 2 ;; esac
    with_lock mutate_transaction toggle "$section" "$3" "" "" "$4"
    ;;
  delete)
    [ "$#" -eq 3 ] || { echo "usage: $0 delete LIST_ID INDEX" >&2; exit 2; }
    case "$3" in ''|*[!0-9]*) exit 2 ;; esac
    with_lock mutate_transaction delete "$section" "$3" "" "" 0
    ;;
  apply)
    [ "$#" -eq 2 ] || exit 2
    export MP PG MODDIR="$MP"
    sh "$MP/scripts/apply.sh" full
    ;;
  *)
    echo "unknown operation: $cmd" >&2
    exit 2
    ;;
esac
