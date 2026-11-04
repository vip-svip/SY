#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
JAVA="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia"
ACTIVITY="$JAVA/FxDiaScriptLibraryActivity.java"
STORE="$JAVA/FxDiaScriptLibraryStore.java"
POLICY="$JAVA/FxDiaScriptLibraryPolicy.java"
MAIN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
MANIFEST="$ROOT/adhook/app/src/main/AndroidManifest.xml"
HOST_TEST="$ROOT/scripts/tests/FxDiaScriptLibraryPolicyHostTest.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for file in "$ACTIVITY" "$STORE" "$POLICY" "$MAIN" "$MANIFEST" "$HOST_TEST"; do
  [ -s "$file" ] || fail "Dia script-library source missing: $file"
done
grep -Fq 'case "JS 脚本列表":' "$MAIN" || fail "JS script list route is missing"
grep -Fq 'FxDiaScriptLibraryActivity.class' "$MAIN" || fail "script pages do not route to the dedicated native Activity"
grep -Fq 'open_new_script' "$MAIN" || fail "script editor route does not open the native editor flow"
grep -Fq 'android:name=".imported.dia.FxDiaScriptLibraryActivity" android:exported="false"' "$MANIFEST" || fail "private script-library Activity is not registered"
grep -Fq 'fx_dia_frida' "$STORE" || fail "script library does not share the original Frida preference file"
grep -Fq 'frida_script_library_v1' "$STORE" || fail "script library does not preserve the existing storage key"
grep -Fq 'FX-DIA-FRIDA-SCRIPTS-1' "$STORE" || fail "script-library JSON compatibility schema changed"
grep -Fq 'startActivityForResult(intent, REQUEST_EDITOR)' "$ACTIVITY" || fail "script editing does not use the existing full-screen editor"
grep -Fq 'mergeImport' "$ACTIVITY" || fail "JSON library import is not connected"
grep -Fq 'exportJson' "$ACTIVITY" || fail "JSON library export is not connected"
grep -Fq '不会自动执行' "$ACTIVITY" || fail "script library does not disclose non-executing behavior"
python3 - "$ACTIVITY" "$STORE" <<'PY'
from pathlib import Path
import sys
activity, store = [Path(p).read_text(encoding="utf-8") for p in sys.argv[1:]]
assert "REQUEST_IMPORT" in activity and "REQUEST_EXPORT" in activity
assert "MAX_LIBRARY_JSON_BYTES - count" in activity, "import stream must have a hard byte limit"
assert "SharedPreferences.MODE_PRIVATE" in store, "script data must remain private to FX"
assert "commit()" in store, "script writes must confirm persistence"
assert "validateScripts" in store and "validateSource" in store, "reads and imports must reject invalid entries"
assert "synchronized (LOCK)" in store, "script-library read/modify/write operations must be serialized"
print("PASS: Dia script library routes, persistent CRUD, editor, bounded JSON import/export")
PY
