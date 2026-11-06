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

is_duplicate_pair() {
  printf '%s' "$1" > "$VALUE_FILE" || return 1
  printf '%s' "$2" > "$NOTE_FILE" || return 1
  awk -F'|' -v vf="$VALUE_FILE" -v nf="$NOTE_FILE" '
    BEGIN { getline v < vf; getline n < nf; close(vf); close(nf) }
    $1 == v && $2 == n { found=1 }
    END { exit !found }
  ' "$ROWS"
}
is_duplicate_local_source() {
  base64 < "$VALUE_FILE" | tr -d '\n' > "$VALUE_B64_FILE" || return 1
  printf '%s' "$1" > "$NOTE_FILE" || return 1
  awk -F'|' -v bf="$VALUE_B64_FILE" -v nf="$NOTE_FILE" '
    BEGIN {
      getline encoded < bf; close(bf)
      getline n < nf; close(nf)
      expected = "FXSRC_B64:" encoded
    }
    $1 == expected && $2 == n { found=1 }
    END { exit !found }
  ' "$ROWS"
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
  add|add-file|add-batch|update|toggle|toggle-all|delete)
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
    VALUE_B64_FILE="$PG/jsruntime/native-script-value64.$$"
    NOTE_FILE="$PG/jsruntime/native-script-note.$$"
    TMP="$CONF.native.tmp.$$"
    BACKUP="$CONF.native.bak.$$"
    cleanup() {
      rm -f "$ROWS" "$VALUE_FILE" "$VALUE_B64_FILE" "$NOTE_FILE" "$TMP" "$BACKUP"
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
        if is_duplicate_pair "$value" "$note"; then
          echo "OK DUPLICATE"
          exit 0
        fi
        printf '%s|%s|%s\n' "$value" "$note" "$enabled" >> "$ROWS"
        ;;
      add-batch)
        [ "$#" -eq 1 ] || { echo "ERROR add-batch expects manifest_path"; exit 64; }
        manifest=$1
        case "$manifest" in
          /data/user/[0-9]*/de.privacyguard.adhook/cache/fx-native-script-batch-*|/data/data/de.privacyguard.adhook/cache/fx-native-script-batch-*) ;;
          *) echo "ERROR batch manifest is outside the approved app cache"; exit 65 ;;
        esac
        [ -f "$manifest" ] && [ ! -L "$manifest" ] || { echo "ERROR batch manifest is missing or unsafe"; exit 65; }
        manifest_size=$(wc -c < "$manifest" 2>/dev/null | tr -d ' ')
        case "$manifest_size" in ''|*[!0-9]*) manifest_size=0 ;; esac
        [ "$manifest_size" -le 8388608 ] || { echo "ERROR batch manifest exceeds 8 MiB"; exit 65; }
        batch_added=0
        batch_duplicate=0
        batch_failed=0
        batch_lines=0
        while IFS='|' read -r kind value64 note64 enabled extra; do
          [ -n "$kind" ] || continue
          batch_lines=$((batch_lines+1))
          if [ "$batch_lines" -gt 512 ] || [ -n "$extra" ]; then
            batch_failed=$((batch_failed+1))
            continue
          fi
          case "$enabled" in 0|1) ;; *) batch_failed=$((batch_failed+1)); continue ;; esac
          case "$kind" in
            URL)
              url=$(decode_b64 "$value64") || { batch_failed=$((batch_failed+1)); continue; }
              note=$(decode_b64 "$note64") || { batch_failed=$((batch_failed+1)); continue; }
              [ -n "$url" ] && [ "${#note}" -le 4096 ] || { batch_failed=$((batch_failed+1)); continue; }
              case "$url" in
                https://*) ;;
                *) batch_failed=$((batch_failed+1)); continue ;;
              esac
              case "$url" in *[[:space:]]*) batch_failed=$((batch_failed+1)); continue ;; esac
              value=$(encode_script_value "$url") || { batch_failed=$((batch_failed+1)); continue; }
              note=$(sanitize_field "$note")
              [ -n "$note" ] || note=$(printf '%s' "$value" | cut -c1-80)
              if is_duplicate_pair "$value" "$note"; then
                batch_duplicate=$((batch_duplicate+1))
                continue
              fi
              printf '%s|%s|%s\n' "$value" "$note" "$enabled" >> "$ROWS" || {
                batch_failed=$((batch_failed+1)); continue;
              }
              batch_added=$((batch_added+1))
              ;;
            SOURCE)
              note=$(decode_b64 "$note64") || { batch_failed=$((batch_failed+1)); continue; }
              [ "${#note}" -le 4096 ] || { batch_failed=$((batch_failed+1)); continue; }
              : > "$VALUE_FILE"
              decode_b64 "$value64" > "$VALUE_FILE" || { batch_failed=$((batch_failed+1)); continue; }
              source_size=$(wc -c < "$VALUE_FILE" 2>/dev/null | tr -d ' ')
              case "$source_size" in ''|*[!0-9]*) source_size=0 ;; esac
              [ "$source_size" -gt 0 ] && [ "$source_size" -le 1048576 ] || {
                batch_failed=$((batch_failed+1)); continue;
              }
              first_line=$(sed -n '1{p;q;}' "$VALUE_FILE")
              if printf '%s' "$first_line" | grep -Eq '^[[:space:]]*[A-Za-z][A-Za-z0-9+.-]*://'; then
                batch_failed=$((batch_failed+1)); continue
              fi
              note=$(sanitize_field "$note")
              [ -n "$note" ] || note="Local JavaScript"
              if is_duplicate_local_source "$note"; then
                batch_duplicate=$((batch_duplicate+1))
                continue
              fi
              printf 'FXSRC_B64:' >> "$ROWS" || { batch_failed=$((batch_failed+1)); continue; }
              if ! base64 < "$VALUE_FILE" | tr -d '\n' >> "$ROWS"; then
                batch_failed=$((batch_failed+1)); continue;
              fi
              printf '|%s|%s\n' "$note" "$enabled" >> "$ROWS" || {
                batch_failed=$((batch_failed+1)); continue;
              }
              batch_added=$((batch_added+1))
              ;;
            *)
              batch_failed=$((batch_failed+1))
              ;;
          esac
        done < "$manifest"
        if [ "$batch_lines" -eq 0 ]; then
          echo "ERROR batch manifest is empty or invalid"
          exit 64
        fi
        if [ "$batch_added" -eq 0 ]; then
          echo "OK added=0 duplicate=$batch_duplicate failed=$batch_failed"
          exit 0
        fi
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
        note_length=$(printf '%s' "$note" | wc -c | tr -d ' ')
        case "$note_length" in ''|*[!0-9]*) note_length=4097 ;; esac
        [ "$note_length" -le 4096 ] || { echo "ERROR script metadata exceeds 4096 bytes"; exit 65; }
        cp "$source_path" "$VALUE_FILE" || { echo "ERROR unable to snapshot staged script"; exit 1; }
        [ -s "$VALUE_FILE" ] || { echo "ERROR script value is empty"; exit 64; }
        # Read only the first line for transport classification. Keep local JS
        # bytes file-backed until base64 encoding, rather than shell-expanding 1 MiB.
        first_line=$(sed -n '1{p;q;}' "$VALUE_FILE")
        case "$first_line" in
          https://*)
            value=$(cat "$VALUE_FILE") || { echo "ERROR unable to read HTTPS subscription"; exit 1; }
            case "$value" in *[[:space:]]*) echo "ERROR invalid HTTPS subscription URL"; exit 65 ;; esac
            value=$(encode_script_value "$value") || { echo "ERROR invalid HTTPS subscription URL"; exit 65; }
            note=$(sanitize_field "$note")
            if is_duplicate_pair "$value" "$note"; then
              echo "OK DUPLICATE"
              exit 0
            fi
            printf '%s|%s|%s\n' "$value" "$note" "$enabled" >> "$ROWS" || {
              echo "ERROR unable to append HTTPS subscription"; exit 1;
            }
            ;;
          *)
            if printf '%s' "$first_line" | grep -Eq '^[A-Za-z][A-Za-z0-9+.-]*://'; then
              echo "ERROR only HTTPS subscriptions or local JS source are supported"
              exit 65
            fi
            source_size=$(wc -c < "$VALUE_FILE" | tr -d ' ')
            case "$source_size" in ''|*[!0-9]*) source_size=0 ;; esac
            [ "$source_size" -gt 0 ] && [ "$source_size" -le 1048576 ] || {
              echo "ERROR local JS source must be between 1 byte and 1 MiB"
              exit 65
            }
            note=$(sanitize_field "$note")
            [ -n "$note" ] || note="Local JavaScript"
            if is_duplicate_local_source "$note"; then
              echo "OK DUPLICATE"
              exit 0
            fi
            if ! {
              printf 'FXSRC_B64:'
              base64 < "$VALUE_FILE" | tr -d '\n'
              printf '|%s|%s\n' "$note" "$enabled"
            } >> "$ROWS"; then
              echo "ERROR unable to append local JavaScript source"
              exit 1
            fi
            ;;
        esac
        ;;
      update)
        [ "$#" -eq 3 ] || { echo "ERROR update expects index value64 note64"; exit 64; }
        index=$1; case "$index" in ''|*[!0-9]*|0) echo "ERROR invalid index"; exit 64 ;; esac
        value=$(decode_b64 "$2") || { echo "ERROR invalid value encoding"; exit 64; }
        note=$(decode_b64 "$3") || { echo "ERROR invalid note encoding"; exit 64; }
        note_length=$(printf '%s' "$note" | wc -c | tr -d ' ')
        case "$note_length" in ''|*[!0-9]*) note_length=4097 ;; esac
        [ "$note_length" -le 4096 ] || { echo "ERROR script metadata exceeds 4096 bytes"; exit 65; }
        value=$(encode_script_value "$value") || { echo "ERROR only HTTPS URLs or local JS source are supported"; exit 65; }; note=$(sanitize_field "$note")
        [ -n "$note" ] || note=$(printf '%s' "$value" | cut -c1-80)
        printf '%s' "$value" > "$VALUE_FILE"; printf '%s' "$note" > "$NOTE_FILE"
        if awk -F'|' -v n="$index" -v vf="$VALUE_FILE" -v nf="$NOTE_FILE" '
          BEGIN { getline v < vf; getline d < nf; close(vf); close(nf) }
          { i++; if(i != n && $1 == v && $2 == d) found=1 }
          END { exit !found }
        ' "$ROWS"; then
          echo "ERROR duplicate script item already exists"
          exit 65
        fi
        awk -F'|' -v n="$index" -v vf="$VALUE_FILE" -v nf="$NOTE_FILE" 'BEGIN{getline v < vf; getline d < nf; OFS="|"} {i++; if(i==n){print v,d,$3; found=1}else print} END{if(!found)exit 4}' "$ROWS" > "$TMP.rows" || { rm -f "$TMP.rows"; echo "ERROR script index not found"; exit 66; }
        mv "$TMP.rows" "$ROWS"
        ;;
      toggle-all)
        [ "$#" -eq 1 ] || { echo "ERROR toggle-all expects enabled"; exit 64; }
        enabled=$1
        case "$enabled" in 0|1) ;; *) echo "ERROR enabled must be 0 or 1"; exit 64 ;; esac
        awk -F'|' -v e="$enabled" 'BEGIN{OFS="|"} NF >= 3 {$3=e; print; next} {print}' "$ROWS" > "$TMP.rows" || {
          echo "ERROR unable to stage bulk script state"; exit 1;
        }
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
    if [ "$ACTION" = "add-batch" ]; then
      echo "OK added=$batch_added duplicate=$batch_duplicate failed=$batch_failed"
    else
      echo "OK"
    fi
    ;;
  *) echo "ERROR usage: native-list.sh list|add|add-file|add-batch|update|toggle|toggle-all|delete"; exit 64 ;;
esac
