#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
mode="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxUiMode.kt"
panel="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxDesignModePanel.kt"
shell="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt"
tokens="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxComposeSkinTokens.kt"
activity="$root/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
host="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeTabActivity.java"
skin="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeSkin.java"
harmony_tokens="$root/adhook/app/src/main/java/de/privacyguard/adhook/HarmonySkinTokens.java"
cupertino_tokens="$root/adhook/app/src/main/java/de/privacyguard/adhook/CupertinoSkinTokens.java"
harmony_renderer="$root/adhook/app/src/main/java/de/privacyguard/adhook/HarmonySkinRenderer.java"
cupertino_renderer="$root/adhook/app/src/main/java/de/privacyguard/adhook/CupertinoSkinRenderer.java"
native_skin_test="$root/adhook/app/src/test/java/de/privacyguard/adhook/FxNativeSkinPaletteTest.kt"
ad_main="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java"
ad_general="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdGeneralActivity.java"
shield_scan="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongScanActivity.java"
shield_rescue="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongRescueActivity.java"
shield_blacklist="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/BlacklistActivity.java"
shield_batch_cleanup="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongBatchCleanupActivity.java"
shield_screen_filter="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongScreenFilterActivity.java"
shield_warning="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongWarningActivity.java"
dia_backup="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaBackupActivity.java"
dia_activity_browser="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaActivityBrowserActivity.java"
dia_code_editor="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaCodeEditorActivity.java"
dia_crash_report="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaCrashReportActivity.java"
dia_file="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFileActivity.java"
dia_inspector="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaInspectorActivity.java"
ad_summary="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdSummaryActivity.java"
ad_firewall="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongFirewallActivity.java"
shield_main="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongShieldActivity.java"
shield_scan="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongScanActivity.java"
shield_daily="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongDailySummaryActivity.java"
shield_warning="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongWarningActivity.java"
dia_frida="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java"
dia_scripts="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaScriptLibraryActivity.java"
for f in "$mode" "$panel" "$shell" "$tokens" "$activity" "$host" "$skin" "$harmony_tokens" "$cupertino_tokens" "$harmony_renderer" "$cupertino_renderer" "$native_skin_test" "$ad_main" "$ad_general" "$ad_summary" "$ad_firewall" "$shield_main" "$shield_scan" "$shield_rescue" "$shield_blacklist" "$shield_batch_cleanup" "$shield_screen_filter" "$shield_warning" "$dia_backup" "$dia_activity_browser" "$dia_code_editor" "$dia_crash_report" "$dia_file" "$dia_inspector" "$dia_frida" "$dia_scripts"; do
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
grep -Fq 'tokens.useLiquidTabsRenderer' "$shell" || { echo "FAIL: liquid renderer is not selected by the skin token set"; exit 1; }
grep -Fq 'fxComposeShellTokens(' "$shell" || { echo "FAIL: shared shell does not resolve the active skin tokens"; exit 1; }
grep -Fq 'tokens.barBorder' "$shell" || { echo "FAIL: per-skin shell border token is not applied"; exit 1; }
grep -Fq '"huawei".equals(uiMode)' "$activity" || { echo "FAIL: HUAWEI native page palette missing"; exit 1; }
grep -Fq '"ios".equals(uiMode)' "$activity" || { echo "FAIL: iOS native page palette missing"; exit 1; }
for token in FxClassicComposeTokens FxLiquidComposeTokens FxMiuixComposeTokens FxHarmonyComposeTokens FxCupertinoComposeTokens; do
  grep -Fq "internal object $token" "$tokens" || { echo "FAIL: missing independent skin token set $token"; exit 1; }
