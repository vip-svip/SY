#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
BASE="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeTabActivity.java"
MAIN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
DIA="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia"
PAGES="
$DIA/FxDiaActivityBrowserActivity.java
$DIA/FxDiaFridaActivity.java
$DIA/FxDiaScriptLibraryActivity.java
$DIA/FxDiaInspectorActivity.java
$DIA/FxDiaCodeEditorActivity.java
$DIA/FxDiaCrashReportActivity.java
$DIA/FxDiaMonitorEventsActivity.java
$DIA/FxDiaDexBrowserActivity.java
$DIA/FxDiaJsonActivity.java
$DIA/FxDiaFileActivity.java
$DIA/FxDiaGpsPickerActivity.java
$DIA/FxDiaSessionLogActivity.java
$DIA/FxDiaSignatureActivity.java
$DIA/FxDiaSystemExpandActivity.java
$DIA/FxDiaWifiProxyActivity.java
"
fail() { echo "FAIL: $*" >&2; exit 1; }
for file in "$BASE" "$MAIN" $PAGES; do
    [ -s "$file" ] || fail "missing native tab source: $file"
done
python3 - "$BASE" "$MAIN" $PAGES <<'PY'
from pathlib import Path
import sys
base, main, *pages = [Path(p).read_text(encoding="utf-8") for p in sys.argv[1:]]
assert "FxNativeAppShellKt.installFxNativeAppShell" in base
assert "ViewTreeLifecycleOwner.set(shell, this)" in base
assert "ViewTreeViewModelStoreOwner.set(shell, this)" in base
assert "ViewTreeSavedStateRegistryOwner.set(shell, this)" in base
assert "index < 0 || index > 5" in base
assert 'putExtra("fx_open_native_tab", index)' in base
assert "if (tab >= 0 && tab <= 5) handleNativeTabSelection(tab);" in main
assert "handleNativeTabIntent(intent);" in main, "MainActivity must consume native tab intents onNewIntent"

# Dia Activity Browser preserves the page viewport across Activity recreation.
activity_browser = next(p for p in pages if "class FxDiaActivityBrowserActivity" in p)
for token in (
    'STATE_SCROLL_Y = "fx_dia_browser_scroll_y"',
    "private ScrollView pageScroll;",
    "restoredScrollY = Math.max(0, state.getInt(STATE_SCROLL_Y, 0));",
    "pageScroll = scroll;",
    "outState.putInt(STATE_SCROLL_Y",
    "scroll.scrollTo(0, restoreY);",
    "pageScroll == scroll && scroll.getParent() != null",
):
    assert token in activity_browser, f"Activity Browser viewport restoration missing: {token}"

# Hook app list must preserve the selected category, search, paging and scroll across return/recreation.
for key in ("STATE_HOOK_APP_LIST_QUERY", "STATE_HOOK_APP_LIST_SCROLL_Y",
            "STATE_HOOK_APP_LIST_VISIBLE_COUNT"):
    assert key in main, f"Hook app-list state key missing: {key}"
assert "nativeScroll = scroll;" in main, "native target pages must retain their ScrollView for category focus"
assert "search.setText(hookAppListQuery);" in main, "restored app-list query must be applied before inventory rendering"
assert "captureHookAppListState();" in main, "opening a target and Activity recreation must capture app-list state"
assert "hookAppListVisibleCount = nextEnd;" in main, "Load more must retain the visible page count"
assert "listScroll.scrollTo(0, restoreY);" in main, "app-list scroll position must restore after async inventory load"
assert "if (isHookAppListVisible() && nativeScroll == listScroll)" in main, "stale restore callbacks must not scroll a newer screen"

# Hook custom-rule screen must retain group/search filters and scroll through rule-edit rebuilds/recreation.
for key in ("STATE_CUSTOM_HOOK_GROUP_FILTER", "STATE_CUSTOM_HOOK_SEARCH",
            "STATE_CUSTOM_HOOK_SCROLL_Y"):
    assert key in main, f"custom-rule screen state key missing: {key}"
assert "captureCustomHookRuleFilters();" in main, "custom-rule edits must capture current view state before rebuilding"
assert "groupFilter.setSelection(restoredGroupPosition);" in main, "custom-rule group filter must restore"
assert "searchFilter.setText(customHookRuleSearchQuery);" in main, "custom-rule search must restore"
assert "customHookRuleGroupFilter = \"全部分组\".equals(value) ? \"\" : value;" in main
assert "customHookRuleSearchQuery = s == null ? \"\" : s.toString();" in main
assert "ruleScroll.scrollTo(0, restoreRuleY);" in main, "custom-rule list scroll must restore"

