#!/system/bin/sh
# Native Android UI backend for FX managed Hosts lists.
# Maps legacy UI IDs to the canonical settings.conf list sections.
set -eu

MP=${MP:-}
if [ -z "$MP" ]; then
  for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do
    if [ -s "$d/module.prop" ] && grep -q '^id=privacyguard$' "$d/module.prop" 2>/dev/null; then MP="$d"; break; fi
  done
fi
[ -n "$MP" ] && [ -s "$MP/module.prop" ] || { echo "FX module is not installed" >&2; exit 20; }
PG=${PG:-/data/adb/privacyguard}
CONF=${CONF:-$PG/settings.conf}
LOCK=${LOCK:-$PG/native-managed-lists.lock}
mkdir -p "$PG"
[ -f "$CONF" ] && [ ! -L "$CONF" ] || { echo "FX settings.conf missing or unsafe" >&2; exit 21; }

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
  case "$1" in *'|'*) return 1 ;; esac
  if printf '%s' "$1" | grep -q '[[:cntrl:]]'; then return 1; fi
  return 0
}
valid_note() {
  [ "${#1}" -le 256 ] || return 1
  case "$1" in *'|'*) return 1 ;; esac
  if printf '%s' "$1" | grep -q '[[:cntrl:]]'; then return 1; fi
  return 0
}
list_rows() {
  section="$1"
  awk -F'|' -v target="[list:$section]" '
    BEGIN { rownum=0; inlist=0 }
    $0==target {inlist=1; next}
    /^\[/ {inlist=0}
    inlist && NF>=3 && $1!="" && $1 !~ /^[[:space:]]*#/ {
      note=$2
      enabled=($3=="0" ? 0 : 1)
      printf "%d|%s|%s|%d\n", rownum++, $1, note, enabled
    }
  ' "$CONF"
}
update_row() {
  section="$1"; wanted="$2"; action="$3"; value="$4"; note="$5"; enabled="$6"
  tmp="$CONF.native-list.$$"
  awk -F'|' -v OFS='|' -v target="[list:$section]" \
      -v wanted="$wanted" -v action="$action" -v value="$value" \
      -v note="$note" -v enabled="$enabled" '
    BEGIN {inlist=0; rownum=0; found=0}
    $0==target {inlist=1; print; next}
    /^\[/ {inlist=0; print; next}
    inlist && NF>=3 && $1!="" && $1 !~ /^[[:space:]]*#/ {
      if(rownum==wanted) {
        found=1
        if(action=="delete") { rownum++; next }
        if(action=="toggle") { print $1,$2,enabled; rownum++; next }
        if(action=="edit") { print value,note,enabled; rownum++; next }
      }
      rownum++
      print
      next
    }
    {print}
    END { if(!found) exit 4 }
  ' "$CONF" > "$tmp" || { rm -f "$tmp"; echo "list item not found" >&2; return 4; }
  [ -s "$tmp" ] || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" && mv -f "$tmp" "$CONF"
}
append_row() {
  section="$1"; value="$2"; note="$3"
  tmp="$CONF.native-list.$$"
  if awk -F'|' -v target="[list:$section]" -v value="$value" '
      $0==target {inlist=1; next}
      /^\[/ {inlist=0}
      inlist && $1==value {found=1}
      END {exit(found ? 0 : 1)}
    ' "$CONF"; then
    echo "duplicate list entry" >&2
    return 3
  fi
  {
    cat "$CONF"
    printf '\n[list:%s]\n%s|%s|1\n' "$section" "$value" "$note"
  } > "$tmp" || { rm -f "$tmp"; return 1; }
  [ -s "$tmp" ] || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" && mv -f "$tmp" "$CONF"
}
with_lock() {
  tries=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    tries=$((tries+1))
    [ "$tries" -lt 20 ] || { echo "managed-list update is busy" >&2; return 10; }
    sleep 1
  done
  trap 'rmdir "$LOCK" 2>/dev/null || :' EXIT HUP INT TERM
  "$@"
}
mutate_transaction() {
  action="$1"; section="$2"; index="$3"; value="$4"; note="$5"; enabled="$6"
  backup="$CONF.native-list-rollback.$$"
  cp -p "$CONF" "$backup" || return 1
  case "$action" in
    add) append_row "$section" "$value" "$note" || { rc=$?; rm -f "$backup"; return "$rc"; } ;;
    edit|toggle|delete)
      update_row "$section" "$index" "$action" "$value" "$note" "$enabled" \
        || { rc=$?; rm -f "$backup"; return "$rc"; } ;;
    *) rm -f "$backup"; return 2 ;;
  esac

  if [ "$section" = rule ]; then apply_mode=full; else apply_mode=fast; fi
  if sh "$MP/scripts/apply.sh" "$apply_mode"; then
    rm -f "$backup"
    echo "applied=1"
    return 0
  fi
  cp -p "$backup" "$CONF.restore.$$" && chmod 600 "$CONF.restore.$$" \
    && mv -f "$CONF.restore.$$" "$CONF" || {
      rm -f "$backup"; echo "managed-list rollback failed" >&2; return 11;
    }
  sh "$MP/scripts/apply.sh" fast >/dev/null 2>&1 || echo "previous list restored; apply reconciliation failed" >&2
  rm -f "$backup"
  echo "apply failed; previous list restored" >&2
  return 1
}

cmd=${1:-list}
[ "$#" -ge 2 ] || { echo "usage: $0 list|add|edit|toggle|delete LIST_ID ..." >&2; exit 2; }
section="$(resolve_section "$2")" || { echo "unknown managed list: $2" >&2; exit 2; }

case "$cmd" in
  list)
    echo FXLIST1
    list_rows "$section"
    ;;
  add)
    [ "$#" -eq 4 ] || { echo "usage: $0 add LIST_ID VALUE NOTE" >&2; exit 2; }
    valid_field "$3" && valid_note "$4" || { echo "invalid value or note" >&2; exit 2; }
    if [ "$section" = rule ]; then
      case "$3" in http://*|https://*) : ;; *) echo "subscription URL must use HTTP(S)" >&2; exit 2 ;; esac
    fi
    with_lock mutate_transaction add "$section" -1 "$3" "$4" 1
    ;;
  edit)
    [ "$#" -eq 6 ] || { echo "usage: $0 edit LIST_ID INDEX VALUE NOTE ENABLED" >&2; exit 2; }
    case "$3" in ''|*[!0-9]*) exit 2 ;; esac
    valid_field "$4" && valid_note "$5" || { echo "invalid value or note" >&2; exit 2; }
    case "$6" in 0|1) : ;; *) exit 2 ;; esac
    with_lock mutate_transaction edit "$section" "$3" "$4" "$5" "$6"
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
    sh "$MP/scripts/apply.sh" full
    ;;
  *)
    echo "unknown operation: $cmd" >&2
    exit 2
    ;;
esac
