#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
MODULE="$ROOT"
if [ -d "$ROOT/fx-module" ]; then MODULE="$ROOT/fx-module"; fi
# The tracked installer/remover are the Host regression's source of truth.
# The partial Host checkout may contain an older Release module copy; the
# KernelSU package lane synchronizes and byte-verifies that copy before running
# this same regression.
INSTALLER="$ROOT/scripts/install_adhook_app.sh"
REMOVER="$ROOT/scripts/remove_adhook_app.sh"
WORKFLOW_ROOT="$ROOT"
[ -s "$WORKFLOW_ROOT/.github/workflows/build-fx-adhook.yml" ] || WORKFLOW_ROOT=$(CDPATH= cd -- "$ROOT/.." && pwd)
WORKFLOW="$WORKFLOW_ROOT/.github/workflows/build-fx-adhook.yml"
KSU_WORKFLOW="$WORKFLOW_ROOT/.github/workflows/build-fx-kernelsu.yml"
SERVICE="$WORKFLOW_ROOT/fx-module/service.sh"
POST_FS_DATA="$WORKFLOW_ROOT/fx-module/post-fs-data.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
pass(){ echo "  PASS: $*"; }
[ -s "$INSTALLER" ] && [ -s "$REMOVER" ] || fail "installer/remover missing"
[ -s "$WORKFLOW" ] || fail "FX APK build workflow missing"
[ -s "$KSU_WORKFLOW" ] || fail "KernelSU ZIP build workflow missing"
grep -Fq '_overlay_apk="$MODDIR/system/app/FX/FX.apk"' "$INSTALLER" || fail "installer does not prefer the system-app overlay"
grep -Fq 'refusing ordinary-app fallback' "$INSTALLER" || fail "installer may silently downgrade a mounted system-app overlay"
grep -Fq 'if [ -s "$_overlay_apk" ] && [ "$_is_system_app" != 1 ]; then' "$INSTALLER" || fail "installer does not require PackageManager system classification for the overlay"
grep -Fq 'install -m 0644 "$BUILT_APK" fx-module/system/app/FX/FX.apk' "$KSU_WORKFLOW" || fail "KernelSU release pipeline does not stage the APK as a system app"
grep -Fq 'sha256sum FX.apk > FX.apk.sha256' "$KSU_WORKFLOW" || fail "KernelSU system-app overlay checksum is missing"
grep -Fq 'test "$BUILT_APK_SHA" = "$SYSTEM_APK_SHA"' "$KSU_WORKFLOW" || fail "KernelSU ZIP overlay is not verified against the signed build output"
grep -Fq 'system/app/FX/FX.apk.sha256' "$KSU_WORKFLOW" || fail "KernelSU package verification does not include the system-app checksum"
grep -Fq 'cmp -s "$RUNNER_TEMP/FX-system-app-overlay.apk" "$RUNNER_TEMP/FXUnifiedHook.zip-entry.apk"' "$KSU_WORKFLOW" || fail "KernelSU ZIP overlay does not match its ordinary APK payload"
! grep -Fq 'fx-module/system/priv-app/FX' "$KSU_WORKFLOW" || fail "unsigned APK must not be staged as a privileged app"
[ -s "$POST_FS_DATA" ] || fail "system-app overlay post-fs-data SELinux handler missing"
sh -n "$POST_FS_DATA" || fail "system-app overlay post-fs-data handler has invalid shell syntax"
grep -Fq 'system-app overlay directory is not mounted' "$POST_FS_DATA" || fail "missing system-app overlay directory does not create a retry marker"
grep -Fq 'system-app overlay APK is missing or unsafe' "$POST_FS_DATA" || fail "missing/unsafe system-app APK does not create a retry marker"
grep -Fq 'The boot service runs' "$POST_FS_DATA" || fail "post-fs-data missing-overlay behavior lacks the PackageManager scan-order rationale"
grep -Fq 'restorecon -RF "$APP_DIR"' "$POST_FS_DATA" || fail "system-app overlay does not apply path-derived SELinux context"
grep -Fq 'chcon u:object_r:system_file:s0' "$POST_FS_DATA" || fail "system-app overlay has no system_file context fallback"
grep -Fq 'chown 0:0 "$APP_DIR" "$APK_PATH"' "$POST_FS_DATA" || fail "system-app overlay ownership is not normalized"
grep -Fq 'chmod 0644 "$APK_PATH"' "$POST_FS_DATA" || fail "system-app APK mode is not normalized"
grep -Fq 'SUM_PATH="$APP_DIR/FX.apk.sha256"' "$POST_FS_DATA" || fail "post-fs-data does not require the packaged overlay checksum"
grep -Fq 'sha256sum "$APK_PATH"' "$POST_FS_DATA" || fail "post-fs-data does not verify the mounted APK digest"
grep -Fq 'DEPLOYMENT_MARKER="$STATE_DIR/system-app-apk.sha256"' "$POST_FS_DATA" || fail "post-fs-data does not reconcile the deployment marker"
grep -Fq 'RETRY_MARKER="$STATE_DIR/system-app-retry"' "$POST_FS_DATA" || fail "post-fs-data does not preserve a retry marker on verification/label failures"
grep -Fq 'deployment marker does not match the mounted overlay' "$POST_FS_DATA" || fail "post-fs-data does not reject stale deployment markers"
grep -Fq 'rm -f "$RETRY_MARKER"' "$POST_FS_DATA" || fail "post-fs-data does not clear retry state after successful verification"
grep -Fq '[ ! -L "$STATE_DIR" ] || exit 0' "$POST_FS_DATA" || fail "post-fs-data retry writer does not reject a symlinked state directory"
grep -Fq '[ -d "$LOG_DIR" ] && [ ! -L "$LOG_DIR" ]' "$POST_FS_DATA" || fail "post-fs-data log writer does not reject a symlinked log directory"
! grep -Eq 'pm grant|privapp-permissions' "$POST_FS_DATA" || fail "unprivileged system app must not receive fabricated privileged grants"
grep -Fq 'pm list packages -s "$1"' "$INSTALLER" || fail "installer does not verify PackageManager system classification"
grep -Fq '_stage_dir="$TMP_DIR/.fx-unified-hook-$.d"' "$INSTALLER" || fail "installer still uses a predictable shared APK staging file"
grep -Fq 'umask 077; mkdir "$_stage_dir"' "$INSTALLER" || fail "Hook staging directory is not created exclusively with a private umask"
grep -Fq 'chmod 0700 "$_stage_dir"' "$INSTALLER" || fail "Hook staging directory is not private"
grep -Fq 'cleanup_stage()' "$INSTALLER" || fail "private Hook staging directory has no bounded cleanup"
# The KSU lane restores an older Release ZIP. It must stage the reviewed installer
# and remover into that module before this test selects its scripts directory.
python3 - "$KSU_WORKFLOW" "$ROOT/fx-patches/patch_system_app_install_stage.py" "$ROOT/scripts/tests/fx-system-app-install-stage-behavior-regression.py" <<'PY'
from pathlib import Path
import sys
workflow, patcher, behavior = (
    Path(path).read_text(encoding="utf-8") for path in sys.argv[1:]
)
patch = workflow.index("python3 fx-patches/patch_system_app_install_stage.py fx-module")
installer_cmp = workflow.index("cmp -s scripts/install_adhook_app.sh fx-module/scripts/install_adhook_app.sh", patch)
remover_cmp = workflow.index("cmp -s scripts/remove_adhook_app.sh fx-module/scripts/remove_adhook_app.sh", patch)
regression = workflow.index("sh scripts/tests/adhook-app-installer-regression.sh", patch)
installer_copy = "install -D -m 0755 scripts/install_adhook_app.sh fx-module/scripts/install_adhook_app.sh"
remover_copy = "install -D -m 0755 scripts/remove_adhook_app.sh fx-module/scripts/remove_adhook_app.sh"
assert workflow.count(installer_copy) == 0 and workflow.count(remover_copy) == 0, \
    "KernelSU workflow must not duplicate the patcher's canonical installer sync"