# Per-app Hook target detail and its custom-rule return path preserve scroll state.
assert 'STATE_HOOK_TARGET_SCROLL_Y = "fx_hook_target_scroll_y"' in main
assert 'state.getInt(STATE_HOOK_TARGET_SCROLL_Y, 0)' in main
assert 'outState.putInt(STATE_HOOK_TARGET_SCROLL_Y, Math.max(0, hookTargetScrollY));' in main
assert "pendingPrivacySection = restoringTarget ? null : privacySection;" in main, "target recreation must not replay the initial category focus over its restored scroll"
assert "final String requested = pendingPrivacySection;" in main, "category auto-focus must be a one-time navigation request"
assert "private void restoreHookTargetScrollAfterBuild()" in main
assert "targetScroll.scrollTo(0, restoreY);" in main
assert "hookTargetScrollRestorePending = false;" in main, "stale target scroll restore must be cleared when its app was uninstalled"
assert 'if (target != null) {' in main and 'hookTargetScrollY = 0;' in main, "missing-target restoration must not leak the old position into a different app"
assert "targetScroll != nativeScroll || packageName == null" in main, "stale target scroll callback must not affect a newer target"
assert "hookTargetScrollY = Math.max(0, nativeScroll.getScrollY());" in main, "target position must be captured before entering custom rules"
assert "if (hookTargetVisible && !hookCustomRulesPageVisible && !hookTargetScrollRestorePending" in main, "target rebuild must capture position but not the custom-rule list"
for page_name in ("showDiaDialogTarget", "showDiaToastTarget", "showDiaKeyControlTarget"):
    start = main.index("private void " + page_name)
    end = main.index("\n    private ", start + 25)
    assert "restoreHookTargetScrollAfterBuild();" in main[start:end], f"{page_name}: target scroll must restore"
assert "nativeScroll == ruleScroll" in main, "stale custom-rule scroll callbacks must be ignored"

# Successful rule CRUD/group operations must rebuild the custom-rule manager, not eject to the generic target page.
custom_refresh = main.count("if (target != null) showCustomHookRulesPage(target,")
assert custom_refresh >= 4, f"expected custom-rule group/rule refresh routes, found {custom_refresh}"
assert "showCustomHookRulesPage(target,\n                            (target.flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0);\n                }).show();\n    }\n\n    private String remapCustomRuleDescriptor" in main, "saving a rule must remain in the custom-rule manager"
assert "showCustomHookRulesPage(target,\n                                        (target.flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0);\n                            }).show());" in main, "deleting a rule must remain in the custom-rule manager"
assert "private void leaveCustomHookRulesPage()" in main and 'showAppList("自定义 Hook");' in main, "explicit Back must still leave the manager normally"

# A rule editor dialog that was open during recreation reopens with its existing persisted draft.
assert 'state.getBoolean("fx_custom_rule_editor_open", false)' in main
assert 'state.getInt("fx_custom_rule_editor_slot", -1)' in main
assert 'state.getString("fx_custom_rule_editor_preset")' in main
assert 'outState.putBoolean("fx_custom_rule_editor_open", true)' in main
assert "if (customRuleEditorRestorePending)" in main
assert "showCustomRuleDialog(restorePreset, restoreSlot);" in main
assert "new android.text.InputFilter.LengthFilter(65536)" not in main, "JSON import editor must not reintroduce an arbitrary character ceiling"
assert "getBytes(java.nio.charset.StandardCharsets.UTF_8).length > 65536" not in main, "JSON import parser must not reintroduce an arbitrary UTF-8 byte ceiling"
assert "new org.json.JSONArray(raw)" in main and "new org.json.JSONObject(raw)" in main, "JSON import must retain array/object parsing after removing the fixed ceiling"
assert 'getPreferences(0).getString(importDraftKey, "")' in main, "JSON import dialog must restore its saved draft"
assert "scheduleCustomRuleImportDraftWrite(input, selectedPackage);" in main, "JSON import edits must persist through the debounced draft writer"
assert "private void scheduleCustomRuleImportDraftWrite(EditText input, String targetPackage)" in main, "JSON import draft writer is missing"
assert 'putString(targetPackage + ":dev_rule_import_json_draft", draft)' in main, "JSON import draft must be keyed to its target package"
assert "flushCustomRuleImportDraftWrite();" in main, "JSON import must flush pending draft writes before closing"
assert "clearCustomRuleEditorDialogState();" in main
assert '.setNegativeButton("取消", (dialog, which) -> clearCustomRuleEditorDialogState())' in main
assert '.setOnCancelListener(dialog -> clearCustomRuleEditorDialogState())' in main
assert 'draftIdentity.equals(getPreferences(0).getString(' in main
assert 'draftPrefix + "identity"' in main

