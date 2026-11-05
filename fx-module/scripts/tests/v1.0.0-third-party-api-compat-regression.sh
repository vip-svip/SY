#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
H="$ROOT/scripts/jsruntime/host.js"
node --check "$H"
for api in '$persistentStore' '$notification' '$notify' '$script' '$argument' '$input' '$surge' '$loon' '$stash' '$rocket' 'statusCode:r.statusCode'; do
  grep -Fq "$api" "$H" || { echo "FAIL: missing compatibility API $api"; exit 1; }
done
grep -q 'notifications.jsonl' "$H"
grep -q 'not non-blocking network I/O' "$H"
grep -Fq 'Math.min(20,Number(options.timeout||globalThis.$httpClient.timeout||10))' "$H" || { echo 'FAIL: HTTP timeout exceeds the per-script bridge budget'; exit 1; }
grep -Fq 'const scriptExecutionTimeout = 25 * time.Second' "$ROOT/mitm/main.go" || { echo 'FAIL: script execution deadline is shorter than the bounded HTTP bridge timeout'; exit 1; }
echo 'FX third-party API compatibility static regression: PASS'
