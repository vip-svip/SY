#!/bin/sh
# Host regression for the single-APK FX Hook installer and safe API-82 migration.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
INSTALLER="$ROOT/scripts/install_adhook_app.sh"
REMOVER="$ROOT/scripts/remove_adhook_app.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$INSTALLER" ] || fail "unified installer missing"
[ -s "$REMOVER" ] || fail "unified remover missing"
PACKAGED_INSTALLER="$ROOT/fx-module/scripts/install_adhook_app.sh"
[ -s "$PACKAGED_INSTALLER" ] || fail "packaged installer missing"
cmp -s "$INSTALLER" "$PACKAGED_INSTALLER" || fail "packaged installer drifted"
TMP="${TMPDIR:-/tmp}/fx-unified-hook-test-$$"
mkdir -p "$TMP/bin" "$TMP/mod/optional" "$TMP/state" "$TMP/tmp" "$TMP/pm"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
printf 'fake unified apk payload\n' > "$TMP/mod/optional/FXAdHook.apk"
sha256sum "$TMP/mod/optional/FXAdHook.apk" > "$TMP/mod/optional/FXAdHook.apk.sha256"
cat > "$TMP/bin/pm" <<'PM'
#!/bin/sh
set -eu
STATE=$FX_ADHOOK_FAKE_PM_STATE
mkdir -p "$STATE"
case "$1" in
  path)
    grep -Fxq "$2" "$STATE/installed" 2>/dev/null && { echo "package:/data/app/$2/base.apk"; exit 0; }
    exit 1
    ;;
  install)
    [ "$2" = "-r" ] || exit 2
    [ -s "$3" ] || exit 3
    if [ "${FX_ADHOOK_FAKE_SIGNATURE_MISMATCH:-0}" = 1 ]; then
      echo 'Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match]' >&2
      exit 1
    fi
    grep -Fxv de.privacyguard.adhook "$STATE/installed" > "$STATE/installed.tmp" 2>/dev/null || :
    mv "$STATE/installed.tmp" "$STATE/installed"
    echo de.privacyguard.adhook >> "$STATE/installed"
    echo install >> "$STATE/calls"
    ;;
  uninstall)
    grep -Fxv "$2" "$STATE/installed" > "$STATE/installed.tmp" 2>/dev/null || :
    mv "$STATE/installed.tmp" "$STATE/installed"
    echo "$2" >> "$STATE/uninstalls"
    ;;
  *) exit 9 ;;
esac
PM
chmod 0755 "$TMP/bin/pm"
export PATH="$TMP/bin:$PATH"
export FX_ADHOOK_FAKE_PM_STATE="$TMP/pm"
export FX_ADHOOK_STATE_DIR="$TMP/state"
export FX_ADHOOK_TMP_DIR="$TMP/tmp"
export FX_ADHOOK_LOG="$TMP/state/install.log"
# Simulate a legacy FX-owned package. Migration removes it only after API-101 succeeds.
printf '%s\n' de.privacyguard.hook > "$TMP/pm/installed"
printf 'legacy-digest\n' > "$TMP/state/adhook-apk-privacyguardhook.sha256"
printf 'fx-managed-v1\n' > "$TMP/state/adhook-apk-privacyguardhook.fx-owned"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "unified install or legacy migration failed"
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "unified API-101 package not installed"
! grep -Fxq de.privacyguard.hook "$TMP/pm/installed" || fail "FX-owned legacy package not migrated away"
[ "$(wc -l < "$TMP/pm/calls" | tr -d ' ')" = 1 ] || fail "installer must install exactly one APK"
[ -s "$TMP/state/adhook-apk-fxadhook.fx-owned" ] || fail "new package ownership marker missing"
[ ! -e "$TMP/state/adhook-apk-privacyguardhook.fx-owned" ] || fail "legacy ownership marker not cleared"
# Idempotent retry must not reinstall.
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "idempotent install failed"
[ "$(wc -l < "$TMP/pm/calls" | tr -d ' ')" = 1 ] || fail "unchanged APK was reinstalled"
# Signature mismatch preserves the current installed package and does not uninstall.
printf 'changed fake apk payload\n' >> "$TMP/mod/optional/FXAdHook.apk"
sha256sum "$TMP/mod/optional/FXAdHook.apk" > "$TMP/mod/optional/FXAdHook.apk.sha256"
export FX_ADHOOK_FAKE_SIGNATURE_MISMATCH=1
if sh "$INSTALLER" "$TMP/mod" >/dev/null 2>&1; then fail "signature mismatch should fail"; fi
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "existing package removed on signature mismatch"
unset FX_ADHOOK_FAKE_SIGNATURE_MISMATCH
# User-owned legacy package without ownership marker must never be removed.
printf '%s\n' de.privacyguard.hook >> "$TMP/pm/installed"
printf 'legacy-digest\n' > "$TMP/state/adhook-apk-privacyguardhook.sha256"
rm -f "$TMP/state/adhook-apk-privacyguardhook.fx-owned"
sh "$REMOVER" "$TMP/mod" "$TMP/state" || fail "unified cleanup failed"
! grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "FX-owned unified package not removed"
grep -Fxq de.privacyguard.hook "$TMP/pm/installed" || fail "pre-existing legacy package was incorrectly removed"
grep -q 'de.privacyguard.hook' "$TMP/state/install.log" || fail "legacy migration was not logged"
if grep -Eqi 'iptables|ip6tables|dns_hijack|vpn_mode|setprop net\.' "$INSTALLER" "$REMOVER"; then
  fail "Hook package installer unexpectedly mutates networking"
fi
echo "PASS: one API-101 Hook APK installs, migrates only FX-owned legacy package, and safely uninstalls"
