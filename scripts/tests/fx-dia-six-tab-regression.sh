#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="$ROOT/adhook/app/src/main"
JAVA="$APP/java/de/privacyguard/adhook/imported/dia"
python3 - "$APP/AndroidManifest.xml" "$JAVA" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

manifest_path, dia_dir = Path(sys.argv[1]), Path(sys.argv[2])
manifest = ET.parse(manifest_path).getroot()
android = "{http://schemas.android.com/apk/res/android}"
declared = {
    item.attrib.get(android + "name", "")
    for item in manifest.findall("./application/activity")
}
pages = {
    "FxDiaActivityBrowserActivity.java": ".imported.dia.FxDiaActivityBrowserActivity",
    "FxDiaFridaActivity.java": ".imported.dia.FxDiaFridaActivity",
    "FxDiaScriptLibraryActivity.java": ".imported.dia.FxDiaScriptLibraryActivity",
    "FxDiaInspectorActivity.java": ".imported.dia.FxDiaInspectorActivity",
    "FxDiaCodeEditorActivity.java": ".imported.dia.FxDiaCodeEditorActivity",
    "FxDiaJsonActivity.java": ".imported.dia.FxDiaJsonActivity",
    "FxDiaMonitorEventsActivity.java": ".imported.dia.FxDiaMonitorEventsActivity",
    "FxDiaBackupActivity.java": ".imported.dia.FxDiaBackupActivity",
    "FxDiaGlobalSettingsActivity.java": ".imported.dia.FxDiaGlobalSettingsActivity",
    "FxDiaSessionLogActivity.java": ".imported.dia.FxDiaSessionLogActivity",
}
for filename, component in pages.items():
    assert any(name == component or name.endswith(component) for name in declared), (
        f"Manifest Activity missing: {component}"
    )
    source = (dia_dir / filename).read_text(encoding="utf-8")
    assert "extends de.privacyguard.adhook.FxNativeTabActivity {" in source, (
        f"{filename}: page must use shared six-tab Activity host"
    )
    assert "setContentViewWithNativeTabs(root, 5);" in source, (
        f"{filename}: page must install shared native tab shell"
    )
    assert "setContentView(root);" not in source, (
        f"{filename}: page bypasses shared native tab shell"
    )
    assert source.count("setContentViewWithNativeTabs(root, 5);") == 1, (
        f"{filename}: expected one root shell installation"
    )

# Keep existing browser-to-inspector, Frida, script-library and editor entry points.
browser = (dia_dir / "FxDiaActivityBrowserActivity.java").read_text(encoding="utf-8")
frida = (dia_dir / "FxDiaFridaActivity.java").read_text(encoding="utf-8")
library = (dia_dir / "FxDiaScriptLibraryActivity.java").read_text(encoding="utf-8")
assert "FxDiaInspectorActivity.class" in browser
assert "FxDiaCodeEditorActivity.class" in library
assert "FxDiaScriptLibraryActivity.class" in frida
print("PASS: Dia browser/Frida/script library/inspector/editor/JSON/monitor pages retain six-tab shell and native routes")
PY
