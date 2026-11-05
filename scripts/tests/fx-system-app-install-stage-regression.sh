#!/system/bin/sh
# Regression for the install-time system-app deployment stage in customize.sh.
#
# Contract: the FX module must validate and materialise its systemless
# system/app/FX/FX.apk payload during installation, fail closed on a damaged
# payload, and record a digest marker. It must never claim privileged status.
#
# Usage: sh fx-system-app-install-stage-regression.sh [path-to-module]
set -u

ROOT=$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)
MODULE=${1:-}
[ -n "$MODULE" ] || MODULE="$ROOT/fx-module"
CUSTOMIZE="$MODULE/customize.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "  ok: $*"; }

[ -s "$CUSTOMIZE" ] || fail "customize.sh missing at $CUSTOMIZE"
sh -n "$CUSTOMIZE" || fail "customize.sh does not parse"

BEGIN_MARK='# >>> fx-system-app-install-stage (managed by fx-patches/patch_system_app_install_stage.py)'
END_MARK='# <<< fx-system-app-install-stage'
grep -Fqx "$BEGIN_MARK" "$CUSTOMIZE" || fail "install-stage begin marker missing"
grep -Fqx "$END_MARK" "$CUSTOMIZE" || fail "install-stage end marker missing"
[ "$(grep -Fxc "$BEGIN_MARK" "$CUSTOMIZE")" -eq 1 ] || fail "install stage must appear exactly once"
grep -Fq 'if fx_system_app_stage; then' "$CUSTOMIZE" || fail "install stage is never invoked"

# FX is not a privileged app: the stage must not fabricate a privapp allowlist.
if grep -Fq 'privapp-permissions' "$CUSTOMIZE"; then
  grep -Fq '不声明 privapp 权限' "$CUSTOMIZE" || fail "customize.sh must state that no privapp allowlist is claimed"
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/fx-sysapp.XXXXXX") || fail "cannot create temp dir"
trap 'rm -rf "$TMP"' EXIT INT TERM

# Extract only the stage function definitions (variable setup + helpers + entry
# point) so the harness exercises the production logic, not a re-implementation.
awk -v begin="$BEGIN_MARK" -v stop='if fx_system_app_stage; then' '
  index($0, begin) { active = 1; next }
  active && index($0, stop) { exit }
  active { print }
' "$CUSTOMIZE" > "$TMP/stage.sh" || fail "cannot extract install stage"
[ -s "$TMP/stage.sh" ] || fail "extracted install stage is empty"
grep -Fq 'fx_system_app_stage() {' "$TMP/stage.sh" || fail "extracted stage lacks the deployment function"
sh -n "$TMP/stage.sh" || fail "extracted install stage does not parse"

HARNESS="$TMP/harness.sh"
cat > "$HARNESS" <<'HARNESS_EOF'
set -u
ui_print() { printf '%s\n' "$*"; }
. "$STAGE_LIB"
fx_system_app_stage
HARNESS_EOF

sha_of() {
  command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum unavailable" >&2; return 1; }
  sha256sum "$1" 2>/dev/null | awk 'NR==1 {print $1}'
}

# run_stage <module-root> <state-dir>
run_stage() {
  MODPATH="$1" STAGE_LIB="$TMP/stage.sh" \
    FX_SYSTEM_APP_STATE_DIR="$2" \
    DATE_PLACEHOLDER=1 \
    sh "$HARNESS" 2>&1
}

make_payload() {
  _dir=$1
  mkdir -p "$_dir/system/app/FX" "$_dir/optional" || return 1
  printf 'FX-APK-PAYLOAD-%s\n' "$2" > "$_dir/system/app/FX/FX.apk" || return 1
  sha_of "$_dir/system/app/FX/FX.apk" > "$_dir/system/app/FX/FX.apk.sha256" || return 1
}

echo "== case 1: valid overlay deploys and commits a digest marker =="
M="$TMP/m1"; S="$TMP/s1"
make_payload "$M" valid || fail "cannot build valid payload fixture"
out=$(run_stage "$M" "$S"); rc=$?
[ "$rc" -eq 0 ] || fail "valid overlay must deploy successfully (rc=$rc): $out"
[ -s "$S/system-app-apk.sha256" ] || fail "deployment marker was not written"
expected=$(sha_of "$M/system/app/FX/FX.apk")
[ "$(cat "$S/system-app-apk.sha256")" = "$expected" ] || fail "deployment marker digest mismatch"
[ ! -e "$S/system-app-retry" ] || fail "successful deployment must not leave a retry marker"
pass "valid overlay deployed, marker=$expected"

