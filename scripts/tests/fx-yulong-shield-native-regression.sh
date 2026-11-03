#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="$ROOT/adhook/app/src/main"
JAVA="$APP/java/de/privacyguard/adhook"
SHIELD="$JAVA/imported/shield"

python3 - "$APP/AndroidManifest.xml" "$JAVA/MainActivity.java" "$SHIELD" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

manifest_path, main_path, shield_dir = map(Path, sys.argv[1:])
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
assert not (required - declared), f"Manifest Activities missing: {sorted(required - declared)}"
vpn_services = [
    node.attrib.get(A + "name", "")
    for node in manifest.findall("./application/service")
    if node.attrib.get(A + "permission") == "android.permission.BIND_VPN_SERVICE"
]
assert not vpn_services, f"Migration added a second VpnService: {vpn_services}"
assert not any(p in manifest_text for p in ("com.youlong.hd", "com.youlong.ad", "dialog.box")), \
    "A source APK/package was registered instead of an in-app Activity"

for label in ("Dia 23.11", "游龙广告插件 7.0.1", "游龙安全护盾 9.9.60"):
    assert label in main, f"Settings migration entry missing: {label}"
for name in ("showImportedSuite", "showImportedSuiteCategory", "openImportedSuitePage"):
    assert name in main, f"3rd/4th-level navigation missing: {name}"

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
print("PASS: Shield native UI, database, caches, opt-in APK content scan, timeout, safe removal, no second VPN and local list management")
PY
