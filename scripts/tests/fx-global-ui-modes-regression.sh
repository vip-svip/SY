#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
mode="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxUiMode.kt"
panel="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxDesignModePanel.kt"
shell="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt"
activity="$root/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
for f in "$mode" "$panel" "$shell" "$activity"; do
  test -s "$f" || { echo "FAIL: missing UI mode source $f"; exit 1; }
done
for token in CLASSIC_WEB_COMPAT FX_LIQUID_NATIVE MIUIX_STYLE HUAWEI_HARMONY_STYLE IOS_CUPERTINO_STYLE classic glass miuix huawei ios; do
  grep -Fq "$token" "$mode" || { echo "FAIL: mode model missing $token"; exit 1; }
done
for token in FxUiMode.CLASSIC_WEB_COMPAT FxUiMode.FX_LIQUID_NATIVE FxUiMode.MIUIX_STYLE FxUiMode.HUAWEI_HARMONY_STYLE FxUiMode.IOS_CUPERTINO_STYLE; do
  grep -Fq "$token" "$panel" || { echo "FAIL: settings panel missing $token"; exit 1; }
done
grep -Fq 'LiquidBottomTabs(' "$shell" || { echo "FAIL: liquid renderer missing"; exit 1; }
grep -Fq 'MiuixTheme(' "$shell" || { echo "FAIL: Miuix renderer missing"; exit 1; }
grep -Fq 'mode == "glass"' "$shell" || { echo "FAIL: liquid mode branch missing"; exit 1; }
grep -Fq 'mode == "miuix"' "$shell" || { echo "FAIL: Miuix mode branch missing"; exit 1; }
grep -Fq 'mode == "classic"' "$shell" || { echo "FAIL: classic mode branch missing"; exit 1; }
grep -Fq '"huawei".equals(uiMode)' "$activity" || { echo "FAIL: HUAWEI native page palette missing"; exit 1; }
grep -Fq '"ios".equals(uiMode)' "$activity" || { echo "FAIL: iOS native page palette missing"; exit 1; }
grep -Fq '"huawei" -> Color(0xFFF1F5FA)' "$shell" || { echo "FAIL: HUAWEI Harmony shell palette missing"; exit 1; }
grep -Fq '"ios" -> Color(0xFFF2F2F7)' "$shell" || { echo "FAIL: iOS Cupertino shell palette missing"; exit 1; }
grep -Fq 'webView.setVisibility(View.VISIBLE)' "$activity" || { echo "FAIL: ClassicWebCompat WebView not mounted"; exit 1; }
grep -Fq 'navigateWebPage(webPageForBottomTab(index))' "$activity" || { echo "FAIL: ClassicWebCompat tab routing missing"; exit 1; }
grep -Fq 'FxUiMode.read(this).getStorageId()' "$activity"
grep -Fq 'FxUiMode.write(MainActivity.this' "$activity"
grep -Fq 'applyWebUiMode();' "$activity"
echo "PASS: five global UI modes have a shared model, selector, shell renderer and persistence path."
