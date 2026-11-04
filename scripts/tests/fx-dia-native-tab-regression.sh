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
print("PASS: nine Dia independent pages retain the shared six-tab shell")
PY
