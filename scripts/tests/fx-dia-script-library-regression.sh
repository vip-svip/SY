#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
JAVA="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia"
ACTIVITY="$JAVA/FxDiaScriptLibraryActivity.java"
STORE="$JAVA/FxDiaScriptLibraryStore.java"
POLICY="$JAVA/FxDiaScriptLibraryPolicy.java"
FRIDA="$JAVA/FxDiaFridaActivity.java"
MAIN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
MANIFEST="$ROOT/adhook/app/src/main/AndroidManifest.xml"
HOST_TEST="$ROOT/scripts/tests/FxDiaScriptLibraryPolicyHostTest.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for file in "$ACTIVITY" "$STORE" "$POLICY" "$MAIN" "$MANIFEST" "$HOST_TEST"; do
  [ -s "$file" ] || fail "Dia script-library source missing: $file"
done
grep -Fq 'Frida JavaScript 脚本库' "$MAIN" || fail "native Frida script-library entry is missing"
grep -Fq 'FxDiaScriptLibraryActivity.class' "$MAIN" || fail "script pages do not route to the dedicated native Activity"
grep -Fq 'getBooleanExtra("open_new_script"' "$ACTIVITY" || fail "native script-library Activity does not preserve the optional initial-editor intent"
grep -Fq 'android:name=".imported.dia.FxDiaScriptLibraryActivity" android:exported="false"' "$MANIFEST" || fail "private script-library Activity is not registered"
grep -Fq 'fx_dia_frida' "$STORE" || fail "script library does not share the original Frida preference file"
grep -Fq 'frida_script_library_v1' "$STORE" || fail "script library does not preserve the existing storage key"
grep -Fq 'FX-DIA-FRIDA-SCRIPTS-1' "$STORE" || fail "script-library JSON compatibility schema changed"
grep -Fq 'if (context == null) throw new IllegalArgumentException("Context 为空。");' "$STORE" || fail "save must reject a null Context with a stable argument error"
grep -Fq 'if (context == null) throw new IllegalArgumentException("Context 为空。");' "$STORE" || fail "export must reject a null Context with a stable argument error"
grep -Fq 'if (context == null) throw new IllegalArgumentException("Context 为空。");' "$STORE" || fail "import preview must reject a null Context with a stable argument error"
grep -Fq 'startActivityForResult(intent, REQUEST_EDITOR)' "$ACTIVITY" || fail "script editing does not use the existing full-screen editor"
grep -Fq 'editorRequestPending = true;' "$ACTIVITY" || fail "script editor request is not tracked"
grep -Fq 'editorRequestPending = false;' "$ACTIVITY" || fail "script editor request is not consumed or rolled back"
grep -Fq 'STATE_EDITOR_REQUEST_PENDING' "$ACTIVITY" || fail "script editor request is not restored across Activity recreation"
grep -Fq 'STATE_IMPORT_REQUEST_PENDING' "$ACTIVITY" || fail "SAF import request is not restored across Activity recreation"
grep -Fq 'STATE_EXPORT_REQUEST_PENDING' "$ACTIVITY" || fail "SAF export request is not restored across Activity recreation"
grep -Fq 'STATE_PENDING_IMPORT_URI' "$ACTIVITY" || fail "pending import preview URI is not restored across Activity recreation"
grep -Fq 'takePersistableUriPermission(uri, grantFlags)' "$ACTIVITY" || fail "SAF import URI is not retained when provider grants persistence"
grep -Fq 'if (pendingImportUri != null) importFrom(pendingImportUri);' "$ACTIVITY" || fail "restored import preview is not revalidated and shown again"
grep -Fq 'clearPendingImportUri()' "$ACTIVITY" || fail "pending SAF import grant is not released after the preview lifecycle"
grep -Fq 'releasePersistableUriPermission' "$ACTIVITY" || fail "persisted SAF import permission is not released"
grep -Fq 'importRequestPending = true;' "$ACTIVITY" || fail "SAF import request is not tracked"
grep -Fq 'exportRequestPending = true;' "$ACTIVITY" || fail "SAF export request is not tracked"
grep -Fq 'mergeImport' "$ACTIVITY" || fail "JSON library import is not connected"
grep -Fq 'FxDiaScriptLibraryStore.mergeImport(this, json, preview.overwrittenNames)' "$ACTIVITY" || fail "confirmed overwrite preview is not passed to the atomic merge"
python3 - "$ACTIVITY" <<'PY'
from pathlib import Path
import sys
activity = Path(sys.argv[1]).read_text(encoding="utf-8")
assert 'String.join("、", preview.overwrittenNames)' in activity, "import preview must show every same-name script"
assert 'preview.overwrittenNames.size() > 5' not in activity, "complete conflict preview must not append a misleading truncation suffix"
PY
grep -Fq 'exportJson' "$ACTIVITY" || fail "JSON library export is not connected"
grep -Fq '不会自动执行' "$ACTIVITY" || fail "script library does not disclose non-executing behavior"
python3 - "$ACTIVITY" "$STORE" "$FRIDA" "$POLICY" "$HOST_TEST" <<'PY'
from pathlib import Path
import sys
activity, store, frida, policy, host = [Path(p).read_text(encoding="utf-8") for p in sys.argv[1:]]
for signature in (
    "public static void save(Context context, String rawName, String source) throws Exception",
    "public static String exportJson(Context context) throws Exception",
    "public static ImportPreview previewImport(Context context, String json) throws Exception",
):
    start = store.index(signature)
    body = store[start:store.index("\n    }", start)]
    assert "if (context == null) throw new IllegalArgumentException(\"Context 为空。\");" in body, f"{signature} must reject null Context consistently"
