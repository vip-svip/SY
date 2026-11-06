#!/system/bin/sh
# Execute one JavaScript script with the FX QuickJS-NG host prelude.
set -u
case "$0" in */scripts/jsruntime/runner.sh) MODDIR=${0%/scripts/jsruntime/runner.sh} ;; *) MODDIR=${MODDIR:-/data/adb/modules/privacyguard} ;; esac
QJS="$MODDIR/bin/arm64/qjs"
HOST="$MODDIR/scripts/jsruntime/host.js"
HTTP="$MODDIR/scripts/jsruntime/http.sh"
PG=${PG:-/data/adb/privacyguard}
STATE="$PG/jsruntime"
[ -x "$QJS" ] || { echo '{"ok":false,"error":"QuickJS ARM64 binary missing"}'; exit 127; }
[ -f "$HOST" ] || { echo '{"ok":false,"error":"host bridge missing"}'; exit 127; }
[ "$#" -ge 1 ] || { echo 'usage: runner.sh SCRIPT.js [event.json]'; exit 64; }
SCRIPT=$1; EVENT=${2:-}
case "$SCRIPT" in /*) ;; *) SCRIPT="$PG/scripts/$SCRIPT" ;; esac
[ -f "$SCRIPT" ] || { echo '{"ok":false,"error":"script file not found"}'; exit 66; }
mkdir -p "$STATE" || exit 73
chmod 700 "$STATE" 2>/dev/null || :
EV="$STATE/event-$$.json"; OUT="$STATE/stdout-$$.log"; ERR="$STATE/stderr-$$.log"; RESULT="$STATE/result-$$.json"
if [ -n "$EVENT" ] && [ -f "$EVENT" ]; then cp "$EVENT" "$EV" || exit 74; else printf '{}\n' > "$EV"; fi
chmod 600 "$EV" 2>/dev/null || :
# FX_EGERN_SCRIPT_ENTRY_V2_BEGIN
EXEC_SCRIPT=$SCRIPT
EGERN_SCRIPT="$STATE/egern-$$.js"
if grep -Eq '^[[:space:]]*export[[:space:]]+default[[:space:]]+(async[[:space:]]+)?function([[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*)?[[:space:]]*\(' "$SCRIPT"; then
  if ! sed -E \
      -e 's/^([[:space:]]*)export[[:space:]]+default[[:space:]]+async[[:space:]]+function([[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*)?[[:space:]]*\(/\1globalThis.__fxEgernMain = async function\2(/' \
      -e 's/^([[:space:]]*)export[[:space:]]+default[[:space:]]+function([[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*)?[[:space:]]*\(/\1globalThis.__fxEgernMain = function\2(/' \
      "$SCRIPT" > "$EGERN_SCRIPT"; then
    rm -f "$EGERN_SCRIPT"
    echo '{"ok":false,"error":"unable to prepare Egern script"}'
    exit 74
  fi
  cat >> "$EGERN_SCRIPT" <<'FX_EGERN_ENTRY'
if (typeof globalThis.__fxEgernMain !== 'function') throw new Error('Egern default function was not found');
try {
  const __fxEgernResult = globalThis.__fxEgernMain(globalThis.ctx);
  if (__fxEgernResult && typeof __fxEgernResult.then === 'function') {
    __fxEgernResult.then(function(value) { globalThis.$done(value); },
      function(error) { globalThis.__fxEgernFail(error); });
  } else {
    globalThis.$done(__fxEgernResult);
  }
} catch (error) {
  globalThis.__fxEgernFail(error);
}
FX_EGERN_ENTRY
  chmod 600 "$EGERN_SCRIPT" 2>/dev/null || :
  EXEC_SCRIPT=$EGERN_SCRIPT
fi
# FX_EGERN_SCRIPT_ENTRY_V2_END
# Bound the JS heap and recursion stack per script. Third-party modules can run
# on every matching request, so malformed/hostile scripts must not exhaust the
# entire MITM process through runaway allocation or recursion.
"$QJS" --std --memory-limit 65536 --stack-size 1024 -C -I "$HOST" "$EXEC_SCRIPT" "$EV" "$STATE" "$HTTP" "$RESULT" >"$OUT" 2>"$ERR"
rc=$?
if [ "$rc" -eq 0 ]; then
  if [ -s "$RESULT" ]; then
    cat "$RESULT"
  else
    echo '{"ok":false,"done":false,"error":"script returned without calling $done(); no changes were applied"}'
    rc=70
  fi
else
  echo '{"ok":false,"done":false,"error":"JavaScript execution failed; inspect stderr log"}'
  cat "$ERR" >&2
fi
rm -f "$EV" "$OUT" "$ERR" "$RESULT" "$EGERN_SCRIPT" "$EGERN_SCRIPT"
exit "$rc"
