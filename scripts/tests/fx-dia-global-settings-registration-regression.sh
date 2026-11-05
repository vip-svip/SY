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
assert "Hook · 工具与运行设置" in global_page, "Dia global settings must be presented as an FX Hook page"
assert "setContentViewWithNativeTabs(root, 4);" in global_page, "Dia global settings must select the Hook tab, not Settings"
expand_page = expand_path.read_text(encoding="utf-8")
manifest = ET.parse(manifest_path).getroot()
ns = "{http://schemas.android.com/apk/res/android}"

route_start = main.index('addNativeActionCard("Hook 工具与运行设置"')
route_end = main.index('addNativeActionCard("系统扩展"', route_start)
route = main[route_start:route_end]
assert "FxDiaGlobalSettingsActivity.class" in route, "Dia global settings card does not route to the native page"
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
assert 'addStoredSwitch("显示 LSPosed 激活状态提示"' in global_page, "active_tip must control the real FX LSPosed service-status banner"
assert 'addUnavailableSwitch("显示原生模块激活提示"' in global_page, "native_active_tip must not be exposed as an active switch without an original consumer"
assert '"active_tip", true' in global_page and '"native_active_tip", true' in global_page, "original default-on values must be preserved"
assert "完整 Smali 检索未发现该键的读取/消费逻辑" in global_page, "native_active_tip must disclose that original APK has no consumer"
compact_main = "".join(main.split())
assert 'getSharedPreferences("digXposed",MODE_PRIVATE).getBoolean("active_tip",true)' in compact_main, "Dia activation banner must honor the migrated active_tip preference (whitespace-insensitive)"
assert "FxLsposedScopeBridge.isConnected()" in main, "Dia activation banner must read the real libXposed service connection"
assert "if (hookHubVisible && hookHubLsposedState != null)" in main, "returning from Dia settings must refresh the existing activation banner"
assert main.count("refreshHookHubLsposedStatus(hookHubLsposedState)") >= 2, "active_tip changes and initial Hook hub render must update the existing banner without creating a duplicate"
assert "不代表 FX Hook 已注入" in main and "服务连接状态不等同于目标进程注入状态" in main, "banner must not confuse service connectivity with verified target process injection"
assert "addUnavailableAction(\"设置语言\"" in global_page, "language must stay unavailable until unified locale resources/lifecycle are migrated"
assert "showLanguagePicker" not in global_page and "addStoredSwitch(\"显示 LSPosed 激活状态提示\"" in global_page, "only a preference with a real native consumer may be enabled"
assert "EMessage" not in global_page, "do not invent an EMessage event-bus dependency for active_tip"
assert 'addStoredSwitch("自动申请 LSPosed 作用域"' in global_page, "migrated automatic scope request must remain an opt-in preference"
assert "通过官方 libXposed 服务向 LSPosed Manager 提交申请" in global_page, "scope request must disclose the official Manager approval route"
assert "Manager 仍须批准" in global_page, "scope request must disclose that Manager approval remains required"
assert "dialog.box.lsp.LScope" not in global_page, "FX must not preserve the legacy Dia Binder package as a fake migrated dependency"
assert 'addAction("重启 LSPosed 框架服务"' in global_page, "Dia framework restart must be a real action with an accurate service-level label"
assert "FRAMEWORK_RESTART_COMMAND" in global_page and '"stop;' in global_page, "original stop/start framework restart command is missing"
assert "RootAccess.execute(" in global_page, "framework restart must use the KernelSU Root broker"
assert "确认重启框架服务" in global_page and "正在运行的应用" in global_page, "framework restart must require explicit confirmation and disclose disruption"
assert "FX_STOP_RC=%s" in global_page and "FX_START_RC=%s" in global_page, "stop and start return codes must be checked independently"
assert r'\"$fx_stop_rc\" \"$fx_start_rc\"' in global_page, "framework command shell variables must remain separately quoted in the Java string literal"
assert r'[ \"$fx_stop_rc\" -eq 0 ] && [ \"$fx_start_rc\" -eq 0 ]' in global_page, "framework restart must require both stop and start to return zero"
assert "setTitle(" in global_page and "Root shell 已返回 stop=0、start=0" in global_page, "framework restart must not claim success without both shell results"
assert "FRAMEWORK_RESTART_EXECUTOR" in global_page and "RejectedExecutionException" in global_page, "restart command must run off-main and handle worker saturation"
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
assert "不会绕过PackageInstaller" in expand_page, "unknown-source management must preserve Android PackageInstaller enforcement"
assert "getAllSessions()" in expand_page and "FxDiaInstallerRestartPolicy.isSafeToRestart" in expand_page, "Package Installer restart must check active, committed and staged sessions"
assert "确认重启" in expand_page and "FX 已取消强制停止" in expand_page, "Package Installer restart must require confirmation and recheck sessions before force-stop"
assert "REQUEST_INSTALL_PACKAGES" in expand_page and "Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES" in expand_page, "unknown source must route to Android per-app settings"
assert "Settings.ACTION_APPLICATION_DETAILS_SETTINGS" in expand_page, "Package Installer action must open real Android app info"
assert "remain visible but disabled" not in expand_page.lower(), "SystemExpand documentation must not claim migrated install-source actions are disabled"
assert "逐安装来源授权和安装器应用信息入口已迁入" in expand_page, "SystemExpand introduction must match the actual migrated install-source and installer actions"
assert "RootAccess.execute" not in expand_page and "pm uninstall" not in expand_page, "SystemExpand must not issue destructive or unchecked Root commands"

print("PASS: Dia global preferences, private navigation, backup route and honest SystemExpand feature boundaries")
PY
