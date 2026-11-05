#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="$ROOT/adhook/app/src/main"
JAVA="$APP/java/de/privacyguard/adhook/imported/shield"
python3 - "$APP/AndroidManifest.xml" "$JAVA" "$APP/java/de/privacyguard/adhook/MainActivity.java" "$APP/java/de/privacyguard/adhook/FxNativeTabActivity.java" "$APP/java/de/privacyguard/adhook/FxNativeAppShell.kt" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

manifest_path, shield_dir, main_path, tab_host_path, shell_path = map(Path, sys.argv[1:])
main = main_path.read_text(encoding="utf-8")
tab_host = tab_host_path.read_text(encoding="utf-8")
shell = shell_path.read_text(encoding="utf-8")
manifest = ET.parse(manifest_path).getroot()
android = "{http://schemas.android.com/apk/res/android}"
# The six primary destinations are fixed and index-compatible across Web/native pages.
labels = 'listOf("VPN", "Ad", "隐私", "脚本", "Hook", "设置")'
assert labels in shell, "Native app shell must expose exactly the six fixed FX tabs in order"
assert "tabsCount = labels.size" in shell, "Glass navigation must use the same six-tab model"
assert ".height(72.dp)" in shell, "Native six-tab bar height contract changed unexpectedly"
assert "index < 0 || index > 5" in tab_host, "Native tab host must reject indices outside 0..5"
assert "Math.max(0, Math.min(5, selectedIndex))" in tab_host, "Native tab host must clamp selected index to six destinations"
assert "handleImportedNativeTabIntent" in main and "tab >= 0 && tab <= 5" in main, "Native pages must route back to the fixed six-tab MainActivity"
for token in ("if (index == 5)", "else if (index == 4)", "else if (index >= 0 && index <= 3)"):
    assert token in main, f"MainActivity top-level tab route missing: {token}"
declared = {
    item.attrib.get(android + "name", "")
    for item in manifest.findall("./application/activity")
}
pages = {
    "FxYulongVirusDatabaseActivity.java": ".imported.shield.FxYulongVirusDatabaseActivity",
    "FxYulongScanActivity.java": ".imported.shield.FxYulongScanActivity",
    "FxYulongIntegrityActivity.java": ".imported.shield.FxYulongIntegrityActivity",
    "FxYulongRescueActivity.java": ".imported.shield.FxYulongRescueActivity",
    "FxYulongBatchCleanupActivity.java": ".imported.shield.FxYulongBatchCleanupActivity",
    "FxYulongScreenFilterActivity.java": ".imported.shield.FxYulongScreenFilterActivity",
    "FxYulongDailySummaryActivity.java": ".imported.shield.FxYulongDailySummaryActivity",
    "FxYulongWarningActivity.java": ".imported.shield.FxYulongWarningActivity",
    "WhitelistActivity.java": ".imported.shield.WhitelistActivity",
    "WhitelistPickerActivity.java": ".imported.shield.WhitelistPickerActivity",
    "BlacklistActivity.java": ".imported.shield.BlacklistActivity",
}
for filename, component in pages.items():
    assert any(name == component or name.endswith(component) for name in declared), (
        f"Manifest Activity missing: {component}"
    )
    source = (shield_dir / filename).read_text(encoding="utf-8")
    assert "extends de.privacyguard.adhook.FxNativeTabActivity {" in source, (
        f"{filename}: page must use the shared six-tab Activity host"
    )
    assert "setContentViewWithNativeTabs(root, 2);" in source, (
        f"{filename}: page must install the shared native tab shell for the Privacy destination"
    )
    assert "setContentView(root);" not in source, (
        f"{filename}: page bypasses the shared native tab shell"
    )
    assert source.count("setContentViewWithNativeTabs(root, 2);") == 1, (
        f"{filename}: expected exactly one Privacy-tab root installation"
    )

