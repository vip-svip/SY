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
blacklist_activity = shield["BlacklistActivity.java"]
blacklist_policy = shield["FxYulongBlacklistPolicy.java"]
protection_service = shield["FxYulongProtectionService.java"]
virus_db = shield["FxYulongVirusDb.java"]
scan_activity = shield["FxYulongScanActivity.java"]
warning_activity = shield["FxYulongWarningActivity.java"]
virus_db_test = (repo_root / "adhook/app/src/test/java/de/privacyguard/adhook/imported/shield/FxYulongVirusDbTest.java").read_text(encoding="utf-8")
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
assert 'case "通知监听与权限提示":' in main and 'showAppList("通知保护")' in main, "Dia notification page must open the per-app notification policy editor"
assert 'case "传感器":' in main and 'showNativeSettingsGroup("sensorPanel"' in main, "Dia sensor page must open the native sensor panel"
assert 'case "网络与代理":' in main and 'showNativeSettingsGroup("netPanel"' in main, "Dia network page must open the native network panel"
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
assert 'button("‹ 返回隐私", this::returnToShieldHub)' in rescue, \
    "Rescue header Back must use the unified FX Privacy route"
assert 'button("返回安全护盾主页", this::returnToShieldHub)' in rescue, \
    "Rescue footer Back must use the caller-aware route"
assert "private ScrollView shieldScroll;" in hub, "Shield hub scroll container must survive Activity recreation"
assert 'STATE_SCROLL_Y = "fx_yulong_shield_scroll_y"' in hub, "Shield hub scroll state key is missing"
assert "onSaveInstanceState(Bundle outState)" in hub and "outState.putInt(STATE_SCROLL_Y" in hub, "Shield hub scroll position is not saved"
assert "state.getInt(STATE_SCROLL_Y, 0)" in hub and "shieldScroll.scrollTo(0, restoreY)" in hub, "Shield hub scroll position is not restored"
assert r'"\\n累计提醒："' not in hub, "Shield status must not show a literal backslash followed by n"
assert '"累计提醒：" +' in hub, "Shield status must retain the cumulative reminder label"
assert r'"\n最近提醒："' in hub, "Recent reminder timestamp must start on a new line"
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
assert '"病毒库完整同步完成（"' in db_page, "Virus list UI must distinguish a complete sync"
assert '"病毒库部分同步（"' in db_page, "Virus list UI must report partial list success"
assert '"病毒库同步失败，原有缓存已保留"' in db_page, "Total list failure must state that cached data was retained"
assert "int successfulLists = 0;" in db_page and "item.ok" in db_page, "Virus list outcome must use per-list success results"
assert "contentSyncSucceeded = contentReady" in db_page, "Ready stale content cache must not be mistaken for a successful refresh"
assert 'STATE_SCROLL_Y = "fx_shield_virus_db_scroll_y"' in db_page, "Virus database page must preserve its scroll state"
assert "private ScrollView databaseScroll;" in db_page and "databaseScroll=scroll;" in db_page, "Virus database scroll state must reference the real container"
assert "databaseScroll.getScrollY()" in db_page and "scroll.scrollTo(0, restoreY)" in db_page, "Virus database page must save and restore its scroll position"
assert "databaseScroll == scroll && scroll.getParent() != null" in db_page, "Stale virus database scroll callbacks must not move a replacement page"
assert "getLastSuccessAt() > previousContentSuccess" in db_page, "Content DB success must be based on this refresh attempt"
assert "本次同步未成功；旧版 APK 特征缓存仍可用" in db_page, "Content DB failure with a usable old cache must be explicit"
scan_page = shield["FxYulongScanActivity.java"]
batch_cleanup = shield["FxYulongBatchCleanupActivity.java"]
engine = shield["FxYulongScanEngine.java"]
db = shield["FxYulongVirusDb.java"]
content_db = shield["FxYulongVirusContentDb.java"]
virus_db = db
scan_activity = scan_page
warning_activity = shield["FxYulongWarningActivity.java"]
virus_db_test = (repo_root / "adhook/app/src/test/java/de/privacyguard/adhook/imported/shield/FxYulongVirusDbTest.java").read_text(encoding="utf-8")

