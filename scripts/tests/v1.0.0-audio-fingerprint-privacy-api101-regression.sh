#!/bin/sh
set -eu
SRC="adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
PARSER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
SER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java"
POLICY="adhook/app/src/main/java/de/privacyguard/adhook/AudioFingerprintPolicy.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -q 'installAudioFingerprintPrivacyHooks' "$SRC" || fail 'AudioRecord perturbation hook installer missing'
grep -q 'ThreadLocalRandom.current().nextInt(3)' "$SRC" || fail 'byte-buffer perturbation missing'
grep -q 'ThreadLocalRandom.current().nextInt(61)' "$SRC" || fail 'short sample perturbation missing'
grep -q 'nextFloat() - 0.5f' "$SRC" || fail 'float sample perturbation missing'
grep -q 'AudioFingerprintPolicy.shouldPerturbSamples' "$SRC" || fail 'fail-open audio fingerprint policy not connected'
grep -q 'case "audio_fp_block"' "$PARSER" || fail 'audio_fp_block parser flag missing'
grep -q 'audio_fp_block' "$SER" || fail 'audio_fp_block serializer flag missing'
grep -q 'target.audioFpBlock && !target.micBlock' "$POLICY" || fail 'mic_block precedence missing'
grep -q 'processPackageCount != 1' "$POLICY" || fail 'shared-process fail-open missing'
grep -q 'org.lsposed.manager' "$POLICY" || fail 'protected-package exclusion missing'
echo 'FX API101 audio fingerprint privacy regression: PASS'