# Dia per-app interaction tools belong to the unified Hook hub; privacy-oriented
# Toast and notification policies remain accessible from the Privacy destination.
hook_hub_start = main.index("private void showHookHub()")
hook_hub_end = main.index("private void refreshHookHubAuthorizationStates()", hook_hub_start)
hook_hub = main[hook_hub_start:hook_hub_end]
for token in (
    'addNativeActionCard("Dialog 对话框 Hook"',
    'showAppList("Dialog处理")',
    'addNativeActionCard("按键动作 Hook"',
    'showAppList("按键控制")',
):
    assert token in hook_hub, f"Hook hub entry is missing: {token}"

app_list_start = main.index("private void showAppList(String privacySection)")
app_list_end = main.index("private void captureHookAppListState()", app_list_start)
app_list = main[app_list_start:app_list_end]
for token in (
    '"自定义 Hook".equals(activePrivacySection)',
    '"Dialog处理".equals(activePrivacySection)',
    '"按键控制".equals(activePrivacySection)',
    'selectedBottomTab = activePrivacySection == null || hookToolsPage ? 4 : 2;',
):
    assert token in app_list, f"Hook-owned per-app route/highlight missing: {token}"

privacy_start = main.index("private void buildNativePrivacyPage()")
privacy_end = main.index("private void refreshNativePrivacyStatus(", privacy_start)
privacy_page = main[privacy_start:privacy_end]
for token in (
    'addNativeActionCard("通知监听与权限提示"',
    'showAppList("通知保护")',
    'addNativeActionCard("Toast 文本过滤"',
    'showAppList("Toast过滤")',
):
    assert token in privacy_page, f"Privacy page is missing its policy entry: {token}"

for token in (
    'if ("Dialog处理".equals(activePrivacySection))',
    'if ("Toast过滤".equals(activePrivacySection))',
    'if ("按键控制".equals(activePrivacySection))',
    'section("通知保护");',
    'toggle("阻止通知监听注册", "notification_listen_block", false);',
    'toggle("隐藏通知权限提示", "notification_permission_hide", false);',
):
    assert token in main, f"per-app policy route is missing: {token}"

# Dialog is owned by Hook, while Toast and notification filtering stay under Privacy.
dialog_start = main.index("private void showDiaDialogTarget(")
dialog_end = main.index("\n    private void showDiaToastTarget(", dialog_start)
dialog_page = main[dialog_start:dialog_end]
for token in ('selectedBottomTab = 4;', 'base("Hook · Dialog 处理 · " + selectedLabel)',
              '返回 Hook 应用列表', 'restoreHookTargetScrollAfterBuild();'):
    assert token in dialog_page, f"Dialog target page must remain inside Hook: {token}"
toast_start = main.index("private void showDiaToastTarget(")
toast_end = main.index("\n    private void showDiaKeyControlTarget(", toast_start)
toast_page = main[toast_start:toast_end]
assert 'selectedBottomTab = 2;' in toast_page, "Toast target page must remain inside Privacy"
assert 'restoreHookTargetScrollAfterBuild();' in toast_page, "Toast target scroll must restore"
route_start = main.index("private void handleNativeTabSelection(int index)")
route_end = main.index("private void styleBottomItem", route_start)
route = main[route_start:route_end]
assert "if (index < 0 || index > 5) return;" in route
assert "selectedBottomTab = 5;" in route and "showSettings();" in route
assert "selectedBottomTab = 4;" in route and "showAppList();" in route
assert "lastWebTabIndex = index;" in route and "renderNativePage(index);" in route
assert "private final int[] nativeTabScrollPositions = new int[4];" in main, "Four native primary pages must have independent scroll positions"
assert 'outState.putIntArray("fx_native_tab_scroll_positions", nativeTabScrollPositions.clone());' in main, "Native tab scroll positions must survive Activity recreation"
assert "captureNativePageScrollPosition();" in main, "Switching tabs must capture the outgoing native page position"
assert "nativePageScroll.scrollTo(0, 0);" in main, "New native pages must not inherit the previous page viewport"
assert "final int restoreY = nativeTabScrollPositions[pageIndex];" in main, "Native page must load its own saved scroll position"
assert "nativePageScroll.scrollTo(0, restoreY);" in main, "Native page must restore its saved scroll position after layout"
assert "renderGeneration != nativePageRenderGeneration" in main and "nativePageContent.getParent() != nativePageScroll" in main, "Stale native page restore callbacks must not move a newer tab"
assert "Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP" in base
assert 'pendingDiaGpsTargetPackage = state.getString("fx_pending_dia_gps_target");' in main
assert 'outState.putString("fx_pending_dia_gps_target", pendingDiaGpsTargetPackage);' in main
assert "REQUEST_DIA_GPS_PICKER" in main and "pendingDiaGpsTargetPackage = selectedPackage;" in main
assert "target.equals(selectedPackage)" in main, "GPS result must remain scoped to the original selected app"
assert "target.equals(pendingRestorePackage)" in main, "GPS result must survive while the selected app is still restoring"
assert "if (!targetEditorRestoring)" in main, "GPS result must defer opening the target until asynchronous app-list restoration completes"
# SAF script export must persist its payload outside the Activity instance and clean up on every result path.
for token in ("NATIVE_SCRIPT_EXPORT_PREFS", "NATIVE_SCRIPT_EXPORT_PAYLOAD", "fx_pending_native_script_export"):
    assert token in main, f"missing SAF export persistence contract: {token}"
