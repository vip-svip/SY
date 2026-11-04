#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MANIFEST="$ROOT/adhook/app/src/main/AndroidManifest.xml"
GRADLE="$ROOT/adhook/app/build.gradle"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$MANIFEST" ] && [ -s "$GRADLE" ] || fail "Android manifest/Gradle configuration missing"
! grep -Eq '<uses-sdk([[:space:]>])' "$MANIFEST" || fail "SDK versions must not be declared in the main manifest under AGP 9"
grep -Eq 'minSdk[[:space:]]+28' "$GRADLE" || fail "minSdk 28 must be declared in Gradle defaultConfig"
grep -Eq 'targetSdk[[:space:]]+34' "$GRADLE" || fail "targetSdk 34 must be declared in Gradle defaultConfig"
grep -Eq 'compileSdk[[:space:]]+37' "$GRADLE" || fail "compileSdk 37 must be retained"
echo "PASS: Android SDK levels are declared in Gradle, not the merged manifest"
