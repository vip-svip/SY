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
test -s "$activity" && test -s "$shell" && test -s "$host" && test -s "$dia_browser" && test -s "$dia_backup" && test -s "$dia_editor" && test -s "$dia_crash" && test -s "$dia_dex"
python3 - "$activity" "$shell" "$host" "$dia_browser" "$dia_backup" "$dia_editor" "$dia_crash" "$dia_dex" <<'PY'
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
print("PASS: Settings has no migration-app hub; native six-tab navigation uses Ad; shared Activity host preserves all five skins; Dia-derived tools route into FX Hook/Settings.")
PY
