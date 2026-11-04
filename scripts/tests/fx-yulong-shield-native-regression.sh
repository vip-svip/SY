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

assert not any(p in manifest_text for p in ("com.youlong.hd", "com.youlong.ad", "dialog.box")), \
    "A source APK/package was registered instead of an in-app Activity"

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
rescue_route_start = main.index('case "悬浮救援入口":')
rescue_route = main[rescue_route_start:rescue_route_start + 420]
assert "FxYulongRescueActivity.class" in rescue_route, \
    "Shield floating rescue entry must open its dedicated recovery page, not the Shield overview"
assert "FxYulongRescueActivity.java" in shield, "Dedicated rescue Activity source missing"
assert r'"\\n累计提醒："' not in shield, "Shield status must not show literal backslash-n"
assert r'"\n累计提醒："' in shield, "Shield status must retain a Java newline escape"
assert r'"\n只恢复用户主动开启的 FX 守护/救援服务' in shield, "Recovery note must render on a new line"
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
volume_ui = shield["FxYulongShieldActivity.java"]
assert "volume_trigger_key" in volume_ui and "volume_trigger_count" in volume_ui
assert "选择救援触发按键" in volume_ui and "连续按键次数（2–10 次）" in volume_ui
assert "volumeKeyButton" in volume_ui and "volumeCountButton" in volume_ui

hub = shield["FxYulongShieldActivity.java"]
db_page = shield["FxYulongVirusDatabaseActivity.java"]
scan_page = shield["FxYulongScanActivity.java"]
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
assert "pm uninstall" not in engine and "su -c" not in engine
assert "private LinearLayout body" in scan_page and "private LinearLayout resultRows" in scan_page
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
