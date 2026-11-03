#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
I="$ROOT/scripts/install_adhook_app.sh"; P="$ROOT/fx-module/scripts/install_adhook_app.sh"; A="$ROOT/docs/FXHOOK-SINGLE-APK-MERGE-AUDIT.md"
fail(){ echo "FAIL: $*" >&2; exit 1; }
MERGE="$ROOT/fx-patches/merge_hook_single_apk.py"
[ -s "$MERGE" ] || fail "unified manifest merger source missing"
python3 - "$MERGE" <<'PY'
import ast
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
module = ast.parse(text, filename=str(path))
calls = []
for node in ast.walk(module):
    if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
            and node.func.attr == "write_text" and len(node.args) >= 1):
        target = node.func.value
        if isinstance(target, ast.Name) and target.id == "manifest":
            calls.append(node)
assert len(calls) == 1, "manifest serializer must have one explicit write path"
constants = [node.value for node in ast.walk(calls[0].args[0])
             if isinstance(node, ast.Constant) and isinstance(node.value, str)]
assert constants and constants[0].startswith('<?xml version="1.0" encoding="utf-8"?>\\n'), \
    "manifest serializer must write a real newline after its XML declaration"
assert "\\n" in constants, "manifest serializer must use a real newline separator"
assert "\\\\n" not in text, "double-escaped newline would corrupt the generated XML declaration"
print("PASS: merged manifest serializer emits valid XML line breaks")
PY
cmp -s "$I" "$P" || fail "module installer drift"
grep -Fq 'optional/FXUnifiedHook.apk' "$I" || fail "unified APK install path missing"
! grep -Eq 'optional/(PrivacyGuardHook|FXAdHook)\.apk|install_one de\.privacyguard\.hook' "$I" || fail "stale two-APK installer remains"
grep -Fq 'de.privacyguard.adhook.AdVisibilityHook' "$ROOT/adhook/app/src/main/resources/META-INF/xposed/java_init.list" || fail "modern entrypoint missing"
grep -Fq 'de.privacyguard.hook.MainHook' "$ROOT/fx-module/lsposed/app/src/main/assets/xposed_init" || fail "legacy entrypoint missing"
grep -Fq '75' "$A" || fail "legacy migration caveat missing"
echo "PASS: one installer APK and both runtime entrypoints are present"