done
grep -Fq 'pageBackground = Color(HarmonySkinTokens.HarmonyColorTokens.BACKGROUND)' "$tokens" || { echo "FAIL: HUAWEI Compose renderer is not using the shared Harmony color tokens"; exit 1; }
grep -Fq 'pageBackground = Color(CupertinoSkinTokens.CupertinoColorTokens.BACKGROUND)' "$tokens" || { echo "FAIL: iOS Compose renderer is not using the shared Cupertino color tokens"; exit 1; }
grep -Fq 'barCornerRadiusDp = HarmonySkinTokens.HarmonyShapeTokens.NAV_BAR_RADIUS_DP' "$tokens" || { echo "FAIL: HUAWEI Compose renderer is not using Harmony shape tokens"; exit 1; }
grep -Fq 'tabBarHeightDp = HarmonySkinTokens.HarmonySpacingTokens.NAV_HEIGHT_DP' "$tokens" || { echo "FAIL: HUAWEI Compose renderer is not using Harmony spacing tokens"; exit 1; }
grep -Fq 'labelSizeSp = HarmonySkinTokens.HarmonyTypographyTokens.TAB_LABEL_SP.toInt()' "$tokens" || { echo "FAIL: HUAWEI Compose renderer is not using Harmony typography tokens"; exit 1; }
grep -Fq 'barCornerRadiusDp = CupertinoSkinTokens.CupertinoShapeTokens.NAV_BAR_RADIUS_DP' "$tokens" || { echo "FAIL: iOS Compose renderer is not using Cupertino shape tokens"; exit 1; }
grep -Fq 'tabBarHeightDp = CupertinoSkinTokens.CupertinoSpacingTokens.NAV_HEIGHT_DP' "$tokens" || { echo "FAIL: iOS Compose renderer is not using Cupertino spacing tokens"; exit 1; }
grep -Fq 'labelSizeSp = CupertinoSkinTokens.CupertinoTypographyTokens.TAB_LABEL_SP.toInt()' "$tokens" || { echo "FAIL: iOS Compose renderer is not using Cupertino typography tokens"; exit 1; }
grep -Fq 'tabBarHeightDp = 60' "$tokens" || { echo "FAIL: Classic tab geometry missing"; exit 1; }
grep -Fq 'tabBarHeightDp = 68' "$tokens" || { echo "FAIL: Miuix tab geometry missing"; exit 1; }
grep -Fq 'NAV_BAR_RADIUS_DP = 18' "$harmony_tokens" || { echo "FAIL: Harmony navigation geometry token missing"; exit 1; }
grep -Fq 'NAV_HEIGHT_DP = 72' "$harmony_tokens" || { echo "FAIL: Harmony tab-bar height token missing"; exit 1; }
grep -Fq 'NAV_BAR_RADIUS_DP = 24' "$cupertino_tokens" || { echo "FAIL: Cupertino navigation geometry token missing"; exit 1; }
grep -Fq 'NAV_HEIGHT_DP = 76' "$cupertino_tokens" || { echo "FAIL: Cupertino tab-bar height token missing"; exit 1; }
grep -Fq 'harmonyRendererUsesItsOwnCardActionAndFormTokens' "$native_skin_test" || { echo "FAIL: Harmony palette unit test missing"; exit 1; }
grep -Fq 'cupertinoRendererUsesItsOwnCardActionAndFormTokens' "$native_skin_test" || { echo "FAIL: Cupertino palette unit test missing"; exit 1; }
grep -Fq 'harmonyAndCupertinoGeometryAndInputsRemainDistinct' "$native_skin_test" || { echo "FAIL: cross-Skin distinction unit test missing"; exit 1; }
grep -Fq 'HarmonyShapeTokens.CARD_RADIUS_DP' "$harmony_renderer" || { echo "FAIL: Harmony native card renderer must use its dedicated card radius"; exit 1; }
grep -Fq 'CupertinoShapeTokens.CARD_RADIUS_DP' "$cupertino_renderer" || { echo "FAIL: Cupertino native card renderer must use its dedicated card radius"; exit 1; }
grep -Fq 'p.cardCornerRadiusDp - 4) * density' "$skin" || { echo "FAIL: native neutral cards must use card radius rather than action radius"; exit 1; }
grep -Fq 'palette.cornerRadiusDp * density' "$skin" || { echo "FAIL: native action buttons must retain the independent action radius"; exit 1; }
grep -Fq 'return HarmonySkinRenderer.palette();' "$skin" || { echo "FAIL: Android Views do not use the Harmony renderer"; exit 1; }
grep -Fq 'return CupertinoSkinRenderer.palette();' "$skin" || { echo "FAIL: Android Views do not use the Cupertino renderer"; exit 1; }
grep -Fq 'HarmonySkinRenderer.applyTaggedComponent(activity, view, mode)' "$skin" || { echo "FAIL: Harmony component renderer is not in the shared native Skin walk"; exit 1; }
grep -Fq 'CupertinoSkinRenderer.applyTaggedComponent(activity, view, mode)' "$skin" || { echo "FAIL: Cupertino component renderer is not in the shared native Skin walk"; exit 1; }
grep -Fq 'private static final WeakHashMap<View, String> TAGGED_COMPONENT_SKINS' "$skin" || { echo "FAIL: tagged component render cache is missing"; exit 1; }
grep -Fq 'TAGGED_COMPONENT_SKINS.get(view)' "$skin" || { echo "FAIL: tagged component cache does not deduplicate the current view"; exit 1; }
python3 - "$harmony_renderer" "$cupertino_renderer" <<'PY'
from pathlib import Path
import sys
for path in sys.argv[1:]:
    source = Path(path).read_text(encoding="utf-8")
    start = source.index("static void applyTaggedComponent(Activity activity, View view, FxUiMode mode)")
    end = source.index("private static int parseRequestedSize", start)
    render = source[start:end]
    gate = render.index("FxNativeSkin.beginTaggedComponentRender(view, mode, role)")
    first_drawable = render.find("setBackground(rounded")
    assert first_drawable < 0 or gate < first_drawable, f"{path}: cached render gate must precede Drawable creation"
print("PASS: Harmony/Cupertino tagged renderers dedupe layout redraws by mode and component role.")
PY
grep -Fq 'FxNativeSkin.shouldPreserveSemanticAction(action)' "$harmony_renderer" || { echo "FAIL: Harmony renderer may recolor semantic actions"; exit 1; }
grep -Fq 'FxNativeSkin.shouldPreserveSemanticAction(action)' "$cupertino_renderer" || { echo "FAIL: Cupertino renderer may recolor semantic actions"; exit 1; }
for role in 't.setTag("fx-title:" + size)' 'button.setTag("fx-action-row")' 'card.setTag("fx-card")' 'card.setTag("fx-setting-card")' 'group.setTag("fx-card-group")' 'h.setTag("fx-card-title")' 'd.setTag("fx-card-detail")' 't.setTag("fx-section:" + s)'; do
  grep -Fq "$role" "$activity" || { echo "FAIL: shared native component role missing: $role"; exit 1; }
