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
KEY_POLICY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaKeyGesturePolicy.java"
KEY_REGISTRY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaKeyGesturePolicyRegistry.java"
KEY_HOST_TEST="$ROOT/scripts/tests/FxDiaKeyGesturePolicyHostTest.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for f in "$HOOK" "$PARSER" "$SER" "$UI" "$POLICY" "$POLICY_TEST" "$PARSER_TEST" "$SER_TEST" "$HOST_TEST" "$KEY_POLICY" "$KEY_REGISTRY" "$KEY_HOST_TEST"; do
    [ -s "$f" ] || fail "missing Dialog source: $f"
done
python3 - "$HOOK" "$PARSER" "$SER" "$UI" "$POLICY" "$POLICY_TEST" "$PARSER_TEST" "$SER_TEST" "$KEY_POLICY" "$KEY_REGISTRY" "$KEY_HOST_TEST" <<'PY'
from pathlib import Path
import re, sys
hook, parser, ser, ui, policy, policy_test, parser_test, ser_test, key_policy, key_registry, key_host_test = [
    Path(p).read_text(encoding="utf-8") for p in sys.argv[1:]
]
imports = re.findall(
    r"^import de\.privacyguard\.adhook\.imported\.dia\.FxDiaDialogMatchPolicy;$",
    hook, re.M)
assert len(imports) == 1, f"Dialog policy import count must be one, got {len(imports)}"
key_policy_import = "import de.privacyguard.adhook.imported.dia.FxDiaKeyGesturePolicy;"
assert parser.count(key_policy_import) == 1, "Parser must import the ActivityKey policy exactly once"
assert ser.count(key_policy_import) == 1, "Serializer must import the ActivityKey policy exactly once"

# Native per-app UI and configuration publication.
assert 'case "对话框与通知":' in ui and 'showAppList("Dialog处理")' in ui
assert "showDiaDialogTarget(ai, targetDebuggable)" in ui
for field in ("dialog_match_enabled", "dialog_text_terms", "dialog_id_terms", "dialog_notify"):
    assert field in ui, f"missing per-app preference {field}"
for field in ("dialog_draft_enabled", "dialog_draft_text_terms", "dialog_draft_id_terms", "dialog_draft_notify"):
    assert field in ui, f"missing recoverable Dialog draft field {field}"
assert "textTerms.addTextChangedListener" in ui and "idTerms.addTextChangedListener" in ui
assert ".remove(draftEnabledKey)" in ui and ".remove(draftTextKey)" in ui
assert ".remove(draftIdsKey)" in ui and ".remove(draftNotifyKey)" in ui
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
assert "FLAG_SYSTEM" in ui and "FLAG_UPDATED_SYSTEM_APP" in ui, "system and updated-system apps must not be Toast targets"
assert "FLAG_UPDATED_SYSTEM_APP" in hook and "final boolean toastFilterForPackage = !systemTarget && target != null" in hook

# Unified parser/serializer validation and bounded literal matching.
for key in ("dialog_match", "dialog_notify", "dialog_text_terms_b64", "dialog_id_terms_b64"):
    assert key in parser, f"parser does not consume {key}"
for key in ("toast_filter", "toast_text_terms_b64"):
    assert key in parser, f"parser does not consume {key}"
assert "toast filtering requires explicit text rules" in parser
assert "toast text rules require toast_filter=1" in parser
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

# Native ActivityKey page, config contract and LSPosed dispatch.
assert 'case "按键控制":' in ui and 'showAppList("按键控制")' in ui
assert "showDiaKeyControlTarget(ai)" in ui
assert "动作一：关闭当前 Activity" in ui and "动作二：暂停 / 恢复当前应用的 Dialog 规则" in ui
assert "key_finish_trigger" in ui and "key_dialog_toggle_trigger" in ui
assert "hasOverlappingTriggers(finishTrigger, dialogTrigger)" in ui
assert "Dialog 切换动作需要先有有效的 debuggable Dialog 规则" in ui
assert "FLAG_UPDATED_SYSTEM_APP" in ui and "不会强制停止进程" in ui
assert "key_finish_trigger" in parser and "key_dialog_toggle_trigger" in parser
assert "trigger < -1 || trigger > 6" in parser
assert "keyDialogToggleTrigger >= 0 && !dialogMatchEnabled" in parser
assert "Dia key actions have overlapping gesture triggers" in parser
assert "key_finish_trigger" in ser and "key_dialog_toggle_trigger" in ser
assert "hasOverlappingTriggers(" in ser
assert "Dialog key toggle requires enabled Dialog rules" in ser
assert 'Activity.class.getDeclaredMethod("dispatchKeyEvent", KeyEvent.class)' in hook
assert 'Activity.class.getDeclaredMethod("onKeyLongPress"' in hook
assert "diaKeyGesturePolicies.forPackage(packageName)" in hook
assert "activity.finish();" in hook
assert "diaKeyDialogActive.put(packageName, next)" in hook
assert "Boolean.FALSE.equals(diaKeyDialogActive.get(packageName))" in hook
assert "must never prevent native key dispatch" in hook
assert "computeIfAbsent(packageName" in key_registry
assert "TRIGGER_VOLUME_DOWN_UP_CHORD" in key_policy
assert "MIN_DOUBLE_PRESS_GAP_MS = 200L" in key_policy
assert "CHORD_WINDOW_MS = 400L" in key_policy
assert "hasOverlappingTriggers(int first, int second)" in key_policy
assert "if (firstBack && secondBack) return true" in key_policy
for case in (
    "parsesPerAppActivityKeyActions",
    "legacyTargetsKeepActivityKeyActionsDisabled",
    "rejectsActivityKeyTriggerOutOfRange",
    "rejectsDialogKeyToggleWithoutDialogRules",
    "rejectsTwoActivityKeyActionsWithOverlappingGestures"):
    assert case in parser_test, f"missing ActivityKey Parser test: {case}"
for case in (
    "serializerRoundTripsPerAppActivityKeyActions",
    "serializerRejectsDialogKeyToggleWithoutDialogRules",
    "serializerRejectsTwoActivityKeyActionsWithOverlappingGestures"):
    assert case in ser_test, f"missing ActivityKey Serializer test: {case}"
for marker in (
    "Back long press emits trigger 5",
    "volume-down/up chord emits trigger 6",
    "repeat key-down event is ignored",
    "registry allocates independent gesture state per package",
    "removing a package resets its previous gesture timestamps",
    "volume-down double and triple gestures overlap",
    "Back double and triple gestures overlap",
    "volume-down double can overlap with volume chord",
    "volume-up double can overlap with volume chord",
    "different volume-key double gestures do not overlap",
    "disabled actions do not conflict"):
    assert marker in key_host_test, f"missing key Host case: {marker}"
print("PASS: Dialog, Toast and ActivityKey UI/config/runtime source contracts")
PY

command -v javac >/dev/null 2>&1 || fail "JDK is required for Dialog policy host tests"
command -v java >/dev/null 2>&1 || fail "JRE is required for Dialog policy host tests"
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT HUP INT TERM
javac -Xlint:all -Werror -d "$OUT" "$POLICY" "$HOST_TEST" "$KEY_POLICY" "$KEY_REGISTRY" "$KEY_HOST_TEST"
java -cp "$OUT" de.privacyguard.adhook.imported.dia.FxDiaDialogMatchPolicyHostTest
java -cp "$OUT" de.privacyguard.adhook.imported.dia.FxDiaKeyGesturePolicyHostTest
echo "PASS: Dia Dialog, per-app Toast and ActivityKey integration regression"
