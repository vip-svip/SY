#!/bin/sh
set -eu
SRC="adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
PARSER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
SER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java"
POLICY="adhook/app/src/main/java/de/privacyguard/adhook/CameraPrivacyPolicy.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -q 'installCameraIdPrivacyHooks' "$SRC" || fail 'camera-ID enumeration hook missing'
grep -q 'getCameraIdList' "$SRC" || fail 'CameraManager API missing'
grep -q 'CameraPrivacyPolicy.shouldHideCameraIds' "$SRC" || fail 'camera-ID fail-open policy missing'
grep -q 'case "camera_id_hide"' "$PARSER" || fail 'camera-ID config parser missing'
grep -q 'camera_id_hide' "$SER" || fail 'camera-ID config serializer missing'
grep -q 'processPackageCount != 1' "$POLICY" || fail 'shared-process fail-open policy missing'
grep -q 'org.lsposed.manager' "$POLICY" || fail 'protected package exclusion missing'
echo 'FX API101 camera-ID privacy regression: PASS'
