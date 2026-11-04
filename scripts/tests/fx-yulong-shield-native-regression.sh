#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="$ROOT/adhook/app/src/main"
JAVA="$APP/java/de/privacyguard/adhook"
SHIELD="$JAVA/imported/shield"

python3 - "$APP/AndroidManifest.xml" "$JAVA/MainActivity.java" "$SHIELD" "$ROOT/fx-patches/merge_hook_single_apk.py" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

manifest_path, main_path, shield_dir, merge_source_arg = map(Path, sys.argv[1:])
# A caller may invoke this script from an alternate runner work directory.
# Resolve the repository root from the manifest's Git work tree, not $PWD.
import subprocess
repo_root = Path(subprocess.check_output(
    ["git", "rev-parse", "--show-toplevel"], cwd=manifest_path.parent, text=True
).strip())
merge_source_path = repo_root / "fx-patches" / "merge_hook_single_apk.py"
manifest_text = manifest_path.read_text(encoding="utf-8")
manifest = ET.parse(manifest_path).getroot()
main = main_path.read_text(encoding="utf-8")
shield = {p.name: p.read_text(encoding="utf-8") for p in shield_dir.glob("*.java")}
A = "{http://schemas.android.com/apk/res/android}"

declared = {node.attrib.get(A + "name", "") for node in manifest.findall("./application/activity")}
required = {
    ".imported.shield.FxYulongShieldActivity",
    ".imported.shield.FxYulongVirusDatabaseActivity",
    ".imported.shield.FxYulongScanActivity",
    ".imported.shield.FxYulongBatchCleanupActivity",
    ".imported.shield.WhitelistActivity",
    ".imported.shield.WhitelistPickerActivity",
    ".imported.shield.BlacklistActivity",
}
missing = {name for name in required if not any(actual == name or actual.endswith(name) for actual in declared)}
assert not missing, f"Manifest Activities missing: {sorted(missing)}; declared={sorted(declared)}"
vpn_services = [
    node.attrib.get(A + "name", "")
    for node in manifest.findall("./application/service")
    if node.attrib.get(A + "permission") == "android.permission.BIND_VPN_SERVICE"
]
assert not vpn_services, f"Migration added a second VpnService: {vpn_services}"
receivers = manifest.findall("./application/receiver")
install_receiver = next((node for node in receivers
                         if node.attrib.get(A + "name", "").endswith("FxYulongInstallScanReceiver")), None)
assert install_receiver is not None, "Yulong install scan receiver is not registered"
assert install_receiver.attrib.get(A + "exported") == "false", "Install scan receiver must not be externally callable"

uninstall_receiver = next((node for node in receivers
                           if node.attrib.get(A + "name", "").endswith("FxYulongUninstallReceiver")), None)
assert uninstall_receiver is not None, "Original Shield notification uninstall receiver is missing"
assert uninstall_receiver.attrib.get(A + "exported") == "false", "Uninstall receiver must remain private"
uninstall_source = shield["FxYulongUninstallReceiver.java"]
protection_service = (repo_root / "adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongProtectionService.java").read_text(encoding="utf-8")
boot_receiver = shield["FxYulongBootReceiver.java"]
keepalive_receiver = shield["FxYulongKeepAliveReceiver.java"]
overlay_service = shield["FxYulongRescueOverlayService.java"]
boot_manifest = next((node for node in receivers
                      if node.attrib.get(A + "name", "").endswith("FxYulongBootReceiver")), None)
keepalive_manifest = next((node for node in receivers
                           if node.attrib.get(A + "name", "").endswith("FxYulongKeepAliveReceiver")), None)
assert boot_manifest is not None and boot_manifest.attrib.get(A + "exported") == "false", \
    "Boot restore receiver must remain private"
assert keepalive_manifest is not None and keepalive_manifest.attrib.get(A + "exported") == "false", \
    "KeepAlive receiver must remain private"
