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
    assert "console" in global_page, "original XML console preference is missing from the source inventory"
assert "SettingsActivity removes" in global_page, "hidden original console preference visibility behavior is undocumented"
assert "addStoredSwitch(\"显示控制台\"" not in global_page, "original SettingsActivity-hidden console preference must not be newly exposed"
    "language_setting", "fast_restart_system", "app_update",
    "data_backup", "system_expand", "internal_community",
):
    # Preference keys are retained in comments or implementation identifiers
    # so the migrated screen can be audited against Dia's original XML.
    assert key in global_page, f"Dia original preference key missing: {key}"

assert "MODE_PRIVATE" in global_page, "legacy world-readable preferences must not be recreated"
assert "FxDiaBackupActivity.class" in global_page, "data backup must use the migrated encrypted backup page"
assert "FxDiaSystemExpandActivity.class" in global_page, "system expansion must have an independent child page"
assert "原版 EMessage 提示事件总线尚未迁移" in global_page, "activation-tip consumer status must be disclosed"
assert "dialog.box.lsp.LScope" in global_page, "LSPosed scope sync limitation must be disclosed"
assert "不会执行重启" in global_page, "framework restart must not silently trigger a device reboot"
assert "CheckUpdateActivity" not in global_page, "old standalone Dia updater must not be launched"

assert "FxDiaWifiProxyActivity.class" in expand_page, "migrated system HTTP proxy must remain reachable"
assert "ro_debuggable" in expand_page, "original ro.debuggable option must remain listed"
assert "restart_package_installer" in expand_page, "original package installer option must remain listed"
assert "不会更改系统属性" in expand_page, "unmigrated system property control must be disabled transparently"
assert "不会强制停止或重启系统 Package Installer" in expand_page, "package installer restart must not be faked"
assert "RootAccess.execute" not in expand_page, "unmigrated system expansion must not issue unchecked Root commands"

print("PASS: Dia global preferences, private navigation, backup route and honest SystemExpand feature boundaries")
PY