done
for token in \
  'HarmonySkinTokens.HarmonyColorTokens.TOP_BAR_BACKGROUND' \
  'CupertinoSkinTokens.CupertinoColorTokens.TOP_BAR_BACKGROUND' \
  'HarmonySkinTokens.HarmonyColorTokens.CARD_SURFACE' \
  'CupertinoSkinTokens.CupertinoColorTokens.CARD_SURFACE' \
  'HarmonySkinTokens.HarmonyColorTokens.CARD_STROKE' \
  'CupertinoSkinTokens.CupertinoColorTokens.CARD_STROKE' \
  'HarmonySkinTokens.HarmonyShapeTokens.SECTION_RADIUS_DP' \
  'CupertinoSkinTokens.CupertinoShapeTokens.SECTION_RADIUS_DP' \
  'HarmonySkinTokens.HarmonyTypographyTokens.PAGE_TITLE_SP' \
  'CupertinoSkinTokens.CupertinoTypographyTokens.PAGE_TITLE_SP' \
  'HarmonySkinTokens.HarmonySpacingTokens.SECTION_VERTICAL_PADDING_DP' \
  'CupertinoSkinTokens.CupertinoSpacingTokens.SECTION_VERTICAL_PADDING_DP' \
  'HarmonySkinTokens.HarmonySpacingTokens.CARD_HORIZONTAL_PADDING_DP' \
  'CupertinoSkinTokens.CupertinoSpacingTokens.CARD_HORIZONTAL_PADDING_DP'; do
  grep -Fq "$token" "$activity" || { echo "FAIL: MainActivity does not apply shared native layout token $token"; exit 1; }
done
for role in 'role.startsWith("fx-title:")' 'role.startsWith("fx-section:")' '"fx-card".equals(role)' '"fx-action-row".equals(role)'; do
  grep -Fq "$role" "$harmony_renderer" || { echo "FAIL: Harmony component role renderer missing: $role"; exit 1; }
  grep -Fq "$role" "$cupertino_renderer" || { echo "FAIL: Cupertino component role renderer missing: $role"; exit 1; }
done
grep -Fq '"fx-card-group".equals(role)' "$harmony_renderer" || { echo "FAIL: Harmony renderer misses grouped action surfaces"; exit 1; }
grep -Fq '"fx-card-group".equals(role)' "$cupertino_renderer" || { echo "FAIL: Cupertino renderer misses grouped action surfaces"; exit 1; }
for role in '"fx-list-row".equals(role)' '"fx-list-title".equals(role)' '"fx-list-subtitle".equals(role)'; do
  grep -Fq "$role" "$harmony_renderer" || { echo "FAIL: Harmony app-list renderer missing $role"; exit 1; }
  grep -Fq "$role" "$cupertino_renderer" || { echo "FAIL: Cupertino app-list renderer missing $role"; exit 1; }
done
for role in 'row.setTag("fx-list-row")' 'name.setTag("fx-list-title")' 'packageName.setTag("fx-list-subtitle")' 'pkg.setTag("fx-list-subtitle")' 'enabled.setTag("fx-switch-row")'; do
  grep -Fq "$role" "$activity" || { echo "FAIL: Hook/VPN app list missing global Skin role $role"; exit 1; }
done
for token in 'LIST_ROW_SURFACE' 'LIST_ROW_BORDER' 'LIST_ROW_RIPPLE' 'LIST_ROW_RADIUS_DP' 'LIST_ROW_TITLE_SP' 'LIST_ROW_SUBTITLE_SP' 'LIST_ROW_MIN_HEIGHT_DP' 'LIST_ROW_HORIZONTAL_PADDING_DP' 'LIST_ROW_VERTICAL_PADDING_DP'; do
  grep -Fq "$token" "$harmony_tokens" || { echo "FAIL: Harmony app-list token missing $token"; exit 1; }
  grep -Fq "$token" "$cupertino_tokens" || { echo "FAIL: Cupertino app-list token missing $token"; exit 1; }
done
grep -Fq 'harmonyAndCupertinoAppListRowsUseIndependentGeometryAndTypography' "$native_skin_test" || { echo "FAIL: app-list Skin token unit test missing"; exit 1; }
for role in 'title.setTag("fx-card-title")' 'detail.setTag("fx-card-body")' 'description.setTag("fx-card-body")' 'sw.setTag("fx-switch-row")'; do
  grep -Fq "$role" "$activity" || { echo "FAIL: shared native page is missing component role assignment: $role"; exit 1; }
done
for role in '"fx-card-title".equals(role)' '"fx-card-body".equals(role)' '"fx-switch-row".equals(role)'; do
  grep -Fq "$role" "$harmony_renderer" || { echo "FAIL: Harmony component renderer does not handle role: $role"; exit 1; }
  grep -Fq "$role" "$cupertino_renderer" || { echo "FAIL: Cupertino component renderer does not handle role: $role"; exit 1; }
done
grep -Fq 'CARD_TITLE_SP' "$harmony_renderer" || { echo "FAIL: Harmony card title typography token not applied"; exit 1; }
grep -Fq 'CARD_TITLE_SP' "$cupertino_renderer" || { echo "FAIL: Cupertino card title typography token not applied"; exit 1; }
for token in 'CARD_SURFACE' 'CARD_STROKE' 'ROW_RIPPLE' 'SECTION_RADIUS_DP' 'PAGE_TITLE_SP' 'SECTION_TITLE_SP' 'CARD_TITLE_SP' 'CARD_DESCRIPTION_SP' 'ROW_MIN_HEIGHT_DP'; do
  grep -Fq "$token" "$harmony_tokens" || { echo "FAIL: Harmony component token missing: $token"; exit 1; }
  grep -Fq "$token" "$cupertino_tokens" || { echo "FAIL: Cupertino component token missing: $token"; exit 1; }
