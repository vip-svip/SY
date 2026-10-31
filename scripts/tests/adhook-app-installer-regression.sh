#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
INSTALLER="$ROOT/scripts/install_adhook_app.sh"; REMOVER="$ROOT/scripts/remove_adhook_app.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$INSTALLER" ] && [ -s "$REMOVER" ] || fail "installer/remover missing"
cmp -s "$INSTALLER" "$ROOT/fx-module/scripts/install_adhook_app.sh" || fail "packaged installer drift"
TMP="${TMPDIR:-/tmp}/fx-unified-installer-$$"; mkdir -p "$TMP/bin" "$TMP/mod/optional" "$TMP/state" "$TMP/tmp" "$TMP/pm"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
printf 'unified apk payload\n' > "$TMP/mod/optional/FXUnifiedHook.apk"; sha256sum "$TMP/mod/optional/FXUnifiedHook.apk" > "$TMP/mod/optional/FXUnifiedHook.apk.sha256"
cat > "$TMP/bin/pm" <<'PM'
#!/bin/sh
set -eu
case "$1" in
 path) grep -Fxq "$2" "$FX_ADHOOK_FAKE_PM_STATE/installed" 2>/dev/null && echo "package:/data/app/$2/base.apk" || exit 1;;
 install) [ "$2" = -r ] || exit 2; grep -q 'unified apk payload' "$3" || exit 3; if [ "${FX_ADHOOK_FAKE_SIGNATURE_MISMATCH:-0}" = 1 ]; then echo 'Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match]' >&2; exit 1; fi; grep -Fxq de.privacyguard.adhook "$FX_ADHOOK_FAKE_PM_STATE/installed" 2>/dev/null || echo de.privacyguard.adhook >> "$FX_ADHOOK_FAKE_PM_STATE/installed"; echo "$3" >> "$FX_ADHOOK_FAKE_PM_STATE/install-calls";;
 uninstall) sed "/^$2$/d" "$FX_ADHOOK_FAKE_PM_STATE/installed" > "$FX_ADHOOK_FAKE_PM_STATE/installed.tmp"; mv "$FX_ADHOOK_FAKE_PM_STATE/installed.tmp" "$FX_ADHOOK_FAKE_PM_STATE/installed";;
 *) exit 9;;
esac
PM
chmod +x "$TMP/bin/pm"; export PATH="$TMP/bin:$PATH" FX_ADHOOK_FAKE_PM_STATE="$TMP/pm" FX_ADHOOK_STATE_DIR="$TMP/state" FX_ADHOOK_TMP_DIR="$TMP/tmp" FX_ADHOOK_LOG="$TMP/state/install.log"
: > "$TMP/pm/installed"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "install failed"
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "unified package absent"
[ "$(wc -l < "$TMP/pm/install-calls" | tr -d ' ')" = 1 ] || fail "must install exactly one APK"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "idempotent install failed"
[ "$(wc -l < "$TMP/pm/install-calls" | tr -d ' ')" = 1 ] || fail "unchanged package reinstalled"
printf 'changed payload\n' >> "$TMP/mod/optional/FXUnifiedHook.apk"; sha256sum "$TMP/mod/optional/FXUnifiedHook.apk" > "$TMP/mod/optional/FXUnifiedHook.apk.sha256"
export FX_ADHOOK_FAKE_SIGNATURE_MISMATCH=1
if sh "$INSTALLER" "$TMP/mod" >/dev/null 2>&1; then fail "signature mismatch not reported"; fi
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "existing package removed after signature mismatch"
[ ! -s "$TMP/pm/uninstall-calls" ] || fail "installer attempted destructive uninstall"
unset FX_ADHOOK_FAKE_SIGNATURE_MISMATCH
# A package first installed by FX must be removed on module uninstall.
sh "$REMOVER" "$TMP/mod" "$TMP/state" || fail "FX-owned package cleanup failed"
if grep -Fxq de.privacyguard.adhook "$TMP/pm/installed"; then fail "FX-owned package survived cleanup"; fi
# A pre-existing app may have a digest record, but without the ownership marker
# the remover must leave the user's package installed.
echo de.privacyguard.adhook >> "$TMP/pm/installed"
printf 'digest-only\\n' > "$TMP/state/adhook-apk-fxunifiedhook.sha256"
rm -f "$TMP/state/adhook-apk-fxunifiedhook.fx-owned"
sh "$REMOVER" "$TMP/mod" "$TMP/state" || fail "safe cleanup of pre-existing package failed"
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "pre-existing user package was removed"
# Keep cleanup compatible with the first unified build's historical marker.
rm -f "$TMP/pm/installed"
printf 'legacy-digest\\n' > "$TMP/state/adhook-apk-fxunified.sha256"
printf 'fx-managed-v1\\n' > "$TMP/state/adhook-apk-fxunified.fx-owned"
sh "$REMOVER" "$TMP/mod" "$TMP/state" || fail "legacy unified marker cleanup failed"
[ ! -s "$TMP/pm/installed" ] || fail "legacy FX-owned package was not removed"
echo "PASS: unified APK, signature safety, ownership-safe uninstall, legacy marker compatibility"
