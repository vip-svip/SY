#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
APK="${1:-$ROOT/adhook/app/build/outputs/apk/debug/app-debug.apk}"
SDK_ROOT="${ANDROID_HOME:-/usr/local/lib/android/sdk}"
AAPT="$SDK_ROOT/build-tools/34.0.0/aapt"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" ] || fail "native MainActivity source missing"
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
