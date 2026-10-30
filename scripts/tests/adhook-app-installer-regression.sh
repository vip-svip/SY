#!/bin/sh
# Host-runnable regression test for ordinary-app Hook APK deployment without metamodule.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
INSTALLER="$ROOT/scripts/install_adhook_app.sh"
REMOVER="$ROOT/scripts/remove_adhook_app.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$INSTALLER" ] || fail "installer helper missing"
[ -s "$REMOVER" ] || fail "remover helper missing"
PACKAGED_INSTALLER="$ROOT/fx-module/scripts/install_adhook_app.sh"
[ -s "$PACKAGED_INSTALLER" ] || fail "packaged installer helper missing"
cmp -s "$INSTALLER" "$PACKAGED_INSTALLER" || fail "packaged installer drifted from tested installer"
TMP="${TMPDIR:-/tmp}/fx-adhook-installer-test-$$"
mkdir -p "$TMP/bin" "$TMP/mod/optional" "$TMP/state" "$TMP/tmp" "$TMP/pm"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
printf 'unified Hook APK payload\n' > "$TMP/mod/optional/FXHook.apk"
sha256sum "$TMP/mod/optional/FXHook.apk" > "$TMP/mod/optional/FXHook.apk.sha256"
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
      *fxhook*) pkg=de.privacyguard.adhook ;;
      *) exit 8 ;;
    esac
    if [ "${FX_ADHOOK_FAKE_SIGNATURE_MISMATCH:-0}" = 1 ] && [ "$pkg" = de.privacyguard.adhook ]; then
      echo 'Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match]' >&2
      exit 1
    fi
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
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "unified Hook not installed as a regular app"
[ "$(wc -l < "$TMP/pm/install-calls" | tr -d ' ')" = 1 ] || fail "expected exactly one package install"
! grep -Fxq de.privacyguard.hook "$TMP/pm/installed" || fail "legacy second Hook package was installed"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "idempotent install retry failed"
[ "$(wc -l < "$TMP/pm/install-calls" | tr -d ' ')" = 1 ] || fail "unchanged unified APK was reinstalled"
printf 'updated fake APK payload\n' >> "$TMP/mod/optional/FXHook.apk"
sha256sum "$TMP/mod/optional/FXHook.apk" > "$TMP/mod/optional/FXHook.apk.sha256"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "APK update failed"
[ "$(wc -l < "$TMP/pm/install-calls" | tr -d ' ')" = 2 ] || fail "updated unified APK was not reinstalled exactly once"
# A signature mismatch must preserve the installed app and its data.
printf 'different-key fake APK payload\n' >> "$TMP/mod/optional/FXHook.apk"
sha256sum "$TMP/mod/optional/FXHook.apk" > "$TMP/mod/optional/FXHook.apk.sha256"
export FX_ADHOOK_FAKE_SIGNATURE_MISMATCH=1
if sh "$INSTALLER" "$TMP/mod" >/dev/null 2>&1; then fail "signature mismatch should be reported as install failure"; fi
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "existing Hook package was removed after signature mismatch"
[ ! -s "$TMP/pm/uninstall-calls" ] || fail "installer attempted to uninstall after signature mismatch"
grep -q 'signing certificate differs' "$TMP/state/install.log" || fail "signature mismatch was not diagnosed in the install log"
unset FX_ADHOOK_FAKE_SIGNATURE_MISMATCH
sh "$REMOVER" "$TMP/mod" "$TMP/state" || fail "tracked package cleanup failed"
[ ! -s "$TMP/pm/installed" ] || fail "FX-managed apps were not removed on uninstall"
[ ! -e "$TMP/state/adhook-apk-fxhook.sha256" ] || fail "unified Hook marker survived uninstall"
if grep -Eqi 'iptables|ip6tables|dns_hijack|vpn_mode|setprop net\.' "$INSTALLER" "$REMOVER"; then
  fail "APK installer unexpectedly contains networking mutations"