assert "android.intent.action.BOOT_COMPLETED" in manifest_text and "android.permission.RECEIVE_BOOT_COMPLETED" in manifest_text
assert "ACTION_KEEPALIVE" in keepalive_receiver and "setAndAllowWhileIdle" in keepalive_receiver
assert boot_receiver.rfind("FxYulongKeepAliveReceiver.refreshSchedule(app)") > boot_receiver.find('if (prefs.getBoolean("overlay_rescue_on", false))'), \
    "Boot receiver must recalculate alarm after permission flags are reconciled"
assert 'if (!Settings.canDrawOverlays(app))' in keepalive_receiver, \
    "KeepAlive must detect an overlay permission revoked after boot"
assert 'putBoolean("overlay_rescue_on", false)' in keepalive_receiver and 'overlay permission revoked' in keepalive_receiver, \
    "KeepAlive must disable only the revoked overlay option and record why"
assert keepalive_receiver.rfind("refreshSchedule(app)") > keepalive_receiver.find('if (prefs.getBoolean("overlay_rescue_on", false))'), \
    "KeepAlive must reschedule after permission degradation"
assert overlay_service.count("FxYulongKeepAliveReceiver.refreshSchedule(this)") >= 3, \
    "Overlay service must cancel/update the alarm after disable, revoked permission and attach failure"
assert 'putString("overlay_restore_error", "overlay permission revoked")' in overlay_service, \
    "Overlay service must report why it disabled the rescue shortcut"
shield_activity = shield["FxYulongShieldActivity.java"]
sync_start = shield_activity.index("private void syncProtectionService(")
sync_end = shield_activity.index("private boolean ensureNotificationPermission()", sync_start)
sync = shield_activity[sync_start:sync_end]
assert 'if (protect && !hasUsageAccess()) {' in sync
assert 'putBoolean("protect_on", false)' in sync
assert 'putString("protect_restore_error", "usage access revoked")' in sync
assert sync.index('protect = false;') < sync.index('if (protect || shake)')
assert 'if (protect || shake)' in sync and 'FxYulongKeepAliveReceiver.refreshSchedule(this)' in sync, \
    "shake rescue must still start and retain its recovery schedule without Usage Access"
for token in ("Intent.ACTION_UNINSTALL_PACKAGE", "Intent.EXTRA_RETURN_RESULT",
              "PackageManager.NameNotFoundException", "FLAG_SYSTEM",
              "FLAG_UPDATED_SYSTEM_APP", "Settings.ACTION_APPLICATION_DETAILS_SETTINGS"):
    assert token in uninstall_source, f"User-confirmed uninstall receiver missing safety behavior: {token}"
assert "FxYulongUninstallReceiver.class" in protection_service
assert '"系统卸载确认"' in protection_service and ".addAction(" in protection_service
assert "pm uninstall" not in uninstall_source and "su -c" not in uninstall_source
assert 'open.setData(Uri.parse("fx-shield-risk://" + Uri.encode(packageName)))' in protection_service, "Warning PendingIntent identity must include the complete package name"
assert 'uninstallIntent.setData(Uri.parse("fx-shield-uninstall://" + Uri.encode(packageName)))' in protection_service, "Uninstall PendingIntent identity must include the complete package name"
assert 'manager.notify("fx-shield-risk:" + packageName, 0x5950, notification)' in protection_service, "Risk notifications must use an exact package tag instead of String.hashCode"
assert '"protect_alert_last_" + packageName' in protection_service, "Per-package alert cooldown must not collide on String.hashCode"
assert "packageName.hashCode()" not in protection_service, "Package-scoped notification identity must not depend on collision-prone String.hashCode"
merge_source = merge_source_path.read_text(encoding="utf-8")
assert "FxYulongInstallScanReceiver" in merge_source
assert "ET.fromstring(manifest_text)" in merge_source, "Unified APK merger must parse the original Manifest tree"
assert 'application_node.set(ANDROID + "label", "FX Hook")' in merge_source
assert 'xposed_metadata = {' in merge_source and '"xposedmodule": "true"' in merge_source, \
    "LSPosed metadata must be added without replacing application children"
