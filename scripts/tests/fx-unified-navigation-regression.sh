#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
activity="$root/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
shell="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt"
host="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeTabActivity.java"
dia_browser="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaActivityBrowserActivity.java"
dia_backup="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaBackupActivity.java"
dia_editor="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaCodeEditorActivity.java"
dia_crash="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaCrashReportActivity.java"
dia_dex="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaDexBrowserActivity.java"
dia_frida="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java"
dia_scripts="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaScriptLibraryActivity.java"
dia_gps="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaGpsPickerActivity.java"
dia_inspector="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaInspectorActivity.java"
dia_wifi="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaWifiProxyActivity.java"
dia_file="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFileActivity.java"
dia_monitor="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaMonitorEventsActivity.java"
dia_session="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaSessionLogActivity.java"
dia_signature="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaSignatureActivity.java"
dia_system="$root/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaSystemExpandActivity.java"
test -s "$activity" && test -s "$shell" && test -s "$host" && test -s "$dia_browser" && test -s "$dia_backup" && test -s "$dia_editor" && test -s "$dia_crash" && test -s "$dia_dex" && test -s "$dia_frida" && test -s "$dia_scripts" && test -s "$dia_gps" && test -s "$dia_inspector" && test -s "$dia_wifi" && test -s "$dia_file" && test -s "$dia_monitor" && test -s "$dia_session" && test -s "$dia_signature" && test -s "$dia_system"
python3 - "$activity" "$shell" "$host" "$dia_browser" "$dia_backup" "$dia_editor" "$dia_crash" "$dia_dex" "$dia_frida" "$dia_scripts" "$dia_gps" "$dia_inspector" "$dia_wifi" "$dia_file" "$dia_monitor" "$dia_session" "$dia_signature" "$dia_system" "$root" <<'PY'
from pathlib import Path
import sys
activity = Path(sys.argv[1]).read_text(encoding="utf-8")
shell = Path(sys.argv[2]).read_text(encoding="utf-8")
host = Path(sys.argv[3]).read_text(encoding="utf-8")
root = Path(sys.argv[19])
def source(relative):
    return (root / relative).read_text(encoding="utf-8")
dia_browser = Path(sys.argv[4]).read_text(encoding="utf-8")
dia_backup = Path(sys.argv[5]).read_text(encoding="utf-8")
dia_editor = Path(sys.argv[6]).read_text(encoding="utf-8")
dia_crash = Path(sys.argv[7]).read_text(encoding="utf-8")
dia_dex = Path(sys.argv[8]).read_text(encoding="utf-8")
dia_frida = Path(sys.argv[9]).read_text(encoding="utf-8")
dia_scripts = Path(sys.argv[10]).read_text(encoding="utf-8")
dia_gps = Path(sys.argv[11]).read_text(encoding="utf-8")
dia_inspector = Path(sys.argv[12]).read_text(encoding="utf-8")
dia_wifi = Path(sys.argv[13]).read_text(encoding="utf-8")
dia_file = Path(sys.argv[14]).read_text(encoding="utf-8")
dia_monitor = Path(sys.argv[15]).read_text(encoding="utf-8")
dia_session = Path(sys.argv[16]).read_text(encoding="utf-8")
dia_signature = Path(sys.argv[17]).read_text(encoding="utf-8")
dia_system = Path(sys.argv[18]).read_text(encoding="utf-8")
dia_json = source("adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaJsonActivity.java")
settings_start = activity.index("    private void showSettings()")
settings_end = activity.index("    private void showNativeWallpaperDialog()", settings_start)
settings = activity[settings_start:settings_end]
for forbidden in ('section("迁移应用")', 'Dia 23.11', '游龙广告插件 7.0.1', '游龙安全护盾 9.9.60'):
    assert forbidden not in settings, f"obsolete source-app entry remains in Settings: {forbidden}"
assert "Ad/Hosts" not in settings and "Ad / Hosts" not in settings
for obsolete_symbol in ("migrationSuite", "migrationCategory", "migrationPage",
                       "migrationLevel", "migrationChildActive", "showImportedSuite",
                       "importedSuiteTitle", "restoreMigrationNavigation"):
    assert obsolete_symbol not in activity, f"legacy migration hub code remains: {obsolete_symbol}"
assert 'case 1: return "pageAd";' in activity, "Ad must be the canonical second-tab WebUI route"
assert 'case "pageAd": tab = "ad"; break;' in activity
assert 'case "pageHosts": tab = "ad"; break;' in activity, "pageHosts is only a compatibility alias"
assert "if(id==='pageHosts')id='pageAd';" in activity, "legacy DOM ID must normalize to Ad"
assert 'var navTab=\'" + tab + "\';' in activity
ad_start = activity.index("    private void buildNativeHostsPage()")
ad_end = activity.index("    private void refreshHostsStatus(", ad_start)
ad_page = activity[ad_start:ad_end]
for feature in ("FxYulongAdActivity.class", "FxYulongAdGeneralActivity.class",
                "FxYulongAdSummaryActivity.class", "FxYulongDnsActivity.class",
                "FxYulongAppStatsActivity.class", "FxYulongFirewallActivity.class",
                "FxYulongAppWhitelistActivity.class"):
    assert feature in ad_page, f"migrated Ad feature is not reachable from Ad tab: {feature}"