fi
# Static regression guard for the modern ad observer's process-global hooks.
HOOK_SRC="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
[ -s "$HOOK_SRC" ] || fail "modern Hook source missing"
grep -q 'private synchronized void installAdViewHooks()' "$HOOK_SRC" || fail "global ad observer installer is not synchronized"
OBS_LINE=$(grep -n 'installAdViewHooks();' "$HOOK_SRC" | head -n 1 | cut -d: -f1)
GUARD_LINE=$(grep -n 'if (!hooksInstalledFor.add(pkg)) return;' "$HOOK_SRC" | head -n 1 | cut -d: -f1)
[ -n "$OBS_LINE" ] && [ -n "$GUARD_LINE" ] && [ "$OBS_LINE" -lt "$GUARD_LINE" ] || fail "per-package guard prevents retrying global observers"
grep -q 'private volatile boolean privacyIdentifierHookInstalled;' "$HOOK_SRC" || fail "process-scoped privacy registration state missing"
grep -q 'UnifiedHookConfigParser.parse(content)' "$HOOK_SRC" || fail "runtime is not wired to the unified config parser"
grep -q 'configLoaded = loadConfig()' "$HOOK_SRC" || fail "remote config load is not connected to module startup"
grep -q 'if (!remoteFilesAvailable)' "$HOOK_SRC" || fail "missing Remote Files capability must fail closed"
! grep -q 'intentionally independent from the current ad-only parser' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java" || fail "stale parser migration comment remains"
PRIVACY_LINE=$(grep -n 'installPrivacyIdentifierHooks(pkg)' "$HOOK_SRC" | head -n 1 | cut -d: -f1)
[ -n "$PRIVACY_LINE" ] && [ "$PRIVACY_LINE" -lt "$GUARD_LINE" ] || fail "privacy hook failure cannot retry before package guard"
grep -q 'private synchronized boolean installPrivacyIdentifierHooks(final String pkg)' "$HOOK_SRC" || fail "privacy hook installer must serialize registration"
grep -q 'if (privacyIdentifierHookInstalled) return true;' "$HOOK_SRC" || fail "privacy hook duplicate registration guard missing"
grep -q 'privacyIdentifierHookInstalled = true;' "$HOOK_SRC" || fail "privacy hook success is not recorded"
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
# Regression: an app package that predates FX must not be claimed or removed.
rm -rf "$TMP/state" "$TMP/pm"
mkdir -p "$TMP/state" "$TMP/pm"
export FX_ADHOOK_FAKE_PM_STATE="$TMP/pm"
export FX_ADHOOK_STATE_DIR="$TMP/state"
export FX_ADHOOK_TMP_DIR="$TMP/tmp"
export FX_ADHOOK_LOG="$TMP/state/install.log"
printf '%s\n' de.privacyguard.adhook > "$TMP/pm/installed"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "install with a pre-existing package failed"
[ ! -e "$TMP/state/adhook-apk-fxhook.fx-owned" ] || fail "pre-existing package was incorrectly marked FX-owned"
sh "$REMOVER" "$TMP/mod" "$TMP/state" || fail "cleanup with a pre-existing package failed"
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "pre-existing package was incorrectly uninstalled"
! grep -Fxq de.privacyguard.hook "$TMP/pm/uninstall-calls" || fail "legacy split Hook package was touched"
# Missing unified artifact must fail closed; never install the historical split APKs.
rm -rf "$TMP/missing" "$TMP/missing-state" "$TMP/missing-pm"
mkdir -p "$TMP/missing/optional" "$TMP/missing-state" "$TMP/missing-pm"
printf 'old API82 payload\n' > "$TMP/missing/optional/PrivacyGuardHook.apk"
printf 'old API101 payload\n' > "$TMP/missing/optional/FXAdHook.apk"
export FX_ADHOOK_FAKE_PM_STATE="$TMP/missing-pm"
export FX_ADHOOK_STATE_DIR="$TMP/missing-state"
export FX_ADHOOK_TMP_DIR="$TMP/tmp"
export FX_ADHOOK_LOG="$TMP/missing-state/install.log"
if sh "$INSTALLER" "$TMP/missing" >/dev/null 2>&1; then fail "missing unified APK should fail"; fi
[ ! -s "$TMP/missing-pm/install-calls" ] || fail "legacy split APK fallback was used"
echo "PASS: installer accepts exactly one unified Hook APK and refuses split-APK fallback"
