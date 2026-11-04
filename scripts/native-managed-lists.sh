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
mkdir -p "$PG"
[ -f "$CONF" ] && [ ! -L "$CONF" ] || { echo "FX settings.conf missing or unsafe" >&2; exit 21; }

TMP_FILE=
BACKUP_FILE=
RESTORE_FILE=
LOCK_HELD=0
cleanup() {
  [ -z "$TMP_FILE" ] || rm -f "$TMP_FILE" 2>/dev/null || :
  [ -z "$BACKUP_FILE" ] || rm -f "$BACKUP_FILE" 2>/dev/null || :
  [ -z "$RESTORE_FILE" ] || rm -f "$RESTORE_FILE" 2>/dev/null || :
  if [ "$LOCK_HELD" = 1 ]; then rmdir "$LOCK" 2>/dev/null || :; LOCK_HELD=0; fi
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
  case "$1" in *'|'*|*'\\'*|*'
'*) return 1 ;; esac
  if printf '%s' "$1" | grep -q '[[:cntrl:]]'; then return 1; fi
  return 0
}
valid_note() {
  [ "${#1}" -le 180 ] || return 1
  case "$1" in *'|'*|*'\\'*|*'
'*) return 1 ;; esac
  if printf '%s' "$1" | grep -q '[[:cntrl:]]'; then return 1; fi
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
      printf '%s\n' "$raw" | grep -Eq '^https?://[A-Za-z0-9._~:/?#@!    rule)
      valid_field "$raw" || return 1
      printf '%s\n' "$raw" | grep -Eq '^https?://[A-Za-z0-9._~:/?#@!$&()*+,;=%-]+$'
      ;;()*+,;=%-]+
    domain|block) normalize_domain "$raw" ;;
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
  awk -F'|' -v OFS='|' -v target="[list:$section]" \
      -v value="$value" -v note="$note" '
    BEGIN {inlist=0; found=0; added=0}
    $0==target {inlist=1; found=1; print; next}
    /^\[/ {
      if(inlist && !added) {print value,note,1; added=1}
      inlist=0; print; next
    }
    {print}
    END {
      if(inlist && !added) print value,note,1
      if(!found) {print ""; print target; print value,note,1}
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
with_lock() {
  tries=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    tries=$((tries+1))
    [ "$tries" -lt 20 ] || { echo "managed-list update is busy" >&2; return 10; }
    sleep 1
  done
  LOCK_HELD=1
  if "$@"; then rc=0; else rc=$?; fi
  rmdir "$LOCK" 2>/dev/null || :
  LOCK_HELD=0
  return "$rc"
}
mutate_transaction() {
  action="$1"; section="$2"; index="$3"; value="$4"; note="$5"; enabled="$6"
  BACKUP_FILE=$(mktemp "$CONF.native-list-rollback.XXXXXX") || return 1
  cp -p "$CONF" "$BACKUP_FILE" || return 1
  case "$action" in
    add) append_row "$section" "$value" "$note" || { rc=$?; return "$rc"; } ;;
    edit|toggle|delete)
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
  sh "$MP/scripts/apply.sh" fast >/dev/null 2>&1 || echo "previous list restored; apply reconciliation failed" >&2
  rm -f "$BACKUP_FILE"; BACKUP_FILE=
  echo "apply failed; previous list restored" >&2
  return 1
}

cmd=${1:-list}
[ "$#" -ge 2 ] || { echo "usage: $0 list|add|edit|toggle|delete LIST_ID ..." >&2; exit 2; }
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
 || return 1
      printf '%s\n' "$raw"
      ;;
    domain|block) normalize_domain "$raw" ;;
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
  awk -F'|' -v OFS='|' -v target="[list:$section]" \
      -v value="$value" -v note="$note" '
    BEGIN {inlist=0; found=0; added=0}
    $0==target {inlist=1; found=1; print; next}
    /^\[/ {
      if(inlist && !added) {print value,note,1; added=1}
      inlist=0; print; next
    }
    {print}
    END {
      if(inlist && !added) print value,note,1
      if(!found) {print ""; print target; print value,note,1}
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
with_lock() {
  tries=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    tries=$((tries+1))
    [ "$tries" -lt 20 ] || { echo "managed-list update is busy" >&2; return 10; }
    sleep 1
  done
  LOCK_HELD=1
  if "$@"; then rc=0; else rc=$?; fi
  rmdir "$LOCK" 2>/dev/null || :
  LOCK_HELD=0
  return "$rc"
}
mutate_transaction() {
  action="$1"; section="$2"; index="$3"; value="$4"; note="$5"; enabled="$6"
  BACKUP_FILE=$(mktemp "$CONF.native-list-rollback.XXXXXX") || return 1
  cp -p "$CONF" "$BACKUP_FILE" || return 1
  case "$action" in
    add) append_row "$section" "$value" "$note" || { rc=$?; return "$rc"; } ;;
    edit|toggle|delete)
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
  sh "$MP/scripts/apply.sh" fast >/dev/null 2>&1 || echo "previous list restored; apply reconciliation failed" >&2
  rm -f "$BACKUP_FILE"; BACKUP_FILE=
  echo "apply failed; previous list restored" >&2
  return 1
}

cmd=${1:-list}
[ "$#" -ge 2 ] || { echo "usage: $0 list|add|edit|toggle|delete LIST_ID ..." >&2; exit 2; }
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
