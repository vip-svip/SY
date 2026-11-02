#!/system/bin/sh
# Execute one enabled local JavaScript entry from the native Script list.
set -u
_d=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
MODDIR=$(CDPATH= cd -- "$_d/../.." 2>/dev/null && pwd)
[ -f "$MODDIR/module.prop" ] || { echo '{"ok":false,"error":"module directory unavailable"}'; exit 2; }
PG=${PG:-/data/adb/privacyguard}
STORE="$MODDIR/scripts/jsruntime/native-list.sh"
RUNNER="$MODDIR/scripts/jsruntime/runner.sh"
STATE="$PG/jsruntime"
[ -x "$STORE" ] || { echo '{"ok":false,"error":"native script store missing"}'; exit 127; }
[ -x "$RUNNER" ] || { echo '{"ok":false,"error":"QuickJS runner missing"}'; exit 127; }
[ "$#" -eq 1 ] || { echo '{"ok":false,"error":"usage: local-run.sh INDEX"}'; exit 64; }
index=$1
case "$index" in ''|*[!0-9]*|0) echo '{"ok":false,"error":"invalid script index"}'; exit 64 ;; esac
[ "$index" -le 128 ] 2>/dev/null || { echo '{"ok":false,"error":"script index out of range"}'; exit 64; }
umask 077
mkdir -p "$STATE/local" || exit 73
chmod 700 "$STATE" "$STATE/local" 2>/dev/null || :
LOCK="$PG/jsruntime/native-script-list.lock"
tries=0
while ! mkdir "$LOCK" 2>/dev/null; do
  owner=$(cat "$LOCK/pid" 2>/dev/null || true)
  case "$owner" in
    ''|*[!0-9]*)
      if [ "$tries" -ge 30 ]; then stale="$LOCK.stale.$$"; mv "$LOCK" "$stale" 2>/dev/null && rm -rf "$stale"; fi
      ;;
    *)
      if ! kill -0 "$owner" 2>/dev/null; then stale="$LOCK.stale.$$"; mv "$LOCK" "$stale" 2>/dev/null && rm -rf "$stale"; fi
      ;;
  esac
  [ "$tries" -lt 60 ] || { echo '{"ok":false,"error":"script list is busy"}'; exit 75; }
  tries=$((tries+1)); sleep 0.1
done
printf '%s\n' "$$" > "$LOCK/pid" || { rmdir "$LOCK" 2>/dev/null || :; exit 1; }
TMP="$STATE/local/source-$$.js"
LIST="$STATE/local/list-$$.txt"
OUT="$STATE/local/out-$$.json"
ERR="$STATE/local/err-$$.log"
cleanup() {
  rm -f "$TMP" "$LIST" "$OUT" "$ERR"
  owner=$(cat "$LOCK/pid" 2>/dev/null || true)
  if [ "$owner" = "$$" ]; then rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null || :; fi
}
trap cleanup EXIT HUP INT TERM
if ! sh "$STORE" list > "$LIST"; then echo '{"ok":false,"error":"unable to read script list"}'; exit 1; fi
row=$(sed -n "$((index+1))p" "$LIST")
[ -n "$row" ] || { echo '{"ok":false,"error":"script index not found"}'; exit 66; }
IFS='|' read -r value64 note64 enabled <<EOF_ROW
$row
EOF_ROW
[ "$enabled" = 1 ] || { echo '{"ok":false,"error":"script is disabled"}'; exit 65; }
stored=$(printf '%s' "$value64" | base64 -d 2>/dev/null) || { echo '{"ok":false,"error":"invalid script encoding"}'; exit 65; }
case "$stored" in
  FXSRC_B64:*) ;;
  *) echo '{"ok":false,"error":"only local JavaScript source can be run here"}'; exit 65 ;;
esac
source64=${stored#FXSRC_B64:}
[ -n "$source64" ] || { echo '{"ok":false,"error":"local JavaScript source is empty"}'; exit 65; }
printf '%s' "$source64" | base64 -d > "$TMP" 2>/dev/null || { echo '{"ok":false,"error":"local JavaScript source is corrupted"}'; exit 65; }
size=$(wc -c < "$TMP" | tr -d ' ')
case "$size" in ''|*[!0-9]*) size=0 ;; esac
[ "$size" -gt 0 ] && [ "$size" -le 65536 ] || { echo '{"ok":false,"error":"local JavaScript source size is invalid"}'; exit 65; }
chmod 600 "$TMP" 2>/dev/null || :
# Release the list lock before execution; the script file is now an immutable snapshot.
rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null || :
trap 'rm -f "$TMP" "$LIST" "$OUT" "$ERR"' EXIT HUP INT TERM
if "$RUNNER" "$TMP" > "$OUT" 2> "$ERR"; then
  result=$(cat "$OUT")
  case "$result" in \{"ok":true*|\{"ok":false*) printf '%s\n' "$result" ;; *) printf '%s\n' '{"ok":false,"error":"QuickJS returned an invalid result"}'; exit 70 ;; esac
  status=ok
else
  rc=$?
  printf '{"ok":false,"error":"QuickJS execution failed (exit %s); inspect private script log"}\n' "$rc"
  status="error:$rc"
fi
log="$STATE/local-run.log"
printf '%s|index=%s|bytes=%s|%s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$index" "$size" "$status" >> "$log"
chmod 600 "$log" 2>/dev/null || :
log_size=$(wc -c < "$log" 2>/dev/null | tr -d ' '); case "$log_size" in ''|*[!0-9]*) log_size=0 ;; esac
if [ "$log_size" -gt 262144 ]; then tail -n 300 "$log" > "$log.tmp.$$" && mv -f "$log.tmp.$$" "$log"; fi
[ "$status" = ok ] || exit 70
