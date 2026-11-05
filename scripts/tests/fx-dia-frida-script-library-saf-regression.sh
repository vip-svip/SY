#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java"
LIBRARY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaScriptLibraryActivity.java"
STORE="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaScriptLibraryStore.java"
POLICY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaScriptLibraryPolicy.java"
[ -s "$ACTIVITY" ] || { echo "FAIL: Dia Frida Activity source missing" >&2; exit 1; }
[ -s "$LIBRARY" ] || { echo "FAIL: Dia Frida script-library Activity source missing" >&2; exit 1; }
[ -s "$STORE" ] || { echo "FAIL: Dia Frida script-library store missing" >&2; exit 1; }
[ -s "$POLICY" ] || { echo "FAIL: Dia Frida script-library policy missing" >&2; exit 1; }
python3 - "$ACTIVITY" "$LIBRARY" "$STORE" "$POLICY" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
library = Path(sys.argv[2]).read_text(encoding="utf-8")

# Reject duplicate method tails accidentally emitted after the Activity class
# closes. This catches Java syntax errors that otherwise cascade hundreds of
# "class, interface, enum, or record expected" diagnostics.
def assert_single_java_class_body(source):
    depth = 0
    state = "code"
    escaped = False
    class_closed_at = None
    i = 0
    while i < len(source):
        ch = source[i]
        nxt = source[i + 1] if i + 1 < len(source) else ""
        if state == "line_comment":
            if ch == "\n":
                state = "code"
        elif state == "block_comment":
            if ch == "*" and nxt == "/":
                state = "code"
                i += 1
        elif state in ("string", "char"):
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif (state == "string" and ch == '"') or (state == "char" and ch == "'"):
                state = "code"
        else:
            if ch == "/" and nxt == "/":
                state = "line_comment"
                i += 1
            elif ch == "/" and nxt == "*":
                state = "block_comment"
                i += 1
            elif ch == '"':
                state = "string"
            elif ch == "'":
                state = "char"
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                assert depth >= 0, "script library has an unmatched closing brace"
                if depth == 0:
                    class_closed_at = i
                    trailing = source[i + 1:].strip()
                    assert not trailing, "script library contains code after its Activity class closes"
        i += 1
    assert depth == 0 and class_closed_at is not None, "script library Activity braces are unbalanced"
assert_single_java_class_body(library)