assert "游龙广告插件" not in ad_page, "Ad home still exposes a source-app identity"
assert "不会启动来源 APK 或第二套过滤服务" in ad_page, "Ad home must clarify unified FX service ownership"
# Per-app VPN routing belongs to VPN (not Ad or Settings) and is directly reachable.
vpn_start = activity.index("    private void renderNativePage(int index)")
vpn_end = activity.index("            case 1:", vpn_start)
vpn_home = activity[vpn_start:vpn_end]
assert 'nativeAction("管理分应用 VPN 路由", this::showNativeVpnAppManager)' in vpn_home
vpn_manager_start = activity.index("    private void showNativeVpnAppManager()")
vpn_manager_end = activity.index("    private void addNativeSettingsCategory(", vpn_manager_start)
vpn_manager = activity[vpn_manager_start:vpn_manager_end]
for token in ('nativeVpnAppManagerVisible = true', 'selectedBottomTab = 0',
              'lastWebTabIndex = 0', 'base("VPN · 分应用路由")',
              'nativeAction("返回 VPN 控制中心", this::showDashboard)'):
    assert token in vpn_manager, f"VPN per-app routing page missing {token}"
assert 'settingsUiVisible = true' not in vpn_manager, "VPN app routing must not masquerade as Settings"
assert 'fx_native_vpn_app_manager_visible' in activity, "VPN app routing recreation state is not saved/restored"
assert 'if (nativeVpnAppManagerVisible) { showWebDashboard(); return; }' in activity, "Back must return to VPN home"
assert 'nativeVpnAppManagerVisible = false;' in activity, "Top-tab switch must leave VPN app-routing subpage"

# Imported Ad activities are internal screens of the Ad destination; they must
# not retain the source plugin identity or send users back to an external hub.
ad_pages = {
    "FxYulongAdActivity.java": ("Ad · 广告过滤控制中心", "返回 Ad", "setContentViewWithNativeTabs(root, 1)"),
    "FxYulongAdGeneralActivity.java": ("Ad · 通用设置与备份恢复", "返回 Ad", "setContentViewWithNativeTabs(root, 1)"),
    "FxYulongAdSummaryActivity.java": ("Ad · 本机防护总结", "返回 Ad", "setContentViewWithNativeTabs(root, 1)"),
    "FxYulongAppStatsActivity.java": ("Ad · 应用统计", "返回 Ad", "setContentViewWithNativeTabs(root, 1)"),
    "FxYulongAppWhitelistActivity.java": ("Ad · 应用白名单", "返回 Ad", "setContentViewWithNativeTabs(root, 1)"),
    "FxYulongDnsActivity.java": ("DNS 查询日志", "返回 Ad", "setContentViewWithNativeTabs(root, 1)"),
    "FxYulongFirewallActivity.java": ("suitePage", "返回 Ad", "setContentViewWithNativeTabs(root, 1)"),
}
for filename, tokens in ad_pages.items():
    page = source("adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/" + filename)
    for token in tokens:
        assert token in page, f"{filename} is not integrated as an Ad subpage: {token}"
    assert "游龙广告插件" not in page, f"{filename} still exposes the source app identity"

dia_json = source("adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaJsonActivity.java")
for token in ("‹ 返回 Hook", "Hook · JSON 操作", "FX Hook JSON", "fx-hook-json.json", "setContentViewWithNativeTabs(root, 4)"):
    assert token in dia_json, f"JSON editor is not integrated as a Hook tool: {token}"
assert "FX Dia JSON" not in dia_json and "Dia ·" not in dia_json
assert "FX Hook JSON" in dia_json and "fx-hook-json.json" in dia_json
assert "setContentViewWithNativeTabs(root, 4)" in dia_json
assert "HUAWEI HarmonyStyle" in settings and "iOS CupertinoStyle" in settings
assert "逐页组件适配仍在继续" in settings
restore_start = activity.index("        if (restoreHookScreen)")
restore_end = activity.index("        handleNativeTabIntent(getIntent());", restore_start)
restore = activity[restore_start:restore_end]
assert "showSettings();" in restore
assert "restoreMigrationNavigation();" not in restore
assert 'listOf("VPN", "Ad", "隐私", "脚本", "Hook", "设置")' in shell
assert "Ad/Hosts" not in shell and "Ad / Hosts" not in shell
assert "FxUiMode.read(this).getStorageId()" in host

