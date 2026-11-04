#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="$ROOT/adhook/app/src/main"
JAVA="$APP/java/de/privacyguard/adhook/imported/shield"
python3 - "$APP/AndroidManifest.xml" "$JAVA" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

manifest_path, shield_dir = Path(sys.argv[1]), Path(sys.argv[2])
manifest = ET.parse(manifest_path).getroot()
android = "{http://schemas.android.com/apk/res/android}"
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
    assert "setContentViewWithNativeTabs(root, 5);" in source, (
        f"{filename}: page must install the shared native tab shell"
    )
    assert "setContentView(root);" not in source, (
        f"{filename}: page bypasses the shared native tab shell"
    )
    assert source.count("setContentViewWithNativeTabs(root, 5);") == 1, (
        f"{filename}: expected exactly one six-tab root installation"
    )

scan = (shield_dir / "FxYulongScanActivity.java").read_text(encoding="utf-8")
rescue = (shield_dir / "FxYulongRescueActivity.java").read_text(encoding="utf-8")
hub = (shield_dir / "FxYulongShieldActivity.java").read_text(encoding="utf-8")
black = (shield_dir / "BlacklistActivity.java").read_text(encoding="utf-8")
assert "STATE_FINDING_PACKAGES" in scan and "onSaveInstanceState" in scan
assert "Intent.ACTION_DELETE" in scan and 'setPositiveButton("打开系统确认"' in scan
assert "Intent.ACTION_DELETE" in rescue
assert "FxYulongRescueActivity.class" in hub
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
print("PASS: Shield database/scan/integrity/rescue pages retain six-tab shell and existing navigation/result/removal contracts")
PY
