#!/system/bin/sh
# Regression for the QuickJS privilege-import bypass: qjs:os/std/bjson and .so
# imports must be blocked while FX host APIs remain usable.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
INFO="$ROOT/bin/arm64/qjs.BUILD-INFO.txt"
SUM="$ROOT/bin/arm64/qjs.sha256"
PROBE="$ROOT/scripts/jsruntime/privileged-import-smoke.js"
RUNNER="$ROOT/scripts/jsruntime/runner.sh"
[ -s "$INFO" ] && grep -qi 'import.*boundary\|module import.*block\|sandbox' "$INFO" || {
  echo 'FAIL: bundled qjs is not marked as hardened'; exit 1;
}
[ -s "$SUM" ] && [ -s "$ROOT/bin/arm64/qjs" ] || { echo 'FAIL: qjs checksum/binary missing'; exit 1; }
(cd "$ROOT/bin/arm64" && sha256sum -c qjs.sha256 >/dev/null) || { echo 'FAIL: qjs SHA-256 mismatch'; exit 1; }
[ -s "$PROBE" ] && [ -s "$ROOT/scripts/jsruntime/host.js" ] || { echo 'FAIL: runtime smoke files missing'; exit 1; }
grep -Fq 'qjs:os' "$INFO" && grep -Fq 'before module-cache lookup' "$INFO" || {
  echo 'FAIL: hardened import boundary metadata missing'; exit 1;
}
sh -n "$RUNNER"
# On an Android target device this actually runs the packaged ARM64 binary in an
# isolated temporary state directory. Host x86 CI only runs the static checks.
if "$ROOT/bin/arm64/qjs" --version >/dev/null 2>&1; then
  T=$(mktemp -d)
  trap 'rm -rf "$T"' EXIT HUP INT TERM
  MOD="$T/module"; PGDIR="$T/state"
  mkdir -p "$MOD/bin/arm64" "$MOD/scripts/jsruntime" "$PGDIR/scripts"
  cp "$ROOT/bin/arm64/qjs" "$MOD/bin/arm64/qjs"
  cp "$ROOT/scripts/jsruntime/runner.sh" "$ROOT/scripts/jsruntime/host.js" "$ROOT/scripts/jsruntime/http.sh" "$MOD/scripts/jsruntime/"
  cp "$PROBE" "$PGDIR/scripts/privileged-import-smoke.js"
  chmod 700 "$PGDIR" "$PGDIR/scripts"
  chmod 755 "$MOD/bin/arm64/qjs" "$MOD/scripts/jsruntime/runner.sh" "$MOD/scripts/jsruntime/http.sh"
  printf '{}\n' > "$T/event.json"
  out=$(PG="$PGDIR" sh "$MOD/scripts/jsruntime/runner.sh" "$PGDIR/scripts/privileged-import-smoke.js" "$T/event.json")
  printf '%s' "$out" | grep -Fq '"sandbox":true' || { echo "FAIL: privileged imports were not all blocked: $out"; exit 1; }
else
  echo 'SKIP: target-runtime smoke requires Android arm64; build metadata and SHA-256 verified on this host.'
fi
echo 'FX QuickJS privileged/native module import regression: PASS (static checks; runtime only on Android arm64)'
