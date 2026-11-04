#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
RULE="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/DeveloperHookRule.java"
HOOK="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
MAIN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
UNIT="$ROOT/adhook/app/src/test/java/de/privacyguard/adhook/DeveloperHookRuleTest.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for file in "$RULE" "$HOOK" "$MAIN" "$UNIT"; do [ -s "$file" ] || fail "missing custom Hook source $file"; done
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
echo "PASS: custom Hook passthrough actions are exact-type, debuggable-only, explicit-opt-in and fail-closed"