store = Path(sys.argv[3]).read_text(encoding="utf-8")
policy = Path(sys.argv[4]).read_text(encoding="utf-8")
required = {
    "export request code": "REQUEST_EXPORT_LIBRARY = 7105",
    "import request code": "REQUEST_IMPORT_LIBRARY = 7106",
    "create-document export": "Intent.ACTION_CREATE_DOCUMENT",
    "open-document import": "Intent.ACTION_OPEN_DOCUMENT",
    "JSON MIME export": 'create.setType("application/json")',
    "JSON MIME import": 'pick.setType("application/json")',
    "real SAF export callback": "requestCode == REQUEST_EXPORT_LIBRARY",
    "real SAF import callback": "requestCode == REQUEST_IMPORT_LIBRARY",
    "strict UTF-8 decoding for JSON SAF imports": "FxDiaScriptLibraryPolicy.decodeUtf8(output.toByteArray())",
    "strict UTF-8 decoding for standalone JS SAF imports": "String source = FxDiaScriptLibraryPolicy.decodeUtf8(output.toByteArray())",
    "private-cache export staging": 'File.createTempFile(PENDING_LIBRARY_EXPORT_PREFIX, ".tmp", getCacheDir())',
    "private-cache export path validation": "resolvePendingFridaLibraryExport(stagedName)",
    "streamed SAF export": "new java.io.FileInputStream(staged)",
    "cancel-safe export cleanup": "deletePendingFridaLibraryExport(stagedName)",
    "rotation saves only filename": "outState.putString(STATE_PENDING_LIBRARY_EXPORT, pendingFridaLibraryExportFileName)",
    "rotation restores filename": "state.getString(STATE_PENDING_LIBRARY_EXPORT)",
    "large script draft cache": "new android.util.AtomicFile(new File(getCacheDir(), SCRIPT_DRAFT_CACHE_NAME))",
    "large script draft Bundle marker": "outState.putBoolean(STATE_SCRIPT_DRAFT_FILE, true)",
    "large script draft restore": "readTransientFridaScriptDraft()",
    "large script draft atomic write": "atomic.finishWrite(output)",
    "large script draft rollback": "atomic.failWrite(output)",
    "large draft cache requires Bundle ownership marker": "if (state == null || !state.getBoolean(STATE_SCRIPT_DRAFT_FILE, false))",
    "corrupt draft cache removed after read failure": "// Do not let a corrupt cache be retried as a valid draft forever.",
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
if "new String(output.toByteArray(), StandardCharsets.UTF_8)" in source[source.index("private String readTransientFridaScriptDraft()"):source.index("private void deleteTransientFridaScriptDraft()")]:
    raise SystemExit("FAIL: large Frida draft restore duplicates the entire byte payload in memory")
if "new java.io.InputStreamReader(" not in source[source.index("private String readTransientFridaScriptDraft()"):source.index("private void deleteTransientFridaScriptDraft()")]:
    raise SystemExit("FAIL: large Frida draft restore is not incrementally decoded")

store_required = {
    "stable JSON schema": 'public static final String SCHEMA = "FX-DIA-FRIDA-SCRIPTS-1"',
    "legacy stored schema validation": "if (!schema.isEmpty() && !SCHEMA.equals(schema))",
    "strict imported schema validation": 'if (!SCHEMA.equals(root.optString("schema", "")))',
    "same-name overlap preview": "if (existing.has(name)) overlaps.add(name)",
    "confirmed overwrite guard": "if (merged.has(name) && !confirmed.contains(name)) unconfirmed.add(name)",
    "merge persists under store lock": "writeLocked(context, merged)",
}
for label, needle in store_required.items():
    if needle not in store:
        raise SystemExit(f"FAIL: missing store {label}: {needle}")
if "MAX_" in policy or "MAX_" in store or "MAX_LIBRARY_JSON_BYTES" in source or "MAX_LIBRARY_JSON_BYTES" in library:
    raise SystemExit("FAIL: arbitrary script-library name/source/count/JSON capacity cap remains")
if "MAX_FRIDA_DRAFT_BYTES" in source or "512 * 1024" in source or "128 * 1024" in source:
    raise SystemExit("FAIL: legacy Frida save/import/export/draft still has an arbitrary size cap")
for label, needle in {
    "file import previews overlaps": "previewAndImportFridaScriptLibraryJson(json)",
    "clipboard import previews overlaps": "previewAndImportFridaScriptLibraryJson(input.getText().toString())",
    "preview lists overwritten names": "preview.overwrittenNames",
    "overwrite requires explicit confirmation": "确认覆盖并导入",
    "only previewed names may be overwritten": "mergeFridaScriptLibraryJson(json, preview.overwrittenNames)",
    "store merge receives confirmation list": "FxDiaScriptLibraryStore.mergeImport(this, json, confirmedOverwrites)",
}.items():
    if needle not in source:
        raise SystemExit(f"FAIL: missing import overwrite safety {label}: {needle}")
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
print("PASS: Dia Frida script library supports unbounded SAF JSON import/export, cancellation and rotation state")

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
    "create name draft saved without truncation": "out.putString(STATE_CREATE_NAME_DRAFT, createNameDraft)",
    "create name draft restored into input": "input.setText(createNameDraft)",
    "create dialog reopens after reload": "else if (createDialogRestorePending) {\n                    createScript();",
    "create dialog clears on explicit cancel": '.setNegativeButton("取消", (d, which) -> clearCreateScriptDialogState())',
    "rotation cancel retains pending draft": "if (!isChangingConfigurations()) clearCreateScriptDialogState();",
}.items():
    if needle not in library:
        raise SystemExit(f"FAIL: script library state restoration missing {label}: {needle}")
if "InputFilter.LengthFilter(64)" in library or "createNameDraft.length() > 64" in library:
    raise SystemExit("FAIL: script name length cap remains in the native create dialog or rotation state")
if "openingInitialEditor = state.getBoolean(STATE_OPENING_INITIAL_EDITOR" not in library:
    raise SystemExit("FAIL: rotation can replay the initial new-script request")
print("PASS: Dia Frida script-library search, scroll, pending editor return and initial-create intent survive recreation")
PY