assert "launcher_activities" in merge_source and "android.intent.category.LAUNCHER" in merge_source
assert "original_component_names = {" in merge_source, "original component inventory snapshot is missing"
assert 'for tag in ("activity", "service", "receiver", "provider")' in merge_source
assert "for tag, original_names in original_component_names.items()" in merge_source, \
    "merged Manifest must compare every original component category after serialization"
assert "ET.tostring(manifest_root" in merge_source and "ET.parse(manifest)" in merge_source, \
    "Unified APK merger must serialize and reparse the preserved XML tree"
assert 'required_migrated_services = {' in merge_source and '".FxAccessibilityService"' in merge_source, \
    "the accessibility service must be explicitly retained"
assert "app_match = re.search" not in merge_source and 'app = """' not in merge_source, \
    "Manifest migration must not reconstruct and discard existing application nodes"
assert 'for tag in ("activity", "service", "receiver", "provider")' in merge_source
assert "for node in application_node.findall(tag)" in merge_source, \
    "Unified APK merger must inventory the original children of every component category"
assert "original_component_names.items()" in merge_source, \
    "component category inventories must be compared after serialization"
for tag in ("activity", "service", "receiver", "provider"):
    names = [
        node.attrib.get(A + "name", "")
        for node in manifest.findall("./application/" + tag)
    ]
    duplicates = sorted(name for name in set(names) if name and names.count(name) > 1)
    assert not duplicates, f"Unified manifest duplicates {tag} components: {duplicates}"

# Legacy package strings are valid in Intent actions used for explicit migration
# compatibility; only the APK package and declared component names must belong
# to the unified FX application.
assert manifest.attrib.get("package") == "de.privacyguard.adhook", \
    "Unified manifest must declare the FX application package, not an original source package"
for tag in ("activity", "service", "receiver", "provider"):
    for node in manifest.findall("./application/" + tag):
        component_name = node.attrib.get(A + "name", "")
        assert not any(source_pkg in component_name for source_pkg in
                       ("com.youlong.hd", "com.youlong.ad", "dialog.box")), \
            f"Original application component was registered instead of migrated in-app component: {tag} {component_name}"
command_guard = next((node for node in manifest.findall("./application/activity")
                      if node.attrib.get(A + "name", "").endswith("FxStellarCommandGuardActivity")), None)
assert command_guard is not None, "Stellar command-guard in-app Activity is missing"
assert command_guard.attrib.get(A + "permission") == "android.permission.INTERACT_ACROSS_USERS_FULL", \
    "Stellar command guard must remain signature-protected"
assert any(item.attrib.get(A + "name") == "com.youlong.hd.intent.action.COMMAND_GUARD"
           for item in command_guard.findall("./intent-filter/action")), \
    "Original Stellar command-guard action must remain compatible"

for label in ("Dia 23.11", "游龙广告插件 7.0.1", "游龙安全护盾 9.9.60"):
    assert label in main, f"Settings migration entry missing: {label}"
for name in ("showImportedSuite", "showImportedSuiteCategory", "openImportedSuitePage"):
    assert name in main, f"3rd/4th-level navigation missing: {name}"
# Dia pages must route to their matching native feature surface. General FX
# privacy groups are not substitutes for Dia's target-specific editors or tools.
for panel in ("notifyPanel", "sensorPanel", "netPanel"):
    assert f'showNativeSettingsGroup("{panel}"' in main, f"Dia feature has lost its matching native settings panel: {panel}"
assert 'case "设备属性":' in main and 'showAppList("设备标识模拟")' in main, \
    "Dia device identity must open the per-target identity editor, not a global device panel"
