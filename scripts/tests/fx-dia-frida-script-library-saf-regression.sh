#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java"
LIBRARY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaScriptLibraryActivity.java"
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
    "large script draft cache": "new android.util.AtomicFile(new File(getCacheDir(), SCRIPT_DRAFT_CACHE_NAME))",
    "large script draft size cap": "MAX_FRIDA_DRAFT_BYTES = 512 * 1024",
    "large script draft Bundle marker": "outState.putBoolean(STATE_SCRIPT_DRAFT_FILE, true)",
    "large script draft restore": "readTransientFridaScriptDraft()",
    "large script draft atomic write": "atomic.finishWrite(output)",
    "large script draft rollback": "atomic.failWrite(output)",
    "large draft cache requires Bundle ownership marker": "if (state == null || !state.getBoolean(STATE_SCRIPT_DRAFT_FILE, false))",
    "corrupt draft cache removed after read failure": "// Do not let a corrupt/oversized cache be retried as a valid draft forever.",
    "failed or oversized new draft removes previous cache": "// A failed write can roll back to an older AtomicFile.",
    "stale private-cache cleanup": "cleanupStalePendingLibraryExports(pendingFridaLibraryExportFileName)",
    "clipboard remains explicitly separate": "copyFridaScriptLibraryJson()",
    "Activity destruction marks worker cancellation": "activityDestroyed = true;\n        targetLoadGeneration++;",
    "worker cancellation checks both lifecycle and interrupt": "activityDestroyed || Thread.currentThread().isInterrupted()",
    "worker import/export loops check cancellation": "ensureFridaWorkerActive();",
    "script export success callback checks Activity lifecycle": 'if (isFinishing() || isDestroyed()) return;\n                    setStatus("当前 JS 脚本已导出。");',
    "script export failure callback checks Activity lifecycle": 'if (isFinishing() || isDestroyed()) return;\n                    setStatus("JS 脚本导出失败："',
}
for label, needle in required.items():
    if needle not in source:
        raise SystemExit(f"FAIL: missing {label}: {needle}")
if source.count("ensureFridaWorkerActive();") < 5:
    raise SystemExit("FAIL: large SAF read/write and binary install paths must check cancellation")
if "导出脚本库 JSON 文件" not in source or "从 JSON 文件批量导入脚本库" not in source:
    raise SystemExit("FAIL: Frida script library UI does not expose file import/export")
if "exportFridaScriptLibrary() {\n        try {\n            org.json.JSONObject root" in source:
    raise SystemExit("FAIL: script library export still bypasses the SAF file picker")
if "已有脚本库导出请求等待系统文件选择器返回" not in source:
    raise SystemExit("FAIL: a second SAF export may overwrite the pending staged filename")
if "pendingFridaLibraryExport;" in source or "outState.putString(STATE_PENDING_LIBRARY_EXPORT, pendingFridaLibraryExport)" in source:
    raise SystemExit("FAIL: script library JSON payload is stored directly in Activity state Bundle")
if "pendingFridaLibraryExportFileName = staged.getName()" not in source:
    raise SystemExit("FAIL: staged export file name is not tracked for Activity restoration")
if 'if (isFinishing()) deleteTransientFridaScriptDraft();' not in source:
    raise SystemExit("FAIL: private large-script draft cache is not cleaned on Activity finish")
if "importFridaScriptLibrary() {\n        EditText input" in source:
    raise SystemExit("FAIL: primary script library import still only uses clipboard paste")
print("PASS: Dia Frida script library supports bounded SAF JSON import/export, cancellation and rotation state")

library = Path(sys.argv[1].replace("FxDiaFridaActivity.java", "FxDiaScriptLibraryActivity.java")).read_text(encoding="utf-8")
for label, needle in {
    "search query saved": "out.putString(STATE_SEARCH",
    "search query restored": 'state.getString(STATE_SEARCH, "")',
    "scroll offset saved": "out.putInt(STATE_SCROLL_Y",
    "scroll offset restored after async reload": "libraryScroll.post(() -> libraryScroll.scrollTo(0, restoredScrollY))",
    "initial new-script request state saved": "out.putBoolean(STATE_OPENING_INITIAL_EDITOR, openingInitialEditor)",
    "initial new-script request state restored": "state.getBoolean(STATE_OPENING_INITIAL_EDITOR",
    "editor return target preserved": "out.putString(STATE_EDITING_NAME, editingName)",
    "create dialog pending state saved": "out.putBoolean(STATE_CREATE_DIALOG_PENDING, createDialogRestorePending)",
    "create dialog pending state restored": "state.getBoolean(STATE_CREATE_DIALOG_PENDING, false)",
    "create name draft saved": "out.putString(STATE_CREATE_NAME_DRAFT, createNameDraft.length() > 64",
    "create name draft restored into input": "input.setText(createNameDraft)",
    "create dialog reopens after reload": "else if (createDialogRestorePending) {\n                    createScript();",
    "create dialog input bounded": "new android.text.InputFilter.LengthFilter(64)",
    "create dialog clears on explicit cancel": '.setNegativeButton("取消", (d, which) -> clearCreateScriptDialogState())',
    "rotation cancel retains pending draft": "if (!isChangingConfigurations()) clearCreateScriptDialogState();",
}.items():
    if needle not in library:
        raise SystemExit(f"FAIL: script library state restoration missing {label}: {needle}")
if "openingInitialEditor = state.getBoolean(STATE_OPENING_INITIAL_EDITOR" not in library:
    raise SystemExit("FAIL: rotation can replay the initial new-script request")
print("PASS: Dia Frida script-library search, scroll, pending editor return and initial-create intent survive recreation")
PY
