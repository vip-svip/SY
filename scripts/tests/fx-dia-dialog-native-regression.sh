#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HOOK="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
PARSER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
SER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java"
UI="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
POLICY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaDialogMatchPolicy.java"
POLICY_TEST="$ROOT/adhook/app/src/test/java/de/privacyguard/adhook/imported/dia/FxDiaDialogMatchPolicyTest.java"
PARSER_TEST="$ROOT/adhook/app/src/test/java/de/privacyguard/adhook/UnifiedHookConfigParserTest.java"
SER_TEST="$ROOT/adhook/app/src/test/java/de/privacyguard/adhook/UnifiedHookConfigSerializerTest.java"
HOST_TEST="$ROOT/scripts/tests/FxDiaDialogMatchPolicyHostTest.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for f in "$HOOK" "$PARSER" "$SER" "$UI" "$POLICY" "$POLICY_TEST" "$PARSER_TEST" "$SER_TEST" "$HOST_TEST"; do
    [ -s "$f" ] || fail "missing Dialog source: $f"
done
python3 - "$HOOK" "$PARSER" "$SER" "$UI" "$POLICY" "$POLICY_TEST" "$PARSER_TEST" "$SER_TEST" <<'PY'
from pathlib import Path
import re, sys
hook, parser, ser, ui, policy, policy_test, parser_test, ser_test = [
    Path(p).read_text(encoding="utf-8") for p in sys.argv[1:]
]
imports = re.findall(
    r"^import de\.privacyguard\.adhook\.imported\.dia\.FxDiaDialogMatchPolicy;$",
    hook, re.M)
assert len(imports) == 1, f"Dialog policy import count must be one, got {len(imports)}"

# Native per-app UI and configuration publication.
assert 'case "对话框与通知":' in ui and 'showAppList("Dialog处理")' in ui
assert "showDiaDialogTarget(ai, targetDebuggable)" in ui
for field in ("dialog_match_enabled", "dialog_text_terms", "dialog_id_terms", "dialog_notify"):
    assert field in ui, f"missing per-app preference {field}"
assert "dialog_text_terms_b64=" in ui and "dialog_id_terms_b64=" in ui
assert "文本规则与资源 ID 规则各最多 32 条" in ui
assert "targetDebuggable &&" in ui, "publish path must re-check debuggable targets"

# Toast filtering is a separate opt-in feature from Dialog feedback and NotificationListener.
assert 'addNativeActionCard("Toast 文本过滤"' in ui, "Privacy page Toast card missing"
assert 'showAppList("Toast过滤")' in ui, "Toast per-app target list missing"
assert "showDiaToastTarget(ai)" in ui, "Toast native target page is not routed"
for field in ("toast_filter_enabled", "toast_text_terms", "toast_filter_draft_enabled", "toast_filter_draft_terms"):
    assert field in ui, f"missing Toast preference/draft field {field}"
assert "Toast 规则未能写入本地存储" in ui and "toast_filter=1,toast_text_terms_b64=" in ui
assert "(ai.flags & ApplicationInfo.FLAG_SYSTEM) == 0" in ui, "system app Toast publishing must stay disabled"

# Unified parser/serializer validation and bounded literal matching.
for key in ("dialog_match", "dialog_notify", "dialog_text_terms_b64", "dialog_id_terms_b64"):
for key in ("toast_filter", "toast_text_terms_b64"):
    assert key in parser, f"parser does not consume {key}"
assert "toast filtering requires explicit text rules" in parser
assert "toast text rules require toast_filter=1" in parser
    assert key in parser, f"parser does not consume {key}"
assert "dialogNotify && !dialogMatchEnabled" in parser
assert "dialog_notify" in ser and "dialog rules/feedback require dialogMatchEnabled" in ser
assert "MAX_TERMS = 32" in policy and "MAX_RAW_UTF8_BYTES = 1024" in policy
assert "MAX_TEXT_CHARS = 4096" in policy
assert "matchesResourceIdExactly" in policy_test

# Toast runtime is opt-in, per package, and fail-open without accessible text.
assert "target.toastFilterEnabled && !target.toastTextTerms.isEmpty()" in hook
assert "if (toastFilterForPackage) installDiaToastHooks();" in hook
assert 'Toast.class.getDeclaredMethod("show")' in hook
assert 'boolean isMakeText = "makeText".equals(name)' in hook
assert 'boolean isSetText = "setText".equals(name)' in hook
assert 'boolean isSetView = "setView".equals(name)' in hook
assert "findToastTextMatch(view, rules.toastTextTerms" in hook
assert "payload.text, rules.toastTextTerms" in hook
assert "Toast text filter failed open" in hook
assert "Never log Toast text or matched rule contents" in hook
assert "dia-toast-block package=" in hook

# Real runtime path: package scope, WindowManager pre-attach and Dialog.show pre-check.
assert "target.dialogMatchEnabled && debuggableTarget" in hook
assert "private UnifiedHookConfigParser.Target dialogRulesFor" in hook
assert 'Class.forName("android.view.WindowManagerImpl"' in hook
assert '"addView".equals(method.getName())' in hook
assert "dialogWindowAddViewMethods.contains(key)" in hook
assert "findDialogRuleMatch(root, target, new int[]{512}, 0)" in hook
assert "WindowManager.addView Dialog check failed open" in hook
assert "Dialog.class.getDeclaredMethod(\"show\")" in hook
assert "dialogRules == null || fullScreen ? null" in hook
assert "dialog pre-display match failed open" in hook
assert "dialogNotifyLastShown.put(packageName, now)" in hook
assert "now - previous < 3000L" in hook

# Parser/serializer regression cases cover defaults, invalid configurations and round trips.
for case in (
    "parsesPerAppToastFilterRules",
    "legacyTargetsDoNotEnableToastFiltering",
    "rejectsToastFilterWithoutExplicitTerms",
    "rejectsToastTermsWhenFilteringIsDisabled",
    "parsesExplicitDialogTextAndResourceRulesWithOptionalFeedback",
    "legacyTargetsDoNotEnableDialogHandlingOrFeedback",
    "rejectsDialogMatchWithoutExplicitRules",
    "rejectsDialogFeedbackWhenMatchingIsDisabled"):
    assert case in parser_test, f"missing Parser test: {case}"
for case in (
    "serializerRoundTripsPerAppToastFilterRules",
    "serializerRejectsToastTermsWhenFilteringIsDisabled",
    "serializerRoundTripsDialogRulesAndFeedbackPerTarget",
    "serializerRejectsDialogFeedbackWithoutEnabledMatcher"):
    assert case in ser_test, f"missing Serializer test: {case}"
print("PASS: Dialog UI/config/runtime source contracts")
PY

command -v javac >/dev/null 2>&1 || fail "JDK is required for Dialog policy host tests"
command -v java >/dev/null 2>&1 || fail "JRE is required for Dialog policy host tests"
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT HUP INT TERM
javac -Xlint:all -Werror -d "$OUT" "$POLICY" "$HOST_TEST"
java -cp "$OUT" de.privacyguard.adhook.imported.dia.FxDiaDialogMatchPolicyHostTest
echo "PASS: Dia native Dialog integration regression"
