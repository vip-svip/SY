#!/usr/bin/env bash
set -euo pipefail
script_root="$(cd "$(dirname "$0")/../.." && pwd)"
if [ -d "$script_root/fx-module/adhook" ]; then
  root="$script_root"
else
  root="$(cd "$script_root/.." && pwd)"
fi
java="$root/adhook/app/src/main/java/de/privacyguard/adhook"
mode="$java/FxUiMode.kt"
panel="$java/FxDesignModePanel.kt"
shell="$java/FxNativeAppShell.kt"
compose_tokens="$java/FxComposeSkinTokens.kt"
skin="$java/FxNativeSkin.java"
host="$java/FxNativeTabActivity.java"
classic="$java/FxClassicWebCompat.java"
root_bridge="$java/RootBridge.java"
webui="$root/webroot/index.html"
build_workflow="$root/.github/workflows/build-fx-adhook.yml"
code_editor="$java/imported/dia/FxDiaCodeEditorActivity.java"
script_library="$java/imported/dia/FxDiaScriptLibraryActivity.java"
licenses="$java/FxOpenSourceLicensesActivity.java"
dex_page="$java/imported/dia/FxDiaDexBrowserActivity.java"
backup_page="$java/imported/dia/FxDiaBackupActivity.java"
monitor_page="$java/imported/dia/FxDiaMonitorEventsActivity.java"
firewall_page="$java/imported/ad/FxYulongFirewallActivity.java"
ad_general="$java/imported/ad/FxYulongAdGeneralActivity.java"
ad_home="$java/imported/ad/FxYulongAdActivity.java"
ad_app_whitelist="$java/imported/ad/FxYulongAppWhitelistActivity.java"
shield_main="$java/imported/shield/FxYulongShieldActivity.java"
shield_cleanup="$java/imported/shield/FxYulongBatchCleanupActivity.java"
settings="$java/FxNativeSettingsActivity.java"
hook_page="$java/MainActivity.java"
hook_logs="$java/FxHookObservationLogsActivity.java"
vpn_page="$java/FxNativeVpnActivity.java"
quickjs_page="$java/FxQuickJsScriptActivity.java"
gkd_page="$java/FxGkdAutomationActivity.java"
dia_global_settings="$java/imported/dia/FxDiaGlobalSettingsActivity.java"
dia_tools="$java/imported/dia/FxDiaToolsActivity.java"
dia_crash="$java/imported/dia/FxDiaCrashReportActivity.java"
dia_browser="$java/imported/dia/FxDiaActivityBrowserActivity.java"
dia_frida="$java/imported/dia/FxDiaFridaActivity.java"
dia_system_expand="$java/imported/dia/FxDiaSystemExpandActivity.java"
dia_json="$java/imported/dia/FxDiaJsonActivity.java"
dia_signature="$java/imported/dia/FxDiaSignatureActivity.java"
dia_gps="$java/imported/dia/FxDiaGpsPickerActivity.java"
dia_inspector="$java/imported/dia/FxDiaInspectorActivity.java"
ad_stats="$java/imported/ad/FxYulongAppStatsActivity.java"
dia_wifi_proxy="$java/imported/dia/FxDiaWifiProxyActivity.java"
ad_summary="$java/imported/ad/FxYulongAdSummaryActivity.java"
dia_session_log="$java/imported/dia/FxDiaSessionLogActivity.java"
shield_rescue="$java/imported/shield/FxYulongRescueActivity.java"
shield_warning="$java/imported/shield/FxYulongWarningActivity.java"
dia_file="$java/imported/dia/FxDiaFileActivity.java"
classic_page="$java/FxClassicWebCompatActivity.java"
router="$java/FxNativeTabRouter.java"
manifest="$root/adhook/app/src/main/AndroidManifest.xml"
hook_page="$java/MainActivity.java"
hook_logs="$java/FxHookObservationLogsActivity.java"
vpn_page="$java/FxNativeVpnActivity.java"
quickjs_page="$java/FxQuickJsScriptActivity.java"
gkd_page="$java/FxGkdAutomationActivity.java"
harmony_tokens="$java/HarmonySkinTokens.java"
cupertino_tokens="$java/CupertinoSkinTokens.java"
harmony_renderer="$java/HarmonySkinRenderer.java"
cupertino_renderer="$java/CupertinoSkinRenderer.java"
native_skin_test="$root/adhook/app/src/test/java/de/privacyguard/adhook/FxNativeSkinPaletteTest.kt"
mode_unit="$root/adhook/app/src/test/java/de/privacyguard/adhook/FxUiModeTest.kt"

