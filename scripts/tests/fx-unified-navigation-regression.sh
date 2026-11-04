#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
activity="$root/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
shell="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt"
host="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeTabActivity.java"
test -s "$activity" && test -s "$shell" && test -s "$host"
python3 - "$activity" "$shell" "$host" <<'PY'
from pathlib import Path
import sys
activity = Path(sys.argv[1]).read_text(encoding="utf-8")
shell = Path(sys.argv[2]).read_text(encoding="utf-8")
host = Path(sys.argv[3]).read_text(encoding="utf-8")
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
print("PASS: Settings has no migration-app hub; native six-tab navigation uses Ad; shared Activity host preserves all five skins.")
PY