# Five-list cache metadata distinguishes attempts from successful cache writes.
for token in (
    'K_LAST_ATTEMPT = "last_attempt_time"',
    'K_LAST_SUCCESS = "last_success_time"',
    'K_SERVER_REACHABLE = "server_reachable"',
    'K_LAST_ERROR = "last_error"',
    'K_LIST_META_PREFIX = "list_status_"',
    "lastAttempt = sp.getLong(K_LAST_ATTEMPT, 0L)",
    "serverReachabilityKnown = sp.contains(K_LAST_ATTEMPT)",
    "status.lastAttemptAt = sp.getLong(prefix + \"last_attempt_at\", 0L)",
    'System.currentTimeMillis() - lastAttempt < MIN_FETCH_INTERVAL_MS',
    "lastFetchTime = lastSuccess;",
    '.putString(K_LAST_ERROR, lastError);',
    'if (!t.matches("[A-Za-z0-9_]+(',
    'return new LinkedHashSet<>();',
    'lower.contains("<html")',
    'lower.contains("bad gateway")',
    r'lower.matches("(?s)^\\[\\s*\\{.*")',
):
    assert token in db, f"Virus DB cache/parser safety contract missing: {token}"
assert "serverReachabilityKnown && sp.getBoolean(K_SERVER_REACHABLE, false)" in db, \
    "Legacy cache without explicit reachability metadata must not claim online state"
assert r'lower.matches("(?s)^\\[\\s*\\{.*")' in db, "Virus DB must reject JSON object arrays even with whitespace after '['"
assert "item.statusLabel()" in db_page, "Per-list cache status must survive Activity recreation"
assert "getLastAttempt()" in db_page and "getLastSuccess()" in db_page
assert "isServerReachabilityKnown()" in db_page, "Legacy server reachability must display as unknown"
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

warning_page = shield["FxYulongWarningActivity.java"]
assert 'STATE_SCROLL_Y = "fx_yulong_warning_scroll_y"' in warning_page, "Warning detail page scroll state key missing"
assert "onSaveInstanceState(Bundle outState)" in warning_page and "outState.putInt(STATE_SCROLL_Y" in warning_page, "Warning detail page must save scroll position"
assert "warningScroll.scrollTo(0, restoreY)" in warning_page, "Warning detail page must restore scroll position after recreation"
for token in (
    "private void refreshTargetAvailability()",
    "@Override protected void onResume()",
    'boolean validRisk = "CERTAIN".equals(severity) || "SUSPECT".equals(severity);',
    "uninstallButton.setEnabled(validPackageName() && validRisk && targetInstalled);",
    "getPackageManager().getApplicationInfo(packageName, 0);",
    "应用当前不存在或系统不允许查询；请重新扫描。",
):
    assert token in warning_page, f"Warning page live-action guard missing: {token}"
assert 'if (!validPackageName() || !("CERTAIN".equals(severity) || "SUSPECT".equals(severity)))' in warning_page, \
    "Invalid severity must not open the system uninstall confirmation"
assert "catch (RuntimeException lookupFailure)" in warning_page, \
    "Whitelist action must handle package visibility/runtime lookup failures without crashing"
assert "catch (RuntimeException unreadablePreference)" in warning_page, \
    "Risk detail whitelist action must handle wrong-type/corrupt SharedPreferences without crashing"
assert "无法按文本读取" in warning_page, \
    "Risk detail whitelist action must explain that unreadable whitelist data was preserved"
assert "FxYulongWhitelistPolicy.isWellFormed(storedWhitelist)" in warning_page, \
    "Risk detail whitelist action must reject malformed original data through the shared parser"
assert "FxYulongWhitelistPolicy.serialize(packages)" in warning_page, \
    "Risk detail whitelist action must use the shared bounded serializer"
assert "if (serialized == null)" in warning_page, \
    "Risk detail whitelist action must reject additions above the shared entry/size limits"
assert "白名单已达到安全上限" in warning_page, \
    "Risk detail page must explain why an over-limit whitelist addition was rejected"
assert '.putString(WHITELIST_KEY, serialized)' in warning_page, \
    "Risk detail page must only commit the validated canonical whitelist string"
assert "本次没有修改任何白名单数据" in warning_page, \
    "Risk detail whitelist action must not silently discard malformed existing entries"
whitelist_policy = shield["FxYulongWhitelistPolicy.java"]
assert "public static boolean isWellFormed(String raw)" in whitelist_policy, \
    "Shared whitelist parser must expose whole-payload validation"
assert "if (!isValidPackageName(candidate)) return false;" in whitelist_policy, \
    "Shared whitelist parser must reject the entire CSV on an invalid token"
assert "if (whitelistDataCorrupt)" in white and "原白名单数据异常" in white, \
    "Whitelist manager must refuse writes when the original list is malformed"
assert "whitelistDataCorrupt" in picker and "原白名单数据异常" in picker, \
    "Whitelist picker must refuse to overwrite malformed original data"
