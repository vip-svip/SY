#!/system/bin/sh
set -eu
ROOT=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
PARSER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
SERIALIZER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java"
RUNTIME="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
POLICY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/WifiScanPrivacyPolicy.java"
GEN="$ROOT/scripts/gen_xposed_conf.sh"
UI="$ROOT/../adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
STATUS="$ROOT/scripts/status.sh"
for f in "$PARSER" "$SERIALIZER" "$RUNTIME" "$POLICY" "$GEN" "$UI" "$STATUS"; do
  [ -s "$f" ] || { echo "FAIL missing $f"; exit 1; }
done
grep -q 'case "wifi_scan_block": wifiScanBlock = on; break;' "$PARSER"
grep -q 'wifiScanBlock' "$SERIALIZER"
grep -q 'key == "wifi_scan_block") wifi_scan=val' "$GEN"
grep -q 'wifi_scan_enabled=$_gxc_wifi_scan' "$GEN"
grep -q 'wifi_scan_block=%s' "$GEN"
grep -q 'wifi_scan_enabled' "$GEN"
grep -Fq 'toggle("限制 Wi-Fi 扫描", "wifi_scan_block"' "$UI"
grep -q 'hook_wifi_scan_targets' "$STATUS"
grep -q 'installWifiScanPrivacyHooks(pkg)' "$RUNTIME"
grep -q 'getScanResults' "$RUNTIME"
grep -q 'isScanAlwaysAvailable' "$RUNTIME"
grep -q 'processPackages.size()' "$RUNTIME"
grep -q 'processPackageCount == 1' "$POLICY"
grep -q 'wifiScanEnabled && target.wifiScanBlock' "$RUNTIME"
grep -q 'org.lsposed.manager' "$POLICY"
sh -n "$GEN"
sh -n "$STATUS"
echo 'PASS API-101 Wi-Fi scan migration wiring, config mapping, protected-package and shared-process fail-open guards'
