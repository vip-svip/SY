#!/usr/bin/env python3
"""Source contract for Dia RuleGroupDataStore add/rename/delete migration."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java").read_text(encoding="utf-8")

def body(signature, next_signature):
    start = source.index(signature)
    end = source.index(next_signature, start)
    return source[start:end]

groups = body("private java.util.LinkedHashSet<String> getCustomRuleGroups(", "private void ensureCustomRuleGroup(")
add = body("private void showAddCustomRuleGroupDialog(", "private void showCustomRuleGroupsDialog()")
manager = body("private void showCustomRuleGroupsDialog()", "private void showCustomRuleGroupActions(")
actions = body("private void showCustomRuleGroupActions(", "private boolean renameCustomRuleGroup(")
rename = body("private boolean renameCustomRuleGroup(", "private void showRenameCustomRuleGroupDialog(")
rename_dialog = body("private void showRenameCustomRuleGroupDialog(", "private void deleteCustomRuleGroup(")
delete = body("private void deleteCustomRuleGroup(", "private void showCustomRuleGroupPicker(")

assert '"默认"' in groups and "dev_rule_groups" in groups
assert 'for (int i = 1; i <= 64; i++)' in groups
assert "validCustomRuleGroupName(value)" in add and "ensureCustomRuleGroup(value)" in add
assert 'showCustomRuleGroupActions(chosen)' in manager
assert '"重命名分组", "删除分组"' in actions
assert 'showRenameCustomRuleGroupDialog(groupName)' in actions
assert 'deleteCustomRuleGroup(groupName)' in actions
assert '"默认".equals(oldName)' in rename and "validCustomRuleGroupName(newName)" in rename
assert "groups.contains(normalized)" in rename and '"默认".equals(normalized)' in rename
assert 'for (int slot = 1; slot <= 64; slot++)' in rename
assert 'edit.putString(key, normalized)' in rename
assert 'edit.putStringSet(selectedPackage + ":dev_rule_groups"' in rename and "edit.commit()" in rename
assert "input.setText(oldName)" in rename_dialog and "renameCustomRuleGroup(oldName, newName)" in rename_dialog
assert '"默认".equals(groupName)' in delete and 'edit.putString(key, "默认")' in delete
assert "edit.commit()" in delete
assert "showCustomRuleGroupPicker(int slot)" in source and "showCustomRuleGroupPicker(slot)" in source
assert "renderCustomRules()" in source and "ensureCustomRuleGroup(groupName)" in source
print("PASS: Dia custom RuleGroup add/rename/delete, reserved default, duplicate guard, atomic reassignment and per-rule move")
