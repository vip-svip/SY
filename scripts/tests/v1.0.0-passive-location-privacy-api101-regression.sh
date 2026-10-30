#!/bin/sh
set -eu
SRC="adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
PARSER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
SER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java"
POLICY="adhook/app/src/main/java/de/privacyguard/adhook/LocationPrivacyPolicy.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -q 'installPassiveLocationPrivacyHooks' "$SRC" || fail 'LocationManager last-known hook missing'
grep -q 'getLastKnownLocation' "$SRC" || fail 'last-known API missing'
grep -q 'LocationPrivacyPolicy.shouldHideLastKnownLocation' "$SRC" || fail 'fail-open policy missing'
grep -q 'case "disable_passive_loc"' "$PARSER" || fail 'config parser missing'
grep -q 'disable_passive_loc' "$SER" || fail 'config serializer missing'
grep -q 'processPackageCount != 1' "$POLICY" || fail 'shared-process fail-open missing'
if grep -q 'getCurrentLocation\|requestLocationUpdates' "$SRC"; then fail 'live location updates are not covered'; fi
echo 'FX API101 cached passive-location privacy regression: PASS'
