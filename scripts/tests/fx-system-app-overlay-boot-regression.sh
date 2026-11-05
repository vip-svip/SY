#!/system/bin/sh
# Host regression for the real early-boot FX system-app overlay verifier.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SOURCE="$ROOT/fx-module/post-fs-data.sh"
[ -s "$SOURCE" ] || { echo "FAIL: post-fs-data source missing" >&2; exit 1; }
sh -n "$SOURCE" || { echo "FAIL: post-fs-data syntax invalid" >&2; exit 1; }
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-overlay-boot.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
BIN="$T/bin"
mkdir -p "$BIN"
# The SELinux command stubs share a file-backed context so tests can
# exercise restorecon/chcon fallback across their separate process invocations.
cat > "$BIN/ls" <<'LS'
#!/bin/sh
if [ "${1:-}" = "-Zd" ]; then
  _context=${FX_TEST_CONTEXT_FILE:-}
  _value='u:object_r:system_file:s0'
  [ -z "$_context" ] || [ ! -s "$_context" ] || _value=$(cat "$_context")
  printf '%s %s\n' "$_value" "${2:-}"
else
  exec /bin/ls "$@"
fi
LS
cat > "$BIN/restorecon" <<'RESTORE'
#!/bin/sh
[ "${FX_TEST_RESTORECON_RC:-0}" -eq 0 ] || exit "${FX_TEST_RESTORECON_RC:-1}"
[ -z "${FX_TEST_CONTEXT_FILE:-}" ] || printf '%s\n' 'u:object_r:system_file:s0' > "$FX_TEST_CONTEXT_FILE"
exit 0
RESTORE
cat > "$BIN/chcon" <<'CHCON'
#!/bin/sh
[ "${FX_TEST_CHCON_RC:-0}" -eq 0 ] || exit "${FX_TEST_CHCON_RC:-1}"
[ -z "${FX_TEST_CONTEXT_FILE:-}" ] || printf '%s\n' "$1" > "$FX_TEST_CONTEXT_FILE"
exit 0
CHCON
chmod 0755 "$BIN/ls" "$BIN/restorecon" "$BIN/chcon"
make_payload(){
  _dir=$1
  mkdir -p "$_dir"
  printf 'FX-APK-%s\n' "$2" > "$_dir/FX.apk"
  sha256sum "$_dir/FX.apk" | awk '{print $1 "  FX.apk"}' > "$_dir/FX.apk.sha256"
}
run_boot(){
  FX_SYSTEM_APP_DIR="$1" FX_SYSTEM_APP_STATE_DIR="$2" PATH="$BIN:$PATH" sh "$SOURCE"
}
run_boot_with_selinux(){
  FX_SYSTEM_APP_DIR="$1" FX_SYSTEM_APP_STATE_DIR="$2" \
    FX_TEST_CONTEXT_FILE="$3" FX_TEST_RESTORECON_RC="$4" \
    FX_TEST_CHCON_RC="$5" PATH="$BIN:$PATH" sh "$SOURCE"
}
echo "== valid overlay writes verified marker atomically =="
APP="$T/system/app/FX"; STATE="$T/state"
make_payload "$APP" valid
run_boot "$APP" "$STATE"
expected=$(sha256sum "$APP/FX.apk" | awk '{print $1}')
[ "$(cat "$STATE/system-app-apk.sha256")" = "$expected" ] || { echo "FAIL: verified deployment marker mismatch" >&2; exit 1; }
[ ! -e "$STATE/system-app-retry" ] || { echo "FAIL: valid overlay left retry marker" >&2; exit 1; }
[ "$(stat -c %a "$STATE/system-app-apk.sha256")" = 600 ] || { echo "FAIL: deployment marker mode is not 0600" >&2; exit 1; }

echo "== restorecon failure falls back to chcon and verifies the resulting label =="
APP_FALLBACK="$T/system-fallback/app/FX"; STATE_FALLBACK="$T/state-fallback"
CONTEXT_FALLBACK="$T/context-fallback"
make_payload "$APP_FALLBACK" selinux-fallback
printf '%s\n' 'u:object_r:vendor_file:s0' > "$CONTEXT_FALLBACK"
run_boot_with_selinux "$APP_FALLBACK" "$STATE_FALLBACK" "$CONTEXT_FALLBACK" 1 0
[ "$(cat "$CONTEXT_FALLBACK")" = 'u:object_r:system_file:s0' ] || { echo "FAIL: chcon fallback did not apply system_file label" >&2; exit 1; }
[ ! -e "$STATE_FALLBACK/system-app-retry" ] || { echo "FAIL: successful chcon fallback left retry marker" >&2; exit 1; }

echo "== failed restorecon and chcon leave a retry marker rather than claiming success =="
APP_LABEL_FAIL="$T/system-label-fail/app/FX"; STATE_LABEL_FAIL="$T/state-label-fail"
CONTEXT_LABEL_FAIL="$T/context-label-fail"
make_payload "$APP_LABEL_FAIL" selinux-failure
printf '%s\n' 'u:object_r:vendor_file:s0' > "$CONTEXT_LABEL_FAIL"
run_boot_with_selinux "$APP_LABEL_FAIL" "$STATE_LABEL_FAIL" "$CONTEXT_LABEL_FAIL" 1 1
[ -s "$STATE_LABEL_FAIL/system-app-retry" ] || { echo "FAIL: unavailable SELinux relabel did not create retry marker" >&2; exit 1; }
[ "$(cat "$CONTEXT_LABEL_FAIL")" = 'u:object_r:vendor_file:s0' ] || { echo "FAIL: failed chcon unexpectedly changed SELinux label" >&2; exit 1; }