assert "REQUEST_IMPORT" in activity and "REQUEST_EXPORT" in activity
assert "MAX_LIBRARY_JSON_BYTES" not in activity, "script-library import must not impose an arbitrary byte limit"
assert "InputFilter.LengthFilter(64)" not in activity, "script names must not have an arbitrary UI length cap"
assert "createNameDraft.length() > 64" not in activity, "script names must not be truncated when Activity state is saved"
assert "FxDiaScriptLibraryPolicy.decodeUtf8(output.toByteArray())" in activity, "JSON import must use strict UTF-8 decoding"
assert "newDecoder()" in policy and "CodingErrorAction.REPORT" in policy, "JSON decoder must reject malformed UTF-8 instead of silently replacing bytes"
assert "malformed UTF-8 must be rejected" in host, "host policy test must cover malformed UTF-8 rejection"
editor_start = activity.index("if (requestCode == REQUEST_EDITOR)")
saf_start = activity.index("if (resultCode != RESULT_OK || data == null || data.getData() == null)")
editor_result = activity[editor_start:saf_start]
assert editor_start < saf_start, "custom editor result must be handled before requiring a SAF Uri"
assert "FxDiaCodeEditorActivity.RESULT_CODE_EDITOR" in editor_result, "custom editor result code is ignored"
assert "if (!editorRequestPending)" in editor_result, "stale editor result must not be accepted without a pending request"
assert "editorRequestPending = false;" in editor_result, "editor result must consume the pending request before processing data"
assert "catch (RuntimeException error)" in activity and "editingName = null;" in activity, "editor launch failure must clear request ownership and pending name"
assert "out.putBoolean(STATE_EDITOR_REQUEST_PENDING, editorRequestPending);" in activity, "editor request ownership must survive Activity recreation"
assert "if (!importRequestPending)" in activity and "importRequestPending = false;" in activity, "stale SAF import results must be rejected and request consumed"
assert "if (!exportRequestPending)" in activity and "exportRequestPending = false;" in activity, "stale SAF export results must be rejected and request consumed"
assert "out.putBoolean(STATE_IMPORT_REQUEST_PENDING, importRequestPending);" in activity
assert "out.putBoolean(STATE_EXPORT_REQUEST_PENDING, exportRequestPending);" in activity
assert "out.putString(STATE_PENDING_IMPORT_URI, pendingImportUri.toString());" in activity, "pending import preview URI must survive Activity recreation"
assert "STATE_PENDING_IMPORT_URI_PERSISTED" in activity, "persistable read grant ownership must be restored"
assert "Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION" in activity, "ACTION_OPEN_DOCUMENT must request persistable access"
assert "takePersistableUriPermission(uri, grantFlags)" in activity, "SAF result grant must be persisted when supported"
assert "if (pendingImportUri != null) importFrom(pendingImportUri);" in activity, "restored pending preview must be regenerated after the library loads"
assert '.setNegativeButton("取消", (dialog, which) -> clearPendingImportUri())' in activity, "cancelling preview must release its URI grant"
assert "clearPendingImportUri();" in activity, "confirmation/failure/finish must clear the retained import URI"
assert "getStringExtra(FxDiaCodeEditorActivity.EXTRA_CODE)" in editor_result, "edited source is not read from the result Intent"
assert "FxDiaScriptLibraryStore.save(this, name, source)" in editor_result, "edited source is not persisted to the shared script library"
assert "Context.MODE_PRIVATE" in store, "script data must remain private to FX"
assert "commit()" in store, "script writes must confirm persistence"
assert "validateScripts" in store and "validateSource" in store, "reads and imports must reject invalid entries"
assert "MAX_" not in policy and "MAX_" not in store and "MAX_LIBRARY_JSON_BYTES" not in frida, "script-library data must not have arbitrary capacity constants"
assert "scripts.length() >" not in store, "script count must not be capped"
assert "synchronized (LOCK)" in store, "script-library read/modify/write operations must be serialized"
assert "instanceof String" in store, "non-string JSON values must be rejected"
assert "replaceAll(Context context" in store, "shared storage replace API is missing"
assert "FxDiaScriptLibraryStore.read(this)" in frida, "legacy Frida page bypasses shared store"
assert "FxDiaScriptLibraryStore.save(this, label, source)" in frida, "legacy Frida save bypasses shared validation"
assert "FxDiaScriptLibraryStore.delete(this, name)" in frida, "legacy Frida delete bypasses shared locking"
assert "FxDiaScriptLibraryStore.mergeImport(this, json, confirmedOverwrites)" in frida, "legacy Frida import bypasses shared validation"
print("PASS: dedicated and legacy Frida pages share one validated, serialized script-library store")
PY

if command -v javac >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT HUP INT TERM
  javac -d "$tmp" "$POLICY" "$HOST_TEST"
  java -cp "$tmp" FxDiaScriptLibraryPolicyHostTest
else
  echo "SKIP: host JVM policy test (JDK unavailable)"
fi
