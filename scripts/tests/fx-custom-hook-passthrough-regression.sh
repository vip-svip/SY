#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
RULE="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/DeveloperHookRule.java"
HOOK="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
MAIN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
UNIT="$ROOT/adhook/app/src/test/java/de/privacyguard/adhook/DeveloperHookRuleTest.java"
PARSER_UNIT="$ROOT/adhook/app/src/test/java/de/privacyguard/adhook/UnifiedHookConfigParserTest.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for file in "$RULE" "$HOOK" "$MAIN" "$UNIT" "$PARSER_UNIT"; do [ -s "$file" ] || fail "missing custom Hook source $file"; done
grep -Fq 'RETURN_ARGUMENT_0' "$RULE" || fail "exact argument passthrough parser action missing"
grep -Fq 'RETURN_THIS' "$RULE" || fail "receiver passthrough parser action missing"
grep -Fq 'parsed.parameterDescriptors.get(0)' "$RULE" || fail "first argument descriptor equality gate missing"
grep -Fq 'method.getReturnType() != parameterTypes[0]' "$HOOK" || fail "runtime argument type identity gate missing"
grep -Fq 'Modifier.isStatic(method.getModifiers())' "$HOOK" || fail "receiver static-method exclusion missing"
grep -Fq 'method.getReturnType().isAssignableFrom(method.getDeclaringClass())' "$HOOK" || fail "receiver return assignability gate missing"
grep -Fq 'MemberTestGate.isEnabled' "$HOOK" || fail "debuggable target and explicit opt-in gate missing"
grep -Fq 'installDeveloperPassthroughHook' "$HOOK" || fail "passthrough actions are not connected to the runtime"
grep -Fq 'RETURN_ARGUMENT_0' "$MAIN" && grep -Fq 'RETURN_THIS' "$MAIN" || fail "native Hook editor doesn't expose passthrough actions"
grep -Fq 'acceptsReturnFirstArgumentOnlyForExactMatchingTypes' "$UNIT" || fail "argument passthrough unit tests missing"
grep -Fq 'acceptsReturnThisOnlyForObjectReturningMethods' "$UNIT" || fail "receiver passthrough unit tests missing"
grep -Fq '清除分组和搜索筛选' "$MAIN" || fail "custom Hook filter reset control missing"
grep -Fq 'groupFilter.setSelection(0)' "$MAIN" || fail "custom Hook filter reset does not clear group selection"
grep -Fq '(parts.length == 5 ? " " + parts[4] : "")' "$MAIN" || fail "custom Hook search omits literal values"
grep -Fq 'DeveloperHookRule.normalizeDescriptor(rawDescriptor, selectedPackage)' "$MAIN" || fail "custom Hook editor has no live signature normalization preview"
grep -Fq '签名有效 · JVM：' "$MAIN" || fail "custom Hook editor normalized signature preview missing"
grep -Fq '签名尚未通过校验' "$MAIN" || fail "custom Hook editor invalid signature feedback missing"
grep -Fq 'Runnable refreshValidation = () ->' "$MAIN" || fail "custom Hook editor live validation callback missing"
grep -Fq 'validationStatus.setText("校验通过 · "' "$MAIN" || fail "custom Hook editor valid-signature feedback missing"
grep -Fq 'refreshValidation.run();' "$MAIN" || fail "custom Hook editor validation refresh missing"
grep -Fq 'getCustomRuleSlots' "$MAIN" || fail "custom Hook UI does not enumerate persisted rule slots dynamically"
grep -Fq 'getCustomRulePreferenceKeys' "$MAIN" || fail "custom Hook import/rollback does not enumerate preference keys dynamically"
if grep -Eq 'for \(int (i|n|slot) = 1; (i|n|slot) <= 64' "$MAIN"; then
    fail "custom Hook UI still scans a fixed 64-slot range"
fi
if grep -Eq '最多 64 条规则|最多配置 64 条自定义规则|当前应用最多保存 64 条规则' "$MAIN"; then
    fail "custom Hook UI still advertises a 64-rule cap"
fi
python3 - "$MAIN" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
start = source.index("private void showCustomRuleImportDialog()")
end = source.index("\n    private ", start + 20)
dialog = source[start:end]
assert "LengthFilter" not in dialog, "custom Hook JSON import still has an editor character ceiling"
assert "65536" not in dialog and "64 KiB" not in dialog, "custom Hook JSON import still has a fixed payload ceiling"
assert "new org.json.JSONArray(raw)" in dialog and "new org.json.JSONObject(raw)" in dialog
print("PASS: custom Hook JSON import has no fixed character or UTF-8 payload cap")
PY
grep -Fq 'parserAndSerializerRoundTripMoreThanSixtyFourDeveloperRules' "$PARSER_UNIT" || fail "more-than-64 parser/serializer unit coverage missing"
grep -Fq 'acceptsSparseLegacyDeveloperRuleSlotsAboveSixtyFour' "$PARSER_UNIT" || fail "sparse legacy slot compatibility test missing"
python3 - "$MAIN" <<'PY'
from pathlib import Path
import re
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
assert "getCustomRuleSlots" in source, "dynamic rule slot enumeration missing"
assert "getCustomRulePreferenceKeys" in source, "dynamic import rollback key enumeration missing"
assert "getCustomRuleSlots(p)" in source, "publish path still omits dynamic rule slots"
assert "getCustomRulePreferenceKeys(selectedPackage, candidates.size())" in source, "import cleanup does not cover new compacted slots"
for fixed_loop in (
    "for (int i = 1; i <= 64; i++)",
    "for (int n = 1; n <= 64; n++)",
    "for (int slot = 1; slot <= 64; slot++)",
):
    assert fixed_loop not in source, "fixed 64-slot loop remains: " + fixed_loop
assert "最多 64 条规则" not in source and "最多配置 64 条自定义规则" not in source
print("PASS: editor, grouping, import/export, render and publish enumerate custom rules dynamically")
PY
echo "PASS: custom Hook passthrough actions are exact-type, debuggable-only, explicit-opt-in and fail-closed"