echo "== invalid overlay creates a private retry marker =="
APP2="$T/system2/app/FX"; STATE2="$T/state2"
make_payload "$APP2" invalid
printf '%064d  FX.apk\n' 0 > "$APP2/FX.apk.sha256"
run_boot "$APP2" "$STATE2"
[ -s "$STATE2/system-app-retry" ] || { echo "FAIL: invalid digest did not create retry marker" >&2; exit 1; }
[ "$(stat -c %a "$STATE2/system-app-retry")" = 600 ] || { echo "FAIL: retry marker mode is not 0600" >&2; exit 1; }

echo "== absent system-app overlay creates a retry marker instead of silently skipping =="
APP_MISSING="$T/not-mounted/system/app/FX"; STATE_MISSING="$T/state-missing"
run_boot "$APP_MISSING" "$STATE_MISSING"
[ -s "$STATE_MISSING/system-app-retry" ] || { echo "FAIL: missing overlay did not create a retry marker" >&2; exit 1; }
[ "$(stat -c %a "$STATE_MISSING/system-app-retry")" = 600 ] || { echo "FAIL: missing-overlay retry marker mode is not 0600" >&2; exit 1; }

echo "== symlinked ancestor is rejected before state/log creation =="
OUT="$T/outside"; PARENT="$T/parent"
mkdir -p "$OUT"
ln -s "$OUT" "$PARENT"
APP3="$T/system3/app/FX"; make_payload "$APP3" bad-parent
printf '%064d  FX.apk\n' 0 > "$APP3/FX.apk.sha256"
run_boot "$APP3" "$PARENT/state"
[ ! -e "$OUT/state" ] || { echo "FAIL: state path followed a symlinked ancestor" >&2; exit 1; }

echo "== pre-created retry temp symlink cannot redirect root write =="
APP4="$T/system4/app/FX"; STATE4="$T/state4"; make_payload "$APP4" bad-temp
printf '%064d  FX.apk\n' 0 > "$APP4/FX.apk.sha256"
mkdir -p "$STATE4"
printf 'keep-me\n' > "$T/sentinel"
PIDFILE="$T/child.pid"; GO="$T/go"
FX_SYSTEM_APP_DIR="$APP4" FX_SYSTEM_APP_STATE_DIR="$STATE4" sh -c 'printf "%s\n" "$$" > "$1"; while [ ! -e "$2" ]; do sleep 0.01; done; exec sh "$3"' sh "$PIDFILE" "$GO" "$SOURCE" &
child=$!
tries=0
while [ ! -s "$PIDFILE" ] && [ "$tries" -lt 200 ]; do tries=$((tries+1)); sleep 0.01; done
[ -s "$PIDFILE" ] || { echo "FAIL: child did not publish PID" >&2; exit 1; }
child_pid=$(cat "$PIDFILE")
# The PID published inside the exec wrapper is authoritative for the script temporary path.
ln -s "$T/sentinel" "$STATE4/system-app-retry.tmp.$child_pid"
touch "$GO"
wait "$child"
[ "$(cat "$T/sentinel")" = "keep-me" ] || { echo "FAIL: retry temp symlink target was overwritten" >&2; exit 1; }
[ ! -e "$STATE4/system-app-retry" ] || { echo "FAIL: unsafe retry temp unexpectedly committed" >&2; exit 1; }

echo "== pre-created deployment marker temp symlink cannot redirect root write =="
APP5="$T/system5/app/FX"; STATE5="$T/state5"; make_payload "$APP5" bad-marker-temp
mkdir -p "$STATE5"
printf 'keep-marker\n' > "$T/marker-sentinel"
PIDFILE5="$T/child5.pid"; GO5="$T/go5"
FX_SYSTEM_APP_DIR="$APP5" FX_SYSTEM_APP_STATE_DIR="$STATE5" sh -c 'printf "%s\n" "$$" > "$1"; while [ ! -e "$2" ]; do sleep 0.01; done; exec sh "$3"' sh "$PIDFILE5" "$GO5" "$SOURCE" &
child5=$!
tries=0
while [ ! -s "$PIDFILE5" ] && [ "$tries" -lt 200 ]; do tries=$((tries+1)); sleep 0.01; done
[ -s "$PIDFILE5" ] || { echo "FAIL: deployment-marker child did not publish PID" >&2; exit 1; }
child5_pid=$(cat "$PIDFILE5")
# The PID published inside the exec wrapper is authoritative for the script temporary path.
ln -s "$T/marker-sentinel" "$STATE5/system-app-apk.sha256.tmp.$child5_pid"
touch "$GO5"
wait "$child5"
[ "$(cat "$T/marker-sentinel")" = "keep-marker" ] || { echo "FAIL: deployment marker temp symlink target was overwritten" >&2; exit 1; }
[ -s "$STATE5/system-app-retry" ] || { echo "FAIL: unsafe deployment marker temp did not produce a retry marker" >&2; exit 1; }
[ ! -e "$STATE5/system-app-apk.sha256" ] || { echo "FAIL: unsafe deployment marker temp unexpectedly committed" >&2; exit 1; }

echo "PASS: early-boot overlay digest, SELinux relabel fallback/failure, atomic markers and symlink regressions"
