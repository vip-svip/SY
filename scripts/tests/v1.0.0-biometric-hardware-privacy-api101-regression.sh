#!/bin/sh
set -eu
SRC="adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
PARSER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
SER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java"
POLICY="adhook/app/src/main/java/de/privacyguard/adhook/BiometricPrivacyPolicy.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -q 'installBiometricPrivacyHooks' "$SRC" || fail 'biometric hook installer missing'
grep -q 'FingerprintManagerCompat' "$SRC" || fail 'AndroidX fingerprint compatibility API missing'
grep -q 'android.hardware.face.FaceManager' "$SRC" || fail 'FaceManager API missing'
grep -q 'android.hardware.biometrics.BiometricManager' "$SRC" || fail 'BiometricManager API missing'
grep -q 'shouldReportNoBiometricHardware' "$SRC" || fail 'BiometricManager fail-open policy missing'
grep -q 'case "hide_fingerprint_hw"' "$PARSER" || fail 'fingerprint hardware flag parser missing'
grep -q 'case "hide_face_hw"' "$PARSER" || fail 'face hardware flag parser missing'
grep -q 'hide_fingerprint_hw' "$SER" || fail 'fingerprint hardware serializer flag missing'
grep -q 'hide_face_hw' "$SER" || fail 'face hardware serializer flag missing'
grep -q 'processPackageCount == 1' "$POLICY" || fail 'single-package fail-open policy missing'
grep -q 'org.lsposed.manager' "$POLICY" || fail 'protected package exclusion missing'
echo 'FX API101 biometric hardware privacy regression: PASS'
