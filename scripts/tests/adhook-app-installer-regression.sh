#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
MODULE="$ROOT"
if [ -s "$ROOT/fx-module/scripts/install_adhook_app.sh" ]; then MODULE="$ROOT/fx-module"; fi
INSTALLER="$MODULE/scripts/install_adhook_app.sh"; REMOVER="$MODULE/scripts/remove_adhook_app.sh"
WORKFLOW_ROOT="$ROOT"
[ -s "$WORKFLOW_ROOT/.github/workflows/build-fx-adhook.yml" ] || WORKFLOW_ROOT=$(CDPATH= cd -- "$ROOT/.." && pwd)
WORKFLOW="$WORKFLOW_ROOT/.github/workflows/build-fx-adhook.yml"
SERVICE="$WORKFLOW_ROOT/fx-module/service.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$INSTALLER" ] && [ -s "$REMOVER" ] || fail "installer/remover missing"
[ -s "$WORKFLOW" ] || fail "FX APK build workflow missing"
grep -Fq '_overlay_apk="$MODDIR/system/app/FX/FX.apk"' "$INSTALLER" || fail "installer does not prefer the system-app overlay"
grep -Fq 'pm list packages -s "$1"' "$INSTALLER" || fail "installer does not verify PackageManager system classification"
grep -Fq 'verified FX Hook as a system app from the systemless /system/app overlay' "$INSTALLER" || fail "system-app overlay verification path missing"
grep -Fq 'install -m 0644 "$apk" fx-module/system/app/FX/FX.apk' "$WORKFLOW" || fail "build pipeline does not stage the APK into the system-app overlay"
grep -Fq 'sha256sum fx-module/system/app/FX/FX.apk' "$WORKFLOW" || fail "system-app overlay checksum is not generated"
grep -Fq 'not a privileged app; no platform signature or privileged permission grant is implied' "$WORKFLOW" || fail "system app build metadata omits privilege/signature boundary"
! grep -Fq 'fx-module/system/priv-app/FX' "$WORKFLOW" || fail "unsigned APK must not be staged as a privileged app"
[ -s "$SERVICE" ] || fail "KernelSU boot service missing"
grep -Fq 'sh "$MODDIR/scripts/install_adhook_app.sh" "$MODDIR"' "$SERVICE" || fail "boot service does not deploy the FX APK"
if [ "$MODULE" != "$ROOT" ]; then
  cmp -s "$ROOT/scripts/install_adhook_app.sh" "$INSTALLER" || fail "packaged installer drift"
  cmp -s "$ROOT/scripts/remove_adhook_app.sh" "$REMOVER" || fail "packaged remover drift"
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
 path) grep -Fxq "$2" "$FX_ADHOOK_FAKE_PM_STATE/installed" 2>/dev/null && [ -s "$FX_ADHOOK_FAKE_PM_STATE/$2.apk" ] && echo "package:$FX_ADHOOK_FAKE_PM_STATE/$2.apk" || exit 1;;
 list) [ "$2" = packages ] && [ "$3" = -s ] || exit 2; if [ "${FX_ADHOOK_FAKE_SYSTEM:-0}" = 1 ] && grep -Fxq "$4" "$FX_ADHOOK_FAKE_PM_STATE/installed" 2>/dev/null; then echo "package:$4"; fi;;
 install) [ "$2" = -r ] || exit 2; case "$3" in */.fx-unified-hook-*.apk) if [ "${FX_ADHOOK_FAKE_SIGNATURE_MISMATCH:-0}" = 1 ]; then echo 'Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match]' >&2; exit 1; fi;; esac; if ! grep -Fxq de.privacyguard.adhook "$FX_ADHOOK_FAKE_PM_STATE/installed" 2>/dev/null; then [ ! -e "$FX_ADHOOK_STATE_DIR/adhook-apk-fxunifiedhook.fx-owned" ] || { echo "ownership marker was committed before pm install" >&2; exit 4; }; echo de.privacyguard.adhook >> "$FX_ADHOOK_FAKE_PM_STATE/installed"; fi; cp "$3" "$FX_ADHOOK_FAKE_PM_STATE/de.privacyguard.adhook.apk"; echo "$3" >> "$FX_ADHOOK_FAKE_PM_STATE/install-calls";;
 uninstall) if [ "$2" = -k ]; then _pkg=$3; echo "-k $_pkg" >> "$FX_ADHOOK_FAKE_PM_STATE/uninstall-calls"; else _pkg=$2; echo "$_pkg" >> "$FX_ADHOOK_FAKE_PM_STATE/uninstall-calls"; fi; sed "/^$_pkg$/d" "$FX_ADHOOK_FAKE_PM_STATE/installed" > "$FX_ADHOOK_FAKE_PM_STATE/installed.tmp"; mv "$FX_ADHOOK_FAKE_PM_STATE/installed.tmp" "$FX_ADHOOK_FAKE_PM_STATE/installed"; rm -f "$FX_ADHOOK_FAKE_PM_STATE/$_pkg.apk";;
 install-multiple) [ "$2" = -r ] || exit 2; shift 2; _found=0; for _apk in "$@"; do [ -s "$_apk" ] || exit 5; cp "$_apk" "$FX_ADHOOK_FAKE_PM_STATE/de.privacyguard.adhook.apk"; _found=1; done; [ "$_found" = 1 ] || exit 6; echo de.privacyguard.adhook >> "$FX_ADHOOK_FAKE_PM_STATE/installed";;
 *) exit 9;;
esac
PM
chmod +x "$TMP/bin/pm"; export PATH="$TMP/bin:$PATH" FX_ADHOOK_FAKE_PM_STATE="$TMP/pm" FX_ADHOOK_STATE_DIR="$TMP/state" FX_ADHOOK_TMP_DIR="$TMP/tmp" FX_ADHOOK_LOG="$TMP/state/install.log"
: > "$TMP/pm/installed"
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
rm -f "$TMP/state/adhook-apk-fxunifiedhook.sha256" "$TMP/state/adhook-apk-fxunifiedhook.fx-owned" "$TMP/pm/installed" "$TMP/pm/de.privacyguard.adhook.apk"
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
printf 'changed payload\n' >> "$TMP/mod/optional/FXUnifiedHook.apk"; sha256sum "$TMP/mod/optional/FXUnifiedHook.apk" > "$TMP/mod/optional/FXUnifiedHook.apk.sha256"
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
echo "PASS: system-app detection, ordinary-app fallback, signature safety, ownership-safe uninstall, and stale-marker cleanup"
