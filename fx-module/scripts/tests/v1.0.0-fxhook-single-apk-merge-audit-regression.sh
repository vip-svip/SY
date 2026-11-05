#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$ROOT/optional/FXUnifiedHook.apk" ] || fail "unified APK missing"
[ ! -e "$ROOT/optional/PrivacyGuardHook.apk" ] || fail "split legacy APK still packaged"
[ ! -e "$ROOT/optional/FXAdHook.apk" ] || fail "split modern APK still packaged"
grep -q 'de.privacyguard.adhook' "$ROOT/adhook/app/build.gradle" 2>/dev/null || :
grep -q 'de.robv.android.xposed:api:82' "$ROOT/../adhook/app/build.gradle" 2>/dev/null || :
[ -s "$ROOT/lsposed/app/src/main/java/de/privacyguard/hook/MainHook.java" ] || fail "original full MainHook source missing"
[ "$(wc -c < "$ROOT/lsposed/app/src/main/java/de/privacyguard/hook/MainHook.java" | tr -d ' ')" -ge 90000 ] || fail "MainHook source unexpectedly truncated"
grep -q '_slug=fxunifiedhook' "$ROOT/scripts/install_adhook_app.sh" || fail "single package installer missing"
grep -q 'optional/FXUnifiedHook.apk' "$ROOT/scripts/install_adhook_app.sh" || fail "unified APK install path missing"
echo "PASS: one APK contains the copied full legacy Hook and modern ad Hook entrypoints"