hub = shield["FxYulongShieldActivity.java"]
rescue_route_start = main.index('case "悬浮救援入口":')
rescue_route = main[rescue_route_start:rescue_route_start + 420]
assert "FxYulongShieldActivity.class" in rescue_route, \
    "Shield floating-rescue settings must open the hub that owns the real enable switch"
assert "FxYulongRescueActivity.java" in shield, "Dedicated rescue Activity source missing"
assert "FxYulongRescueActivity.class" in hub and "打开救援中心" in hub, \
    "The hub must retain a separate path into the original recovery actions"
rescue = shield["FxYulongRescueActivity.java"]
assert "new Intent(context, FxYulongRescueActivity.class)" in protection_service, \
    "Rescue notification must open the dedicated Rescue screen, not the Shield Hub"
assert "FxYulongRescueActivity.EXTRA_OPENED_FROM_NOTIFICATION, true" in protection_service, \
    "Notification launch must carry the Rescue caller-origin marker"
assert "private void returnToShieldHub()" in rescue, "Rescue caller-aware back routing is missing"
assert "onBackPressed()" in rescue and "returnToShieldHub();" in rescue, \
    "System Back must use the same caller-aware route as the header button"
assert 'button("‹ 返回安全护盾", this::returnToShieldHub)' in rescue, \
    "Rescue header Back must use the caller-aware route"
assert 'button("返回安全护盾主页", this::returnToShieldHub)' in rescue, \
    "Rescue footer Back must use the caller-aware route"
assert "private ScrollView shieldScroll;" in hub, "Shield hub scroll container must survive Activity recreation"
assert 'STATE_SCROLL_Y = "fx_yulong_shield_scroll_y"' in hub, "Shield hub scroll state key is missing"
assert "onSaveInstanceState(Bundle outState)" in hub and "outState.putInt(STATE_SCROLL_Y" in hub, "Shield hub scroll position is not saved"
assert "state.getInt(STATE_SCROLL_Y, 0)" in hub and "shieldScroll.scrollTo(0, restoreY)" in hub, "Shield hub scroll position is not restored"
assert r'"\\n累计提醒："' not in hub, "Shield status must not show a literal backslash followed by n"
assert r'"\n累计提醒："' in hub, "Shield status must retain a Java newline escape"
assert r'"\n只恢复用户主动开启的 FX 守护/救援服务' in hub, "Recovery note must render on a new line"
assert 'case "位置与 GPS":' in main and 'showAppList("位置隐私")' in main, \
    "Dia GPS settings must open the per-target location/GPS editor"
assert 'case "Wi-Fi 模拟":' in main and 'showAppList("Wi-Fi 环境模拟")' in main, \
    "Dia Wi-Fi simulation must open its per-target editor"
assert 'case "网络类型模拟":' in main and 'showAppList("网络类型模拟")' in main, \
    "Dia network-type simulation must open its per-target editor"
assert 'case "文件与 so 库":' in main and "FxDiaFileActivity.class" in main, \
    "Dia file/SO tools must open the SAF-backed native file browser"
assert 'case "按键控制":' in main and 'loadDiaMonitorTemplate("key")' in (repo_root / "adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java").read_text(encoding="utf-8"), \
    "Dia key-control page must open its key-event observer template"
assert 'case "应用版本":' in main and 'case "签名信息":' in main and "FxDiaSignatureActivity.class" in main, \
    "Dia version/signature pages must open the native PackageManager signing inspector"
frida_activity = (repo_root / "adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java").read_text(encoding="utf-8")
assert "FX QuickJS 脚本页仍是独立运行时，不会被当作 Frida。" in frida_activity, "Frida and QuickJS runtimes must remain explicitly distinct"
assert 'wifi_simulate' in main and 'network_type_sim' in main and 'publishConfig();' in main, \
    "Dia network simulation UI must persist per-target drafts and publish configuration"