assert "putString(NATIVE_SCRIPT_EXPORT_PAYLOAD, payload).commit()" in main, "SAF export payload must survive Activity recreation"
assert "getString(NATIVE_SCRIPT_EXPORT_PAYLOAD, null)" in main
assert "MAX_NATIVE_SCRIPT_EXPORT_BYTES" not in main, "script export must not impose an arbitrary product-level payload ceiling"
assert "finally {\n                clearPendingNativeScriptExport();\n            }" in main
assert "clearPendingNativeScriptExport();" in main, "cancel/launch failure must clear staged export payload"
for page in pages:
    assert "extends de.privacyguard.adhook.FxNativeTabActivity" in page
    expected_tab = 3 if "class FxDiaScriptLibraryActivity" in page else 0 if "class FxDiaWifiProxyActivity" in page else 4
    assert f"setContentViewWithNativeTabs(root, {expected_tab});" in page, (
        "Dia Activity must select its owning FX destination: "
        + ("Scripts" if expected_tab == 3 else "VPN" if expected_tab == 0 else "Hook")
    )
    assert "setContentView(root);" not in page
    assert "onCreate(" in page
file_page = next(p for p in pages if "class FxDiaFileActivity" in p)
for token in ("ACTION_OPEN_DOCUMENT_TREE", "takePersistableUriPermission",
              "DocumentsContract.createDocument", "onActivityResult(",
              "loadDirectory(", "submitIo("):
    assert token in file_page, f"File/ELF behavior missing: {token}"
gps_page = next(p for p in pages if "class FxDiaGpsPickerActivity" in p)
for token in ("STATE_PAIR", "STATE_LATITUDE", "STATE_LONGITUDE", "STATE_STATUS", "onSaveInstanceState("):
    assert token in gps_page, f"GPS picker state missing: {token}"
session_page = next(p for p in pages if "class FxDiaSessionLogActivity" in p)
for token in ("STATE_SEARCH", "STATE_SCROLL_Y", "onSaveInstanceState("):
    assert token in session_page, f"Session Log state missing: {token}"
print("PASS: GPS picker and Session Log state restoration anchors remain")
signature_page = next(p for p in pages if "class FxDiaSignatureActivity" in p)
for token in ("SigningInfo", "MessageDigest", "getInstalledApplications", "chooseApp(", "inspect("):
    assert token in signature_page, f"Signature viewer behavior missing: {token}"
system_page = next(p for p in pages if "class FxDiaSystemExpandActivity" in p)
for token in ("PackageInstaller", "allowed_install_from_unknown_source",
              "restart_package_installer", "RootAccess", "setPositiveButton"):
    assert token in system_page, f"System Expand guarded action missing: {token}"
print("PASS: Signature viewer remains read-only and System Expand keeps guarded settings actions")
wifi_page = next(p for p in pages if "class FxDiaWifiProxyActivity" in p)
for token in ("FxDiaWifiProxyState.mayRestore", "FxDiaWifiProxyState.evaluate",
              "RootAccess.execute", "setPositiveButton", "worker.shutdownNow()"):
    assert token in wifi_page, f"Wi-Fi proxy guarded restore/worker lifecycle missing: {token}"
print("PASS: Wi-Fi proxy guarded restore and worker shutdown remain")
print("PASS: Dia independent pages retain the shared six-tab shell")
print("PASS: File/ELF SAF grant, import/export, directory and worker paths remain")
PY
