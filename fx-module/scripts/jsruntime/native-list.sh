#!/system/bin/sh
# Native FX Hook script-list store. settings.conf [list:script] remains the
# single source of truth consumed by pg_list and jsruntime/sync-subs.sh.
set -eu
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
MODDIR=$(CDPATH= cd -- "$SELF_DIR/../.." 2>/dev/null && pwd)
[ -f "$MODDIR/module.prop" ] || { echo "ERROR module directory unavailable"; exit 2; }
PG=${PG:-/data/adb/privacyguard}
CONF=${CONF:-$PG/settings.conf}
UTIL="$MODDIR/scripts/util.sh"
[ -r "$UTIL" ] || { echo "ERROR FX config library unavailable"; exit 2; }
. "$UTIL"
mkdir -p "$PG/jsruntime" || exit 1

sanitize_field() { printf '%s' "$1" | tr '\r\n' '  ' | sed 's/|/｜/g'; }
encode_script_value() {
  case "$1" in
    https://*) sanitize_field "$1" ;;
    http://*) return 1 ;;
    *)
      if printf '%s' "$1" | grep -Eq '^[A-Za-z][A-Za-z0-9+.-]*://'; then return 1; fi
      printf 'FXSRC_B64:%s' "$(printf '%s' "$1" | base64 | tr -d '\n')"
      ;;
  esac
}
decode_b64() {
  # Base64 producers may wrap long payloads; base64 -d safely ignores line breaks.
  # The argument is never evaluated by the shell, only passed to printf as data.
  printf '%s' "$1" | base64 -d 2>/dev/null
}
ACTION=${1:-}
shift || :
case "$ACTION" in
  list)
    [ -r "$CONF" ] || { echo "ERROR settings.conf unavailable"; exit 1; }
    printf 'FXSCRIPT1\n'
    pg_list script | while IFS='|' read -r value note enabled rest; do
      case "$value" in ''|\#*) continue ;; esac
      case "$enabled" in 1) enabled=1 ;; *) enabled=0 ;; esac
      value64=$(printf '%s' "$value" | base64 | tr -d '\n')
      note64=$(printf '%s' "$note" | base64 | tr -d '\n')
      printf '%s|%s|%s\n' "$value64" "$note64" "$enabled"
    done
    ;;
  add|add-file|update|toggle|delete)
    [ -f "$CONF" ] || { echo "ERROR settings.conf missing"; exit 1; }
    LOCK="$PG/jsruntime/native-script-list.lock"
    tries=0
    while ! mkdir "$LOCK" 2>/dev/null; do
      owner=$(cat "$LOCK/pid" 2>/dev/null || true)
      case "$owner" in
        ''|*[!0-9]*)
          if [ "$tries" -ge 20 ]; then stale="$LOCK.stale.$$"; mv "$LOCK" "$stale" 2>/dev/null && rm -rf "$stale"; fi
          ;;
        *)
          if ! kill -0 "$owner" 2>/dev/null; then stale="$LOCK.stale.$$"; mv "$LOCK" "$stale" 2>/dev/null && rm -rf "$stale"; fi
          ;;
      esac
      [ "$tries" -lt 60 ] || { echo "ERROR script list is busy"; exit 75; }
      tries=$((tries+1)); sleep 0.1
    done
    printf '%s\n' "$$" > "$LOCK/pid"
    ROWS="$PG/jsruntime/native-script-rows.$$"
    VALUE_FILE="$PG/jsruntime/native-script-value.$$"
    NOTE_FILE="$PG/jsruntime/native-script-note.$$"
    TMP="$CONF.native.tmp.$$"
    BACKUP="$CONF.native.bak.$$"
    cleanup() {
      rm -f "$ROWS" "$VALUE_FILE" "$NOTE_FILE" "$TMP" "$BACKUP"
      owner=$(cat "$LOCK/pid" 2>/dev/null || true)
      if [ "$owner" = "$$" ]; then rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null || :; fi
    }
    trap cleanup EXIT HUP INT TERM
    # Do not race a WebUI config transaction that has not committed yet.
    if [ -e "$CONF.txn" ] || [ -e "$CONF.tmp" ]; then
      echo "ERROR settings.conf transaction in progress; retry after it finishes"; exit 75
    fi
    pg_list script | awk 'NF && $0 !~ /^[[:space:]]*#/ {print}' > "$ROWS"
    count=$(wc -l < "$ROWS" | tr -d ' ')
    case "$count" in ''|*[!0-9]*) count=0 ;; esac
    case "$ACTION" in
      add)
        [ "$#" -eq 3 ] || { echo "ERROR add expects value64 note64 enabled"; exit 64; }
        value=$(decode_b64 "$1") || { echo "ERROR invalid value encoding"; exit 64; }
        note=$(decode_b64 "$2") || { echo "ERROR invalid note encoding"; exit 64; }
        enabled=$3
        case "$enabled" in 0|1) ;; *) echo "ERROR enabled must be 0 or 1"; exit 64 ;; esac
        [ -n "$value" ] || { echo "ERROR script value is empty"; exit 64; }
        [ "${#note}" -le 4096 ] || { echo "ERROR script metadata exceeds 4096 characters"; exit 65; }
        value=$(encode_script_value "$value") || { echo "ERROR only HTTPS URLs or local JS source are supported"; exit 65; }; note=$(sanitize_field "$note")
        [ -n "$note" ] || note=$(printf '%s' "$value" | cut -c1-80)
        printf '%s|%s|%s\n' "$value" "$note" "$enabled" >> "$ROWS"
        ;;
      add-file)
        [ "$#" -eq 3 ] || { echo "ERROR add-file expects source_path note64 enabled"; exit 64; }
        source_path=$1
        case "$source_path" in
          /data/user/[0-9]*/de.privacyguard.adhook/cache/fx-native-script-*|/data/data/de.privacyguard.adhook/cache/fx-native-script-*|"$PG"/jsruntime/staging/fx-native-script-*) ;;
          *) echo "ERROR source file is outside an approved staging area"; exit 65 ;;
        esac
        [ -f "$source_path" ] && [ ! -L "$source_path" ] || { echo "ERROR staged script file is missing or unsafe"; exit 65; }
        note=$(decode_b64 "$2") || { echo "ERROR invalid note encoding"; exit 64; }
        enabled=$3
        case "$enabled" in 0|1) ;; *) echo "ERROR enabled must be 0 or 1"; exit 64 ;; esac
        [ "${#note}" -le 4096 ] || { echo "ERROR script metadata exceeds 4096 characters"; exit 65; }
        cp "$source_path" "$VALUE_FILE" || { echo "ERROR unable to snapshot staged script"; exit 1; }
        [ -s "$VALUE_FILE" ] || { echo "ERROR script value is empty"; exit 64; }
        # Read one line for transport classification only. Local source bytes stay
        # file-backed all the way through base64 encoding; never copy the full
        # JavaScript payload into a shell variable.
        first_line=$(sed -n '1{p;q;}' "$VALUE_FILE")
        case "$first_line" in
          https://*)
            value=$(cat "$VALUE_FILE") || { echo "ERROR unable to read HTTPS subscription"; exit 1; }
            case "$value" in *[[:space:]]*) echo "ERROR invalid HTTPS subscription URL"; exit 65 ;; esac
            value=$(encode_script_value "$value") || { echo "ERROR invalid HTTPS subscription URL"; exit 65; }
            printf '%s|%s|%s\n' "$value" "$(sanitize_field "$note")" "$enabled" >> "$ROWS"
            ;;
          *)
            if printf '%s' "$first_line" | grep -Eq '^[A-Za-z][A-Za-z0-9+.-]*://'; then
              echo "ERROR only HTTPS subscriptions or local JS source are supported"; exit 65
            fi
            note=$(sanitize_field "$note")
            [ -n "$note" ] || note="Local JavaScript"
            printf 'FXSRC_B64:' >> "$ROWS"
            base64 < "$VALUE_FILE" | tr -d '\n' >> "$ROWS"
            printf '|%s|%s\n' "$note" "$enabled" >> "$ROWS"
            ;;
        esac
        ;;
      update)
        [ "$#" -eq 3 ] || { echo "ERROR update expects index value64 note64"; exit 64; }
        index=$1; case "$index" in ''|*[!0-9]*|0) echo "ERROR invalid index"; exit 64 ;; esac
        value=$(decode_b64 "$2") || { echo "ERROR invalid value encoding"; exit 64; }
        note=$(decode_b64 "$3") || { echo "ERROR invalid note encoding"; exit 64; }
        [ -n "$value" ] && [ "${#note}" -le 4096 ] || { echo "ERROR invalid script value or name"; exit 65; }
        value=$(encode_script_value "$value") || { echo "ERROR only HTTPS URLs or local JS source are supported"; exit 65; }; note=$(sanitize_field "$note")
        [ -n "$note" ] || note=$(printf '%s' "$value" | cut -c1-80)
        printf '%s' "$value" > "$VALUE_FILE"; printf '%s' "$note" > "$NOTE_FILE"
        awk -F'|' -v n="$index" -v vf="$VALUE_FILE" -v nf="$NOTE_FILE" 'BEGIN{getline v < vf; getline d < nf; OFS="|"} {i++; if(i==n){print v,d,$3; found=1}else print} END{if(!found)exit 4}' "$ROWS" > "$TMP.rows" || { rm -f "$TMP.rows"; echo "ERROR script index not found"; exit 66; }
        mv "$TMP.rows" "$ROWS"
        ;;
      toggle)
        [ "$#" -eq 2 ] || { echo "ERROR toggle expects index enabled"; exit 64; }
        index=$1; enabled=$2
        case "$index" in ''|*[!0-9]*|0) echo "ERROR invalid index"; exit 64 ;; esac
        case "$enabled" in 0|1) ;; *) echo "ERROR enabled must be 0 or 1"; exit 64 ;; esac
        awk -F'|' -v n="$index" -v e="$enabled" 'BEGIN{OFS="|"} {i++; if(i==n){print $1,$2,e; found=1}else print} END{if(!found)exit 4}' "$ROWS" > "$TMP.rows" || { rm -f "$TMP.rows"; echo "ERROR script index not found"; exit 66; }
        mv "$TMP.rows" "$ROWS"
        ;;
      delete)
        [ "$#" -eq 1 ] || { echo "ERROR delete expects index"; exit 64; }
        index=$1; case "$index" in ''|*[!0-9]*|0) echo "ERROR invalid index"; exit 64 ;; esac
        awk -F'|' -v n="$index" '{i++; if(i==n){found=1;next} print} END{if(!found)exit 4}' "$ROWS" > "$TMP.rows" || { rm -f "$TMP.rows"; echo "ERROR script index not found"; exit 66; }
        mv "$TMP.rows" "$ROWS"
        ;;
    esac
    awk -v rows="$ROWS" '
      function emit_rows(line) { while ((getline line < rows) > 0) print line; close(rows) }
      $0 == "[list:script]" { if (!seen) { print; emit_rows(); seen=1 } in_script=1; next }
      /^\[/ { in_script=0 }
      in_script { next }
      { print }
      END { if (!seen) { print ""; print "[list:script]"; emit_rows() } }
    ' "$CONF" > "$TMP" || { echo "ERROR unable to stage settings.conf"; exit 1; }
    [ -s "$TMP" ] || { echo "ERROR staged settings.conf is empty"; exit 1; }
    cp -p "$CONF" "$BACKUP" && cmp -s "$CONF" "$BACKUP" || { echo "ERROR unable to verify settings backup"; exit 1; }
    mv -f "$TMP" "$CONF" || { echo "ERROR unable to commit settings.conf"; exit 1; }
    chmod 600 "$CONF" 2>/dev/null || { cp -p "$BACKUP" "$CONF"; echo "ERROR unable to protect settings.conf"; exit 1; }
    # The Android module invokes this as root. Host regressions may run as an
    # unprivileged CI user; do not fail a valid atomic write merely because that
    # user cannot chown. Root execution naturally preserves root ownership.
    if [ "$(id -u)" = 0 ]; then
      chown 0:0 "$CONF" 2>/dev/null || { cp -p "$BACKUP" "$CONF"; echo "ERROR unable to restore settings ownership"; exit 1; }
    fi
    [ -f "$CONF" ] || { cp -p "$BACKUP" "$CONF"; echo "ERROR committed settings.conf missing"; exit 1; }
    echo "OK"
    ;;
  *) echo "ERROR usage: native-list.sh list|add|update|toggle|delete"; exit 64 ;;
esac