assert "whitelistDataCorrupt = !raw.isEmpty() && !FxYulongWhitelistPolicy.isWellFormed(raw);" in white
assert "whitelistDataCorrupt = !raw.isEmpty() && !FxYulongWhitelistPolicy.isWellFormed(raw);" in picker

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
assert "private static final int REQUEST_BATCH_CLEANUP = 0x59b2;" in scan_page, "Batch cleanup must return to the owning scan page"
assert "startActivityForResult(intent, REQUEST_BATCH_CLEANUP);" in scan_page, "Scan page must receive batch cleanup completion"
assert "if (requestCode != REQUEST_BATCH_CLEANUP) return;" in scan_page, "Only the cleanup queue result may invalidate the scan"
assert "selectedForCleanup.clear();" in scan_page and "restoreRequiresRescan = true;" in scan_page, "Returning from cleanup must invalidate stale scan selections"
assert "原扫描结果可能已过期。请重新扫描后再处理。" in scan_page, "Stale scan results must be explained to the user"
assert "if (!isFinishing() && !isDestroyed() && scanScroll == scroll && scroll.getParent() != null)" in scan_page, "Stale scan scroll callbacks must be lifecycle- and container-guarded"
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
assert "whitelistDataCorrupt = !raw.isEmpty() && !FxYulongWhitelistPolicy.isWellFormed(raw)" in picker, \
    "Whitelist picker must detect partially malformed source data atomically"
assert "if (whitelistDataCorrupt)" in picker and "已阻止覆盖" in picker, \
    "Whitelist picker must not overwrite malformed legacy data when adding selected apps"
assert "RootAccess" not in white and "yulong-stellar-control.sh" not in white \
    and "pkg-sync" not in white, \
    "Shield risk-exemption whitelist must remain separate from Stellar Root privilege authorization"
assert '"blacklist_pkgs"' in black, "Blacklist manager must preserve the original blacklist key"
assert "StellarUtils" not in white and "syncToStellar" not in picker

# Blacklist CSV is bounded and all-or-nothing; the live service and UI share the policy.
assert "MAX_RAW_CHARS = 1024 * 1024" in blacklist_policy
assert "MAX_ENTRIES = 10000" in blacklist_policy
assert "public static boolean isWellFormed(String raw)" in blacklist_policy, "Blacklist policy must expose its full-input validator"
assert "if (!isWellFormed(raw)) return Collections.emptySet();" in blacklist_policy
assert "serialize(Iterable<String> packageNames)" in blacklist_policy
assert 'Set<String> blacklist = split(prefs);' in protection_service, "Protection service must load blacklist through guarded preference access"
assert 'private Set<String> split(SharedPreferences prefs)' in protection_service
assert 'FxYulongBlacklistPolicy.parse(prefs.getString("blacklist_pkgs", ""))' in protection_service
assert "catch (RuntimeException corruptPreference)" in protection_service, "Wrong-type blacklist preference must not crash foreground warning service"
assert "return java.util.Collections.emptySet();" in protection_service, "Unreadable blacklist preference must fail open instead of enforcing a partial list"
assert "blacklistDataCorrupt = true;" in blacklist_activity and '|| (!raw.isEmpty() && !FxYulongBlacklistPolicy.isWellFormed(raw))' in blacklist_activity, \
    "Blacklist manager must retain read failures and reject malformed stored data atomically"
