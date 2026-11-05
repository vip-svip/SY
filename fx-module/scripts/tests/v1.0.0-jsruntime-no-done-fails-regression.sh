#!/bin/sh
# Prove the runner does not report success when a script forgets to call $done().
set -eu
SRC=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
MOD="$TMP/module"
PG="$TMP/state"
mkdir -p "$MOD/bin/arm64" "$MOD/scripts/jsruntime" "$PG/scripts"
: > "$MOD/module.prop"
cp "$SRC/scripts/jsruntime/runner.sh" "$MOD/scripts/jsruntime/runner.sh"
cp "$SRC/scripts/jsruntime/host.js" "$MOD/scripts/jsruntime/host.js"
cp "$SRC/scripts/jsruntime/http.sh" "$MOD/scripts/jsruntime/http.sh"
chmod +x "$MOD/scripts/jsruntime/runner.sh" "$MOD/scripts/jsruntime/http.sh"
# Host-side stub stands in for qjs: it exits cleanly but never invokes host $done().
cat > "$MOD/bin/arm64/qjs" <<'STUB'
#!/bin/sh
exit 0
STUB
chmod +x "$MOD/bin/arm64/qjs"
printf '// intentionally does not call $done()\n' > "$PG/scripts/no-done.js"
set +e
out=$(PG="$PG" sh "$MOD/scripts/jsruntime/runner.sh" "$PG/scripts/no-done.js" 2>&1)
rc=$?
set -e
[ "$rc" -eq 70 ] || { echo "FAIL: expected runner rc=70, got $rc output=$out"; exit 1; }
printf '%s' "$out" | grep -Fq 'without calling $done()' || { echo "FAIL: missing no-done diagnostic: $out"; exit 1; }
printf '%s' "$out" | grep -Fq '"ok":false' || { echo "FAIL: no-done result was not marked failed: $out"; exit 1; }
echo 'FX JS script missing-$done fail-state regression: PASS'