done
grep -Fq 'applyTextInputSkin(activity, (EditText) view, mode, palette)' "$skin" || { echo "FAIL: EditText controls must use skin hint tokens"; exit 1; }
grep -Fq 'applySpinnerSkin(activity, (Spinner) view, mode, palette)' "$skin" || { echo "FAIL: Spinner controls must use skin selection tokens"; exit 1; }
for token in   'HarmonySkinTokens.HarmonyTypographyTokens.SPINNER_LABEL_SP'   'HarmonySkinTokens.HarmonySpacingTokens.SPINNER_HORIZONTAL_PADDING_DP'   'CupertinoSkinTokens.CupertinoTypographyTokens.SPINNER_LABEL_SP'   'CupertinoSkinTokens.CupertinoSpacingTokens.SPINNER_VERTICAL_PADDING_DP'; do
  grep -Fq "$token" "$activity" || { echo "FAIL: MainActivity Spinner renderer does not use shared Skin token $token"; exit 1; }
done
grep -Fq 'control.setHintTextColor(palette.secondaryText)' "$skin" || { echo "FAIL: EditText placeholder color is not skin-aware"; exit 1; }
grep -Fq 'palette.inputBorder' "$skin" || { echo "FAIL: focused/unfocused form border token is missing"; exit 1; }
grep -Fq 'INPUT_BORDER = 0xffb7cce5' "$harmony_tokens" || { echo "FAIL: Harmony form border token missing"; exit 1; }
grep -Fq 'INPUT_BORDER = 0xffc6c6cc' "$cupertino_tokens" || { echo "FAIL: Cupertino form border token missing"; exit 1; }
[[ "$(grep -Fc 'static final int INPUT_BORDER' "$harmony_tokens")" -eq 1 ]] || { echo "FAIL: Harmony INPUT_BORDER must be declared exactly once"; exit 1; }
[[ "$(grep -Fc 'static final int INPUT_BORDER' "$cupertino_tokens")" -eq 1 ]] || { echo "FAIL: Cupertino INPUT_BORDER must be declared exactly once"; exit 1; }
[[ "$(grep -Fc 'static final int INPUT_MIN_HEIGHT_DP' "$harmony_tokens")" -eq 1 ]] || { echo "FAIL: Harmony INPUT_MIN_HEIGHT_DP must be declared exactly once"; exit 1; }
[[ "$(grep -Fc 'static final int INPUT_MIN_HEIGHT_DP' "$cupertino_tokens")" -eq 1 ]] || { echo "FAIL: Cupertino INPUT_MIN_HEIGHT_DP must be declared exactly once"; exit 1; }
python3 - "$harmony_tokens" "$cupertino_tokens" <<'PY'
from collections import Counter
from pathlib import Path
import re
import sys

for filename in sys.argv[1:]:
    source = Path(filename).read_text(encoding="utf-8")
    names = re.findall(r"static\s+final\s+\w+\s+(\w+)\s*=", source)
    duplicates = [name for name, count in Counter(names).items() if count > 1]
    assert not duplicates, f"{filename}: duplicate Skin token declarations: {duplicates}"
print("PASS: Harmony and Cupertino token names are unique; duplicate Java constants cannot break compilation.")
PY
grep -Fq 'control.setMinimumHeight(Math.max(control.getMinimumHeight()' "$skin" || { echo "FAIL: native form controls lack minimum touch height"; exit 1; }

# Imported feature Activities share the same Harmony/Cupertino component renderer.
# Their helper-built cards and action buttons must carry role tags or the Skin
# adapter cannot transform those legacy pages.
for page in "$ad_main" "$ad_general" "$ad_summary" "$ad_firewall" "$shield_main" "$shield_scan" "$shield_daily" "$shield_warning" "$dia_frida" "$dia_scripts"; do
  grep -Fq 'setTag("fx-card")' "$page" || { echo "FAIL: imported feature card is not tagged for global Skin: $page"; exit 1; }
  grep -Fq 'setTag("fx-card-title")' "$page" || { echo "FAIL: imported feature card title is not tagged for global Skin: $page"; exit 1; }
  grep -Fq 'setTag("fx-card-detail")' "$page" || { echo "FAIL: imported feature card detail is not tagged for global Skin: $page"; exit 1; }
  grep -Fq 'setTag("fx-action-row")' "$page" || { echo "FAIL: imported feature actions are not tagged for global Skin: $page"; exit 1; }
done
python3 - "$harmony_renderer" "$cupertino_renderer" <<'PY'
from pathlib import Path
import sys

for path in sys.argv[1:]:
    source = Path(path).read_text(encoding="utf-8")
    assert source.count('if ("fx-card-title".equals(role)') == 1, f"{path}: duplicate/unreachable card title renderer"
    assert '("fx-card-detail".equals(role) || "fx-card-body".equals(role))' in source, f"{path}: description roles are not unified"
    assert '("fx-card".equals(role) || "fx-card-group".equals(role) || "fx-setting-card".equals(role))' in source
print("PASS: Harmony/Cupertino component renderers process card title/detail tags once.")
PY
# Shield pages use shared component roles while keeping scan severity as an explicit semantic color.
for token in 'setTag("fx-card")' 'setTag("fx-card-title")' 'setTag("fx-card-detail")' 'setTag("fx-action-row")'; do
  grep -Fq "$token" "$shield_main" || { echo "FAIL: Shield home card renderer role missing: $token"; exit 1; }
  grep -Fq "$token" "$shield_daily" || { echo "FAIL: Shield daily summary card renderer role missing: $token"; exit 1; }
  grep -Fq "$token" "$shield_warning" || { echo "FAIL: Shield warning page renderer role missing: $token"; exit 1; }
