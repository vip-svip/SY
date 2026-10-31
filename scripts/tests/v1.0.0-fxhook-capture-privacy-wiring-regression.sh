#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PARSER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
SERIALIZER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java"
RUNTIME="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
UI="$ROOT/webroot/index.html"
TESTS="$ROOT/adhook/app/src/test/java/de/privacyguard/adhook"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for key in mic_silence camera_access_block location_access_block mic_access_block media_store_query_block; do
  grep -Fq "case \"$key\"" "$PARSER" || fail "parser missing $key"
  grep -Fq ",$key=" "$SERIALIZER" || fail "serializer missing $key"
  grep -Fq "'$key'" "$UI" || fail "target editor missing $key"
done
grep -Fq 'installAudioRecordSilenceHooks(pkg)' "$RUNTIME" || fail "AudioRecord silence runtime not wired"
grep -Fq 'installCameraAccessBlockHooks(pkg)' "$RUNTIME" || fail "camera access denial runtime not wired"
grep -Fq 'installLocationAccessBlockHooks(pkg)' "$RUNTIME" || fail "location access denial runtime not wired"
grep -Fq 'installMicrophoneAccessBlockHooks(pkg)' "$RUNTIME" || fail "microphone start denial runtime not wired"
grep -Fq 'installMediaStoreQueryBlockHooks(pkg)' "$RUNTIME" || fail "MediaStore query privacy runtime not wired"
grep -Fq '"media".equals(((Uri) first).getAuthority())' "$RUNTIME" || fail "MediaStore authority scope guard missing"
grep -Fq 'processPackages.size() != 1' "$RUNTIME" || fail "shared-process fail-open guard missing"
grep -Fq 'ExceptionMode.PASSTHROUGH' "$RUNTIME" || fail "explicit access denial must use passthrough exception mode"
grep -Fq 'AudioRecordSilencePolicy.zero(args' "$RUNTIME" || fail "silence policy not called after successful read"
grep -Fq 'microphoneAccessBlock' "$TESTS/UnifiedHookConfigParserTest.java" || fail "mic denial parser tests missing"
grep -Fq 'cameraAccessBlock' "$TESTS/UnifiedHookConfigParserTest.java" || fail "camera denial parser tests missing"
grep -Fq 'locationAccessBlock' "$TESTS/UnifiedHookConfigParserTest.java" || fail "location denial parser tests missing"
grep -Fq 'AudioRecordSilencePolicy' "$TESTS/AudioRecordSilencePolicyTest.java" || fail "AudioRecord buffer tests missing"
echo "PASS: capture privacy parser, serializer, UI, runtime gates, fail-open guards, and host tests are wired"
