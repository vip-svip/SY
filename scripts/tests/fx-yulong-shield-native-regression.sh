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

manifest_path, main_path, shield_dir, merge_source_path = map(Path, sys.argv[1:])
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
merge_source = (Path(__file__).resolve().parents[1] / "fx-patches/merge_hook_single_apk.py").read_text(encoding="utf-8")
assert "FxYulongInstallScanReceiver" in merge_source
for kind in ("ACTIVITIES", "SERVICES", "RECEIVERS", "PROVIDERS"):
    marker = "FX_PRESERVED_MIGRATED_" + kind
    assert marker in merge_source, f"Unified APK merger has no {kind.lower()} preservation slot"
    assert "retained_" + kind.lower() in merge_source, f"Unified APK merger does not collect retained {kind.lower()} components"
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
for panel in ("notifyPanel", "sensorPanel", "netPanel", "devicePanel", "filePanel",
              "locationPanel", "miscPanel"):
    assert f'showNativeSettingsGroup("{panel}"' in main, f"Dia page is not wired to native FX panel: {panel}"
assert "FX 当前的 QuickJS 脚本运行时不是 Frida" in main, "Frida must not be mislabeled as QuickJS"
assert 'case "Wi-Fi 模拟"' not in main and 'case "网络类型模拟"' not in main, \
    "Unimplemented Dia Wi-Fi/network simulation must remain explicitly pending"
assert 'case "按键控制"' not in main and 'case "应用版本"' not in main and 'case "签名信息"' not in main, \
    "Unimplemented Dia features must not be routed to unrelated settings panels"

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

for source, label in ((white, "WhitelistActivity"), (picker, "WhitelistPickerActivity"),
                      (black, "BlacklistActivity")):
    assert '"fx_yulong_shield_prefs"' in source, f"{label} preference namespace missing"
    assert "com.youlong.hd" not in source, f"{label} still references source package"
assert "StellarUtils" not in white and "syncToStellar" not in picker

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
print("PASS: Shield native UI/database/scanner, safe removal, no second VPN, bounded whitelist app/icon workers and lifecycle cleanup")
PY
