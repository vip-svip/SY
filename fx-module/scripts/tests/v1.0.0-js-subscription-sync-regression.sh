#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
S="$ROOT/scripts/jsruntime/sync-subs.sh"
M="$ROOT/mitm/main.go"
[ -x "$S" ] || { echo 'FAIL: script subscription synchronizer missing'; exit 1; }
grep -Fq 'https://*) ;;' "$S"
grep -Fq '1048576' "$S"
grep -Fq 'sha256sum' "$S"
grep -Fq -- '--proto-redir' "$S"
# The size cap must be enforced by curl while downloading, not only after the file is on disk.
grep -Fq -- '--max-filesize 1048576' "$S" || { echo 'FAIL: JS subscription download has no transfer-time size cap'; exit 1; }
grep -Fq 'curl required for HTTPS-only script downloads' "$S"
grep -Fq 'last known good script' "$S"
grep -Fq 'FX-SCRIPT-TYPE' "$S"
grep -Fq 'FX-SCRIPT-MATCH' "$S"
grep -Fq 'FXMETA_B64:' "$S"
grep -Fq 'base64 -d' "$S"
grep -Fq 'applyRequestScripts(req)' "$M"
grep -Fq 'applyResponseScripts(req, resp)' "$M"
grep -Fq 'scriptBodyLimit = 1 << 20' "$M"
sh -n "$S"

# End-to-end sync test with a fake curl transport: metadata wrapping, commit hash, and last-known-good retention.
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
MOD="$T/module"; PGDIR="$T/pg"; mkdir -p "$MOD/scripts/jsruntime" "$T/bin"
cp "$ROOT/module.prop" "$MOD/module.prop"
cp "$ROOT/scripts/util.sh" "$MOD/scripts/util.sh"
cp "$S" "$MOD/scripts/jsruntime/sync-subs.sh"
URL='https://scripts.example.net/rewrite.js'
META=$(printf '%s\n%s\n' response '^https://example\.com/api/.*' | base64 | tr -d '\r\n')
mkdir -p "$PGDIR"
cat > "$PGDIR/settings.conf" <<EOF_CONF
[list:script]
$URL|FXMETA_B64:$META|1
EOF_CONF
cat > "$T/fixture.js" <<'JS'
$done({body: $response.body});
JS
cat > "$T/bin/curl" <<'CURL'
#!/bin/sh
out=''
while [ "$#" -gt 0 ]; do
  if [ "$1" = '-o' ]; then shift; out=$1; fi
  shift
done
[ -n "$out" ] || exit 64
[ "${FAIL_FETCH:-0}" = 1 ] && exit 7
if [ "${SLOW_FETCH:-0}" = 1 ]; then
  if [ -n "${COUNTER_DIR:-}" ]; then
    if ! mkdir "$COUNTER_DIR/active" 2>/dev/null; then touch "$COUNTER_DIR/overlap"; exit 67; fi
    sleep 1
    rmdir "$COUNTER_DIR/active" 2>/dev/null || :
  else
    sleep 1
  fi
fi
cat "$FIXTURE" > "$out"
CURL
chmod 755 "$T/bin/curl"
PATH="$T/bin:$PATH" FIXTURE="$T/fixture.js" PG="$PGDIR" sh "$MOD/scripts/jsruntime/sync-subs.sh" > "$T/sync.json"
key=$(printf '%s\n%s' "$URL" "FXMETA_B64:$META" | cksum | awk '{print $1}')
TARGET="$PGDIR/jsruntime/scripts/pgsub_${key}.js"
[ -s "$TARGET" ] || { echo 'FAIL: synchronized script missing'; exit 1; }
sed -n '1p' "$TARGET" | grep -Fq '// FX-SCRIPT-TYPE: response'
sed -n '2p' "$TARGET" | grep -Fq '^https://example\.com/api/.*'
expected=$(sha256sum "$TARGET" | awk '{print $1}')
actual=$(awk '{print $1}' "$TARGET.sha256")
[ "$expected" = "$actual" ] || { echo 'FAIL: script SHA-256 sidecar mismatch'; exit 1; }
# Concurrent manual refresh / scheduler / engine-start calls must serialize because
# each process publishes an active manifest and prunes files absent from its snapshot.
mkdir -p "$T/parallel-counter"
LOCK="$PGDIR/jsruntime/sync-subs.lock"
PATH="$T/bin:$PATH" FIXTURE="$T/fixture.js" PG="$PGDIR" SLOW_FETCH=1 COUNTER_DIR="$T/parallel-counter" sh "$MOD/scripts/jsruntime/sync-subs.sh" > "$T/parallel1.json" 2>"$T/parallel1.err" &
p1=$!
i=0
while [ ! -f "$LOCK/pid" ] && [ "$i" -lt 100 ]; do sleep 0.02; i=$((i + 1)); done
[ -f "$LOCK/pid" ] || { echo 'FAIL: script sync did not publish its lock owner'; exit 1; }
PATH="$T/bin:$PATH" FIXTURE="$T/fixture.js" PG="$PGDIR" SLOW_FETCH=1 COUNTER_DIR="$T/parallel-counter" sh "$MOD/scripts/jsruntime/sync-subs.sh" > "$T/parallel2.json" 2>"$T/parallel2.err" &
p2=$!
rc1=0; rc2=0
wait "$p1" || rc1=$?
wait "$p2" || rc2=$?
[ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] || { echo "FAIL: serialized sync failed (rc1=$rc1 rc2=$rc2)"; cat "$T/parallel1.err" "$T/parallel2.err"; exit 1; }
[ ! -e "$T/parallel-counter/overlap" ] || { echo 'FAIL: two script sync processes overlapped the active fetch'; exit 1; }
[ ! -e "$LOCK" ] || { echo 'FAIL: script sync lock was not released'; exit 1; }
if PATH="$T/bin:$PATH" FIXTURE="$T/fixture.js" PG="$PGDIR" FAIL_FETCH=1 sh "$MOD/scripts/jsruntime/sync-subs.sh" > "$T/fail.json" 2>/dev/null; then
  echo 'FAIL: simulated network error reported success'; exit 1
fi
[ -f "$TARGET" ] || { echo 'FAIL: failed refresh removed last-known-good script'; exit 1; }
[ "$(sha256sum "$TARGET" | awk '{print $1}')" = "$expected" ] || { echo 'FAIL: failed refresh changed cached script'; exit 1; }
echo 'FX script subscription sync regression (atomic install + concurrency): PASS'
