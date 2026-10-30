#!/bin/sh
set -eu
SRC="adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
POLICY="adhook/app/src/main/java/de/privacyguard/adhook/AudioPrivacyPolicy.java"
TEST="adhook/app/src/test/java/de/privacyguard/adhook/AudioPrivacyPolicyTest.java"
PARSER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -q 'installMicrophoneReadBlockHooks' "$SRC" || fail 'AudioRecord read interception missing'
grep -q 'AudioPrivacyPolicy.shouldSilenceAudioRecord' "$SRC" || fail 'microphone fail-open policy not connected'
grep -q 'case "mic_block"' "$PARSER" || fail 'mic_block parser flag missing'
grep -q 'target.micBlock' "$POLICY" || fail 'per-app mic_block policy missing'
grep -q 'processPackageCount != 1' "$POLICY" || fail 'shared-process fail-open missing'
grep -q 'org.lsposed.manager' "$POLICY" || fail 'protected package exclusions missing'
grep -q 'de.privacyguard.adhook' "$POLICY" || fail 'Hook self-protection missing'
grep -q 'MediaRecorder/native capture are not covered' "$SRC" || fail 'coverage limitation must be explicit'
grep -q 'disabledPerAppFlagDoesNotSuppressAudio' "$TEST" || fail 'disabled-flag unit test missing'
echo 'FX API101 AudioRecord microphone privacy regression: PASS'
