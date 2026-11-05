#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
HOST="$ROOT/scripts/jsruntime/host.js"
RUNNER="$ROOT/scripts/jsruntime/runner.sh"
grep -Fq 'const _fxEventPath = scriptArgs[1];' "$HOST"
grep -Fq 'const _fxStateDir = scriptArgs[2];' "$HOST"
grep -Fq 'const _fxHttp = scriptArgs[3];' "$HOST"
grep -Fq '"$QJS" --std --memory-limit 65536 --stack-size 1024 -C -I "$HOST" "$SCRIPT" "$EV" "$STATE" "$HTTP" "$RESULT"' "$RUNNER"
grep -Fq 'globalThis.$prefs' "$HOST"
grep -Fq 'globalThis.$task' "$HOST"
grep -Fq 'globalThis.$done' "$HOST"
# Optional real-engine regression on development hosts that have built QuickJS-NG.
QJS_NATIVE=${QJS_NATIVE:-/mnt/data/qjs-src/host-build/qjs}
if [ -x "$QJS_NATIVE" ]; then
  T=$(mktemp -d)
  trap 'rm -rf "$T"' EXIT HUP INT TERM
  cat > "$T/event.json" <<'JSON'
{"request":{"url":"https://example.test/path","method":"GET"},"response":{"status":204}}
JSON
  cat > "$T/test.js" <<'JS'
if ($request.url !== 'https://example.test/path') throw new Error('request event missing');
if ($response.statusCode !== 204) throw new Error('response statusCode mismatch');
$prefs.setValueForKey('runtime-test', 'pass');
Promise.resolve({pass:true}).then(v => $done(v));
JS
  "$QJS_NATIVE" --std -C -I "$HOST" "$T/test.js" "$T/event.json" "$T/state" /bin/true "$T/result.json" > "$T/out"
  cat "$T/result.json" > "$T/out"
  grep -Fq '"ok":true' "$T/out"
  grep -Fq '"done":true' "$T/out"
  grep -Fq '"pass":true' "$T/out"
  grep -Fq '"pass":"runtime-test"' "$T/out"
fi
echo 'FX QuickJS runtime argv regression: PASS'