assert patch < installer_cmp < remover_cmp < regression, \
    "canonical installer/remover must be synchronized by the patcher, byte-verified, then tested"
assert "def sync_packaged_installer(root: Path)" in patcher and "sync_packaged_installer(root)" in patcher, \
    "system-app patcher must own canonical installer/remover synchronization"
assert 'patcher must synchronize canonical {name} into the module fixture' in behavior, \
    "system-app behavior fixture must prove the patcher's canonical module sync"
PY
grep -Fq 'verified FX Hook system app and module APK digest; no PackageManager reinstall required' "$INSTALLER" || fail "system-app overlay verification path missing"
grep -Fq '_installed_digest=$(sha256sum "$_system_installed_path"' "$INSTALLER" || fail "installer does not verify the PackageManager-resolved system APK digest"
grep -Fq '_is_system_app=1' "$INSTALLER" || fail "installer does not preserve system-app classification during updates"
grep -Fq 'install -m 0644 "$apk" fx-module/system/app/FX/FX.apk' "$WORKFLOW" || fail "build pipeline does not stage the APK into the system-app overlay"
grep -Fq 'sha256sum fx-module/system/app/FX/FX.apk' "$WORKFLOW" || fail "system-app overlay checksum is not generated"
grep -Fq 'not a privileged app; no platform signature or privileged permission grant is implied' "$WORKFLOW" || fail "system app build metadata omits privilege/signature boundary"
! grep -Fq 'fx-module/system/priv-app/FX' "$WORKFLOW" || fail "unsigned APK must not be staged as a privileged app"
[ -s "$SERVICE" ] || fail "KernelSU boot service missing"
sh -n "$SERVICE" || fail "KernelSU boot service has invalid shell syntax"
grep -Fq 'sh "$MODDIR/scripts/install_adhook_app.sh" "$MODDIR"' "$SERVICE" || fail "boot service does not deploy the FX APK"

# KernelSU must mount and label the systemless /system/app overlay before
# PackageManager's boot scan. Only verify/install through pm after boot completes.
python3 - "$SERVICE" "$POST_FS_DATA" <<'PY'
from pathlib import Path
import sys
service, post_fs_data = (Path(p).read_text(encoding="utf-8") for p in sys.argv[1:])
boot_wait = service.index('while [ "$(getprop sys.boot_completed)" != "1" ]')
boot_complete_gate = service.index('if [ "$(getprop sys.boot_completed)" = "1" ]; then', boot_wait)
apk_deploy = service.index('sh "$MODDIR/scripts/install_adhook_app.sh" "$MODDIR"')
defer_branch = service.index('Hook APK PackageManager work deferred: sys.boot_completed is not 1', boot_complete_gate)
assert boot_wait < boot_complete_gate < apk_deploy < defer_branch, \
    "Hook PackageManager work must be gated on boot completion and explicitly deferred after timeout"
assert "restorecon -RF \"$APP_DIR\"" in post_fs_data, "post-fs-data must label the mounted system-app overlay before zygote"
assert "pm install" not in post_fs_data and "pm path" not in post_fs_data, \
    "post-fs-data must not race PackageManager before its system-app scan"
