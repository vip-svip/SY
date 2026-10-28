#!/bin/sh
# Host-runnable regression test for ordinary-app Hook APK deployment without metamodule.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
INSTALLER="$ROOT/scripts/install_adhook_app.sh"
REMOVER="$ROOT/scripts/remove_adhook_app.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$INSTALLER" ] || fail "installer helper missing"
[ -s "$REMOVER" ] || fail "remover helper missing"
TMP="${TMPDIR:-/tmp}/fx-adhook-installer-test-$$"
mkdir -p "$TMP/bin" "$TMP/mod/optional" "$TMP/state" "$TMP/tmp" "$TMP/pm"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
printf 'fake legacy apk payload\n' > "$TMP/mod/optional/PrivacyGuardHook.apk"
printf 'fake modern apk payload\n' > "$TMP/mod/optional/FXAdHook.apk"
for _name in PrivacyGuardHook FXAdHook; do
  _p="$TMP/mod/optional/$_name.apk"
  sha256sum "$_p" > "$_p.sha256"
done
cat > "$TMP/bin/pm" <<'PM'
#!/bin/sh
set -eu
STATE=$FX_ADHOOK_FAKE_PM_STATE
mkdir -p "$STATE"
case "$1" in
  path)
    pkg=$2
    if grep -Fxq "$pkg" "$STATE/installed" 2>/dev/null; then echo "package:/data/app/$pkg/base.apk"; else exit 1; fi
    ;;
  install)
    [ "${2:-}" = "-r" ] || exit 2
    apk=$3
    [ -s "$apk" ] || exit 3
    case "$(basename "$apk")" in
      *privacyguardhook*) pkg=de.privacyguard.hook ;;
      *fxadhook*) pkg=de.privacyguard.adhook ;;
      *) if grep -q 'fake legacy apk payload' "$apk"; then pkg=de.privacyguard.hook; else pkg=de.privacyguard.adhook; fi ;;
    esac
    grep -Fxv "$pkg" "$STATE/installed" > "$STATE/installed.tmp" 2>/dev/null || :
    mv "$STATE/installed.tmp" "$STATE/installed"
    echo "$pkg" >> "$STATE/installed"; echo "$pkg" >> "$STATE/install-calls"
    ;;
  uninstall)
    pkg=$2
    grep -Fxv "$pkg" "$STATE/installed" > "$STATE/installed.tmp" 2>/dev/null || :
    mv "$STATE/installed.tmp" "$STATE/installed"
    echo "$pkg" >> "$STATE/uninstall-calls"
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
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "first install attempt failed"
grep -Fxq de.privacyguard.hook "$TMP/pm/installed" || fail "legacy Hook not installed as a regular app"
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "FXAdHook not installed as a regular app"
[ "$(wc -l < "$TMP/pm/install-calls" | tr -d ' ')" = 2 ] || fail "expected two package installs"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "idempotent install retry failed"
[ "$(wc -l < "$TMP/pm/install-calls" | tr -d ' ')" = 2 ] || fail "unchanged packages were reinstalled"
printf 'updated fake APK payload\n' >> "$TMP/mod/optional/FXAdHook.apk"
sha256sum "$TMP/mod/optional/FXAdHook.apk" > "$TMP/mod/optional/FXAdHook.apk.sha256"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "APK update failed"
[ "$(wc -l < "$TMP/pm/install-calls" | tr -d ' ')" = 3 ] || fail "updated APK was not reinstalled exactly once"
sh "$REMOVER" "$TMP/mod" "$TMP/state" || fail "tracked package cleanup failed"
[ ! -s "$TMP/pm/installed" ] || fail "FX-managed apps were not removed on uninstall"
[ ! -e "$TMP/state/adhook-apk-privacyguardhook.sha256" ] || fail "legacy marker survived uninstall"
[ ! -e "$TMP/state/adhook-apk-fxadhook.sha256" ] || fail "modern marker survived uninstall"
if grep -Eqi 'iptables|ip6tables|dns_hijack|vpn_mode|setprop net\.' "$INSTALLER" "$REMOVER"; then
  fail "APK installer unexpectedly contains networking mutations"
fi
# Static regression guard for the modern ad observer's process-global hooks.
HOOK_SRC="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
[ -s "$HOOK_SRC" ] || fail "modern Hook source missing"
grep -q 'private synchronized void installAdViewHooks()' "$HOOK_SRC" || fail "global ad observer installer is not synchronized"
for flag in activityObserverInstalled dialogObserverInstalled popupObserversInstalled dynamicChildObserversInstalled; do
  grep -q "private volatile boolean $flag;" "$HOOK_SRC" || fail "missing independent observer state: $flag"
done
! grep -q 'adObserversInstalled' "$HOOK_SRC" || fail "obsolete all-or-nothing observer state remains"
grep -q 'if (!dynamicChildObserversInstalled) dynamicChildObserversInstalled = installDynamicAdChildHooks();' "$HOOK_SRC" || fail "dynamic observer failure is not retryable"
grep -q 'popupObserverMethods.add(key)' "$HOOK_SRC" || fail "popup overload successes are not tracked individually"
grep -q 'dynamicChildObserverMethods.add(key)' "$HOOK_SRC" || fail "addView overload successes are not tracked individually"
grep -q 'eligible > 0 && popupObserverMethods.size() >= eligible' "$HOOK_SRC" || fail "partial popup registration incorrectly counts as complete"
grep -q 'eligible > 0 && dynamicChildObserverMethods.size() >= eligible' "$HOOK_SRC" || fail "partial child registration incorrectly counts as complete"
grep -q 'private UnifiedHookConfigParser.Target adTargetFor(String pkg)' "$HOOK_SRC" || fail "package-scoped dynamic target resolver missing"
grep -q 'installDynamicAdChildHooks()' "$HOOK_SRC" || fail "global dynamic child observer not installed"
! grep -q 'installAdViewHooks(pkg, target)' "$HOOK_SRC" || fail "old package-capturing observer call remains"
! grep -q 'installDynamicAdChildHooks(pkg, target)' "$HOOK_SRC" || fail "old package-capturing dynamic observer call remains"
echo "PASS: Hook APKs install as ordinary apps, idempotently update, and clean up without network mutations"
