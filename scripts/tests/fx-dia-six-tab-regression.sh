#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="$ROOT/adhook/app/src/main"
JAVA="$APP/java/de/privacyguard/adhook/imported/dia"
python3 - "$APP/AndroidManifest.xml" "$JAVA" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

manifest_path, dia_dir, shell_path = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
shell = shell_path.read_text(encoding="utf-8")
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
    "FxDiaCrashReportActivity.java": ".imported.dia.FxDiaCrashReportActivity",
    "FxDiaDexBrowserActivity.java": ".imported.dia.FxDiaDexBrowserActivity",
    "FxDiaFileActivity.java": ".imported.dia.FxDiaFileActivity",
    "FxDiaSignatureActivity.java": ".imported.dia.FxDiaSignatureActivity",
    "FxDiaSystemExpandActivity.java": ".imported.dia.FxDiaSystemExpandActivity",
    "FxDiaWifiProxyActivity.java": ".imported.dia.FxDiaWifiProxyActivity",
    "FxDiaGpsPickerActivity.java": ".imported.dia.FxDiaGpsPickerActivity",
}
assert "import androidx.compose.foundation.layout.navigationBarsPadding" in shell, "native tab shell must import Android navigation insets"
assert "import androidx.compose.foundation.layout.imePadding" in shell, "native tab shell must import IME insets"
assert shell.count(".imePadding()") == 1, "shared native host must apply IME avoidance exactly once"
root_box = shell[shell.index("Box(\n            Modifier"):shell.index("            // Record the real page")]
assert ".fillMaxSize()" in root_box and ".imePadding()" in root_box, "page and six-tab bar must move above the soft keyboard"
assert root_box.index(".imePadding()") < root_box.index(".background("), "IME inset must constrain the shared host, not only decorate the background"
assert 'listOf("VPN", "Ad", "隐私", "脚本", "Hook", "设置")' in shell, "native shell must keep the fixed six primary tabs in the required order"
assert "selectedIndex.coerceIn(0, 5)" in shell, "native shell must clamp tab selection to the six-tab range"
assert shell.count(".navigationBarsPadding()") == 3, "page content and both bottom bar variants must account for navigation insets"
assert shell.index(".navigationBarsPadding()") < shell.index(".padding(bottom = 72.dp)"), "native page viewport must reserve system navigation and tab bar"
bar_section = shell[shell.index('if (mode == "glass")'):]
assert bar_section.count(".navigationBarsPadding()") == 2, "glass and classic/Miuix bottom bars must both avoid the system gesture area"
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
assert 'button("打开 Frida 脚本库", () -> showFridaScriptLibrary())' in frida, "Frida page must retain its native script-library entry"
assert "private void showFridaScriptLibrary()" in frida, "Frida script-library screen must remain implemented in the native page"
print("PASS: Dia browser/Frida/script library/inspector/editor/JSON/monitor pages retain six-tab shell and native routes")
PY