# Source functions must be reachable inside the correct FX business tab; imported
# Activity pages are implementation details, not separate source-app navigation.
shield = source("adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongShieldActivity.java")
dia_settings = source("adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaGlobalSettingsActivity.java")
ad_main = source("adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java")
ad_general = source("adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdGeneralActivity.java")
ad_summary = source("adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdSummaryActivity.java")
ad_dns = source("adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongDnsActivity.java")
ad_firewall = source("adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongFirewallActivity.java")
ad_whitelist = source("adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAppWhitelistActivity.java")
dia_dex = source("adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaDexBrowserActivity.java")
assert 'FxYulongShieldActivity.class' in activity[activity.index("private void buildNativePrivacyPage()"):activity.index("private void refreshNativePrivacyStatus(")]
assert 'section("安全防护中心")' in activity
assert 'section("Hook 工具与调试")' in activity
hook_hub = activity[activity.index("private void showHookHub()"):activity.index("private void refreshHookHubAuthorizationStates()")]
for feature in ("FxDiaFridaActivity.class", "FxDiaDexBrowserActivity.class",
                "FxDiaMonitorEventsActivity.class", "FxDiaActivityBrowserActivity.class",
                "FxDiaFileActivity.class", "FxDiaJsonActivity.class",
                "FxDiaInspectorActivity.class", "FxDiaSignatureActivity.class",
                "FxDiaCrashReportActivity.class", "FxDiaSystemExpandActivity.class",
                "FxDiaGlobalSettingsActivity.class"):
    assert feature in hook_hub, f"Hook tab cannot reach {feature}"
settings_start = activity.index("private void showSettings()")
settings_end = activity.index("private void showNativeWallpaperDialog()", settings_start)
assert 'section("备份与恢复")' in activity[settings_start:settings_end]
assert 'FxDiaBackupActivity.class' in activity[settings_start:settings_end]
script_start = activity.index("private void buildNativeScriptPage()")
script_end = activity.index("private void ", script_start+20)
assert 'FxDiaScriptLibraryActivity.class' in activity[script_start:script_end]
assert "FxDiaScriptLibraryActivity.class" not in hook_hub
assert "FxDiaBackupActivity.class" not in hook_hub
assert 'txt("Ad · 广告过滤控制中心"' in ad_main and 'btn("‹ 返回 Ad"' in ad_main
assert '游龙广告插件 7.0.1' not in ad_main
assert 'text("Ad · 通用设置与备份恢复"' in ad_general
assert '游龙广告插件 7.0.1' not in ad_general and '自己的四级页面' not in ad_general
assert 'text("Ad · 本机防护总结"' in ad_summary and '游龙广告插件' not in ad_summary
for source_text in (ad_main, ad_general, ad_summary, ad_dns, ad_firewall, ad_whitelist):
    assert "游龙广告插件" not in source_text and "游龙广告过滤" not in source_text, "Ad page still exposes legacy source branding"
assert 'FX Ad · DNS 查询日志' in ad_dns
assert 'FX Ad · ' in ad_firewall
assert 'Ad · 应用白名单' in ad_whitelist
assert "Dia 23.11 随附的 Android Framework DEX" not in dia_dex
assert "此操作复刻 Dia 23.11" not in dia_settings
assert 'text("隐私 · 安全防护中心"' in shield
assert 'action("‹ 返回隐私"' in shield
assert 'setContentViewWithNativeTabs(root, 2);' in shield
assert 'text("Hook · 工具与运行设置"' in dia_settings
assert 'setContentViewWithNativeTabs(root, 4);' in dia_settings
assert '关于 Dia 23.11' not in dia_settings and 'Dia · 全局设置' not in dia_settings

shield_pages = (
    "FxYulongShieldActivity", "FxYulongScreenFilterActivity", "FxYulongDailySummaryActivity",
    "FxYulongVirusDatabaseActivity", "FxYulongScanActivity", "FxYulongIntegrityActivity",
    "FxYulongRescueActivity", "FxYulongWarningActivity", "FxYulongBatchCleanupActivity",
    "WhitelistActivity", "WhitelistPickerActivity", "BlacklistActivity"
)
for page in shield_pages:
    path = root / "adhook/app/src/main/java/de/privacyguard/adhook/imported/shield" / f"{page}.java"
    page_text = path.read_text(encoding="utf-8")
    assert "setContentViewWithNativeTabs(root, 2);" in page_text, f"{page} must highlight Privacy tab"

