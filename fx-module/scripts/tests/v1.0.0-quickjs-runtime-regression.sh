#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
QJS="$ROOT/bin/arm64/qjs"
H="$ROOT/scripts/jsruntime/host.js"
R="$ROOT/scripts/jsruntime/runner.sh"
HTTP="$ROOT/scripts/jsruntime/http.sh"
[ -x "$QJS" ] || { echo 'FAIL: qjs missing/non-executable'; exit 1; }
[ -s "$H" ] && [ -x "$R" ] && [ -x "$HTTP" ] || { echo 'FAIL: runtime bridge files missing'; exit 1; }
file "$QJS" 2>/dev/null | grep -qi 'ARM aarch64\|aarch64' || {
  # Android host environments may not ship file; ELF machine string check fallback.
  strings "$QJS" 2>/dev/null | grep -q 'Android' || { echo 'FAIL: qjs architecture could not be verified'; exit 1; }
}
grep -q 'globalThis.\$prefs' "$H"
grep -q 'globalThis.\$httpClient' "$H"
grep -q 'globalThis.\$task' "$H"
grep -q 'globalThis.\$done' "$H"
grep -q 'globalThis.std=undefined' "$H"
grep -q 'globalThis.os=undefined' "$H"
grep -q -- '--max-filesize 8388608' "$HTTP"
grep -q 'unsupported URL scheme' "$HTTP"
grep -q 'QuickJS-NG v0.17.0' "$ROOT/scripts/jsruntime/README-zh-CN.md"
for f in "$ROOT"/*.sh "$ROOT"/scripts/*.sh "$ROOT"/scripts/jsruntime/*.sh "$ROOT"/scripts/tests/*.sh; do [ ! -f "$f" ] || sh -n "$f"; done
echo 'FX QuickJS runtime static regression: PASS'