assert 'installWifiInfoSimulationHooks' in (repo_root / "adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java").read_text(encoding="utf-8"), \
    "Wi-Fi simulation settings have no runtime Hook implementation"
assert 'installNetworkTypeSimulationHooks' in (repo_root / "adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java").read_text(encoding="utf-8"), \
    "Network-type simulation settings have no runtime Hook implementation"
assert 'Intent.ACTION_OPEN_DOCUMENT_TREE' in (repo_root / "adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFileActivity.java").read_text(encoding="utf-8"), \
    "Dia file browser must use explicit SAF directory grants"
assert 'GET_SIGNING_CERTIFICATES' in (repo_root / "adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaSignatureActivity.java").read_text(encoding="utf-8"), \
    "Dia signature inspector must read PackageManager signing certificates"

accessibility = (repo_root / "adhook/app/src/main/java/de/privacyguard/adhook/FxAccessibilityService.java").read_text(encoding="utf-8")
risk_dispatcher = (repo_root / "adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongRiskScanDispatcher.java").read_text(encoding="utf-8")
virus_database_page = (repo_root / "adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongVirusDatabaseActivity.java").read_text(encoding="utf-8")
assert "onVirusDatabaseUpdated" in risk_dispatcher and "FULL_SCAN_RUNNING" in risk_dispatcher, "database refresh must trigger one serialized full-app scan"
assert virus_database_page.count("FxYulongRiskScanDispatcher.onVirusDatabaseUpdated") == 2, "both list and content database refreshes must dispatch the full scan"
assert "FxYulongVirusDb.isServerReachable()" in virus_database_page, "list DB scan must only follow a successful remote sync"
assert "getLastSuccessAt() > previousContentSuccess" in virus_database_page, "content DB scan must only follow successful data/304 refresh"
install_receiver = shield["FxYulongInstallScanReceiver.java"]
assert "onForegroundPackageChanged(this, pkg)" in accessibility, "foreground package changes must feed Yulong auto-risk scanning"
for token in ("onForegroundPackageChanged", "onPackageInstalled", "PACKAGE_COOLDOWN_MS",
              "auto_block_on", "auto_block_mode", "automatic_scan_count_today",
              'manager.notify("fx-yulong-auto-risk:" + finding.packageName',
              "Intent.ACTION_DELETE"):
    assert token in risk_dispatcher, f"Yulong shared auto-risk dispatcher missing {token}"
assert "FxYulongRiskScanDispatcher.onPackageInstalled" in install_receiver
assert 'getBoolean("automatic_install_scan_enabled", true)' in shield["FxYulongShieldActivity.java"], \
       "install scan must preserve original default-on behavior"
for token in ("auto_block_on", "auto_block_mode", "自动前台风险扫描",
              "directMode", "confirmMode", "FxAccessibilityService.isConnected()"):
    assert token in shield["FxYulongShieldActivity.java"], f"Yulong risk mode UI missing {token}"
assert "pm uninstall" not in risk_dispatcher and "su -c" not in risk_dispatcher, \
       "automatic risk handling must never uninstall without Android's confirmation UI"
volume_sequence = shield["FxYulongVolumeTriggerSequence.java"]
volume_sequence_test = (repo_root / "adhook/app/src/test/java/de/privacyguard/adhook/imported/shield/FxYulongVolumeTriggerSequenceTest.java").read_text(encoding="utf-8")
accessibility_xml = (repo_root / "adhook/app/src/main/res/xml/fx_accessibility_service.xml").read_text(encoding="utf-8")
assert 'android:canRequestFilterKeyEvents="true"' in accessibility_xml, "AccessibilityService XML must request key filtering"
assert "flagRequestFilterKeyEvents" in accessibility_xml, "AccessibilityService key filtering flag is missing"
assert "volume_trigger_key" in accessibility and "volume_trigger_count" in accessibility
assert "volumeTriggerSequence.recordPress" in accessibility
assert "event.getAction() == KeyEvent.ACTION_UP" in accessibility
assert "return false; // Preserve normal Android volume behavior." in accessibility
assert "volumeUpCount >= 6" not in accessibility, "fixed six-volume-up placeholder remains"
for token in ("DEFAULT_COUNT = 3", "MIN_COUNT = 2", "MAX_COUNT = 10",
              "sequenceWindowMs", "TRIGGER_COOLDOWN_MS", "resetSequence()"):
    assert token in volume_sequence, f"Volume trigger sequence helper missing {token}"
