#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
INSTALLER="$ROOT/scripts/install_adhook_app.sh"; REMOVER="$ROOT/scripts/remove_adhook_app.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
TMP="${TMPDIR:-/tmp}/fx-unified-installer-test-$$"
mkdir -p "$TMP/bin" "$TMP/mod/optional" "$TMP/state" "$TMP/tmp" "$TMP/pm"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
printf 'fake unified apk payload\n' > "$TMP/mod/optional/FXUnifiedHook.apk"
sha256sum "$TMP/mod/optional/FXUnifiedHook.apk" > "$TMP/mod/optional/FXUnifiedHook.apk.sha256"
cat > "$TMP/bin/pm" <<'PM'
#!/bin/sh
set -eu
S=$FX_ADHOOK_FAKE_PM_STATE; mkdir -p "$S"
case "$1" in
 path) grep -Fxq "$2" "$S/installed" 2>/dev/null && echo "package:/data/app/$2/base.apk" || exit 1 ;;
 install)
  [ "$2" = "-r" ]; apk=$3; [ -s "$apk" ]; pkg=de.privacyguard.adhook
  if [ "${FX_ADHOOK_FAKE_SIGNATURE_MISMATCH:-0}" = 1 ]; then echo 'Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match]' >&2; exit 1; fi
  grep -Fxv "$pkg" "$S/installed" > "$S/installed.tmp" 2>/dev/null || :
  mv "$S/installed.tmp" "$S/installed"; echo "$pkg" >> "$S/installed"; echo "$pkg" >> "$S/install-calls" ;;
 uninstall) pkg=$2; grep -Fxv "$pkg" "$S/installed" > "$S/installed.tmp" 2>/dev/null || :; mv "$S/installed.tmp" "$S/installed"; echo "$pkg" >> "$S/uninstall-calls" ;;
 *) exit 9 ;;
esac
PM
chmod 0755 "$TMP/bin/pm"
export PATH="$TMP/bin:$PATH" FX_ADHOOK_FAKE_PM_STATE="$TMP/pm" FX_ADHOOK_STATE_DIR="$TMP/state" FX_ADHOOK_TMP_DIR="$TMP/tmp" FX_ADHOOK_LOG="$TMP/state/install.log"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "first unified install failed"
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "unified package not installed"
[ "$(wc -l < "$TMP/pm/install-calls" | tr -d ' ')" = 1 ] || fail "expected exactly one package install"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "idempotent install failed"
[ "$(wc -l < "$TMP/pm/install-calls" | tr -d ' ')" = 1 ] || fail "unchanged APK reinstalled"
printf 'updated payload\n' >> "$TMP/mod/optional/FXUnifiedHook.apk"
sha256sum "$TMP/mod/optional/FXUnifiedHook.apk" > "$TMP/mod/optional/FXUnifiedHook.apk.sha256"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "APK update failed"
[ "$(wc -l < "$TMP/pm/install-calls" | tr -d ' ')" = 2 ] || fail "updated APK not reinstalled"
printf 'different key\n' >> "$TMP/mod/optional/FXUnifiedHook.apk"
sha256sum "$TMP/mod/optional/FXUnifiedHook.apk" > "$TMP/mod/optional/FXUnifiedHook.apk.sha256"
export FX_ADHOOK_FAKE_SIGNATURE_MISMATCH=1
if sh "$INSTALLER" "$TMP/mod" >/dev/null 2>&1; then fail "signature mismatch should fail"; fi
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "existing package removed after signature mismatch"
[ ! -s "$TMP/pm/uninstall-calls" ] || fail "installer uninstalled package after signature mismatch"
unset FX_ADHOOK_FAKE_SIGNATURE_MISMATCH
sh "$REMOVER" "$TMP/mod" "$TMP/state" || fail "unified package cleanup failed"
[ ! -s "$TMP/pm/installed" ] || fail "FX-managed unified package not removed"
echo "PASS: unified Hook APK installs and updates idempotently with signature-safe rollback"
