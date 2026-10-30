#!/bin/sh
set -eu
SRC="adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
PARSER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
SER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java"
POLICY="adhook/app/src/main/java/de/privacyguard/adhook/AudioPrivacyPolicy.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -q 'installMicrophoneReadBlockHooks' "$SRC" || fail 'AudioRecord read hook missing'
grep -q 'android.media.AudioRecord' "$SRC" || fail 'AudioRecord class lookup missing'
grep -q 'bufferType == byte\[\].class' "$SRC" || fail 'byte-array read overload missing'
grep -q 'bufferType == short\[\].class' "$SRC" || fail 'short-array read overload missing'
grep -q 'bufferType == float\[\].class' "$SRC" || fail 'float-array read overload missing'
grep -q 'ByteBuffer' "$SRC" || fail 'ByteBuffer read overload missing'
grep -q 'AudioPrivacyPolicy.shouldSilenceAudioRecord' "$SRC" || fail 'shared-process policy missing'
grep -q 'case "mic_block"' "$PARSER" || fail 'mic_block config parser missing'
grep -q 'mic_block' "$SER" || fail 'mic_block config serializer missing'
grep -q 'processPackageCount != 1' "$POLICY" || fail 'shared-process fail-open missing'
if grep -q 'android.media.MediaRecorder' "$SRC"; then fail 'MediaRecorder coverage must not be claimed'; fi
echo 'FX API101 AudioRecord microphone privacy regression: PASS'
