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
[ "$#" -eq 2 ] || { echo '{"ok":false,"error":"usage: local-run.sh INDEX EXPECTED_SHA256"}'; exit 64; }
index=$1
expected_sha=$2
case "$expected_sha" in ''|*[!0-9a-fA-F]*) echo '{"ok":false,"error":"invalid expected source hash"}'; exit 64 ;; esac
[ "${#expected_sha}" -eq 64 ] || { echo '{"ok":false,"error":"invalid expected source hash length"}'; exit 64; }
case "$index" in ''|*[!0-9]*|0) echo '{"ok":false,"error":"invalid script index"}'; exit 64 ;; esac
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
  if [ "$owner" = "$$" ]; then
    released="$LOCK.release.$$"
    if mv "$LOCK" "$released" 2>/dev/null; then rm -rf "$released"; fi
  fi
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
[ "$size" -gt 0 ] || { echo '{"ok":false,"error":"local JavaScript source is empty"}'; exit 65; }
chmod 600 "$TMP" 2>/dev/null || :
actual_sha=$(sha256sum "$TMP" 2>/dev/null | awk '{print $1}')
[ "$actual_sha" = "$expected_sha" ] || { echo '{"ok":false,"error":"script list changed; refresh the Script page before running"}'; exit 75; }
# Release the list lock before execution; the script file is now an immutable snapshot.
released="$LOCK.release.$$"
if mv "$LOCK" "$released" 2>/dev/null; then rm -rf "$released"; fi
trap 'rm -f "$TMP" "$LIST" "$OUT" "$ERR"' EXIT HUP INT TERM
if command -v timeout >/dev/null 2>&1; then
  timeout -k 2 25 "$RUNNER" "$TMP" > "$OUT" 2> "$ERR"
  rc=$?
elif command -v busybox >/dev/null 2>&1 && busybox timeout -k 2 25 "$RUNNER" "$TMP" > "$OUT" 2> "$ERR"; then
  rc=0
else
  rc=$?
  if ! command -v timeout >/dev/null 2>&1 && ! command -v busybox >/dev/null 2>&1; then
    printf '%s\n' '{"ok":false,"error":"bounded execution unavailable: timeout command missing"}'
    exit 127
  fi
fi
if [ "$rc" -eq 0 ]; then
  result=$(cat "$OUT")
  if printf '%s' "$result" | grep -Eq '^[[:space:]]*\{[[:space:]]*"ok"[[:space:]]*:[[:space:]]*(true|false)([,}])'; then
    printf '%s\n' "$result"
  else
    printf '%s\n' '{"ok":false,"error":"QuickJS returned an invalid result"}'
    exit 70
  fi
  status=ok
else
  printf '{"ok":false,"error":"QuickJS execution failed or timed out (exit %s); inspect private script log"}\n' "$rc"
  status="error:$rc"
fi
log="$STATE/local-run.log"
printf '%s|index=%s|bytes=%s|%s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$index" "$size" "$status" >> "$log"
chmod 600 "$log" 2>/dev/null || :
log_size=$(wc -c < "$log" 2>/dev/null | tr -d ' '); case "$log_size" in ''|*[!0-9]*) log_size=0 ;; esac
if [ "$log_size" -gt 262144 ]; then tail -n 300 "$log" > "$log.tmp.$$" && mv -f "$log.tmp.$$" "$log"; fi
[ "$status" = ok ] || exit 70