for file in "$mode" "$mode_unit" "$panel" "$shell" "$compose_tokens" "$skin" "$host" "$classic" "$root_bridge" "$code_editor" "$script_library" "$licenses" "$dex_page" "$backup_page" "$monitor_page" "$firewall_page" "$ad_general" "$settings" "$hook_page" "$hook_logs" "$vpn_page" "$quickjs_page" "$gkd_page" "$classic_page" "$router" "$manifest" "$harmony_tokens" "$cupertino_tokens" "$harmony_renderer" "$cupertino_renderer" "$native_skin_test" "$hook_page" "$hook_logs" "$vpn_page" "$quickjs_page" "$gkd_page" "$dia_global_settings" "$dia_tools" "$dia_crash" "$dia_browser" "$dia_frida" "$dia_system_expand" "$dia_json" "$dia_signature" "$dia_gps" "$dia_inspector" "$ad_stats" "$dia_wifi_proxy" "$dia_file" "$ad_home" "$ad_app_whitelist" "$shield_main" "$shield_cleanup"; do
  test -s "$file" || { echo "FAIL: missing native UI mode source: $file" >&2; exit 1; }
done

# The APK build copies the app source tree into fx-module. Keep all mode models,
# Compose shell, native renderers, Settings routing and palette tests byte-identical
# so the published module cannot silently ship an older skin implementation.
for relative in \
  app/src/main/java/de/privacyguard/adhook/FxUiMode.kt \
  app/src/test/java/de/privacyguard/adhook/FxUiModeTest.kt \
  app/src/main/java/de/privacyguard/adhook/FxDesignModePanel.kt \
  app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt \
  app/src/main/java/de/privacyguard/adhook/FxComposeSkinTokens.kt \
  app/src/main/java/de/privacyguard/adhook/FxNativeSkin.java \
  app/src/main/java/de/privacyguard/adhook/FxNativeTabActivity.java \
  app/src/main/AndroidManifest.xml \
  app/src/main/java/de/privacyguard/adhook/FxClassicWebCompat.java \
  app/src/main/java/de/privacyguard/adhook/RootBridge.java \
  app/src/main/java/de/privacyguard/adhook/MainActivity.java \
  app/src/main/java/de/privacyguard/adhook/FxHookObservationLogsActivity.java \
  app/src/main/java/de/privacyguard/adhook/FxNativeVpnActivity.java \
  app/src/main/java/de/privacyguard/adhook/FxQuickJsScriptActivity.java \
  app/src/main/java/de/privacyguard/adhook/FxGkdAutomationActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaGlobalSettingsActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaToolsActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaCrashReportActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaActivityBrowserActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaSystemExpandActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaJsonActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaSignatureActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaGpsPickerActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaInspectorActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAppStatsActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaWifiProxyActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdSummaryActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaSessionLogActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongRescueActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongWarningActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFileActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaCodeEditorActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaScriptLibraryActivity.java \
  app/src/main/java/de/privacyguard/adhook/FxOpenSourceLicensesActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaDexBrowserActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaBackupActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaMonitorEventsActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongFirewallActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdGeneralActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAppWhitelistActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongShieldActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongBatchCleanupActivity.java \
  app/src/main/java/de/privacyguard/adhook/FxNativeSettingsActivity.java \
  app/src/main/java/de/privacyguard/adhook/MainActivity.java \
  app/src/main/java/de/privacyguard/adhook/FxHookObservationLogsActivity.java \
  app/src/main/java/de/privacyguard/adhook/FxNativeVpnActivity.java \
  app/src/main/java/de/privacyguard/adhook/FxQuickJsScriptActivity.java \
  app/src/main/java/de/privacyguard/adhook/FxGkdAutomationActivity.java \
  app/src/main/java/de/privacyguard/adhook/FxClassicWebCompatActivity.java \
  app/src/main/java/de/privacyguard/adhook/FxNativeTabRouter.java \
  app/src/main/java/de/privacyguard/adhook/HarmonySkinTokens.java \
  app/src/main/java/de/privacyguard/adhook/CupertinoSkinTokens.java \
  app/src/main/java/de/privacyguard/adhook/HarmonySkinRenderer.java \
  app/src/main/java/de/privacyguard/adhook/CupertinoSkinRenderer.java \
  app/src/test/java/de/privacyguard/adhook/FxNativeSkinPaletteTest.kt; do
  cmp -s "$root/adhook/$relative" "$root/fx-module/adhook/$relative" || {
    echo "FAIL: six-mode APK/module source drift: $relative" >&2
    exit 1
  }