PY
grep -Fq 'cmp -s scripts/install_adhook_app.sh fx-module/scripts/install_adhook_app.sh' "$KSU_WORKFLOW" || fail "KernelSU package does not verify canonical installer sync"
grep -Fq 'cmp -s scripts/remove_adhook_app.sh fx-module/scripts/remove_adhook_app.sh' "$KSU_WORKFLOW" || fail "KernelSU package does not verify canonical remover sync"
python3 - "$KSU_WORKFLOW" <<'PY'
from pathlib import Path
import sys
workflow = Path(sys.argv[1]).read_text(encoding="utf-8")
backup = workflow.index('install -m 0755 fx-module/post-fs-data.sh "$canonical_post_fs_data"')
release_copy = workflow.index('cp -a "$source_root/." fx-module/', backup)
restore = workflow.index('install -m 0755 "$canonical_post_fs_data" fx-module/post-fs-data.sh', release_copy)
verify = workflow.index('cmp -s "$canonical_post_fs_data" fx-module/post-fs-data.sh', restore)
assert backup < release_copy < restore < verify, \
    "Release restore must preserve and restore the reviewed SELinux post-fs-data handler"
PY
if [ "$MODULE" != "$ROOT" ]; then
  if cmp -s "$ROOT/scripts/install_adhook_app.sh" "$MODULE/scripts/install_adhook_app.sh" \
      && cmp -s "$ROOT/scripts/remove_adhook_app.sh" "$MODULE/scripts/remove_adhook_app.sh"; then
    echo "PASS: restored module installer/remover match canonical sources"
  else
    echo "SKIP: Host checkout contains stale Release installer copies; KernelSU workflow must synchronize and cmp both scripts before this regression."
  fi
