#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
APP="$ROOT/adhook/app/src/main"
HTML="$APP/assets/webroot/index.html"
fail(){ echo "FAIL: $*" >&2; exit 1; }

[ -s "$HTML" ] || fail "complete FX WebUI was not staged into APK assets"
[ "$(wc -c < "$HTML" | tr -d ' ')" -gt 500000 ] || fail "FX WebUI asset is unexpectedly truncated"
for page in pageVpn pageAd pageHosts pagePrivacy pageScript pageMore; do
  grep -q "id=\"$page\"" "$HTML" || fail "missing migrated UI page: $page"
done
for panel in vpnPanel rootPanel advPanel netPanel permPanel sensorPanel locationPanel devicePanel mediaPanel filePanel notifyPanel kernelPanel miscPanel crashPanel stylePanel langPanel; do
  grep -q "id=\"$panel\"" "$HTML" || fail "missing migrated settings panel: $panel"
done
for marker in fxHookAppList fxHookSync builtinCerts mitmTrafficEnable hostsOpenEditor vpnSubUpdateAll; do
  grep -q "$marker" "$HTML" || fail "missing migrated feature marker: $marker"
done

ACTIVITY="$APP/java/de/privacyguard/adhook/MainActivity.java"
BRIDGE="$APP/java/de/privacyguard/adhook/RootBridge.java"
ROOT_ACCESS="$APP/java/de/privacyguard/adhook/RootAccess.java"
[ -s "$ACTIVITY" ] || fail "MainActivity missing"
[ -s "$BRIDGE" ] || fail "RootBridge missing"
[ -s "$ROOT_ACCESS" ] || fail "RootAccess missing"
grep -q 'WebViewAssetLoader' "$ACTIVITY" || fail "secure app asset loader missing"
grep -q 'appassets.androidplatform.net/assets/webroot/index.html' "$ACTIVITY" || fail "WebUI is not loaded from app-owned assets"
grep -q 'setAllowFileAccess(false)' "$ACTIVITY" || fail "WebView file access must remain disabled"
grep -q 'setAllowUniversalAccessFromFileURLs(false)' "$ACTIVITY" || fail "universal file URL access must remain disabled"
grep -q 'window.ksu={exec:function' "$ACTIVITY" || fail "KernelSU WebUI compatibility bridge missing"
grep -q 'window.showSaveFilePicker' "$ACTIVITY" || fail "native export bridge shim missing"
grep -q 'onShowFileChooser' "$ACTIVITY" || fail "native import file picker missing"
grep -q 'openHookManager' "$BRIDGE" || fail "native Hook manager entry missing"
grep -q 'FXRoot.exec' "$ACTIVITY" || fail "WebUI root execution shim missing"
grep -q 'CALLBACK' "$BRIDGE" || fail "callback name validation missing"
grep -q '@JavascriptInterface' "$BRIDGE" || fail "JavaScript bridge annotation missing"
grep -q 'saveBase64' "$BRIDGE" || fail "Android Downloads export bridge missing"
grep -q 'new ProcessBuilder("su", "-c", command)' "$ROOT_ACCESS" || fail "KernelSU su executor missing"
grep -q '120000L' "$BRIDGE" || fail "long-running module command timeout missing"
grep -q "androidx.webkit:webkit:1.12.1" "$ROOT/adhook/app/build.gradle" || fail "WebViewAssetLoader dependency missing"
grep -q 'android.permission.INTERNET' "$ROOT/adhook/app/src/main/AndroidManifest.xml" || fail "network permission missing"
grep -q 'FX_FULL_APP_MIGRATION_COMPLETE' "$ROOT/.github/workflows/build-fx-adhook.yml" || fail "APK build gate missing"
grep -q 'FX_FULL_APP_MIGRATION_COMPLETE' "$ROOT/.github/workflows/build-fx-kernelsu.yml" || fail "KernelSU build gate missing"
echo "PASS: complete FX WebUI is packaged in the app with KernelSU bridge, file import/export, and native Hook entry"