for token in ("triggersOnlyAfterConfiguredVolumeDownCount",
              "selectedDirectionMustMatchAndOppositeKeyResetsSequence",
              "countControlsWindowUsingLegacyMinimumAndPerPressTiming",
              "completedSequenceHasCooldownAndThenCanTriggerAgain"):
    assert token in volume_sequence_test, f"Volume trigger unit test missing {token}"
for method in ("onInterrupt()", "onUnbind(Intent intent)", "onServiceConnected()", "onDestroy()"):
    block = accessibility.split(method, 1)[1].split("@Override", 1)[0]
    assert "volumeTriggerSequence.resetSequence()" in block, f"partial volume sequence must reset on {method}"
assert "return false; // Preserve normal Android volume behavior." in accessibility, "volume trigger must not consume system volume keys"

volume_ui = shield["FxYulongShieldActivity.java"]
assert "volume_trigger_key" in volume_ui and "volume_trigger_count" in volume_ui
assert "选择救援触发按键" in volume_ui and "连续按键次数（2–10 次）" in volume_ui
assert "volumeKeyButton" in volume_ui and "volumeCountButton" in volume_ui

hub = shield["FxYulongShieldActivity.java"]
db_page = shield["FxYulongVirusDatabaseActivity.java"]
scan_page = shield["FxYulongScanActivity.java"]
batch_cleanup = shield["FxYulongBatchCleanupActivity.java"]
engine = shield["FxYulongScanEngine.java"]
db = shield["FxYulongVirusDb.java"]
content_db = shield["FxYulongVirusContentDb.java"]
white, picker, black = (shield[x] for x in (
    "WhitelistActivity.java", "WhitelistPickerActivity.java", "BlacklistActivity.java"))

for page in ("FxYulongVirusDatabaseActivity.class", "FxYulongScanActivity.class",
             "WhitelistActivity.class", "BlacklistActivity.class"):
    assert page in hub, f"Shield hub misses child page: {page}"
for item in ("safe1.json", "safe2.json", "mingcheng1.json", "mingcheng2.json",
             "key.json", "mian1.json", "mian2.json"):
    assert item in db, f"Original list / legacy merge missing: {item}"
assert '"fx_yulong_virus_db"' in db
assert '"fx_yulong_virus_content_db"' in content_db
assert '"fx_yulong_virus_verdict_cache"' in content_db
assert "FxYulongVirusDb.getServerHost()" in content_db
assert "getContentDatabaseStatusJson" in content_db
assert "static Verdict inspectApk(Context ctx, String pkg, long deadlineMs)" in content_db
for forbidden in ("StellarUtils.", "roro.stellar.", "VirusAutoScanner.", "pushSnapshot(ctx)"):
    assert forbidden not in content_db, f"Unavailable privileged runtime leaked into host APK: {forbidden}"

assert "getInstalledApplications" in engine and "CATEGORY_LAUNCHER" in engine
assert "FLAG_UPDATED_SYSTEM_APP" in engine
assert "com.youlong.zoo" in engine and "com.youlong.tool" in engine
assert "System.currentTimeMillis() + 8000L" in engine
assert "FxYulongVirusContentDb.inspectApk" in engine
assert "catch (Throwable itemError)" in engine
assert 'getBoolean("content_scan_enabled", false)' in scan_page
assert "Intent.ACTION_DELETE" in scan_page and 'setPositiveButton("打开系统确认"' in scan_page

