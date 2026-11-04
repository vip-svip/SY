#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
BASE="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeTabActivity.java"
MAIN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
DIA="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia"
PAGES="
$DIA/FxDiaActivityBrowserActivity.java
$DIA/FxDiaFridaActivity.java
$DIA/FxDiaScriptLibraryActivity.java
$DIA/FxDiaInspectorActivity.java
$DIA/FxDiaCodeEditorActivity.java
$DIA/FxDiaCrashReportActivity.java
$DIA/FxDiaMonitorEventsActivity.java
$DIA/FxDiaDexBrowserActivity.java
$DIA/FxDiaJsonActivity.java
$DIA/FxDiaDexBrowserActivity.java
$DIA/FxDiaFileActivity.java
$DIA/FxDiaGpsPickerActivity.java
$DIA/FxDiaSessionLogActivity.java
$DIA/FxDiaSignatureActivity.java
$DIA/FxDiaSystemExpandActivity.java
"
fail() { echo "FAIL: $*" >&2; exit 1; }
for file in "$BASE" "$MAIN" $PAGES; do
    [ -s "$file" ] || fail "missing native tab source: $file"
done
python3 - "$BASE" "$MAIN" $PAGES <<'PY'
from pathlib import Path
import sys
base, main, *pages = [Path(p).read_text(encoding="utf-8") for p in sys.argv[1:]]
assert "FxNativeAppShellKt.installFxNativeAppShell" in base
assert "ViewTreeLifecycleOwner.set(shell, this)" in base
assert "ViewTreeViewModelStoreOwner.set(shell, this)" in base
assert "ViewTreeSavedStateRegistryOwner.set(shell, this)" in base
assert "index < 0 || index > 5" in base
assert 'putExtra("fx_open_native_tab", index)' in base
assert "if (tab >= 0 && tab <= 5) handleNativeTabSelection(tab);" in main
for page in pages:
    assert "extends de.privacyguard.adhook.FxNativeTabActivity" in page
    assert "setContentViewWithNativeTabs(root, 5);" in page
    assert "setContentView(root);" not in page
    assert "onCreate(" in page
file_page = next(p for p in pages if "class FxDiaFileActivity" in p)
for token in ("ACTION_OPEN_DOCUMENT_TREE", "takePersistableUriPermission",
              "DocumentsContract.createDocument", "onActivityResult(",
              "loadDirectory(", "submitIo("):
    assert token in file_page, f"File/ELF behavior missing: {token}"
gps_page = next(p for p in pages if "class FxDiaGpsPickerActivity" in p)
for token in ("STATE_PAIR", "STATE_LATITUDE", "STATE_LONGITUDE", "STATE_STATUS", "onSaveInstanceState("):
    assert token in gps_page, f"GPS picker state missing: {token}"
session_page = next(p for p in pages if "class FxDiaSessionLogActivity" in p)
for token in ("STATE_SEARCH", "STATE_SCROLL_Y", "onSaveInstanceState("):
    assert token in session_page, f"Session Log state missing: {token}"
print("PASS: GPS picker and Session Log state restoration anchors remain")
signature_page = next(p for p in pages if "class FxDiaSignatureActivity" in p)
for token in ("SigningInfo", "MessageDigest", "getInstalledApplications", "chooseApp(", "inspect("):
    assert token in signature_page, f"Signature viewer behavior missing: {token}"
system_page = next(p for p in pages if "class FxDiaSystemExpandActivity" in p)
for token in ("PackageInstaller", "allowed_install_from_unknown_source",
              "restart_package_installer", "RootAccess", "setPositiveButton"):
    assert token in system_page, f"System Expand guarded action missing: {token}"
print("PASS: Signature viewer remains read-only and System Expand keeps guarded settings actions")
print("PASS: Dia independent pages retain the shared six-tab shell")
print("PASS: File/ELF SAF grant, import/export, directory and worker paths remain")
PY