fi
[ -s "$MODULE/uninstall.sh" ] || fail "KernelSU uninstall hook missing"
grep -Fq 'sh "$REMOVER" "$MODDIR" "$STATE_DIR"' "$MODULE/uninstall.sh" || fail "KernelSU uninstall hook does not invoke ownership-safe remover"
TMP="${TMPDIR:-/tmp}/fx-unified-installer-$$"; mkdir -p "$TMP/bin" "$TMP/mod/optional" "$TMP/mod/system/app/FX" "$TMP/state" "$TMP/tmp" "$TMP/pm"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
printf 'unified apk payload\n' > "$TMP/mod/optional/FXUnifiedHook.apk"; sha256sum "$TMP/mod/optional/FXUnifiedHook.apk" > "$TMP/mod/optional/FXUnifiedHook.apk.sha256"
cp "$TMP/mod/optional/FXUnifiedHook.apk" "$TMP/mod/system/app/FX/FX.apk"
sha256sum "$TMP/mod/system/app/FX/FX.apk" > "$TMP/mod/system/app/FX/FX.apk.sha256"
cat > "$TMP/bin/pm" <<'PM'
#!/bin/sh
set -eu
case "$1" in
 path) grep -Fxq "$2" "$FX_ADHOOK_FAKE_PM_STATE/installed" 2>/dev/null || exit 1; if [ "${FX_ADHOOK_FAKE_SYSTEM_DATA_PATH:-0}" = 1 ]; then [ -s "$FX_ADHOOK_FAKE_PM_STATE/$2.apk" ] && echo "package:$FX_ADHOOK_FAKE_PM_STATE/$2.apk" || exit 1; elif [ "${FX_ADHOOK_FAKE_SYSTEM_OVERLAY:-0}" = 1 ]; then echo "package:/system/app/FX/FX.apk"; else [ -s "$FX_ADHOOK_FAKE_PM_STATE/$2.apk" ] && echo "package:$FX_ADHOOK_FAKE_PM_STATE/$2.apk" || exit 1; fi;;
 list) [ "$2" = packages ] && [ "$3" = -s ] || exit 2; if [ "${FX_ADHOOK_FAKE_SYSTEM:-0}" = 1 ] && grep -Fxq "$4" "$FX_ADHOOK_FAKE_PM_STATE/installed" 2>/dev/null; then echo "package:$4"; fi;;
 install) [ "$2" = -r ] || exit 2; case "$3" in */.fx-unified-hook.*/*) _stage_dir=${3%/*}; [ -d "$_stage_dir" ] && [ ! -L "$_stage_dir" ] || exit 11; [ "$(stat -c '%a' "$_stage_dir")" = 700 ] || exit 12; if [ "${FX_ADHOOK_FAKE_SIGNATURE_MISMATCH:-0}" = 1 ]; then echo 'Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match]' >&2; exit 1; fi;; esac; if ! grep -Fxq de.privacyguard.adhook "$FX_ADHOOK_FAKE_PM_STATE/installed" 2>/dev/null; then [ ! -e "$FX_ADHOOK_STATE_DIR/adhook-apk-fxunifiedhook.fx-owned" ] || { echo "ownership marker was committed before pm install" >&2; exit 4; }; echo de.privacyguard.adhook >> "$FX_ADHOOK_FAKE_PM_STATE/installed"; fi; cp "$3" "$FX_ADHOOK_FAKE_PM_STATE/de.privacyguard.adhook.apk"; echo "$3" >> "$FX_ADHOOK_FAKE_PM_STATE/install-calls";;
 uninstall) if [ "$2" = -k ]; then _pkg=$3; echo "-k $_pkg" >> "$FX_ADHOOK_FAKE_PM_STATE/uninstall-calls"; else _pkg=$2; echo "$_pkg" >> "$FX_ADHOOK_FAKE_PM_STATE/uninstall-calls"; fi; sed "/^$_pkg$/d" "$FX_ADHOOK_FAKE_PM_STATE/installed" > "$FX_ADHOOK_FAKE_PM_STATE/installed.tmp"; mv "$FX_ADHOOK_FAKE_PM_STATE/installed.tmp" "$FX_ADHOOK_FAKE_PM_STATE/installed"; rm -f "$FX_ADHOOK_FAKE_PM_STATE/$_pkg.apk";;
 install-multiple) [ "$2" = -r ] || exit 2; shift 2; _found=0; for _apk in "$@"; do [ -s "$_apk" ] || exit 5; cp "$_apk" "$FX_ADHOOK_FAKE_PM_STATE/de.privacyguard.adhook.apk"; _found=1; done; [ "$_found" = 1 ] || exit 6; echo de.privacyguard.adhook >> "$FX_ADHOOK_FAKE_PM_STATE/installed";;
 *) exit 9;;
esac
PM
REAL_MKTEMP=$(command -v mktemp)
cat > "$TMP/bin/mktemp" <<'MKTEMP'
#!/bin/sh
set -eu
[ "${FX_ADHOOK_FAIL_MKTEMP:-0}" = 1 ] && exit 1
exec "$FX_ADHOOK_REAL_MKTEMP" "$@"
MKTEMP
chmod +x "$TMP/bin/mktemp"
export FX_ADHOOK_REAL_MKTEMP="$REAL_MKTEMP"
chmod +x "$TMP/bin/pm"; export PATH="$TMP/bin:$PATH" FX_ADHOOK_FAKE_PM_STATE="$TMP/pm" FX_ADHOOK_STATE_DIR="$TMP/state" FX_ADHOOK_TMP_DIR="$TMP/tmp" FX_ADHOOK_LOG="$TMP/state/install.log"
: > "$TMP/pm/installed"

# If unique private-directory creation fails, the installer must fail closed
# before PackageManager installation or ownership markers are written.
export FX_ADHOOK_FAIL_MKTEMP=1
out=$(sh "$INSTALLER" "$TMP/mod" 2>&1) && fail "failed private staging directory creation unexpectedly succeeded"
unset FX_ADHOOK_FAIL_MKTEMP
case "$out" in *"cannot create a private Hook staging directory"*) ;; *) fail "mktemp failure was not reported safely: $out" ;; esac
[ ! -s "$TMP/pm/install-calls" ] || fail "mktemp failure reached PackageManager install"
[ ! -e "$TMP/state/adhook-apk-fxunifiedhook.fx-owned" ] || fail "mktemp failure wrote an ownership marker"
pass "private staging directory creation failure is fail-closed"

# Reject symlinked APK payloads and checksum sidecars before PackageManager.
mv "$TMP/mod/system/app/FX/FX.apk" "$TMP/overlay-real.apk"
ln -s "$TMP/overlay-real.apk" "$TMP/mod/system/app/FX/FX.apk"
: > "$TMP/pm/install-calls"
out=$(sh "$INSTALLER" "$TMP/mod" 2>&1) && fail "symlinked system-app APK payload unexpectedly succeeded"
case "$out" in *"system-app overlay path is a symlink"*) ;; *) fail "symlinked APK payload was not rejected by the path guard: $out" ;; esac
[ ! -s "$TMP/pm/install-calls" ] || fail "symlinked APK payload reached PackageManager"
rm "$TMP/mod/system/app/FX/FX.apk"
mv "$TMP/overlay-real.apk" "$TMP/mod/system/app/FX/FX.apk"

mv "$TMP/mod/system/app/FX/FX.apk.sha256" "$TMP/overlay-real.sha256"
ln -s "$TMP/overlay-real.sha256" "$TMP/mod/system/app/FX/FX.apk.sha256"
: > "$TMP/pm/install-calls"
out=$(sh "$INSTALLER" "$TMP/mod" 2>&1) && fail "symlinked system-app checksum unexpectedly succeeded"
case "$out" in *"module APK checksum path is unsafe"*) ;; *) fail "symlinked APK checksum was not rejected: $out" ;; esac
[ ! -s "$TMP/pm/install-calls" ] || fail "symlinked APK checksum reached PackageManager"
rm "$TMP/mod/system/app/FX/FX.apk.sha256"
mv "$TMP/overlay-real.sha256" "$TMP/mod/system/app/FX/FX.apk.sha256"

# New system-app overlays must carry a well-formed checksum sidecar. Missing,
# malformed or mismatched metadata must fail before PackageManager is touched.
cp "$TMP/mod/system/app/FX/FX.apk.sha256" "$TMP/overlay.expected.sha256"
rm -f "$TMP/mod/system/app/FX/FX.apk.sha256"
if sh "$INSTALLER" "$TMP/mod" >/dev/null 2>&1; then fail "system overlay without checksum sidecar unexpectedly succeeded"; fi
[ ! -s "$TMP/pm/install-calls" ] || fail "missing overlay checksum reached PackageManager install"
[ ! -e "$TMP/state/adhook-apk-fxunifiedhook.sha256" ] || fail "missing overlay checksum wrote an ownership digest"
cp "$TMP/overlay.expected.sha256" "$TMP/mod/system/app/FX/FX.apk.sha256"
printf 'not-a-sha256  FX.apk\n' > "$TMP/mod/system/app/FX/FX.apk.sha256"
if sh "$INSTALLER" "$TMP/mod" >/dev/null 2>&1; then fail "malformed system overlay checksum unexpectedly succeeded"; fi
[ ! -s "$TMP/pm/install-calls" ] || fail "malformed overlay checksum reached PackageManager install"
cp "$TMP/overlay.expected.sha256" "$TMP/mod/system/app/FX/FX.apk.sha256"
printf '%064d  FX.apk\\n' 0 > "$TMP/mod/system/app/FX/FX.apk.sha256"
if sh "$INSTALLER" "$TMP/mod" >/dev/null 2>&1; then fail "mismatched system overlay checksum unexpectedly succeeded"; fi
[ ! -s "$TMP/pm/install-calls" ] || fail "mismatched overlay checksum reached PackageManager install"
[ ! -e "$TMP/state/adhook-apk-fxunifiedhook.fx-owned" ] || fail "mismatched overlay checksum wrote an ownership marker"
cp "$TMP/overlay.expected.sha256" "$TMP/mod/system/app/FX/FX.apk.sha256"

# An updated system app is stored in /data/app but remains classified as a
# system package by PackageManager. The installer must not reinstall it.
echo de.privacyguard.adhook > "$TMP/pm/installed"
cp "$TMP/mod/system/app/FX/FX.apk" "$TMP/pm/de.privacyguard.adhook.apk"
export FX_ADHOOK_FAKE_SYSTEM=1
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "system-app verification failed"
[ ! -s "$TMP/pm/install-calls" ] || fail "system app path must not run pm install"
# A changed signer on an updated system app must fail closed. The ordinary-app
# uninstall -k migration could not safely roll back a system package's base APK.
printf 'old system-signed update\\n' > "$TMP/pm/de.privacyguard.adhook.apk"
export FX_ADHOOK_FAKE_SIGNATURE_MISMATCH=1
if sh "$INSTALLER" "$TMP/mod" >/dev/null 2>&1; then fail "system-app signer mismatch unexpectedly succeeded"; fi
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "system-app signer mismatch removed the installed package"
if grep -Fq -- '-k de.privacyguard.adhook' "$TMP/pm/uninstall-calls" 2>/dev/null; then fail "system-app signer mismatch attempted destructive uninstall -k"; fi
unset FX_ADHOOK_FAKE_SIGNATURE_MISMATCH FX_ADHOOK_FAKE_SYSTEM
# A system app updated by PackageManager may have its active code path in
# /data/app. A changed module APK must update that package without relabeling
# it as an ordinary user app or writing FX ownership markers.
printf 'older system-app update under data/app\\n' > "$TMP/pm/de.privacyguard.adhook.apk"
export FX_ADHOOK_FAKE_SYSTEM_DATA_PATH=1 FX_ADHOOK_FAKE_SYSTEM=1
: > "$TMP/pm/install-calls"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "updated system app under /data/app was not refreshed"
[ "$(wc -l < "$TMP/pm/install-calls" | tr -d ' ')" = 1 ] || fail "updated system app must be refreshed exactly once"
grep -Fq "updated existing FX system app through PackageManager; system classification retained" "$TMP/state/install.log" || fail "updated system app was logged as an ordinary app"
[ ! -e "$TMP/state/adhook-apk-fxunifiedhook.fx-owned" ] || fail "updated pre-existing system app was incorrectly claimed as FX-owned"
unset FX_ADHOOK_FAKE_SYSTEM_DATA_PATH FX_ADHOOK_FAKE_SYSTEM
rm -f "$TMP/state/adhook-apk-fxunifiedhook.sha256" "$TMP/state/adhook-apk-fxunifiedhook.fx-owned" "$TMP/pm/installed" "$TMP/pm/de.privacyguard.adhook.apk"
: > "$TMP/pm/install-calls"

# A new module with its systemless overlay mounted must never silently install
# the same APK as an ordinary /data/app package when PackageManager misses it.
if sh "$INSTALLER" "$TMP/mod" >/dev/null 2>&1; then fail "unrecognized system overlay unexpectedly downgraded to ordinary app"; fi
[ ! -s "$TMP/pm/install-calls" ] || fail "system overlay fallback invoked pm install"
[ ! -e "$TMP/state/adhook-apk-fxunifiedhook.sha256" ] || fail "deferred system overlay install wrote an ownership digest"
[ ! -e "$TMP/state/adhook-apk-fxunifiedhook.fx-owned" ] || fail "deferred system overlay install wrote an ownership marker"

# An already installed ordinary/user app must also remain untouched while the
# required system overlay is present but not recognized as a system package.
echo de.privacyguard.adhook > "$TMP/pm/installed"
printf 'pre-existing ordinary Hook APK\\n' > "$TMP/pm/de.privacyguard.adhook.apk"
_before_user_digest=$(sha256sum "$TMP/pm/de.privacyguard.adhook.apk")
if sh "$INSTALLER" "$TMP/mod" >/dev/null 2>&1; then fail "ordinary app was upgraded through a system-overlay deployment"; fi
[ "$(sha256sum "$TMP/pm/de.privacyguard.adhook.apk")" = "$_before_user_digest" ] || fail "ordinary app was modified by failed system-app deployment"
[ ! -s "$TMP/pm/install-calls" ] || fail "ordinary app fallback called pm install"
rm -f "$TMP/pm/installed" "$TMP/pm/de.privacyguard.adhook.apk"

# Only archives that do not contain the new system-app overlay may use the
# historical optional/ ordinary-app compatibility path.
mv "$TMP/mod/system/app/FX/FX.apk" "$TMP/mod/system/app/FX/FX.apk.overlay-test"
: > "$TMP/pm/install-calls"
echo de.privacyguard.hook > "$TMP/pm/installed"
printf "old standalone Hook APK\n" > "$TMP/pm/de.privacyguard.hook.apk"
sha256sum "$TMP/pm/de.privacyguard.hook.apk" > "$TMP/state/adhook-apk-privacyguardhook.sha256"
printf 'fx-managed-v1\n' > "$TMP/state/adhook-apk-privacyguardhook.fx-owned"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "install failed"
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "unified package absent"
if grep -Fxq de.privacyguard.hook "$TMP/pm/installed"; then fail "obsolete standalone Hook survived unified install"; fi
grep -Fxq de.privacyguard.hook "$TMP/pm/uninstall-calls" || fail "obsolete standalone Hook was not retired"
[ "$(wc -l < "$TMP/pm/install-calls" | tr -d ' ')" = 1 ] || fail "must install exactly one APK"
echo de.privacyguard.hook >> "$TMP/pm/installed"
printf "old standalone Hook APK\n" > "$TMP/pm/de.privacyguard.hook.apk"
sha256sum "$TMP/pm/de.privacyguard.hook.apk" > "$TMP/state/adhook-apk-privacyguardhook.sha256"
printf 'fx-managed-v1\n' > "$TMP/state/adhook-apk-privacyguardhook.fx-owned"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "idempotent install failed"
if grep -Fxq de.privacyguard.hook "$TMP/pm/installed"; then fail "idempotent path left obsolete Hook installed"; fi
[ "$(wc -l < "$TMP/pm/install-calls" | tr -d ' ')" = 1 ] || fail "unchanged package reinstalled"
# A legacy package without FX ownership proof is a user app and must be preserved.
echo de.privacyguard.hook > "$TMP/pm/installed"
printf 'unowned user Hook APK\n' > "$TMP/pm/de.privacyguard.hook.apk"
rm -f "$TMP/state/adhook-apk-privacyguardhook.sha256" "$TMP/state/adhook-apk-privacyguardhook.fx-owned"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "install with unowned legacy app failed"
grep -Fxq de.privacyguard.hook "$TMP/pm/installed" || fail "unowned user Hook app was removed"
[ "$(grep -Fc de.privacyguard.hook "$TMP/pm/uninstall-calls" 2>/dev/null || true)" = 2 ] || fail "unowned legacy package was uninstalled"
# The compatibility scenario above intentionally removed the system overlay;
# mutate and re-hash its selected legacy optional payload for signer migration.
printf 'changed payload\n' >> "$TMP/mod/optional/FXUnifiedHook.apk"
sha256sum "$TMP/mod/optional/FXUnifiedHook.apk" > "$TMP/mod/optional/FXUnifiedHook.apk.sha256"
export FX_ADHOOK_FAKE_SIGNATURE_MISMATCH=1
if sh "$INSTALLER" "$TMP/mod" >/dev/null 2>&1; then fail "signature mismatch not reported"; fi
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "old package was not restored after signature-mismatch migration"
grep -q 'unified apk payload' "$TMP/pm/de.privacyguard.adhook.apk" || fail "rollback did not restore the old signed APK"
grep -Fq -- '-k de.privacyguard.adhook' "$TMP/pm/uninstall-calls" || fail "signature mismatch did not use data-preserving uninstall -k"
[ "$(grep -Fc de.privacyguard.hook "$TMP/pm/uninstall-calls" 2>/dev/null || true)" = 2 ] || fail "signature mismatch triggered unexpected legacy package removal"
unset FX_ADHOOK_FAKE_SIGNATURE_MISMATCH
# A package first installed by FX must be removed on module uninstall.
sh "$REMOVER" "$TMP/mod" "$TMP/state" || fail "FX-owned package cleanup failed"
if grep -Fxq de.privacyguard.adhook "$TMP/pm/installed"; then
  echo "--- installer/remover log ---" >&2; cat "$TMP/state/install.log" >&2 || :
  echo "--- expected/installed digest ---" >&2; cat "$TMP/state/adhook-apk-fxunifiedhook.sha256" >&2 || :
  sha256sum "$TMP/pm/de.privacyguard.adhook.apk" >&2 || :
  echo "--- fake package paths ---" >&2; ls -l "$TMP/pm" >&2 || :
  fail "FX-owned package survived cleanup"
fi
# A failed first install must never leave ownership markers that can later
# delete an app installed independently by the user.
rm -f "$TMP/pm/installed" "$TMP/state/adhook-apk-fxunifiedhook.sha256" "$TMP/state/adhook-apk-fxunifiedhook.fx-owned"
export FX_ADHOOK_FAKE_SIGNATURE_MISMATCH=1
if sh "$INSTALLER" "$TMP/mod" >/dev/null 2>&1; then fail "fresh signature-mismatch install unexpectedly succeeded"; fi
[ ! -e "$TMP/state/adhook-apk-fxunifiedhook.sha256" ] || fail "failed first install left a digest marker"
[ ! -e "$TMP/state/adhook-apk-fxunifiedhook.fx-owned" ] || fail "failed first install left an FX ownership marker"
unset FX_ADHOOK_FAKE_SIGNATURE_MISMATCH
echo de.privacyguard.adhook > "$TMP/pm/installed"
printf 'user-installed replacement APK\n' > "$TMP/pm/de.privacyguard.adhook.apk"
sh "$REMOVER" "$TMP/mod" "$TMP/state" || fail "cleanup after failed install was not safe"
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "failed install's stale marker caused user app removal"
rm -f "$TMP/pm/installed"
# A pre-existing app may have a digest record, but without the ownership marker
# the remover must leave the user's package installed.
echo de.privacyguard.adhook >> "$TMP/pm/installed"
printf 'pre-existing user APK\n' > "$TMP/pm/de.privacyguard.adhook.apk"
printf 'digest-only\\n' > "$TMP/state/adhook-apk-fxunifiedhook.sha256"
rm -f "$TMP/state/adhook-apk-fxunifiedhook.fx-owned"
sh "$REMOVER" "$TMP/mod" "$TMP/state" || fail "safe cleanup of pre-existing package failed"
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "pre-existing user package was removed"
# Keep cleanup compatible with the first unified build's historical marker.
rm -f "$TMP/pm/installed"
echo de.privacyguard.adhook > "$TMP/pm/installed"
printf 'legacy unified apk\n' > "$TMP/pm/de.privacyguard.adhook.apk"
sha256sum "$TMP/pm/de.privacyguard.adhook.apk" > "$TMP/state/adhook-apk-fxunified.sha256"
printf 'fx-managed-v1\\n' > "$TMP/state/adhook-apk-fxunified.fx-owned"
sh "$REMOVER" "$TMP/mod" "$TMP/state" || fail "legacy unified marker cleanup failed"
[ ! -s "$TMP/pm/installed" ] || fail "legacy FX-owned package was not removed"
# If the user already removed the app, uninstall must clear both markers so a
# later manual reinstall cannot inherit stale FX ownership.
printf 'stale-digest\\n' > "$TMP/state/adhook-apk-fxunifiedhook.sha256"
printf 'fx-managed-v1\\n' > "$TMP/state/adhook-apk-fxunifiedhook.fx-owned"
sh "$REMOVER" "$TMP/mod" "$TMP/state" || fail "absent package cleanup failed"
[ ! -e "$TMP/state/adhook-apk-fxunifiedhook.sha256" ] || fail "stale digest marker retained"
[ ! -e "$TMP/state/adhook-apk-fxunifiedhook.fx-owned" ] || fail "stale ownership marker retained"
echo de.privacyguard.adhook > "$TMP/pm/installed"
printf 'user reinstalled replacement APK\n' > "$TMP/pm/de.privacyguard.adhook.apk"
sh "$REMOVER" "$TMP/mod" "$TMP/state" || fail "cleanup after manual reinstall failed"
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "manual reinstall was removed by stale ownership"

# Restore the exact system overlay fixture for system-app uninstall semantics.
mv "$TMP/mod/system/app/FX/FX.apk.overlay-test" "$TMP/mod/system/app/FX/FX.apk"

# A real /system/app overlay is removed by module unmount, not pm uninstall.
# The remover must clear FX ownership records while leaving PackageManager's
# system package entry alone; this also guards against accidental system-app deletion.
rm -f "$TMP/pm/installed" "$TMP/pm/uninstall-calls"
echo de.privacyguard.adhook > "$TMP/pm/installed"
printf 'system-overlay-digest\\n' > "$TMP/state/adhook-apk-fxunifiedhook.sha256"
printf 'fx-managed-v1\\n' > "$TMP/state/adhook-apk-fxunifiedhook.fx-owned"
export FX_ADHOOK_FAKE_SYSTEM_OVERLAY=1
sh "$REMOVER" "$TMP/mod" "$TMP/state" || fail "system-overlay cleanup failed"
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "module uninstall removed the system package from PackageManager"
[ ! -e "$TMP/state/adhook-apk-fxunifiedhook.sha256" ] || fail "system-overlay digest marker survived module uninstall"
[ ! -e "$TMP/state/adhook-apk-fxunifiedhook.fx-owned" ] || fail "system-overlay ownership marker survived module uninstall"
[ ! -s "$TMP/pm/uninstall-calls" ] || fail "system-overlay cleanup invoked pm uninstall instead of module unmount"
unset FX_ADHOOK_FAKE_SYSTEM_OVERLAY
# Root state, temp and log paths must not traverse symlinks, even when the
# symlink points to an otherwise writable-looking directory or file.
PATH_GUARD="$TMP/path-guard"
mkdir -p "$PATH_GUARD/state-target" "$PATH_GUARD/tmp-target" "$PATH_GUARD/safe-state" "$PATH_GUARD/safe-tmp"
printf 'keep-state-target\n' > "$PATH_GUARD/state-target/sentinel"
printf 'keep-parent-target\n' > "$PATH_GUARD/tmp-target/sentinel"
printf 'keep-log-target\n' > "$PATH_GUARD/log-target"
ln -s "$PATH_GUARD/state-target" "$PATH_GUARD/state-link"
ln -s "$PATH_GUARD/tmp-target" "$PATH_GUARD/tmp-link"
ln -s "$PATH_GUARD/tmp-target" "$PATH_GUARD/parent-link"
if FX_ADHOOK_STATE_DIR="$PATH_GUARD/state-link" FX_ADHOOK_TMP_DIR="$PATH_GUARD/safe-tmp" \
   FX_ADHOOK_LOG="$PATH_GUARD/state-link/install.log" sh "$INSTALLER" "$TMP/mod" >/dev/null 2>&1; then
  fail "installer accepted a symlinked state directory"
fi
grep -Fxq 'keep-state-target' "$PATH_GUARD/state-target/sentinel" || fail "state symlink target was modified"
[ ! -e "$PATH_GUARD/state-target/install.log" ] || fail "installer opened a log through a symlinked state directory"
if FX_ADHOOK_STATE_DIR="$PATH_GUARD/parent-link/state" FX_ADHOOK_TMP_DIR="$PATH_GUARD/safe-tmp" \
   FX_ADHOOK_LOG="$PATH_GUARD/parent-link/state/install.log" sh "$INSTALLER" "$TMP/mod" >/dev/null 2>&1; then
  fail "installer accepted a symlink in a state-directory parent"
fi
grep -Fxq 'keep-parent-target' "$PATH_GUARD/tmp-target/sentinel" || fail "symlinked parent target was modified"
if FX_ADHOOK_STATE_DIR="$PATH_GUARD/safe-state" FX_ADHOOK_TMP_DIR="$PATH_GUARD/tmp-link" \
   FX_ADHOOK_LOG="$PATH_GUARD/safe-state/install.log" sh "$INSTALLER" "$TMP/mod" >/dev/null 2>&1; then
  fail "installer accepted a symlinked temporary directory"
fi
grep -Fxq 'keep-parent-target' "$PATH_GUARD/tmp-target/sentinel" || fail "temporary symlink target was modified"
ln -s "$PATH_GUARD/log-target" "$PATH_GUARD/safe-state/install.log"
if FX_ADHOOK_STATE_DIR="$PATH_GUARD/safe-state" FX_ADHOOK_TMP_DIR="$PATH_GUARD/safe-tmp" \
   FX_ADHOOK_LOG="$PATH_GUARD/safe-state/install.log" sh "$INSTALLER" "$TMP/mod" >/dev/null 2>&1; then
  fail "installer accepted a symlinked log file"
fi
grep -Fxq 'keep-log-target' "$PATH_GUARD/log-target" || fail "installer appended through a symlinked log file"
# A log path whose parent directory is a symlink must be rejected before
# opening/creating the log, even when state and temp directories are safe.
mkdir -p "$PATH_GUARD/log-parent-target"
ln -s "$PATH_GUARD/log-parent-target" "$PATH_GUARD/log-parent-link"
if FX_ADHOOK_STATE_DIR="$PATH_GUARD/safe-state" FX_ADHOOK_TMP_DIR="$PATH_GUARD/safe-tmp" \
   FX_ADHOOK_LOG="$PATH_GUARD/log-parent-link/install.log" sh "$INSTALLER" "$TMP/mod" >/dev/null 2>&1; then
  fail "installer accepted a symlinked log parent directory"
fi
[ ! -e "$PATH_GUARD/log-parent-target/install.log" ] || fail "installer created a log through a symlinked parent directory"



# The remover must not read ownership proof or write logs through a symlinked
# state directory, even when the target contains a valid digest and owner marker.
REMOVE_TARGET="$PATH_GUARD/remove-target"
mkdir -p "$REMOVE_TARGET"
printf 'remove-state-target\n' > "$REMOVE_TARGET/sentinel"
printf 'de.privacyguard.adhook\n' > "$TMP/pm/installed"
printf 'remove-target APK payload\n' > "$TMP/pm/de.privacyguard.adhook.apk"
REMOVE_DIGEST=$(sha256sum "$TMP/pm/de.privacyguard.adhook.apk" | awk '{print $1}')
printf '%s\n' "$REMOVE_DIGEST" > "$REMOVE_TARGET/adhook-apk-fxunifiedhook.sha256"
printf 'fx-managed-v1\n' > "$REMOVE_TARGET/adhook-apk-fxunifiedhook.fx-owned"
ln -s "$REMOVE_TARGET" "$PATH_GUARD/remove-state-link"
: > "$TMP/pm/uninstall-calls"
if FX_ADHOOK_LOG="$PATH_GUARD/remove-state-link/adhook-install.log" \
   sh "$REMOVER" "$TMP/mod" "$PATH_GUARD/remove-state-link" >/dev/null 2>&1; then
  fail "remover accepted a symlinked ownership state directory"
fi
grep -Fxq 'remove-state-target' "$REMOVE_TARGET/sentinel" || fail "remover modified symlink target state"
grep -Fxq "$REMOVE_DIGEST" "$REMOVE_TARGET/adhook-apk-fxunifiedhook.sha256" || fail "remover read/deleted digest marker through state symlink"
grep -Fxq 'fx-managed-v1' "$REMOVE_TARGET/adhook-apk-fxunifiedhook.fx-owned" || fail "remover read/deleted ownership marker through state symlink"
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "remover uninstalled package through symlinked state"
[ ! -s "$TMP/pm/uninstall-calls" ] || fail "remover reached PackageManager through symlinked state"
[ ! -e "$REMOVE_TARGET/adhook-install.log" ] || fail "remover opened a log through symlinked state"

# A symlinked digest marker inside a safe state directory is not ownership proof.
REMOVE_SAFE="$PATH_GUARD/remove-safe-state"
mkdir -p "$REMOVE_SAFE" "$PATH_GUARD/remove-marker-target"
printf '%s\n' "$REMOVE_DIGEST" > "$PATH_GUARD/remove-marker-target/digest"
ln -s "$PATH_GUARD/remove-marker-target/digest" "$REMOVE_SAFE/adhook-apk-fxunifiedhook.sha256"
printf 'fx-managed-v1\n' > "$REMOVE_SAFE/adhook-apk-fxunifiedhook.fx-owned"
: > "$TMP/pm/uninstall-calls"
if FX_ADHOOK_LOG="$REMOVE_SAFE/adhook-install.log" \
   sh "$REMOVER" "$TMP/mod" "$REMOVE_SAFE" >/dev/null 2>&1; then
  fail "remover accepted a symlinked digest ownership marker"
fi
[ -L "$REMOVE_SAFE/adhook-apk-fxunifiedhook.sha256" ] || fail "remover replaced or deleted a symlinked digest marker"
grep -Fxq "$REMOVE_DIGEST" "$PATH_GUARD/remove-marker-target/digest" || fail "remover followed a symlinked digest marker"
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "remover uninstalled package from symlinked ownership metadata"
[ ! -s "$TMP/pm/uninstall-calls" ] || fail "remover called PackageManager for symlinked ownership metadata"


# The Root uninstall entry point must reject relative state paths rather than
# resolving ownership markers against the caller's working directory.
: > "$TMP/pm/uninstall-calls"
if FX_ADHOOK_LOG="$TMP/state/install.log" sh "$REMOVER" "$TMP/mod" "relative-remove-state" >/dev/null 2>&1; then
  fail "remover accepted a relative ownership state path"
fi
[ ! -s "$TMP/pm/uninstall-calls" ] || fail "remover reached PackageManager with a relative state path"
echo "PASS: remover rejects relative state paths"
 
echo "PASS: system-overlay fail-closed deployment, legacy fallback, system-app detection, overlay-safe uninstall, signature safety, ownership-safe cleanup, and stale-marker handling"