# Batch cleanup must reject malformed or truncated queue payloads atomically.
for token in (
    "inputPackages == null || inputLabels == null || inputReasons == null",
    "inputPackages.size() > MAX_QUEUE_ITEMS",
    "inputLabels.size() != inputPackages.size()",
    "inputReasons.size() != inputPackages.size()",
    "!uniquePackages.add(pkg)",
    "!uniquePackages.contains(pkg)",
    "restoredIndex < 0 || restoredIndex > inputPackages.size()",
    "STATE_QUEUE_INVALID",
    "if (queueInvalid) return;",
    "if (queueInvalid) {",
    "uninstall.setEnabled(false);",
    "next.setEnabled(false);",
):
    assert token in batch_cleanup, f"Batch cleanup queue integrity guard missing: {token}"
assert "Math.min(Math.min(inputPackages.size(), inputLabels.size()), MAX_QUEUE_ITEMS)" not in batch_cleanup, \
    "Batch cleanup must not silently truncate mismatched queue fields"
assert "pm uninstall" not in engine and "su -c" not in engine
assert "private LinearLayout body" in scan_page and "private LinearLayout resultRows" in scan_page
assert 'STATE_SCAN_SCROLL_Y = "fx_shield_scan_scroll_y"' in scan_page, "Shield scan result list must have an explicit scroll restoration key"
assert "private ScrollView scanScroll;" in scan_page, "Shield scan must retain its actual ScrollView"
assert "scanScroll=scroll;" in scan_page, "Shield scan scroll state must be tied to its page container"
assert "scanScroll.getScrollY()" in scan_page and "scroll.scrollTo(0, restoreY)" in scan_page, "Shield scan page must save and restore the result-list position"
assert "if (scanScroll == scroll && scroll.getParent() != null)" in scan_page, "Stale scan scroll callbacks must not move a replacement page"
assert "resultRows.removeAllViews()" in scan_page and "resultRows.addView(item" in scan_page
assert "findings.removeAllViews()" not in scan_page

# Keep the original shield_prefs namespace so lists created by the 9.9.60
# app remain visible after migration; do not invent a second FX-only list store.
for source, label in ((white, "WhitelistActivity"), (picker, "WhitelistPickerActivity"),
                      (black, "BlacklistActivity")):
    assert 'getSharedPreferences("shield_prefs", MODE_PRIVATE)' in source, \
        f"{label} no longer reads the compatible Shield preference namespace"
    assert "com.youlong.hd" not in source, f"{label} still references source package"
assert '"whitelist_pkgs"' in white and '"whitelist_pkgs"' in picker, \
    "Whitelist manager and picker must share the original whitelist key"
assert "RootAccess" not in white and "yulong-stellar-control.sh" not in white \
    and "pkg-sync" not in white, \
    "Shield risk-exemption whitelist must remain separate from Stellar Root privilege authorization"
assert '"blacklist_pkgs"' in black, "Blacklist manager must preserve the original blacklist key"
assert "StellarUtils" not in white and "syncToStellar" not in picker

# Blacklist inventory and selection must not enumerate every installed package on
# the UI thread or create a giant MultiChoiceItems dialog.
assert "private void loadAppsAsync()" in black
assert "appLoader.execute(() -> {" in black
assert "new ArrayBlockingQueue<>(1)" in black
assert "getInstalledApplications(0)" in black
assert "appByPackage.get(pkg)" in black
assert "pageSize = 50" in black
assert "search.addTextChangedListener" in black
assert "appLoadGeneration.incrementAndGet()" in black
assert "appLoader.shutdownNow();" in black
assert "activityDestroyed = true;" in black
assert "private void loadApps()" not in black
assert "setMultiChoiceItems(names, checked" not in black