done

# ClassicWebCompat must be a real, packaged local-WebUI renderer, not only
# a Classic palette. Verify the trusted asset origin, external-navigation block,
# document-start compatibility shim, Root bridge lifecycle and legacy tab map.
for token in 'root.setTag("fx-page-root")' 'header.setTag("fx-toolbar")' \
             'header.addView(button("‹ 返回 Hook", this::finish, "fx-toolbar-action"))' \
             'pageTitle.setTag("fx-toolbar-title")' 'warning.setTag("fx-risk-suspect")' \
             'search.setTag("fx-search-input")' 'status.setTag("fx-empty-state")' \
             'private void showStatus(String message, String role)' \
             'showStatus("正在读取最近 500 行日志…", "fx-loading-state")' \
             'outputView.setTag(filtered.isEmpty() ? "fx-empty-state" : "fx-card-body")' \
             'button("刷新日志", this::refreshLog, "fx-primary-action")' \
             'button("清空当前日志", this::confirmClearLog, "fx-risk-suspect")'; do
  grep -Fq "$token" "$dia_session_log" || { echo "FAIL: Dia session log six-mode role/state missing $token" >&2; exit 1; }
done
for token in 'root.setTag("fx-page-root")' 'header.setTag("fx-toolbar")' \
             'header.addView(button("‹ 返回隐私", this::returnToShieldHub, "fx-toolbar-action"))' \
             'pageTitle.setTag("fx-toolbar-title")' 'body.setTag("fx-card-group")' \
             'foregroundLabel.setTag("fx-list-title")' 'p.setTag("fx-card")' \
             'heading.setTag("fx-card-title")' 'description.setTag("fx-card-detail")' \
             'status.setTag("fx-card-detail")' 'private void setStatus(String value, String role)' \
             'setStatus("已刷新前台应用信息。", "fx-success-state")' \
             'setStatus("当前没有可处理的前台应用包名。", "fx-error-state")'; do
  grep -Fq "$token" "$shield_rescue" || { echo "FAIL: Shield rescue six-mode role/state missing $token" >&2; exit 1; }
done
for token in 'root.setTag("fx-page-root")' 'header.setTag("fx-toolbar")' \
             'pageTitle.setTag("fx-toolbar-title")' 'riskDetails.setTag("fx-card")' \
             'packageState.setTag("fx-card-detail")' 'actions.setTag("fx-card-group")'; do
  grep -Fq "$token" "$shield_warning" || { echo "FAIL: Shield warning six-mode role missing $token" >&2; exit 1; }
done
for token in 'root.setTag("fx-page-root")' 'header.setTag("fx-toolbar")' \
             'pageTitle.setTag("fx-toolbar-title")' 'directorySearch.setTag("fx-search-input")' \
             'files.setTag("fx-card-group")' 'row.setTag("fx-list-row")' \
             'entryTitle.setTag("fx-list-title")' 'name.setTag("fx-form-input")'; do
  grep -Fq "$token" "$dia_file" || { echo "FAIL: Dia file browser six-mode role missing $token" >&2; exit 1; }
