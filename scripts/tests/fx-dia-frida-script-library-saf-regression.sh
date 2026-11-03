#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java"
[ -s "$ACTIVITY" ] || { echo "FAIL: Dia Frida Activity source missing" >&2; exit 1; }
python3 - "$ACTIVITY" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
required = {
    "export request code": "REQUEST_EXPORT_LIBRARY = 7105",
    "import request code": "REQUEST_IMPORT_LIBRARY = 7106",
    "bounded JSON import/export": "MAX_LIBRARY_JSON_BYTES = 1024 * 1024",
    "create-document export": "Intent.ACTION_CREATE_DOCUMENT",
    "open-document import": "Intent.ACTION_OPEN_DOCUMENT",
    "JSON MIME export": 'create.setType("application/json")',
    "JSON MIME import": 'pick.setType("application/json")',
    "real SAF export callback": "requestCode == REQUEST_EXPORT_LIBRARY",
    "real SAF import callback": "requestCode == REQUEST_IMPORT_LIBRARY",
    "bounded streaming import": "MAX_LIBRARY_JSON_BYTES - count",
    "schema validation": '"FX-DIA-FRIDA-SCRIPTS-1".equals(root.optString("schema"))',
    "bounded per-script import": "source.getBytes(StandardCharsets.UTF_8).length > 128 * 1024",
    "duplicate name merge persistence": "writeFridaScriptLibrary(merged)",
    "private-cache export staging": 'File.createTempFile(PENDING_LIBRARY_EXPORT_PREFIX, ".tmp", getCacheDir())',
    "private-cache export path validation": "resolvePendingFridaLibraryExport(stagedName)",
    "streamed SAF export": "new java.io.FileInputStream(staged)",
    "cancel-safe export cleanup": "deletePendingFridaLibraryExport(stagedName)",
    "rotation saves only filename": "outState.putString(STATE_PENDING_LIBRARY_EXPORT, pendingFridaLibraryExportFileName)",
    "rotation restores filename": "state.getString(STATE_PENDING_LIBRARY_EXPORT)",
    "stale private-cache cleanup": "cleanupStalePendingLibraryExports(pendingFridaLibraryExportFileName)",
    "clipboard remains explicitly separate": "copyFridaScriptLibraryJson()",
}
for label, needle in required.items():
    if needle not in source:
        raise SystemExit(f"FAIL: missing {label}: {needle}")
if "导出脚本库 JSON 文件" not in source or "从 JSON 文件批量导入脚本库" not in source:
    raise SystemExit("FAIL: Frida script library UI does not expose file import/export")
if "exportFridaScriptLibrary() {\n        try {\n            org.json.JSONObject root" in source:
    raise SystemExit("FAIL: script library export still bypasses the SAF file picker")
if "pendingFridaLibraryExport;" in source or "outState.putString(STATE_PENDING_LIBRARY_EXPORT, pendingFridaLibraryExport)" in source:
    raise SystemExit("FAIL: script library JSON payload is stored directly in Activity state Bundle")
if not re.search(r"pendingFridaLibraryExportFileName = staged.getName\(\)", source):
    raise SystemExit("FAIL: staged export file name is not tracked for Activity restoration")
if "importFridaScriptLibrary() {\n        EditText input" in source:
    raise SystemExit("FAIL: primary script library import still only uses clipboard paste")
print("PASS: Dia Frida script library supports bounded SAF JSON import/export, cancellation and rotation state")
PY