# Whitelist and blacklist pages retain their visible position and active filters
# when Android recreates their Activities.
assert 'STATE_QUERY = "fx_shield_whitelist_query"' in white
assert 'STATE_SCROLL_Y = "fx_shield_whitelist_scroll_y"' in white
assert "onSaveInstanceState(Bundle outState)" in white
assert "outState.putString(STATE_QUERY" in white and "outState.putInt(STATE_SCROLL_Y" in white
assert "searchInput.setText(query)" in white and "whitelistScroll.scrollTo(0, restoreY)" in white
assert 'STATE_PAGE = "fx_shield_blacklist_page"' in black
assert 'STATE_SCROLL_Y = "fx_shield_blacklist_scroll_y"' in black
assert "outState.putInt(STATE_PAGE" in black and "outState.putInt(STATE_SCROLL_Y" in black
assert "savedInstanceState.getInt(STATE_PAGE, 1)" in black
assert "blacklistScroll.scrollTo(0, restoreY)" in black
picker = shield["WhitelistPickerActivity.java"]
assert 'STATE_QUERY = "fx_shield_whitelist_picker_query"' in picker
assert 'STATE_SELECTED = "fx_shield_whitelist_picker_selected"' in picker
assert 'STATE_FIRST_POSITION = "fx_shield_whitelist_picker_first_position"' in picker
assert 'STATE_FIRST_TOP = "fx_shield_whitelist_picker_first_top"' in picker
assert "outState.putStringArrayList(STATE_SELECTED" in picker
assert "outState.putString(STATE_QUERY" in picker
assert "outState.putInt(STATE_FIRST_POSITION" in picker and "outState.putInt(STATE_FIRST_TOP" in picker
assert "selected.addAll(restored)" in picker and "searchInput.setText(query)" in picker
assert "listView.setSelectionFromTop(position, top)" in picker

# Whitelist label/icon refresh must not spawn overlapping unbounded raw threads.
assert "ThreadPoolExecutor(1, 1, 30L" in white
assert "new ArrayBlockingQueue<>(1)" in white
assert "labelLoadGeneration.incrementAndGet()" in white
assert "generation != labelLoadGeneration.get()" in white
assert "labelWorker.shutdownNow();" in white
assert "activityDestroyed = true;" in white
assert white.count("new Thread(") == 1, "WhitelistActivity must only create its named executor worker"

# App enumeration and lazy icons must use independent bounded pools; queue saturation
# must not crash ListView.getView and stale callbacks must not update a destroyed Activity.
assert "ThreadPoolExecutor(1, 1, 30L" in picker
assert "new ArrayBlockingQueue<>(1)" in picker
assert "ThreadPoolExecutor(2, 2, 30L" in picker
assert "new ArrayBlockingQueue<>(32)" in picker
assert "appLoader.shutdownNow();" in picker and "iconExecutor.shutdownNow();" in picker
assert "catch (RejectedExecutionException full)" in picker
assert "activityDestroyed || isFinishing() || isDestroyed()" in picker
assert picker.count("new Thread(") == 2, "WhitelistPickerActivity should only create its two named executor workers"
scan_engine = shield["FxYulongScanEngine.java"]
assert "new ArrayBlockingQueue<>(32)" in scan_engine, "install and manual scan backlog must be bounded"
assert "new ThreadPoolExecutor.AbortPolicy()" in scan_engine, "queue saturation must be rejected explicitly"
assert "catch (RejectedExecutionException full)" in scan_engine, "queue saturation failure must be handled"
assert "扫描队列繁忙，本次请求未执行" in scan_engine, "queue saturation must be reported instead of silently dropping scans"
assert "Executors.newSingleThreadExecutor" not in scan_engine, "unbounded scanner executor must not return"
print("PASS: Shield native UI/database/scanner, safe removal, no second VPN, bounded whitelist app/icon workers and lifecycle cleanup and foreground/install risk scanning")
PY