assert "if (blacklistDataCorrupt)" in blacklist_activity and "已阻止覆盖" in blacklist_activity
assert 'prefs.edit().putString("blacklist_pkgs", serialized).commit()' in blacklist_activity, "Blacklist writes must be checked and synchronous"
assert "currentBlacklist.removeAll(staged);" in blacklist_activity and "currentBlacklist.add(item.packageName);" in blacklist_activity, "Failed blacklist writes must roll back in-memory edits"
assert "管控名单保存失败，原有配置保持不变。" in blacklist_activity

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
assert 'STATE_PAGE = "fx_shield_whitelist_page"' in white
assert 'STATE_SCROLL_Y = "fx_shield_whitelist_scroll_y"' in white
assert "WHITELIST_PAGE_SIZE = 50" in white, "Whitelist list must render in bounded 50-row batches"
assert "whitelistPage * WHITELIST_PAGE_SIZE" in white, "Whitelist page must cap the number of materialized row views"
assert 'more.setText("加载更多（已显示 "' in white, "Whitelist list must expose progressive loading"
assert "whitelistPage = 1;" in white and "refreshWhitelistUI();" in white, "Changing the search query must restart from the first result page"
assert white.index("searchInput.setText(query)") < white.index("whitelistPage = Math.max(1, Math.min(200, savedInstanceState.getInt(STATE_PAGE, 1)))"), "Saved whitelist page must be restored after the search watcher is invoked"
assert "outState.putInt(STATE_PAGE" in white, "Whitelist page must survive Activity recreation"
assert "onSaveInstanceState(Bundle outState)" in white
assert "outState.putString(STATE_QUERY" in white and "outState.putInt(STATE_SCROLL_Y" in white
assert "searchInput.setText(query)" in white and "whitelistScroll.scrollTo(0, restoreY)" in white
assert 'STATE_PAGE = "fx_shield_blacklist_page"' in black
assert 'STATE_QUERY = "fx_shield_blacklist_query"' in black
assert 'STATE_SCROLL_Y = "fx_shield_blacklist_scroll_y"' in black
assert "blacklistSearchInput.addTextChangedListener" in black
assert 'blacklistQuery = value == null ? "" : value.toString().trim();' in black
assert "label.contains(q) || pkg.contains(q)" in black
assert "blacklistPage = 1;" in black
assert "blacklistPage * BLACKLIST_PAGE_SIZE" in black
assert 'more.setText("加载更多（已显示 "' in black
assert "outState.putString(STATE_QUERY" in black
assert "outState.putInt(STATE_PAGE" in black and "outState.putInt(STATE_SCROLL_Y" in black
assert black.index("blacklistSearchInput.setText(blacklistQuery)") < black.rindex("blacklistPage = Math.max(1, savedInstanceState.getInt(STATE_PAGE, 1))")
assert "savedInstanceState.getInt(STATE_PAGE, 1)" in black
assert "blacklistScroll.scrollTo(0, restoreY)" in black
assert "MAX_PICKER_STAGED = 100" in black, "Blacklist picker must cap staged selections to the Bundle-restorable limit"
assert "staged.size() >= MAX_PICKER_STAGED" in black, "Blacklist picker must reject selections beyond the saved-state cap"
assert "单次最多选择 " in black, "Blacklist picker must explain its explicit selection limit"
assert "outState.putStringArrayList(STATE_PICKER_STAGED" in black, "Blacklist staged selection must be persisted during Activity recreation"
assert "if (pickerDialogOpen) showAppPicker(true);" in black, "Blacklist picker must reopen after asynchronous app inventory restoration"
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
assert "private boolean isEligibleUserApp(String pkg)" in picker, "whitelist picker must revalidate staged packages at commit time"
assert "pm.getApplicationInfo(pkg, 0)" in picker, "whitelist selection must verify the package is still installed"
assert "if (!isEligibleUserApp(p))" in picker, "uninstalled or unavailable staged apps must not be persisted"
assert "int added = 0;" in picker and '"已加入 " + added + " 个应用"' in picker, "success count must report actual newly persisted apps"
assert "(ai.flags & ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0" in white, "updated system apps must follow the same eligibility policy as the picker"
assert "(ai.flags & ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0" in picker, "updated system apps must follow the same eligibility policy as the manager"

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
assert "public static boolean isWellFormed(String raw)" in blacklist_policy, \
    "Blacklist policy must validate the complete original CSV"
assert "if (!isValidPackageName(candidate)) return false;" in blacklist_policy, \
    "Blacklist policy must reject malformed entries atomically"
assert "if (blacklistDataCorrupt)" in blacklist_activity, \
    "Blacklist UI must block all mutations when stored data is malformed"
assert "catch (RuntimeException wrongTypeOrReadFailure)" in blacklist_activity, \
    "Blacklist UI must not overwrite preferences that cannot be read as strings"
assert 'prefs.edit().putString("blacklist_pkgs", serialized).commit()' in blacklist_activity, \
    "Blacklist updates must synchronously confirm persistence"
assert "管控名单保存失败，原有配置保持不变" in blacklist_activity, \
    "Blacklist persistence failure must be surfaced to the user"
assert "if (!saveBlacklist())" in blacklist_activity, \
    "Blacklist add/remove/clear flows must roll back in-memory state on failed writes"
assert "public MatchEvidence matchCertain(String pkg, String label)" in virus_db, "certain match evidence missing"
assert "matchSuspectEvidence(String pkg, String label)" in virus_db, "suspect match evidence missing"
assert "STATE_FINDING_SOURCES" in scan_activity and "STATE_FINDING_MATCHES" in scan_activity, "scan evidence is not persisted across recreation"
assert 'putExtra("matched_entry", finding.matchedEntry)' in scan_activity, "warning detail route drops match evidence"
assert "匹配条目 / 特征族：" in warning_activity, "risk detail does not show evidence"
assert "certainMatchesExposeTheirRealListAndMatchedEntry" in virus_db_test, "virus DB evidence tests missing"
print("PASS: Shield native UI/database/scanner, safe removal, no second VPN, bounded whitelist app/icon workers and lifecycle cleanup and foreground/install risk scanning")
PY