done
grep -Fq 'setTag("fx-switch-row")' "$shield_main" || { echo "FAIL: Shield switches are not routed through the active Skin"; exit 1; }
grep -Fq 'setTag("fx-card")' "$shield_scan" || { echo "FAIL: Shield scan status card is not tagged"; exit 1; }
grep -Fq 'setTag("fx-card-title")' "$shield_scan" || { echo "FAIL: Shield scan card title is not tagged"; exit 1; }
grep -Fq 'contentScan.setTag("fx-switch-row")' "$shield_scan" || { echo "FAIL: Shield content-scan switch is not Skin-aware"; exit 1; }
grep -Fq 'resultHeading.setTag("fx-section:风险结果")' "$shield_scan" || { echo "FAIL: Shield findings section title is not tagged"; exit 1; }
grep -Fq 'item.setTag(finding.severity==FxYulongScanEngine.Severity.CERTAIN?"fx-risk-certain":"fx-risk-suspect")' "$shield_scan" || { echo "FAIL: scan findings lost severity-specific card roles"; exit 1; }
grep -Fq 'riskTitle.setTag(finding.severity==FxYulongScanEngine.Severity.CERTAIN?"fx-risk-title-certain":"fx-risk-title-suspect")' "$shield_scan" || { echo "FAIL: scan findings lost severity-specific title roles"; exit 1; }
for renderer in "$harmony_renderer" "$cupertino_renderer"; do
  grep -Fq '"fx-risk-certain".equals(role)' "$renderer" || { echo "FAIL: semantic certain-risk card renderer missing: $renderer"; exit 1; }
  grep -Fq '"fx-risk-suspect".equals(role)' "$renderer" || { echo "FAIL: semantic suspect-risk card renderer missing: $renderer"; exit 1; }
  grep -Fq '"fx-risk-title-certain".equals(role)' "$renderer" || { echo "FAIL: semantic certain-risk title renderer missing: $renderer"; exit 1; }
  grep -Fq '"fx-risk-title-suspect".equals(role)' "$renderer" || { echo "FAIL: semantic suspect-risk title renderer missing: $renderer"; exit 1; }
done
for tokens_file in "$harmony_tokens" "$cupertino_tokens"; do
  grep -Fq 'RISK_CERTAIN_SURFACE' "$tokens_file" || { echo "FAIL: certain-risk surface token missing: $tokens_file"; exit 1; }
  grep -Fq 'RISK_SUSPECT_SURFACE' "$tokens_file" || { echo "FAIL: suspect-risk surface token missing: $tokens_file"; exit 1; }
  grep -Fq 'RISK_CERTAIN_TEXT' "$tokens_file" || { echo "FAIL: certain-risk text token missing: $tokens_file"; exit 1; }
  grep -Fq 'RISK_SUSPECT_TEXT' "$tokens_file" || { echo "FAIL: suspect-risk text token missing: $tokens_file"; exit 1; }
done
grep -Fq 'uninstallButton.setTextColor(0xffa32620)' "$shield_warning" || { echo "FAIL: warning page must preserve destructive-action semantics"; exit 1; }
grep -Fq 'riskDetails.addView(text(advice, 12, 0xff8a5b12, false))' "$shield_warning" || { echo "FAIL: warning advice must preserve semantic amber text"; exit 1; }

grep -Fq 'webView.setVisibility(View.VISIBLE)' "$activity" || { echo "FAIL: ClassicWebCompat WebView not mounted"; exit 1; }
grep -Fq 'navigateWebPage(webPageForBottomTab(index))' "$activity" || { echo "FAIL: ClassicWebCompat tab routing missing"; exit 1; }
grep -Fq 'FxUiMode.read(this).getStorageId()' "$activity"
grep -Fq 'FxUiMode.write(MainActivity.this' "$activity"
grep -Fq 'applyWebUiMode();' "$activity"
grep -Fq 'FxNativeSkin.watch(this, pageContent);' "$host" || { echo "FAIL: imported native screens do not receive shared Skin tokens"; exit 1; }
grep -Fq 'static void showDialog(Activity activity, Dialog dialog)' "$skin" || { echo "FAIL: shared native dialog renderer missing"; exit 1; }
grep -Fq 'import androidx.appcompat.app.AlertDialog;' "$activity" || { echo "FAIL: MainActivity must use the same AlertDialog type as the shared Skin-aware Builder"; exit 1; }
! grep -Fq 'import android.app.AlertDialog;' "$activity" || { echo "FAIL: MainActivity platform AlertDialog type is incompatible with the AppCompat Skin builder"; exit 1; }
grep -Fq 'static AlertDialog.Builder builder(Activity activity)' "$skin" || { echo "FAIL: centralized Skin-aware AlertDialog Builder missing"; exit 1; }
grep -Fq 'protected final AlertDialog.Builder fxDialogBuilder()' "$host" || { echo "FAIL: imported FX tabs need a platform AlertDialog Skin builder"; exit 1; }
grep -Fq 'FxNativeSkin.showDialog(FxNativeTabActivity.this, dialog);' "$host" || { echo "FAIL: imported FX tabs must route modal show() through shared renderer"; exit 1; }
grep -Fq 'protected final void showFxDialog(Dialog dialog)' "$host" || { echo "FAIL: imported FX tabs need the custom OnShowListener dialog display path"; exit 1; }
grep -Fq 'showFxDialog(picker);' "$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongFirewallActivity.java" || { echo "FAIL: Firewall time picker bypasses the shared modal Skin"; exit 1; }
grep -Fq 'FxNativeSkin.showDialog(activity, dialog);' "$skin" || { echo "FAIL: Skin-aware Builder does not intercept show()"; exit 1; }
grep -Fq 'static AlertDialog.Builder builder(Activity activity)' "$skin" || { echo "FAIL: Skin-aware AlertDialog Builder missing"; exit 1; }
python3 - "$activity" "$skin" <<'PY'
from pathlib import Path
import sys
activity = Path(sys.argv[1]).read_text(encoding="utf-8")
skin = Path(sys.argv[2]).read_text(encoding="utf-8")
assert "new AlertDialog.Builder(this)" not in activity
assert "new AlertDialog.Builder(MainActivity.this)" not in activity
assert "FxNativeSkin.builder(this)" in activity
assert "FxNativeSkin.builder(MainActivity.this)" in activity
assert activity.count("FxNativeSkin.builder(") >= 90, "MainActivity must route native dialogs through the shared Skin-aware Builder"
start = skin.index("static AlertDialog.Builder builder(Activity activity)")
end = skin.index("static void showDialog(Activity activity, Dialog dialog)", start)
builder = skin[start:end]
assert "if (activity == null)" in builder
assert "@Override public AlertDialog show()" in builder
assert "AlertDialog dialog = create();" in builder
assert "FxNativeSkin.showDialog(activity, dialog);" in builder
print("PASS: MainActivity native dialogs preserve Builder callbacks while all show() paths apply the active global Skin.")
PY