scan = (shield_dir / "FxYulongScanActivity.java").read_text(encoding="utf-8")
rescue = (shield_dir / "FxYulongRescueActivity.java").read_text(encoding="utf-8")
hub = (shield_dir / "FxYulongShieldActivity.java").read_text(encoding="utf-8")
assert 'text("隐私 · 安全防护中心"' in hub, "Shield hub must use the FX Privacy product identity"
assert "setContentViewWithNativeTabs(root, 2);" in hub, "Shield hub must select the Privacy tab"
black = (shield_dir / "BlacklistActivity.java").read_text(encoding="utf-8")
assert "STATE_FINDING_PACKAGES" in scan and "onSaveInstanceState" in scan
assert "Intent.ACTION_DELETE" in scan and 'setPositiveButton("打开系统确认"' in scan
assert "Intent.ACTION_DELETE" in rescue
assert "FxYulongRescueActivity.class" in hub
assert "FxYulongDailySummaryActivity.class" in hub

# Rescue Center can be launched from either the Shield Hub or the persistent notification.
service = (shield_dir / "FxYulongRescueOverlayService.java").read_text(encoding="utf-8")
assert "Intent open=new Intent(this,FxYulongRescueActivity.class);" in service
assert "open.putExtra(FxYulongRescueActivity.EXTRA_OPENED_FROM_NOTIFICATION, true);" in service
assert "Intent open=new Intent(this,FxYulongShieldActivity.class);" in service, "floating bubble must continue opening the Shield Hub"
assert "getIntent().getBooleanExtra(EXTRA_OPENED_FROM_NOTIFICATION, false)" in rescue
assert "Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP" in rescue
assert "// Hub-launched rescue screens simply finish to the existing caller." in rescue, "Hub-origin Rescue Center must return to its existing caller"
assert "finish();" in rescue, "Hub-origin Rescue Center must finish rather than create a duplicate Hub"
assert "FxYulongWarningActivity.class" in scan
assert "FxYulongVirusDatabaseActivity.class" in hub
for key in ("STATE_PICKER_OPEN", "STATE_PICKER_QUERY", "STATE_PICKER_PAGE", "STATE_PICKER_STAGED", "STATE_PICKER_SCROLL_Y"):
    assert key in black, f"Blacklist picker state missing: {key}"
assert "pickerDialogOpen = savedInstanceState.getBoolean(STATE_PICKER_OPEN, false)" in black
assert "if (pickerDialogOpen) showAppPicker(true)" in black, "picker must reopen after app inventory is restored"
assert "scroll.post(() -> scroll.scrollTo(0, restorePickerY))" in black
assert "if (!isChangingConfigurations())" in black, "configuration recreation must not discard picker draft"
assert "currentBlacklist.addAll(staged)" in black, "only explicit confirmation may commit staged packages"
assert "pickerStaged.clear();" in black, "dismissed/cancelled picker draft must be cleared"
assert "FxYulongScanActivity.class" in hub
daily = (shield_dir / "FxYulongDailySummaryActivity.java").read_text(encoding="utf-8")
for token in ("shield_prefs", "automatic_scan_last_result", "FxYulongProtectionService", "FxYulongRescueOverlayService"):
    assert token in daily, f"daily summary data source missing: {token}"
assert 'body.addView(button("返回安全护盾首页",this::finish));' in daily
assert 'body.addView(button("返回安全护盾首页",()->startActivity(new Intent(this,FxYulongShieldActivity.class))));' not in daily
assert r'+"\\n"' not in daily, "daily summary must render real line breaks, not literal \\n"
assert r'+"\n"' in daily, "daily summary service/permission lines must use newline separators"
warning = (shield_dir / "FxYulongWarningActivity.java").read_text(encoding="utf-8")
for token in ("MAX_PACKAGE_NAME", "MAX_WHITELIST_CHARS", "Intent.ACTION_DELETE",
              "WHITELIST_KEY", "AlertDialog", "package:"):
    assert token in warning, f"warning confirmation/safety contract missing: {token}"
print("PASS: Shield database/scan/integrity/rescue/daily-summary/warning pages retain six-tab shell and existing navigation/result/removal contracts")
PY
