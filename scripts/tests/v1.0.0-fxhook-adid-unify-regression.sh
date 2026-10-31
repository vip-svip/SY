#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
if [ -d "$ROOT/adhook/app/src/main/java" ]; then
  REPO_ROOT="$ROOT"; MODULE_ROOT="$ROOT/fx-module"
else
  REPO_ROOT=$(dirname "$ROOT"); MODULE_ROOT="$ROOT"
fi
ACTIVITY="$REPO_ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
PARSER="$REPO_ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
SERIALIZER="$REPO_ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java"
RUNTIME="$REPO_ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
IDENTIFIER="$REPO_ROOT/adhook/app/src/main/java/de/privacyguard/adhook/PrivacyIdentifier.java"
IDENTIFIER_TEST="$REPO_ROOT/adhook/app/src/test/java/de/privacyguard/adhook/PrivacyIdentifierTest.java"
MERGE="$REPO_ROOT/fx-patches/merge_hook_single_apk.py"
STATUS="$MODULE_ROOT/scripts/status.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }

grep -Fq 'toggle("统一广告标识（应用内）", "ad_id_unify", false);' "$ACTIVITY" || fail "native per-app editor lacks ad_id_unify opt-in"
grep -Fq '{"ad_id_unify","ad_id_unify"}' "$ACTIVITY" || fail "native publisher does not suppress duplicate legacy ad_id_unify"
grep -Fq '"notification_permission_hide","ad_id_unify","mic_silence"' "$ACTIVITY" || fail "native target publisher omits ad_id_unify"
grep -Fq 'k.equals("ad_id_unify")' "$ACTIVITY" || fail "ad_id_unify does not activate the privacy master"

grep -Fq 'public final boolean adIdUnify;' "$PARSER" || fail "parser Target field missing"
grep -Fq 'case "ad_id_unify": adIdUnify = on; break;' "$PARSER" || fail "parser does not accept ad_id_unify"
grep -Fq 'adIdUnify=false;' "$PARSER" || fail "legacy/default parser path does not default ad_id_unify off"
grep -Fq '.append(",ad_id_unify=")' "$SERIALIZER" || fail "serializer does not emit ad_id_unify"

grep -Fq 'installAdvertisingIdHooks(param.getClassLoader(), pkg)' "$RUNTIME" || fail "API-101 runtime does not install advertising ID hooks"
grep -Fq 'com.google.android.gms.ads.identifier.AdvertisingIdClient$Info' "$RUNTIME" || fail "Google Ads ID accessor is not covered"
grep -Fq 'com.huawei.hms.ads.identifier.AdvertisingIdClient' "$RUNTIME" || fail "Huawei OAID accessor is not covered"
grep -Fq 'processPackages.size() != 1' "$RUNTIME" || fail "shared-process fail-open guard missing"
grep -Fq 'PrivacyIdentifier.forAdvertisingId(activePackage)' "$RUNTIME" || fail "package-scoped ID derivation is not called"
grep -Fq 'originalId.isEmpty()' "$RUNTIME" || fail "empty platform opt-out ID is not preserved"
grep -Fq 'public static String forAdvertisingId(String packageName)' "$IDENTIFIER" || fail "advertising ID derivation helper missing"
grep -Fq 'advertisingIdentifierIsStablePackageScopedAndUuidShaped' "$IDENTIFIER_TEST" || fail "advertising ID helper tests missing"

grep -Fq '"block_mediastore", "ad_id_unify"' "$MERGE" || fail "legacy API-101 ownership map does not suppress duplicate ad_id_unify"
grep -Fq 'new_privacy_pattern = "privacy=1|ad_id_unify=1|exif_strip=1"' "$MERGE" || fail "packaged status.sh privacy target count is not updated"
if [ -f "$STATUS" ]; then
  grep -Fq 'ad_id_unify=1' "$STATUS" || fail "packaged status.sh omits ad_id_unify from privacy target accounting"
fi
echo "PASS: ad_id_unify native UI, config, API-101 runtime, package scope, fail-open and legacy duplicate suppression are wired"