grep -Fq 'applyComponents(activity, decor);' "$skin" || { echo "FAIL: dialog renderer does not skin the inflated decor tree"; exit 1; }
grep -Fq 'decor.post(() ->' "$skin" || { echo "FAIL: dialog renderer does not reapply after first layout"; exit 1; }
grep -Fq 'FxNativeSkin.showDialog(this, managedDialog);' "$activity" || { echo "FAIL: Ad rule add/edit dialogs bypass the shared Skin"; exit 1; }
grep -Fq 'FxNativeSkin.showDialog(this, nativeCertificateDialog);' "$activity" || { echo "FAIL: system CA dialog bypasses the shared Skin"; exit 1; }
grep -Fq 'FxNativeSkin.showDialog(this, dialog);' "$activity" || { echo "FAIL: Hosts/wallpaper dialogs bypass the shared Skin"; exit 1; }
grep -Fq 'fxDialogBuilder()' "$ad_general" || { echo "FAIL: Ad general backup-import dialog bypasses the shared Skin"; exit 1; }
! grep -Fq 'new android.app.AlertDialog.Builder' "$ad_general" || { echo "FAIL: Ad general page still uses a platform AlertDialog builder"; exit 1; }
grep -Fq 'fxDialogBuilder()' "$shield_scan" || { echo "FAIL: Shield scan confirmation bypasses the shared Skin"; exit 1; }
! grep -Fq 'new AlertDialog.Builder' "$shield_scan" || { echo "FAIL: Shield scan page still uses a platform AlertDialog builder"; exit 1; }
grep -Fq 'fxDialogBuilder()' "$shield_rescue" || { echo "FAIL: Shield rescue confirmations bypass the shared Skin"; exit 1; }
! grep -Fq 'new AlertDialog.Builder' "$shield_rescue" || { echo "FAIL: Shield rescue page still uses a platform AlertDialog builder"; exit 1; }
for page in "$shield_blacklist" "$shield_batch_cleanup" "$shield_screen_filter" "$shield_warning" "$dia_backup"; do
  grep -Fq 'fxDialogBuilder()' "$page" || { echo "FAIL: integrated Shield/Dia Activity bypasses the shared dialog Skin: $page"; exit 1; }
  ! grep -Fq 'new AlertDialog.Builder' "$page" || { echo "FAIL: integrated Shield/Dia Activity still uses a platform AlertDialog builder: $page"; exit 1; }
done
grep -Fq 'showFxDialog(dialog)' "$shield_blacklist" || { echo "FAIL: custom Shield multi-select dialog bypasses the shared Skin"; exit 1; }
grep -Fq 'protected final AlertDialog.Builder fxDialogBuilder()' "$host" || { echo "FAIL: integrated Activity host does not expose the shared Skin-aware Builder"; exit 1; }
grep -Fq 'protected final void showFxDialog(Dialog dialog)' "$host" || { echo "FAIL: integrated Activity host does not expose the custom modal Skin path"; exit 1; }
for page in "$dia_activity_browser" "$dia_code_editor" "$dia_crash_report" "$dia_file" "$dia_inspector"; do
  grep -Fq 'fxDialogBuilder()' "$page" || { echo "FAIL: Dia Hook Activity bypasses the shared dialog Skin: $page"; exit 1; }
  ! grep -Fq 'new AlertDialog.Builder' "$page" || { echo "FAIL: Dia Hook Activity still uses a platform AlertDialog builder: $page"; exit 1; }
done
grep -Fq 'FxNativeSkin.watch(this, pageContent);' "$activity" || { echo "FAIL: MainActivity native pages do not receive shared Skin tokens"; exit 1; }
grep -Fq 'static void applyComponents(Activity activity, View content)' "$skin" || { echo "FAIL: detached dialog component Skin entry is missing"; exit 1; }
grep -Fq 'FxNativeSkin.applyComponents(this, panel);' "$activity" || { echo "FAIL: dynamic privacy dialog must use the detached component-only renderer"; exit 1; }
python3 - "$activity" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
start = source.index("private void renderNativePrivacySettingsGroup(JSONObject panelSchema, String title)")
end = source.index("private void setNativePrivacySetting(", start)
method = source[start:end]
for token in ('panel.setTag("fx-card")', 'row.setTag("fx-card-group")',
              'summary.setTag("fx-card-detail")', 'detail.setTag("fx-card-body")',
              'toggle.setTag(key)', 'toggle.setOnCheckedChangeListener'):
    assert token in method, f"privacy dialog component integration missing: {token}"
