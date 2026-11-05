#!/system/bin/sh
set -eu
ROOT=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
PARSER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
SERIALIZER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java"
HOOK="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
POLICY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AudioRecordSilencePolicy.java"
UI="$ROOT/../adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
PUBLISHER="$ROOT/scripts/gen_xposed_conf.sh"
TEST="$ROOT/adhook/app/src/test/java/de/privacyguard/adhook/AudioRecordSilencePolicyTest.java"
for f in "$PARSER" "$SERIALIZER" "$HOOK" "$POLICY" "$UI" "$PUBLISHER" "$TEST"; do [ -s "$f" ] || { echo "missing $f" >&2; exit 1; }; done
grep -q 'case "mic_silence": microphoneSilence = on' "$PARSER"
grep -q 'mic_silence=' "$SERIALIZER"
grep -q 'installAudioRecordSilenceHooks' "$HOOK"
grep -q 'processPackages.size() != 1' "$HOOK"
grep -q 'AudioRecordSilencePolicy.zero' "$HOOK"
grep -q 'mic_silence' "$PUBLISHER"
grep -Fq 'toggle("录音静音（保留录音流程）", "mic_silence"' "$UI"
grep -q 'zeroesOnlyReturnedByteRangeAndHonorsOffset' "$TEST"
if sed -n '/private void installAudioRecordSilenceHooks/,/private boolean isMicrophoneSilenceAuthorized/p' "$HOOK" | grep -q 'startRecording'; then echo 'unexpected startRecording interception in silence hook' >&2; exit 1; fi
if grep -q 'noise' "$POLICY"; then echo 'unexpected synthetic-noise mode' >&2; exit 1; fi
echo 'PASS: AudioRecord silence migration wiring and fail-open guards'
