#!/bin/sh
set -eu
SRC="adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
PARSER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
SER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java"
POLICY="adhook/app/src/main/java/de/privacyguard/adhook/RadioPrivacyPolicy.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -q 'installWifiScanPrivacyHooks' "$SRC" || fail 'Wi-Fi scan hook missing'
grep -q 'installCellInfoPrivacyHooks' "$SRC" || fail 'cell-info hook missing'
grep -q 'getScanResults' "$SRC" || fail 'Wi-Fi scan API missing'
grep -q 'getAllCellInfo' "$SRC" || fail 'cell-info API missing'
grep -q 'RadioPrivacyPolicy.shouldHideWifiScan' "$SRC" || fail 'Wi-Fi fail-open policy missing'
grep -q 'RadioPrivacyPolicy.shouldHideCellInfo' "$SRC" || fail 'cell-info fail-open policy missing'
grep -q 'case "wifi_scan_hide"' "$PARSER" || fail 'Wi-Fi config parser missing'
grep -q 'case "cell_info_hide"' "$PARSER" || fail 'cell-info config parser missing'
grep -q 'wifi_scan_hide' "$SER" || fail 'Wi-Fi serializer missing'
grep -q 'cell_info_hide' "$SER" || fail 'cell-info serializer missing'
grep -q 'processPackageCount == 1' "$POLICY" || fail 'shared-process fail-open policy missing'
echo 'FX API101 Wi-Fi scan/cell-info privacy regression: PASS'
