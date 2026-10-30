#!/bin/sh
set -eu
SRC="adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
PARSER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
SER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java"
POLICY="adhook/app/src/main/java/de/privacyguard/adhook/RegionCompatibilityPolicy.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -q 'installRegionCompatibilityDiagnostics' "$SRC" || fail 'region diagnostic installer missing'
grep -q 'getSimCountryIso' "$SRC" || fail 'SIM country observation missing'
grep -q 'getNetworkCountryIso' "$SRC" || fail 'network country observation missing'
grep -q 'Locale.getDefault().getCountry()' "$SRC" || fail 'locale country comparison missing'
grep -q 'return result;' "$SRC" || fail 'original country value must remain unchanged'
grep -q 'case "region_diag"' "$PARSER" || fail 'region_diag parser missing'
grep -q 'region_diag' "$SER" || fail 'region_diag serializer missing'
grep -q 'processPackageCount != 1' "$POLICY" || fail 'shared-process fail-open missing'
if grep -q 'setResult\|return "[A-Z][A-Z]"' "$SRC"; then fail 'region diagnostic must not spoof country values'; fi
echo 'FX API101 read-only region compatibility diagnostic regression: PASS'
