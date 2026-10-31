#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
APK="${1:-$ROOT/adhook/app/build/outputs/apk/debug/app-debug.apk}"
SDK_ROOT="${ANDROID_HOME:-/usr/local/lib/android/sdk}"
AAPT="$SDK_ROOT/build-tools/34.0.0/aapt"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" ] || fail "native MainActivity source missing"
[ -s "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootAccess.java" ] || fail "KernelSU root access helper missing"
grep -q "showDashboard()" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "unified native dashboard missing"
grep -q "申请 / 重新检查 Root 权限" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "root authorization action missing"
grep -q "new ProcessBuilder(\"su\", \"-c\", command)" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootAccess.java" || fail "KernelSU su bridge missing"
grep -Eq "waitFor\(Math\.max\(1000L, timeoutMs\), TimeUnit\.MILLISECONDS\)" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootAccess.java" || fail "bounded root command timeout missing"
grep -q "destroyForcibly()" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootAccess.java" || fail "root timeout process cleanup missing"
grep -q 'RootAccess.execute(command)' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "root config publisher missing"
grep -q 'fx-hook-targets.conf' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "Remote Files target config path missing"
grep -q 'DeveloperHookRule.parse(ruleId+"|"+method+"|OBSERVE|0"' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "read-only custom rule validation missing"
grep -q 'android.intent.action.MAIN' "$ROOT/adhook/app/src/main/AndroidManifest.xml" || fail "launcher MAIN action missing"
grep -q 'android.intent.category.LAUNCHER' "$ROOT/adhook/app/src/main/AndroidManifest.xml" || fail "launcher category missing"
grep -q 'QUERY_ALL_PACKAGES' "$ROOT/adhook/app/src/main/AndroidManifest.xml" || fail "installed-app visibility permission missing"
[ -s "$APK" ] || fail "built Hook APK missing"
[ -x "$AAPT" ] || fail "Android aapt missing"
BADGING=$("$AAPT" dump badging "$APK")
printf '%s\n' "$BADGING" | grep -q "^package: name='de.privacyguard.adhook'" || fail "unexpected package id"
printf '%s\n' "$BADGING" | grep -q "^launchable-activity:" || fail "APK has no launcher activity"
printf '%s\n' "$BADGING" | grep -q "uses-permission: name='android.permission.QUERY_ALL_PACKAGES'" || fail "APK package visibility permission absent"
echo "PASS: FX Hook APK contains a native launcher entry and app discovery permission"