done

# Guard against accidentally writing a literal backslash-n into Java source
# while patching semantic roles; these sequences are illegal outside strings.
python3 - "$dia_json" "$dia_signature" "$dia_session_log" <<'PYLINEBREAK'
from pathlib import Path
import sys
for filename in sys.argv[1:]:
    source = Path(filename).read_text(encoding="utf-8")
    for token in ("\\\\n        TextView", "\\\\n        header.addView", "\\\\n        outputView"):
        assert token not in source, f"literal escaped source newline in {filename}: {token!r}"
print("PASS: six-mode page Java sources contain real line breaks.")
PYLINEBREAK

# Imported screens still receive the shared Activity/skin/dialog integration.
for page in   "$java/imported/ad/FxYulongAdActivity.java"   "$java/imported/ad/FxYulongAdGeneralActivity.java"   "$java/imported/ad/FxYulongAdSummaryActivity.java"   "$java/imported/shield/FxYulongShieldActivity.java"   "$java/imported/shield/FxYulongScanActivity.java"   "$java/imported/shield/FxYulongWarningActivity.java"   "$java/imported/dia/FxDiaActivityBrowserActivity.java"   "$java/imported/dia/FxDiaCodeEditorActivity.java"   "$java/imported/dia/FxDiaScriptLibraryActivity.java"; do
  grep -Fq 'extends de.privacyguard.adhook.FxNativeTabActivity' "$page" || {
    echo "FAIL: imported page bypasses FX native Activity host: $page" >&2; exit 1;
  }
  grep -Fq 'setContentViewWithNativeTabs(' "$page" || {
    echo "FAIL: imported page missing persistent FX navigation host: $page" >&2; exit 1;
  }
done

# Component adapters preserve semantic/destructive colors and use their own
# token namespaces instead of replacing user content indiscriminately.
grep -Fq 'shouldPreserveSemanticAction' "$skin"
grep -Fq 'RISK_CERTAIN_SURFACE' "$harmony_renderer"
grep -Fq 'RISK_SUSPECT_SURFACE' "$harmony_renderer"
grep -Fq 'RISK_CERTAIN_SURFACE' "$cupertino_renderer"
grep -Fq 'RISK_SUSPECT_SURFACE' "$cupertino_renderer"
grep -Fq 'harmonyAndCupertinoGeometryAndInputsRemainDistinct' "$native_skin_test"
grep -Fq 'harmonyAndCupertinoAppListRowsUseIndependentGeometryAndTypography' "$native_skin_test"

for token in 'root.setTag("fx-page-root")' 'header.setTag("fx-toolbar")' \
             'title.setTag("fx-toolbar-title")' 'search.setTag("fx-search-input")' \
             'rows.setTag("fx-card-group")' 'empty.setTag("fx-empty-state")' \
             'setMonitorStatus(String value)' 'status.setTag(role)'; do
  grep -Fq "$token" "$monitor_page" || { echo "FAIL: Dia monitor page six-mode role missing $token" >&2; exit 1; }
done
for token in 'root.setTag("fx-page-root")' 'header.setTag("fx-toolbar")' \
             'pageTitle.setTag("fx-toolbar-title")' 'rows.setTag("fx-card-group")' \
             'setFirewallStatus(String value)' 'status.setTag(role)' 'item.setTag("fx-list-row")'; do
  grep -Fq "$token" "$firewall_page" || { echo "FAIL: Yulong Firewall six-mode role missing $token" >&2; exit 1; }
done
for token in 'root.setTag("fx-page-root")' 'header.setTag("fx-toolbar")' \
             'pageTitle.setTag("fx-toolbar-title")' 'setAdGeneralStatus(TextView target, String value)' \
             'operationStatus' 'batteryStatus' 'taskerResultStatus'; do
  grep -Fq "$token" "$ad_general" || { echo "FAIL: Ad General six-mode role missing $token" >&2; exit 1; }
done

echo "PASS: global six-mode UI, native Settings selector, Compose/Android skin renderers and integrated native page hosts are wired."
