#!/system/bin/sh
set -eu
ROOT=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
P="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook"
grep -q 'case "mic_silence": microphoneSilence = on' "$P/UnifiedHookConfigParser.java"
grep -q 'mic_silence=' "$P/UnifiedHookConfigSerializer.java"
grep -q 'installAudioRecordSilenceHooks' "$P/AdVisibilityHook.java"
grep -q 'processPackages.size() != 1' "$P/AdVisibilityHook.java"
grep -q 'AudioRecordSilencePolicy.zero' "$P/AdVisibilityHook.java"
grep -q 'zeroesOnlyReturnedByteRangeAndHonorsOffset' "$ROOT/adhook/app/src/test/java/de/privacyguard/adhook/AudioRecordSilencePolicyTest.java"
! grep -q 'startRecording' "$P/AdVisibilityHook.java"
! grep -q 'noise' "$P/AudioRecordSilencePolicy.java"
echo 'PASS: AudioRecord silence API-101 regression'