assert method.index("FxNativeSkin.applyComponents(this, panel)") < method.index("FxNativeSkin.builder(this).setTitle(title)")
assert method.index("toggle.setTag(key)") < method.index("toggle.setOnCheckedChangeListener")
print("PASS: dynamic Privacy dialog is skinned without changing its persisted key or toggle listener.")
PY
grep -Fq 'pageContent.post(() -> {' "$activity" || { echo "FAIL: MainActivity Skin pass does not run after dynamic page construction"; exit 1; }
grep -Fq 'pageContent.getParent() != null' "$activity" || { echo "FAIL: deferred Skin pass does not check that the page is still mounted"; exit 1; }
for token in \
  'HarmonySkinTokens.HarmonyColorTokens.BACKGROUND' \
  'CupertinoSkinTokens.CupertinoColorTokens.BACKGROUND' \
  'HarmonySkinTokens.HarmonyColorTokens.SURFACE' \
  'CupertinoSkinTokens.CupertinoColorTokens.SURFACE' \
  'HarmonySkinTokens.HarmonyColorTokens.PRIMARY_TEXT' \
  'CupertinoSkinTokens.CupertinoColorTokens.PRIMARY_TEXT' \
  'HarmonySkinTokens.HarmonyShapeTokens.CARD_RADIUS_DP' \
  'CupertinoSkinTokens.CupertinoShapeTokens.CARD_RADIUS_DP' \
  'HarmonySkinTokens.HarmonyColorTokens.SURFACE_VARIANT' \
  'CupertinoSkinTokens.CupertinoColorTokens.SURFACE_VARIANT'; do
  grep -Fq "$token" "$activity" || { echo "FAIL: MainActivity card/section renderer does not use shared Skin token $token"; exit 1; }
done
for token in 'case HUAWEI_HARMONY_STYLE:' 'case IOS_CUPERTINO_STYLE:' '0xfff0f3f7' '0xff17212b' 'wallpaperActive ? 0x00000000'; do
  grep -Fq "$token" "$skin" || { echo "FAIL: shared native Skin adapter missing $token"; exit 1; }
done
python3 - "$skin" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
start = source.index("private static void apply(Activity activity")
end = source.index("private static boolean isKnownPageBackground", start)
apply = source[start:end]
assert "isKnownPageBackground(rootBackground, palette, rootColor)" in apply
assert "pageContent.setBackgroundColor(rootColor)" in apply
helper = source[source.index("private static boolean isKnownPageBackground"):source.index("private static Palette palette")]
assert "if (!(background instanceof ColorDrawable)) return false;" in helper
assert "background == null" in helper
assert "color == palette.background" in helper
print("PASS: Skin adapter only rewrites known neutral ColorDrawable roots; custom GradientDrawable/selector/ripple roots remain untouched.")
PY
python3 - "$skin" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
switch = source.index("if (view instanceof Switch)")
choice = source.index("else if (view instanceof android.widget.CompoundButton)", switch)
button = source.index("else if (view instanceof Button)", choice)
assert switch < choice < button, "Switch/CompoundButton must be dispatched before generic Button"
assert "control.setThumbTintList" in source and "control.setTrackTintList" in source
assert "control.setButtonTintList" in source
print("PASS: Switch and CheckBox/RadioButton tint adapters are reachable before generic Button styling.")
PY
python3 - "$skin" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
for token in (
    "case 0xff697681:", "case 0xff536170:", "case 0xff263443:",
    "case 0xff155a9c:", "return p.accent;"
):
    assert token in source, f"five-skin text palette token missing: {token}"
# Semantic alert colors must remain untouched by the neutral text remapper.
replacement = source[source.index("private static Integer replacementText"):source.index("\n    }\n}", source.index("private static Integer replacementText"))]
for alert in ("0xff9b2c2c", "0xffa32620", "0xffa12d2d",
              "0xfffff6e8", "0xff7a4b13", "0xff79552b",
              "0xff237347", "0xff24734a", "0xff2e7d32"):
    assert alert not in replacement, f"alert/success color should not be remapped: {alert}"
print("PASS: primary, secondary and accent text tokens map across all five skins while alert colors remain semantic.")
PY

python3 - "$skin" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
start = source.index("private static void applyButtonSkin")
end = source.index("private static boolean isSemanticActionBackground", start)
button_skin = source[start:end]
assert "shouldPreserveSemanticAction(button)" in button_skin
assert button_skin.index("shouldPreserveSemanticAction(button)") < button_skin.index("BUTTON_SKINS")
semantic_guard = source[source.index("static boolean shouldPreserveSemanticAction"):source.index("private static boolean isSemanticActionBackground")]
assert "isSemanticActionColor(button.getCurrentTextColor())" in semantic_guard
assert "isSemanticActionBackground(button.getBackground())" in semantic_guard
semantic = source[source.index("private static boolean isSemanticActionColor"):source.index("private static void applySwitchSkin")]
for color in ("0xff9b2c2c", "0xffa32620", "0xffa12d2d",
              "0xfffff6e8", "0xff7a4b13", "0xff79552b",
              "0xff237347", "0xff24734a", "0xff2e7d32"):
    assert color in semantic, f"semantic action color missing from preservation guard: {color}"
print("PASS: semantic destructive/warning/success buttons bypass generic accent recoloring.")
PY

