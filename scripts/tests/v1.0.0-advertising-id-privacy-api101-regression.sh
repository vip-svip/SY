#!/bin/sh
set -eu
SRC="adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
PARSER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
SER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java"
POLICY="adhook/app/src/main/java/de/privacyguard/adhook/AdvertisingIdPrivacyPolicy.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -q 'installAdvertisingIdPrivacyHooks' "$SRC" || fail 'Advertising ID hook installer missing'
grep -q 'com.google.android.gms.ads.identifier.AdvertisingIdClient' "$SRC" || fail 'Google Advertising ID SDK path missing'
grep -q 'com.huawei.hms.ads.identifier.AdvertisingIdClient' "$SRC" || fail 'Huawei OAID SDK path missing'
grep -q 'AdvertisingIdPrivacyPolicy.shouldUnify' "$SRC" || fail 'single-package Advertising ID policy not connected'
grep -q 'case "ad_id_unify"' "$PARSER" || fail 'ad_id_unify parser flag missing'
grep -q 'ad_id_unify' "$SER" || fail 'ad_id_unify serializer flag missing'
grep -q 'processPackageCount == 1' "$POLICY" || fail 'shared-process fail-open missing'
grep -q 'org.lsposed.manager' "$POLICY" || fail 'protected package exclusion missing'
grep -q 'syntheticIdsAreStablePackageScopedUuidValues' adhook/app/src/test/java/de/privacyguard/adhook/AdvertisingIdPrivacyPolicyTest.java || fail 'stable app-scoped UUID test missing'
echo 'FX API101 Advertising ID privacy regression: PASS'
