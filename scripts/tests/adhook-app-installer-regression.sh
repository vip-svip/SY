#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
MODULE="$ROOT"
if [ -s "$ROOT/fx-module/scripts/install_adhook_app.sh" ]; then MODULE="$ROOT/fx-module"; fi
INSTALLER="$MODULE/scripts/install_adhook_app.sh"; REMOVER="$MODULE/scripts/remove_adhook_app.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$INSTALLER" ] && [ -s "$REMOVER" ] || fail "installer/remover missing"
if [ "$MODULE" != "$ROOT" ]; then
  cmp -s "$ROOT/scripts/install_adhook_app.sh" "$INSTALLER" || fail "packaged installer drift"
  cmp -s "$ROOT/scripts/remove_adhook_app.sh" "$REMOVER" || fail "packaged remover drift"
fi
[ -s "$MODULE/uninstall.sh" ] || fail "KernelSU uninstall hook missing"
grep -Fq 'sh "$REMOVER" "$MODDIR" "$STATE_DIR"' "$MODULE/uninstall.sh" || fail "KernelSU uninstall hook does not invoke ownership-safe remover"
TMP="${TMPDIR:-/tmp}/fx-unified-installer-$$"; mkdir -p "$TMP/bin" "$TMP/mod/optional" "$TMP/state" "$TMP/tmp" "$TMP/pm"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
printf 'unified apk payload\n' > "$TMP/mod/optional/FXUnifiedHook.apk"; sha256sum "$TMP/mod/optional/FXUnifiedHook.apk" > "$TMP/mod/optional/FXUnifiedHook.apk.sha256"
cat > "$TMP/bin/pm" <<'PM'
#!/bin/sh
set -eu
case "$1" in
 path) grep -Fxq "$2" "$FX_ADHOOK_FAKE_PM_STATE/installed" 2>/dev/null && [ -s "$FX_ADHOOK_FAKE_PM_STATE/$2.apk" ] && echo "package:$FX_ADHOOK_FAKE_PM_STATE/$2.apk" || exit 1;;
 install) [ "$2" = -r ] || exit 2; grep -q 'unified apk payload' "$3" || exit 3; if [ "${FX_ADHOOK_FAKE_SIGNATURE_MISMATCH:-0}" = 1 ]; then echo 'Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match]' >&2; exit 1; fi; if ! grep -Fxq de.privacyguard.adhook "$FX_ADHOOK_FAKE_PM_STATE/installed" 2>/dev/null; then [ ! -e "$FX_ADHOOK_STATE_DIR/adhook-apk-fxunifiedhook.fx-owned" ] || { echo "ownership marker was committed before pm install" >&2; exit 4; }; echo de.privacyguard.adhook >> "$FX_ADHOOK_FAKE_PM_STATE/installed"; fi; cp "$3" "$FX_ADHOOK_FAKE_PM_STATE/de.privacyguard.adhook.apk"; echo "$3" >> "$FX_ADHOOK_FAKE_PM_STATE/install-calls";;
 uninstall) echo "$2" >> "$FX_ADHOOK_FAKE_PM_STATE/uninstall-calls"; sed "/^$2$/d" "$FX_ADHOOK_FAKE_PM_STATE/installed" > "$FX_ADHOOK_FAKE_PM_STATE/installed.tmp"; mv "$FX_ADHOOK_FAKE_PM_STATE/installed.tmp" "$FX_ADHOOK_FAKE_PM_STATE/installed"; rm -f "$FX_ADHOOK_FAKE_PM_STATE/$2.apk";;
 *) exit 9;;
esac
PM
chmod +x "$TMP/bin/pm"; export PATH="$TMP/bin:$PATH" FX_ADHOOK_FAKE_PM_STATE="$TMP/pm" FX_ADHOOK_STATE_DIR="$TMP/state" FX_ADHOOK_TMP_DIR="$TMP/tmp" FX_ADHOOK_LOG="$TMP/state/install.log"
: > "$TMP/pm/installed"
echo de.privacyguard.hook > "$TMP/pm/installed"
printf "old standalone Hook APK\n" > "$TMP/pm/de.privacyguard.hook.apk"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "install failed"
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "unified package absent"
if grep -Fxq de.privacyguard.hook "$TMP/pm/installed"; then fail "obsolete standalone Hook survived unified install"; fi
grep -Fxq de.privacyguard.hook "$TMP/pm/uninstall-calls" || fail "obsolete standalone Hook was not retired"
[ "$(wc -l < "$TMP/pm/install-calls" | tr -d ' ')" = 1 ] || fail "must install exactly one APK"
echo de.privacyguard.hook >> "$TMP/pm/installed"
printf "old standalone Hook APK\n" > "$TMP/pm/de.privacyguard.hook.apk"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "idempotent install failed"
if grep -Fxq de.privacyguard.hook "$TMP/pm/installed"; then fail "idempotent path left obsolete Hook installed"; fi
[ "$(wc -l < "$TMP/pm/install-calls" | tr -d ' ')" = 1 ] || fail "unchanged package reinstalled"
printf 'changed payload\n' >> "$TMP/mod/optional/FXUnifiedHook.apk"; sha256sum "$TMP/mod/optional/FXUnifiedHook.apk" > "$TMP/mod/optional/FXUnifiedHook.apk.sha256"
export FX_ADHOOK_FAKE_SIGNATURE_MISMATCH=1
if sh "$INSTALLER" "$TMP/mod" >/dev/null 2>&1; then fail "signature mismatch not reported"; fi
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "existing package removed after signature mismatch"
[ "$(grep -Fc de.privacyguard.hook "$TMP/pm/uninstall-calls" 2>/dev/null || true)" = 2 ] || fail "signature mismatch triggered unexpected package removal"
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
echo "PASS: unified APK, signature safety, ownership-safe uninstall, and stale-marker cleanup"
