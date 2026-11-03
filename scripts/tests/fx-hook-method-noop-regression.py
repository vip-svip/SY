#!/usr/bin/env python3
"""Source contract for the narrowed Dia MethodActivity migration."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
def read(path):
    target = ROOT / path
    assert target.is_file(), f"missing source: {path}"
    return target.read_text(encoding="utf-8")
rule = read("adhook/app/src/main/java/de/privacyguard/adhook/DeveloperHookRule.java")
assert "NO_OP_VOID" in rule and '"DO_NOTHING".equals(actionText)' in rule
assert '!"V".equals(parsed.returnDescriptor)' in rule and '"<init>".equals(parsed.name)' in rule
assert "this.replacement = action == Action.RETURN_TRUE;" in rule
assert "this.replacement = action == Action.NO_OP_VOID" not in rule
assert "rule.action == DeveloperHookRule.Action.NO_OP_VOID" in read("adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java")
runtime = read("adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java")
assert "rule.action == DeveloperHookRule.Action.NO_OP_VOID" in runtime
assert "installDeveloperVoidNoOpHook(param.getClassLoader(), pkg" in runtime
start = runtime.index("private void installDeveloperVoidNoOpHook(")
end = runtime.index("private void installDeveloperBooleanTestHook(", start)
body = runtime[start:end]
for token in ("MemberTestGate.isEnabled", "targetDeveloperOptIn(packageName)",
              '"V".equals(parsed.returnDescriptor)', "parsed.resolve(loader)",
              "method.getReturnType() != void.class", "Modifier.isAbstract",
              "Modifier.isNative", "XposedInterface.ExceptionMode.PROTECTIVE",
              ".intercept(chain ->", "return null;",
              "developerVoidNoOpHookedExecutables.remove(executable)"):
    assert token in body, f"void no-op runtime contract missing: {token}"
ui = read("adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java")
for token in ('"NO_OP_VOID".equals(actionText)', "NO_OP_VOID 只接受精确 void 方法",
              "NO_OP_VOID 必须是返回 void 的真实方法",
              'if (!debuggable && !"OBSERVE".equals(actionText))'):
    assert token in ui, f"custom Hook UI contract missing: {token}"
tests = read("adhook/app/src/test/java/de/privacyguard/adhook/DeveloperHookRuleTest.java")
assert "acceptsNoOpOnlyForExactVoidMethods" in tests
assert "rejectsNoOpForNonVoidConstructorsAndLegacyAmbiguousSignatures" in tests
serializer = read("adhook/app/src/test/java/de/privacyguard/adhook/UnifiedHookConfigSerializerTest.java")
assert "serializerRoundTripsDebugOnlyVoidNoOpAction" in serializer
print("PASS: Dia MethodActivity safe NO_OP_VOID source, UI gate, parser and serializer contracts")
