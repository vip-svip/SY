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
cat > "$BIN/ls" <<'LS'
#!/bin/sh
if [ "${1:-}" = "-Zd" ]; then
  printf 'u:object_r:system_file:s0 %s\n' "${2:-}"
else
  exec /bin/ls "$@"
fi
LS
cat > "$BIN/restorecon" <<'RESTORE'
#!/bin/sh
exit 0
RESTORE
chmod 0755 "$BIN/ls" "$BIN/restorecon"
make_payload(){
  _dir=$1
  mkdir -p "$_dir"
  printf 'FX-APK-%s\n' "$2" > "$_dir/FX.apk"
  sha256sum "$_dir/FX.apk" | awk '{print $1 "  FX.apk"}' > "$_dir/FX.apk.sha256"
}
run_boot(){
  FX_SYSTEM_APP_DIR="$1" FX_SYSTEM_APP_STATE_DIR="$2" PATH="$BIN:$PATH" sh "$SOURCE"
}
echo "== valid overlay writes verified marker atomically =="
APP="$T/system/app/FX"; STATE="$T/state"
make_payload "$APP" valid
run_boot "$APP" "$STATE"
expected=$(sha256sum "$APP/FX.apk" | awk '{print $1}')
[ "$(cat "$STATE/system-app-apk.sha256")" = "$expected" ] || { echo "FAIL: verified deployment marker mismatch" >&2; exit 1; }
[ ! -e "$STATE/system-app-retry" ] || { echo "FAIL: valid overlay left retry marker" >&2; exit 1; }
[ "$(stat -c %a "$STATE/system-app-apk.sha256")" = 600 ] || { echo "FAIL: deployment marker mode is not 0600" >&2; exit 1; }

echo "== invalid overlay creates a private retry marker =="
APP2="$T/system2/app/FX"; STATE2="$T/state2"
make_payload "$APP2" invalid
printf '%064d  FX.apk\n' 0 > "$APP2/FX.apk.sha256"
run_boot "$APP2" "$STATE2"
[ -s "$STATE2/system-app-retry" ] || { echo "FAIL: invalid digest did not create retry marker" >&2; exit 1; }
[ "$(stat -c %a "$STATE2/system-app-retry")" = 600 ] || { echo "FAIL: retry marker mode is not 0600" >&2; exit 1; }

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
FX_SYSTEM_APP_DIR="$APP4" FX_SYSTEM_APP_STATE_DIR="$STATE4" sh -c 'printf "%s\n" "$" > "$1"; while [ ! -e "$2" ]; do sleep 0.01; done; exec sh "$3"' sh "$PIDFILE" "$GO" "$SOURCE" &
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
FX_SYSTEM_APP_DIR="$APP5" FX_SYSTEM_APP_STATE_DIR="$STATE5" sh -c 'printf "%s\n" "$" > "$1"; while [ ! -e "$2" ]; do sleep 0.01; done; exec sh "$3"' sh "$PIDFILE5" "$GO5" "$SOURCE" &
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

echo "PASS: early-boot overlay digest, atomic markers, ancestor symlink, retry-temp and deployment-marker-temp symlink regressions"
