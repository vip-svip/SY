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
import_start = ui.index("private void showCustomRuleImportDialog()")
import_end = ui.index("private ApplicationInfo findApp(", import_start)
import_ui = ui[import_start:import_end]
assert '"NO_OP_VOID".equals(action)' in import_ui, \
    "portable rule-group importer must accept exported NO_OP_VOID actions"
assert 'if (!debugBuild && !"OBSERVE".equals(action)' in import_ui, \
    "imported behavior replacements, including NO_OP_VOID, must remain debuggable-only"
tests = read("adhook/app/src/test/java/de/privacyguard/adhook/DeveloperHookRuleTest.java")
assert "acceptsNoOpOnlyForExactVoidMethods" in tests
assert "rejectsNoOpForNonVoidConstructorsAndLegacyAmbiguousSignatures" in tests
serializer = read("adhook/app/src/test/java/de/privacyguard/adhook/UnifiedHookConfigSerializerTest.java")
assert "serializerRoundTripsDebugOnlyVoidNoOpAction" in serializer
runtime = read("adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java")
observe_start = runtime.index("private void installDeveloperObservationHook(")
observe_end = runtime.index("private void logDeveloperObservation(", observe_start)
observe = runtime[observe_start:observe_end]
assert "logDeveloperObservation(Log.INFO" in observe and "logDeveloperObservation(Log.WARN" in observe, \
    "OBSERVE hit and exception metadata must reach Android logcat"
logger_start = runtime.index("private void logDeveloperObservation(")
logger_end = runtime.index("private boolean targetDeveloperOptIn(", logger_start)
logger = runtime[logger_start:logger_end]
assert "Log.println(priority, TAG, message)" in logger and "logFx(priority, message)" in logger, \
    "OBSERVE events must retain module logging and also reach logcat"
for token in ("arg.getClass().getName()", "result.getClass().getName()", "durationUs=", "exception="):
    assert token in observe, f"OBSERVE metadata field missing: {token}"
assert "arg.toString()" not in observe and "result.toString()" not in observe, \
    "OBSERVE must not serialize argument or result values"
main = read("adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java")
assert 'observeLogs.setText("查看 OBSERVE 方法日志")' in main, \
    "per-target Hook page must expose the OBSERVE log viewer"
viewer_start = main.index("private void showCustomHookObservationLogs()")
viewer_end = main.index("private void renderCustomRules()", viewer_start)
viewer = main[viewer_start:viewer_end]
for token in ("logcat -d -v threadtime -t 5000", "'dev-observe'",
              'shellQuote("package=" + packageName + " executable=")',
              "tail -n 300", "output.length() > 24000"):
    assert token in viewer, f"bounded package-scoped OBSERVE log reader missing: {token}"
print("PASS: Dia MethodActivity safe NO_OP_VOID source, UI gate, parser and serializer contracts")