dia_hook_pages = (
    "FxDiaActivityBrowserActivity", "FxDiaCodeEditorActivity", "FxDiaCrashReportActivity",
    "FxDiaDexBrowserActivity", "FxDiaFileActivity", "FxDiaFridaActivity",
    "FxDiaGlobalSettingsActivity", "FxDiaGpsPickerActivity", "FxDiaInspectorActivity",
    "FxDiaJsonActivity", "FxDiaMonitorEventsActivity", "FxDiaSessionLogActivity",
    "FxDiaSignatureActivity", "FxDiaSystemExpandActivity"
)
for page in dia_hook_pages:
    path = root / "adhook/app/src/main/java/de/privacyguard/adhook/imported/dia" / f"{page}.java"
    page_text = path.read_text(encoding="utf-8")
    assert "setContentViewWithNativeTabs(root, 4);" in page_text, f"{page} must highlight Hook tab"
script_library = source("adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaScriptLibraryActivity.java")
assert "setContentViewWithNativeTabs(root, 3);" in script_library, "JS script library belongs to Script tab"
assert "setContentViewWithNativeTabs(root, 5);" in dia_backup, "unified data backup belongs to Settings"
assert "setContentViewWithNativeTabs(root, 0);" in dia_wifi, "system HTTP proxy belongs to VPN"
assert '"huawei".equals(mode)' not in host and '"ios".equals(mode)' not in host

# Dia-derived user-facing tools are presented as FX Hook or FX Settings pages.
for token in ('‹ 返回 Hook', 'Hook · Activity 入口与禁用', 'setContentViewWithNativeTabs(root, 4)'):
    assert token in dia_browser, f"Activity browser is not integrated into Hook: {token}"
for token in ('‹ 返回设置', '设置 · 数据备份与恢复', 'setContentViewWithNativeTabs(root, 5)'):
    assert token in dia_backup, f"unified data backup is not integrated into Settings: {token}"
assert 'Dia · JavaScript 脚本编辑器' not in dia_editor and 'Dia · Java 代码编辑器' not in dia_editor
assert 'Hook · JavaScript 规则编辑器' in dia_editor and 'Hook · Java 代码编辑器' in dia_editor
assert 'setContentViewWithNativeTabs(root, 4)' in dia_editor
for source, tokens, page in (
    (dia_crash, ('‹ 返回 Hook', 'Hook · 崩溃报告', 'setContentViewWithNativeTabs(root, 4)'), 'crash report'),
    (dia_dex, ('‹ 返回 Hook', 'Hook · DEX 查找与解析', 'setContentViewWithNativeTabs(root, 4)'), 'DEX browser')
):
    for token in tokens:
        assert token in source, f"{page} is not integrated into Hook: {token}"
for token in ('‹ 返回 Hook', 'Hook · ', 'setContentViewWithNativeTabs(root, 4)'):
    assert token in dia_frida, f"Frida runtime is not integrated into Hook: {token}"
assert 'Dia 23.11 ·' not in dia_frida
for token in ('‹ 返回脚本', '脚本 · Frida JavaScript 脚本库', 'setContentViewWithNativeTabs(root, 3)'):
    assert token in dia_scripts, f"Frida script library is not integrated into Script: {token}"
for token in ('‹ 返回 Hook', 'Hook · GPS 地图选点', 'setContentViewWithNativeTabs(root, 4)'):
    assert token in dia_gps, f"GPS picker is not integrated into Hook: {token}"
for token in ('‹ 返回 Hook', 'Hook · 内存快照', 'Hook · 数据库监控', 'setContentViewWithNativeTabs(root, 4)'):
    assert token in dia_inspector, f"inspector tools are not integrated into Hook: {token}"
for token in ('‹ 返回 VPN', 'VPN · 系统 HTTP 代理', 'setContentViewWithNativeTabs(root, 0)'):
    assert token in dia_wifi, f"system proxy editor is not integrated into VPN: {token}"
for source, tokens, page in (
    (dia_file, ('‹ 返回 Hook', 'Hook · 文件与 so 库', 'setContentViewWithNativeTabs(root, 4)'), 'file and ELF page'),
    (dia_monitor, ('‹ 返回 Hook', 'Hook · 结构化监控事件', 'setContentViewWithNativeTabs(root, 4)'), 'monitor events'),
    (dia_session, ('‹ 返回 Hook', 'Hook · Frida 运行日志', 'setContentViewWithNativeTabs(root, 4)'), 'Frida session log'),
    (dia_signature, ('‹ 返回 Hook', 'Hook · APK 签名信息', 'setContentViewWithNativeTabs(root, 4)'), 'APK signature info'),
    (dia_system, ('‹ 返回 Hook', 'Hook · 系统扩展', 'setContentViewWithNativeTabs(root, 4)'), 'system extensions')
):
    for token in tokens:
        assert token in source, f"{page} is not integrated into Hook: {token}"
print("PASS: Settings has no migration-app hub; six primary tabs remain unified; wallpaper/five skins shared; Dia tools consistently route into FX Hook/Script/VPN/Settings.")
PY