python3 - "$skin" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
transform = source[source.index("private static void transformKnownLegacyTokens"):source.index("private static void applyButtonSkin")]
assert "background instanceof ColorDrawable" in transform
assert "background instanceof GradientDrawable" in transform
assert "ColorStateList fill = ((GradientDrawable) background).getColor()" in transform
assert "if (fill != null) legacyBackgroundColor = fill.getDefaultColor()" in transform
assert "replacementBackgroundDrawable(" in transform and "legacyBackgroundColor, palette, wallpaperActive, density" in transform
helper = source[source.index("private static Drawable replacementBackgroundDrawable"):source.index("private static Integer replacementText")]
assert "case 0xfff0f3f7:" in helper and "case 0xffffffff:" in helper
assert "case 0xffe9eef3:" in helper and "case 0xffe5e5ea:" in helper
assert "roundedSurface(p.surface," in helper and "roundedSurface(p.surfaceVariant," in helper
assert "Math.max(10, p.cardCornerRadiusDp - 4) * density" in helper
assert "Math.max(8, p.cardCornerRadiusDp - 8) * density" in helper
assert "surface.setCornerRadius(radiusPx)" in helper
assert "surface.setStroke(1, strokeColor)" in helper
assert helper.index("default:") > helper.index("case 0xffe3e8ee:"), "unknown custom backgrounds must fall through untouched"
assert "return null;" in helper, "unknown/custom background tokens must remain untouched"
print("PASS: known neutral ColorDrawable and solid GradientDrawable cards receive five-skin surfaces; gradients, selectors, ripples and unknown drawables remain intact.")
PY
grep -Fq 'addOnGlobalLayoutListener' "$skin" || { echo "FAIL: dynamic native pages are not re-skinned after layout"; exit 1; }
grep -Fq 'addOnAttachStateChangeListener' "$skin" || { echo "FAIL: Skin observer is not attached to the live page root"; exit 1; }
grep -Fq 'removeOnGlobalLayoutListener(layoutListener)' "$skin" || { echo "FAIL: Skin observer is not removed when page detaches"; exit 1; }
grep -Fq 'private static final class SkinSnapshot' "$skin" || { echo "FAIL: Skin observer has no mutable per-page snapshot"; exit 1; }
grep -Fq 'private static final WeakHashMap<View, SkinSnapshot> WATCHED' "$skin" || { echo "FAIL: Skin observer deduplication is missing"; exit 1; }
grep -Fq 'existing.mode = mode' "$skin" || { echo "FAIL: repeated watch() calls do not refresh the live Skin mode"; exit 1; }
grep -Fq 'existing.wallpaperActive = wallpaperActive' "$skin" || { echo "FAIL: repeated watch() calls do not refresh the live wallpaper state"; exit 1; }
grep -Fq 'apply(activity, pageContent, snapshot.mode, snapshot.wallpaperActive)' "$skin" || { echo "FAIL: layout observer can replay stale Skin state"; exit 1; }
grep -Fq 'activity.isDestroyed()' "$skin" || { echo "FAIL: Skin observer does not stop for destroyed Activities"; exit 1; }
grep -Fq 'applyButtonSkin(activity, (Button) view, mode, palette)' "$skin" || { echo "FAIL: native buttons do not receive Skin tokens"; exit 1; }
grep -Fq 'new RippleDrawable(' "$skin" || { echo "FAIL: native buttons lack mode-aware ripple surfaces"; exit 1; }
grep -Fq 'applySwitchSkin(activity, (Switch) view, mode, palette)' "$skin" || { echo "FAIL: native switches do not receive Skin tokens"; exit 1; }
grep -Fq 'setThumbTintList(' "$skin" && grep -Fq 'setTrackTintList(' "$skin" || { echo "FAIL: native switches lack selected/off Skin colors"; exit 1; }
grep -Fq 'applyChoiceControlSkin(' "$skin" || { echo "FAIL: radio/choice controls do not receive Skin tokens"; exit 1; }
! grep -Fq 'control.setBackgroundColor(android.graphics.Color.TRANSPARENT)' "$skin" || { echo "FAIL: switch Skin pass must not erase card/row surfaces"; exit 1; }
# Run adjacent UI fixtures here as well: a Skin-only source change must not
# leave the targeted workflow with an unmapped source path, and these tests
# explicitly distinguish source-only checkout from Release-staged resources.
bash "$root/scripts/tests/fx-wallpaper-regression.sh"
sh "$root/scripts/tests/fx-native-vpn-api-regression.sh"
sh "$root/scripts/tests/fx-vpn-transparent-toggle-regression.sh"
sh "$root/scripts/tests/v1.0.0-fxhook-capture-privacy-wiring-regression.sh"
sh "$root/scripts/tests/vpncore-default-node-fallback-regression.sh"
python3 - "$harmony_tokens" "$cupertino_tokens" "$skin" <<'PY'
from collections import Counter
from pathlib import Path
import re
import sys

for name in sys.argv[1:3]:
    source = Path(name).read_text(encoding="utf-8")
    fields = re.findall(r"static final (?:int|float|long|boolean|String)\s+(\w+)\s*=", source)
    duplicates = [key for key, count in Counter(fields).items() if count > 1]
    assert not duplicates, f"{name}: duplicate Java token fields: {duplicates}"

skin = Path(sys.argv[3]).read_text(encoding="utf-8")
assert "int inputBorder, int cardCornerRadiusDp, float buttonTextSizeSp" in skin
assert "this.cardCornerRadiusDp = cardCornerRadiusDp;" in skin
assert "static boolean shouldPreserveSemanticAction(Button button)" in skin
print("PASS: Harmony/Cupertino token declarations are unique and native Skin palette constructor fields are wired.")
PY
echo "PASS: five global UI modes share persistence, shell rendering, and live tokens on MainActivity and imported pages."
