#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
H="$ROOT/scripts/jsruntime/host.js"
R="$ROOT/scripts/jsruntime/runner.sh"
node --check "$H"
grep -Fq "const _fxResultPath = scriptArgs[4] || (_fxStateDir + '/last-result.json');" "$H"
grep -Fq '_fxWrite(_fxResultPath,JSON.stringify(out));' "$H"
grep -Fq 'RESULT="$STATE/result-$$.json"' "$R"
grep -Fq 'cat "$RESULT"' "$R"
grep -Fq 'rm -f "$EV" "$OUT" "$ERR" "$RESULT"' "$R"
echo 'FX JS runtime isolated-result regression: PASS'
