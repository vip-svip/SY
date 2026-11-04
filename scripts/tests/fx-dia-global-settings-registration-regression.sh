#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
APP="$ROOT/adhook/app/src/main"
MAIN="$APP/java/de/privacyguard/adhook/MainActivity.java"
MANIFEST="$APP/AndroidManifest.xml"
GLOBAL="$APP/java/de/privacyguard/adhook/imported/dia/FxDiaGlobalSettingsActivity.java"
EXPAND="$APP/java/de/privacyguard/adhook/imported/dia/FxDiaSystemExpandActivity.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for file in "$MAIN" "$MANIFEST" "$GLOBAL" "$EXPAND"; do
  [ -s "$file" ] || fail "missing Dia global settings migration source: $file"
done
python3 - "$MAIN" "$MANIFEST" "$GLOBAL" "$EXPAND" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

main_path, manifest_path, global_path, expand_path = map(Path, sys.argv[1:])
main = main_path.read_text(encoding="utf-8")
global_page = global_path.read_text(encoding="utf-8")
expand_page = expand_path.read_text(encoding="utf-8")
manifest = ET.parse(manifest_path).getroot()
ns = "{http://schemas.android.com/apk/res/android}"

route = main.split('case "全局设置":', 1)[1].split("case ", 1)[0]
assert "FxDiaGlobalSettingsActivity.class" in route, "Dia global settings does not route to the native page"
assert "showImportedSuitePendingPage" not in route, "Dia global settings still points to the pending placeholder"

activities = {
    node.attrib.get(ns + "name"): node
    for node in manifest.findall("./application/activity")
}
for name in (
    ".imported.dia.FxDiaGlobalSettingsActivity",
    ".imported.dia.FxDiaSystemExpandActivity",
):
    assert name in activities, f"Manifest is missing {name}"
    assert activities[name].attrib.get(ns + "exported") == "false", f"{name} must remain private"

for key in (
    "digXposed", "active_tip", "native_active_tip", "lsp_sync",
    "language_setting", "fast_restart_system", "app_update",
    "data_backup", "system_expand", "internal_community",
):
    # Preference keys are retained in comments or implementation identifiers
    # so the migrated screen can be audited against Dia's original XML.
    assert key in global_page, f"Dia original preference key missing: {key}"

assert "console" in global_page, "original XML console preference is missing from the source inventory"
assert "SettingsActivity removes" in global_page, "hidden original console preference visibility behavior is undocumented"
assert 'addStoredSwitch("显示控制台"' not in global_page, "original SettingsActivity-hidden console preference must not be newly exposed"

assert "MODE_PRIVATE" in global_page, "legacy world-readable preferences must not be recreated"
assert "FxDiaBackupActivity.class" in global_page, "data backup must use the migrated encrypted backup page"
assert "FxDiaSystemExpandActivity.class" in global_page, "system expansion must have an independent child page"
assert 'addUnavailableSwitch("显示 Xposed 激活提示"' in global_page, "active_tip must remain disabled until its Dia home warning consumer is migrated"
assert 'addUnavailableSwitch("显示原生模块激活提示"' in global_page, "native_active_tip must not be exposed as an active switch without a consumer"
assert '"active_tip", true' in global_page and '"native_active_tip", true' in global_page, "original default-on values must be preserved in read-only rows"
assert "Dia 主界面的 activeVersionName() 检查和提示横幅" in global_page, "active_tip limitation must identify the original runtime dependency"
assert "完整 Smali 检索未发现该键的读取/消费逻辑" in global_page, "native_active_tip must disclose that original APK has no consumer"
assert "addUnavailableAction(\"设置语言\"" in global_page, "language must stay unavailable until unified locale resources/lifecycle are migrated"
assert "showLanguagePicker" not in global_page and "addStoredSwitch" not in global_page, "no saved-only preference control may masquerade as an operational setting"
assert "EMessage" not in global_page, "do not invent an EMessage event-bus dependency for active_tip"
assert "dialog.box.lsp.LScope" in global_page, "LSPosed scope sync limitation must be disclosed"
assert "不会执行重启" in global_page, "framework restart must not silently trigger a device reboot"
assert "CheckUpdateActivity" not in global_page, "old standalone Dia updater must not be launched"

assert "FxDiaWifiProxyActivity.class" in expand_page, "migrated system HTTP proxy must remain reachable"
assert "ro_debuggable" in expand_page, "original ro.debuggable option must remain listed"
assert "restart_package_installer" in expand_page, "original package installer option must remain listed"
assert "不向 Android framework/System UI 注入此类全局钩子" in expand_page, "ro_debuggable must disclose the missing framework-wide runtime scope"
assert "Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS" in expand_page, "debug settings must open Android developer options"
assert "REQUEST_INSTALL_PACKAGES" in expand_page, "unknown-source management must enumerate actual install-source callers"
assert "PackageManager.GET_PERMISSIONS" in expand_page, "install-source discovery must read declared package permissions"
assert "Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES" in expand_page, "selected source app must open Android's per-app install permission page"
assert "PackageManager.MATCH_DEFAULT_ONLY" in expand_page and "Settings.ACTION_APPLICATION_DETAILS_SETTINGS" in expand_page, "Package Installer management must open its real app-info page"
assert "worker.shutdownNow()" in expand_page and "RejectedExecutionException" in expand_page, "install-source inventory worker must be bounded and lifecycle-safe"
assert "不会绕过PackageInstaller" in expand_page and "不会强制停止或重启" in expand_page, "system install security and active installer sessions must remain protected"
assert "RootAccess.execute" not in expand_page and "pm uninstall" not in expand_page, "SystemExpand must not issue destructive or unchecked Root commands"

print("PASS: Dia global preferences, private navigation, backup route and honest SystemExpand feature boundaries")
PY