echo "== case 2: digest mismatch fails closed =="
M="$TMP/m2"; S="$TMP/s2"
make_payload "$M" corrupt || fail "cannot build corrupt payload fixture"
printf '%064d  FX.apk\n' 0 > "$M/system/app/FX/FX.apk.sha256"
out=$(run_stage "$M" "$S"); rc=$?
[ "$rc" -ne 0 ] || fail "digest mismatch must fail, got rc=0: $out"
[ ! -e "$S/system-app-apk.sha256" ] || fail "failed deployment must not write a success marker"
case "$out" in *"摘要与校验清单不一致"*) ;; *) fail "digest mismatch was not reported to the installer: $out" ;; esac
pass "corrupt overlay refused"

echo "== case 3: overlay without checksum sidecar fails closed =="
M="$TMP/m3"; S="$TMP/s3"
make_payload "$M" nosum || fail "cannot build fixture"
rm -f "$M/system/app/FX/FX.apk.sha256"
out=$(run_stage "$M" "$S"); rc=$?
[ "$rc" -ne 0 ] || fail "missing checksum sidecar must fail, got rc=0: $out"
[ ! -e "$S/system-app-apk.sha256" ] || fail "no marker may be written without a checksum"
pass "missing checksum refused"

echo "== case 4: malformed checksum sidecar fails closed =="
M="$TMP/m4"; S="$TMP/s4"
make_payload "$M" bad || fail "cannot build fixture"
printf 'not-a-sha256  FX.apk\n' > "$M/system/app/FX/FX.apk.sha256"
out=$(run_stage "$M" "$S"); rc=$?
[ "$rc" -ne 0 ] || fail "malformed checksum must fail, got rc=0: $out"
pass "malformed checksum refused"

echo "== case 5: legacy archive stages the overlay from the optional payload =="
M="$TMP/m5"; S="$TMP/s5"
mkdir -p "$M/optional" || fail "cannot build legacy fixture"
printf 'FX-LEGACY-PAYLOAD\n' > "$M/optional/FXUnifiedHook.apk"
out=$(run_stage "$M" "$S"); rc=$?
[ "$rc" -eq 0 ] || fail "legacy payload must be staged (rc=$rc): $out"
[ -s "$M/system/app/FX/FX.apk" ] || fail "legacy payload did not materialise the overlay APK"
[ -s "$M/system/app/FX/FX.apk.sha256" ] || fail "legacy staging did not write a checksum sidecar"
expected=$(sha_of "$M/optional/FXUnifiedHook.apk")
[ "$(cat "$M/system/app/FX/FX.apk.sha256" | awk 'NR==1 {print $1}')" = "$expected" ] ||
  fail "staged overlay checksum does not match the optional payload"
[ "$(sha_of "$M/system/app/FX/FX.apk")" = "$expected" ] || fail "staged overlay content differs from the optional payload"
[ -s "$S/system-app-apk.sha256" ] || fail "legacy staging did not commit a marker"
pass "legacy payload promoted to a validated system-app overlay"

echo "== case 6: archive without any payload skips cleanly =="
M="$TMP/m6"; S="$TMP/s6"
mkdir -p "$M" || fail "cannot build empty fixture"
out=$(run_stage "$M" "$S"); rc=$?
[ "$rc" -eq 0 ] || fail "absent payload must be a clean skip (rc=$rc): $out"
[ ! -e "$M/system" ] || fail "skip path must not create a system-app directory"
[ ! -e "$S/system-app-apk.sha256" ] || fail "skip path must not write a marker"
pass "absent payload skipped"

echo "== case 7: redeploy is idempotent =="
M="$TMP/m1"; S="$TMP/s1"
first=$(cat "$S/system-app-apk.sha256")
out=$(run_stage "$M" "$S"); rc=$?
[ "$rc" -eq 0 ] || fail "repeat deployment must succeed (rc=$rc): $out"
[ "$(cat "$S/system-app-apk.sha256")" = "$first" ] || fail "repeat deployment changed the marker"
pass "repeat deployment stable"

echo "PASS: install-time system-app deployment validates, stages, fails closed and stays idempotent"
