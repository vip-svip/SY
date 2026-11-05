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
test -s "$activity" && test -s "$shell" && test -s "$host" && test -s "$dia_browser" && test -s "$dia_backup" && test -s "$dia_editor" && test -s "$dia_crash" && test -s "$dia_dex" && test -s "$dia_frida" && test -s "$dia_scripts" && test -s "$dia_gps" && test -s "$dia_inspector" && test -s "$dia_wifi"
python3 - "$activity" "$shell" "$host" "$dia_browser" "$dia_backup" "$dia_editor" "$dia_crash" "$dia_dex" "$dia_frida" "$dia_scripts" "$dia_gps" "$dia_inspector" "$dia_wifi" <<'PY'
from pathlib import Path
import sys
activity = Path(sys.argv[1]).read_text(encoding="utf-8")
shell = Path(sys.argv[2]).read_text(encoding="utf-8")
host = Path(sys.argv[3]).read_text(encoding="utf-8")
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
settings_start = activity.index("    private void showSettings()")
settings_end = activity.index("    private String importedSuiteTitle(", settings_start)
settings = activity[settings_start:settings_end]
for forbidden in ('section("迁移应用")', 'Dia 23.11', '游龙广告插件 7.0.1', '游龙安全护盾 9.9.60'):
    assert forbidden not in settings, f"obsolete source-app entry remains in Settings: {forbidden}"
assert "Ad/Hosts" not in settings and "Ad / Hosts" not in settings
ad_start = activity.index("    private void buildNativeHostsPage()")
ad_end = activity.index("    private void refreshHostsStatus(", ad_start)
ad_page = activity[ad_start:ad_end]
for feature in ("FxYulongAdActivity.class", "FxYulongAdGeneralActivity.class",
                "FxYulongAdSummaryActivity.class", "FxYulongFirewallActivity.class",
                "FxYulongAppWhitelistActivity.class"):
    assert feature in ad_page, f"migrated Ad feature is not reachable from Ad tab: {feature}"
assert "HUAWEI HarmonyStyle" in settings and "iOS CupertinoStyle" in settings
assert "逐页组件适配仍在继续" in settings
restore_start = activity.index("        if (restoreHookScreen)")
restore_end = activity.index("        handleImportedNativeTabIntent(getIntent());", restore_start)
restore = activity[restore_start:restore_end]
assert "showSettings();" in restore
assert "restoreMigrationNavigation();" not in restore
assert 'listOf("VPN", "Ad", "隐私", "脚本", "Hook", "设置")' in shell
assert "Ad/Hosts" not in shell and "Ad / Hosts" not in shell
assert "FxUiMode.read(this).getStorageId()" in host
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
print("PASS: Settings has no migration-app hub; six primary tabs remain unified; wallpaper and five skins are shared; migrated Dia tools route into FX Hook/Script/VPN/Settings.")
PY
