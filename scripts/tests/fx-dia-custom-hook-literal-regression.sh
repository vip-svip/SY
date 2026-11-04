#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
JAVA="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook"
MAIN="$JAVA/MainActivity.java"
RULE="$JAVA/DeveloperHookRule.java"
ENGINE="$JAVA/AdVisibilityHook.java"
SER="$JAVA/UnifiedHookConfigSerializer.java"
PARSER="$JAVA/UnifiedHookConfigParser.java"
LOGS="$JAVA/FxHookObservationLogsActivity.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for f in "$MAIN" "$RULE" "$ENGINE" "$SER" "$PARSER" "$LOGS"; do [ -s "$f" ] || fail "missing Hook literal source: $f"; done
grep -Fq 'RETURN_LITERAL' "$RULE" || fail "rule model lacks typed literal action"
grep -Fq 'parseLiteralValue' "$RULE" || fail "literal type/range validator is missing"
grep -Fq 'literalValue.getText().toString()' "$MAIN" || fail "native editor does not collect a constant value"
grep -Fq 'item.put("value", parts[4])' "$MAIN" || fail "portable JSON export loses literal values"
grep -Fq 'rawLiteral instanceof String' "$MAIN" || fail "portable JSON import does not validate literal field"
grep -Fq 'rule.toEncodedString()' "$SER" || fail "serializer does not preserve literal payload"
grep -Fq 'installDeveloperLiteralReturnHook' "$ENGINE" || fail "runtime does not install typed literal returns"
grep -Fq 'MemberTestGate.isEnabled' "$ENGINE" || fail "literal runtime must retain debuggable and explicit opt-in gate"
grep -Fq 'new BigInteger' "$RULE" || fail "integer literal parsing must be range checked"
grep -Fq 'new BigDecimal' "$RULE" || fail "floating-point literal parsing must be finite checked"
grep -Fq 'pausedLiteralRuleKeepsItsValueAndRemainsInert' "$ROOT/adhook/app/src/test/java/de/privacyguard/adhook/DeveloperHookRuleTest.java" || fail "paused literal compatibility test missing"
python3 - "$MAIN" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
editor_start = source.index("private void showCustomRuleDialog(String presetDescriptor, int editingSlot)")
editor_end = source.index("\n    private ", editor_start + 20)
editor = source[editor_start:editor_end]
for token in (
    '":dev_rule_editor_draft_"',
    'draftIdentity.equals(getPreferences(0).getString',
    'draftPrefix + "id"', 'draftPrefix + "descriptor"', 'draftPrefix + "literal"',
    'draftPrefix + "group"', 'draftPrefix + "priority"',
    'draftPrefix + "syntax"', 'draftPrefix + "action"',
    'id.addTextChangedListener(draftWatcher)',
    'descriptor.addTextChangedListener(draftWatcher)',
    'literalValue.addTextChangedListener(draftWatcher)',
    'group.addTextChangedListener(draftWatcher)',
    'priority.addTextChangedListener(draftWatcher)',
    'editor.remove(draftPrefix + field)',
):
    assert token in editor, f"custom rule editor draft recovery missing {token}"
assert "if (!editor.commit())" in editor, "rule editor must commit before clearing its recoverable draft"
import_start = source.index("private void showCustomRuleImportDialog()")
import_end = source.index("\n    private ", import_start + 20)
importer = source[import_start:import_end]
for token in (
    '":dev_rule_import_json_draft"',
    'getPreferences(0).getString(importDraftKey, "")',
    'input.addTextChangedListener(',
    'editor.remove(importDraftKey)',
    'if (!editor.commit())',
):
    assert token in importer, f"custom rule import draft/atomic persistence missing {token}"
assert "editor.apply()" not in importer, "rule import must not report success after an unchecked async write"
PY
echo "PASS: typed constant returns are validated; custom-rule editor/import drafts recover and import commits atomically"
python3 - "$LOGS" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
for token in (
    "extends FxNativeTabActivity",
    "setContentViewWithNativeTabs(root, 4);",
    'button("‹ 返回", this::finish)',
    'state.getString("fx_hook_observe_search", "")',
    'state.getInt("fx_hook_observe_scroll_y", 0)',
    'search.setText(restoredSearch)',
    'search.addTextChangedListener(',
    'outState.putString("fx_hook_observe_search"',
    'outState.putInt("fx_hook_observe_scroll_y"',
    'restoreScrollPending ? restoredScrollY',
    'logScroll.post(() -> logScroll.scrollTo(0, previousScrollY))',
):
    assert token in source, f"OBSERVE log state restoration missing {token}"
