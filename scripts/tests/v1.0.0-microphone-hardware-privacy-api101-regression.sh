#!/bin/sh
set -eu
SRC="adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
PARSER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
SER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java"
POLICY="adhook/app/src/main/java/de/privacyguard/adhook/MicrophoneHardwarePrivacyPolicy.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -q 'installMicrophoneHardwarePrivacyHooks' "$SRC" || fail 'microphone hardware hook installer missing'
grep -q 'AudioManager' "$SRC" || fail 'AudioManager input-device enumeration missing'
grep -q 'getDevices' "$SRC" || fail 'AudioManager.getDevices interception missing'
grep -q 'getMicrophones' "$SRC" || fail 'AudioManager.getMicrophones interception missing'
grep -q 'getRoutedDevice' "$SRC" || fail 'AudioRecord routed-device metadata interception missing'
grep -q 'getActiveMicrophones' "$SRC" || fail 'active microphone metadata interception missing'
grep -q 'MicrophoneHardwarePrivacyPolicy.shouldHideInputDevices' "$SRC" || fail 'fail-open policy not connected'
grep -q 'case "mic_hw_hide"' "$PARSER" || fail 'mic_hw_hide parser flag missing'
grep -q 'mic_hw_hide' "$SER" || fail 'mic_hw_hide serializer flag missing'
grep -q 'processPackageCount != 1' "$POLICY" || fail 'shared-process fail-open missing'
grep -q 'org.lsposed.manager' "$POLICY" || fail 'LSPosed protected-package exclusion missing'
grep -q 'de.privacyguard.adhook' "$POLICY" || fail 'Hook self-protection missing'
echo 'FX API101 microphone hardware privacy regression: PASS'