assert "worker.shutdownNow()" in source and "generation++" in source, \
    "log refresh worker must still be cancelled on Activity teardown"
PY
echo "PASS: Hook OBSERVE search filter and log scroll position survive Activity recreation"
python3 - "$MAIN" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
for token in (
    'state.getBoolean("fx_custom_rule_import_open", false)',
    'outState.putBoolean("fx_custom_rule_import_open", true)',
    'customRuleImportDialogOpen = true',
    'customRuleImportDialogOpen = false',
    'else if (customRuleImportRestorePending)',
    'showCustomRuleImportDialog();',
    'setOnCancelListener(dialog -> {',
):
    assert token in source, f"custom-rule import dialog recreation missing {token}"
assert "customRuleImportRestorePending = false;" in source, \
    "cancel/submit must clear pending import-dialog restoration state"
PY
echo "PASS: Hook custom-rule JSON import dialog reopens with its persisted draft after Activity recreation"
python3 - "$MAIN" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
assert "customRuleGroupDialogRestorePending" in source
assert 'state.getString("fx_custom_rule_group_dialog_mode")' in source
assert 'outState.putString("fx_custom_rule_group_dialog_mode", customRuleGroupDialogMode)' in source
assert 'else if (customRuleGroupDialogRestorePending)' in source
assert 'private void clearCustomRuleGroupDialogState()' in source
add_start = source.index("private void showAddCustomRuleGroupDialog()")
add_end = source.index("\n    private ", add_start + 20)
add = source[add_start:add_end]
for token in (
    '":dev_rule_group_add_draft"',
    'getPreferences(0).getString(draftKey, "")',
    'input.addTextChangedListener(',
    'if (!ensureCustomRuleGroup(value))',
):
    assert token in add, f"add-group draft/commit behavior missing {token}"
ensure_start = source.index("private boolean ensureCustomRuleGroup(")
ensure_end = source.index("\n    private ", ensure_start + 20)
assert "commitCustomRuleGroupUpdate(" in source[ensure_start:ensure_end], "group creation must use the checked atomic update path"
helper_start = source.index("private boolean commitCustomRuleGroupUpdate(")
helper_end = source.index("\\n    private ", helper_start + 20)
helper = source[helper_start:helper_end]
assert "if (update.commit())" in helper and "lastCustomRuleGroupRollbackSaved = rollback.commit()" in helper, \\
    "group updates must synchronously commit and verify rollback on storage failure"
rename_start = source.index("private void showRenameCustomRuleGroupDialog(String oldName)")
rename_end = source.index("\n    private ", rename_start + 20)
rename = source[rename_start:rename_end]
assert '":dev_rule_group_rename_draft:" + oldName' in rename
assert "input.addTextChangedListener(" in rename
picker_start = source.index("private void showCustomRuleGroupPicker(int slot)")
picker_end = source.index("\n    private ", picker_start + 20)
assert '.putString(key, group).commit()' in source[picker_start:picker_end], \
    "moving a rule between groups must report a synchronous persistence result"
PY
echo "PASS: Hook add/rename/move group forms preserve drafts and commit group changes atomically"
python3 - "$MAIN" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
for token in (
    'outState.putInt("fx_custom_rule_group_dialog_slot", customRuleGroupDialogSlot)',
    'outState.putInt("fx_custom_rule_group_dialog_choice", customRuleGroupDialogChoice)',
    'state.getInt("fx_custom_rule_group_dialog_slot", -1)',
    'state.getInt("fx_custom_rule_group_dialog_choice", 0)',
    'else if ("list".equals(mode)) showCustomRuleGroupsDialog()',
    'else if ("actions".equals(mode) && value != null) showCustomRuleGroupActions(value)',
    'else if ("delete".equals(mode) && value != null) showDeleteCustomRuleGroupConfirmation(value)',
    'else if ("picker".equals(mode) && customRuleGroupDialogSlot > 0)',
    'customRuleGroupDialogChoice = which',
    'private void showDeleteCustomRuleGroupConfirmation(String groupName)',
):
    assert token in source, f"rule group nested-dialog state missing {token}"
picker_start = source.index("private void showCustomRuleGroupPicker(int slot, int restoreChoice)")
picker_end = source.index("\n    private ", picker_start + 20)
picker = source[picker_start:picker_end]
assert "restoreChoice" in picker and "customRuleGroupDialogChoice = which" in picker
assert "commitCustomRuleGroupUpdate(" in picker or ".putString(key, group).commit()" in picker
PY
echo "PASS: Hook rule-group list/actions/delete/picker dialogs restore their route and picker selection"
