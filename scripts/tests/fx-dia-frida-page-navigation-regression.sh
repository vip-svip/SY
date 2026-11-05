#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MAIN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java"
EDITOR="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaCodeEditorActivity.java"
LIBRARY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaScriptLibraryActivity.java"
SESSION="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaSessionLogActivity.java"
MONITOR="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaMonitorEventsActivity.java"
SKIN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeSkin.java"
[ -s "$MAIN" ] && [ -s "$ACTIVITY" ] && [ -s "$EDITOR" ] && [ -s "$LIBRARY" ] && [ -s "$SESSION" ] && [ -s "$MONITOR" ] && [ -s "$SKIN" ] || { echo "FAIL: Dia source files missing" >&2; exit 1; }
python3 - "$MAIN" "$ACTIVITY" "$EDITOR" "$LIBRARY" "$SESSION" "$MONITOR" "$SKIN" <<'PY'
from pathlib import Path
import sys
main = Path(sys.argv[1]).read_text(encoding="utf-8")
frida = Path(sys.argv[2]).read_text(encoding="utf-8")
editor = Path(sys.argv[3]).read_text(encoding="utf-8")
library = Path(sys.argv[4]).read_text(encoding="utf-8")
session = Path(sys.argv[5]).read_text(encoding="utf-8")
monitor = Path(sys.argv[6]).read_text(encoding="utf-8")
skin = Path(sys.argv[7]).read_text(encoding="utf-8")
hook_hub_start = main.index("private void showHookHub()")
hook_hub_end = main.index("private void refreshHookHubAuthorizationStates()", hook_hub_start)
hook_hub = main[hook_hub_start:hook_hub_end]
frida_route_start = hook_hub.index('addNativeActionCard("Frida 环境与注入"')
frida_route = hook_hub[frida_route_start:frida_route_start + 650]
target_picker_start = frida.index("private void showTargetPicker(List<Target> targets)")
target_picker_end = frida.index("private void clearPendingProcessPickerState()", target_picker_start)
target_picker = frida[target_picker_start:target_picker_end]
if "FxDiaFridaActivity.class" not in frida_route or '.putExtra("dia_page", "Frida 环境")' not in frida_route:
    raise SystemExit("FAIL: FX Hook hub must open the integrated Frida runtime Activity")
if "showNativeRuntimeLogs()" in frida_route:
    raise SystemExit("FAIL: Frida runtime entry is incorrectly routed to the FX module log viewer")
if 'button("查看当前目标注入日志", () -> showSessionLog())' not in frida:
    raise SystemExit("FAIL: Frida runtime page does not expose its target session log")
session_log_start = frida.index("private void showSessionLog()")
session_log_end = frida.index("private void showMonitorEvents()", session_log_start)
session_log = frida[session_log_start:session_log_end]
for token in (
    'button.setTag("fx-action-row")',
    'title.setTag("fx-title:18")',
    'note.setTag("fx-card-detail")'
):
    if token not in editor:
        raise SystemExit(f"FAIL: full-screen Hook editor is missing Skin role {token}")

# The library, session log and monitor event list must use the same role tags
# as the main Hook page so Harmony/Cupertino do not fall back to legacy colors.
for token in (
    'view.setTag("fx-action-row")',
    'pageTitle.setTag("fx-title:18")',
    'actions.setTag("fx-card-group")',
    'row.setTag("fx-list-row")',
    'scriptName.setTag("fx-list-title")',
    'metadata.setTag("fx-list-subtitle")'
):
    if token not in library:
        raise SystemExit(f"FAIL: Frida script library is missing Skin role {token}")
for token in (
    'view.setTag("fx-action-row")',
    'pageTitle.setTag("fx-title:18")',
    'targetIdentity.setTag("fx-card-detail")',
    'controls.setTag("fx-card-group")'
):
    if token not in session:
        raise SystemExit(f"FAIL: Frida session log is missing Skin role {token}")
for token in (
    'view.setTag("fx-action-row")',
    'title.setTag("fx-title:18")',
    'controls.setTag("fx-card-group")',
    'autoRefreshSwitch.setTag("fx-switch-row")',
    'row.setTag("fx-list-row")',
    'eventText.setTag("fx-list-subtitle")',
    'showFxDialog(dialog);'
):
    if token not in monitor:
        raise SystemExit(f"FAIL: monitor event page is missing Skin role {token}")
if "public final class FxNativeSkin" not in skin:
    raise SystemExit("FAIL: shared Skin facade must be public to integrated dia subpackages")
if "public static void showDialog(Activity activity, Dialog dialog)" not in skin:
    raise SystemExit("FAIL: shared dialog renderer must be public to integrated dia subpackages")
checks = {

    "target picker open state saved": "outState.putBoolean(STATE_TARGET_PICKER_OPEN" in frida,
    "target picker open state restored": 'state.getBoolean(STATE_TARGET_PICKER_OPEN, false)' in frida,
    "target picker reopens after Activity recreation": "if (restoreTargetPickerPending)" in frida and "chooseTarget();" in frida,
    "target picker cancellation clears pending state": "pickerDialog.setOnCancelListener(dialog -> {" in target_picker and "targetPickerOpen = false;" in target_picker,
    "target picker searches app names and package names": "adapter.getFilter().filter(targetPickerQuery)" in target_picker and "search.setHint(\"搜索应用名称或包名\")" in target_picker,
    "target picker displays package identity": 'return label + " · " + packageName;' in frida,
    "target picker shows empty search state": "list.setEmptyView(empty);" in target_picker,
    "target picker search query saved": "outState.putString(STATE_TARGET_PICKER_QUERY" in frida,
    "target picker search query restored": "state.getString(STATE_TARGET_PICKER_QUERY" in frida,
    "process picker open state saved": "outState.putBoolean(STATE_PROCESS_PICKER_OPEN" in frida,
    "process picker open state restored": 'state.getBoolean(STATE_PROCESS_PICKER_OPEN, false)' in frida,
    "process picker query saved": "outState.putString(STATE_PROCESS_PICKER_QUERY" in frida,
    "process picker query restored": 'state.getString(STATE_PROCESS_PICKER_QUERY, "")' in frida,
    "process picker has native search": 'search.setHint("搜索进程名或 PID")' in frida and "search.addTextChangedListener(new TextWatcher()" in frida,
    "process picker filters process labels and PIDs": "label.toLowerCase(Locale.ROOT).contains(normalized)" in frida,
    "process picker has filtered empty state": "list.setEmptyView(empty)" in frida,
    "process picker preserves selections while filtering": "list.clearChoices();" in frida and "pendingProcessPickerPids.contains(visiblePids.get(i))" in frida,
    "process picker keeps hidden selections on save": "selectedProcessPids.addAll(pendingProcessPickerPids)" in frida,
    "process picker uses searchable multi-choice list": "ListView.CHOICE_MODE_MULTIPLE" in frida and "setMultiChoiceItems(" not in frida,

    "process picker staged PID selection saved": "outState.putStringArrayList(STATE_PROCESS_PICKER_STAGED_PIDS" in frida,
    "process picker staged PID selection restored": "state.getStringArrayList(STATE_PROCESS_PICKER_STAGED_PIDS)" in frida,
    "process picker Root result validates target and generation": "operationGeneration != processPickerGeneration" in frida and "!requestedPackage.equals(targetPackage)" in frida,
    "switching targets invalidates the old process-picker request": (
        "processPickerGeneration++;" in target_picker
        and "clearPendingProcessPickerState();" in target_picker
        and "targetPackage = selected.packageName;" in target_picker
    ),
    "process picker multi-choice stages PID changes": "pendingProcessPickerPids.add(pid)" in frida and "pendingProcessPickerPids.remove(pid)" in frida,
    "process picker explicit empty selection retained": "checked[i] = hasPendingProcessPickerSelection" in frida and "staged.contains(pids.get(i))" in frida,
    "delayed picker restoration remains saved until runnable": "targetPickerOpen || targetLoading || restoreTargetPickerPending" in frida and "processPickerOpen || restoreProcessPickerPending" in frida,
    "persist selected debug package": '.putString("target_package", targetPackage)' in frida,
    "persist selected target label": '.putString("target_name", targetName)' in frida,
    "restore target without Activity Bundle": 'prefs.getString("target_package", null)' in frida,
    "validate persisted target before reuse": 'ApplicationInfo.FLAG_DEBUGGABLE' in frida and 'ApplicationInfo.FLAG_SYSTEM' in frida,
    "clear stale target selection": 'remove("target_package").remove("target_name")' in frida,
    "restore target even on a fresh page launch": 'restoreTransientState(state);' in frida,
    "retain Frida manager scroll container": 'pageScroll = scroll;' in frida,
    "save Frida manager scroll position": 'outState.putInt(STATE_FRIDA_SCROLL_Y, Math.max(0, pageScroll.getScrollY()));' in frida,
    "restore Frida manager scroll position after layout": 'scroll.scrollTo(0, restoreY);' in frida,
    "guard stale scroll restoration": 'pageScroll == scroll && scroll.getParent() != null' in frida,
    "save-script dialog pending state saved": "outState.putBoolean(STATE_SAVE_SCRIPT_DIALOG_PENDING, restoreSaveScriptDialog)" in frida,
    "save-script dialog pending state restored": "state.getBoolean(STATE_SAVE_SCRIPT_DIALOG_PENDING, false)" in frida,
    "save-script name draft saved without truncation": "outState.putString(STATE_SAVE_SCRIPT_NAME_DRAFT, saveScriptNameDraft)" in frida,
    "save-script dialog name restored": "name.setText(saveScriptNameDraft);" in frida,
    "save-script dialog reopens after page creation": "scroll.post(this::showSaveFridaScriptDialog)" in frida,
    "rotation does not clear pending save dialog": "if (!isChangingConfigurations()) clearSaveScriptDialogState();" in frida,
    "run log page opens target log": 'body.post(() -> {\n                if (targetPackage == null) chooseTarget();\n                else showSessionLog();\n            });' in frida,
    "script editor page opens full-screen editor": 'else if ("脚本编辑器".equals(title)) {\n            body.post(this::openFullScreenCodeEditor);' in frida,
    "full-screen editor request records target identity": "pendingFullEditorTargetPackage = targetPackage;" in frida,
    "full-screen editor request records source fingerprint": "pendingFullEditorSourceSha256 = sourceFingerprint;" in frida,
    "full-screen editor pending state survives parent recreation": "outState.putBoolean(STATE_FULL_EDITOR_PENDING, fullEditorPending)" in frida and "state.getBoolean(STATE_FULL_EDITOR_PENDING, false)" in frida,
    "full-screen editor validates source fingerprint on return": "requestedFingerprint.equals(currentFingerprint)" in frida,
    "full-screen editor validates target on return": "Objects.equals(requestedTarget, targetPackage)" in frida,
    "stale full-screen editor return is rejected": "全屏编辑器的旧返回结果已丢弃" in frida,
    "editor page restores file-backed source and baseline": "FxDiaCodeEditorTransfer.read(this, sourceFile, \".source\")" in editor and "state.getString(STATE_BASELINE" in editor,
    "editor saves large draft outside Activity Bundle": "FxDiaCodeEditorTransfer.write(this, draftFile, source)" in editor and "STATE_DRAFT_SAVED" in editor,
    "editor has no fixed 48 KiB input cap": "MAX_SOURCE_BYTES" not in editor,
    "editor result is returned through private file": "FxDiaCodeEditorTransfer.write(this, resultFile, source)" in editor and "EXTRA_SOURCE_FILE" in editor,
    "editor returns code only on successful save": "setResult(RESULT_CODE_EDITOR, result);" in editor and "private void saveAndReturn()" in editor,
}
for label, ok in checks.items():
    if not ok:
        raise SystemExit(f"FAIL: {label}")
if "new android.text.InputFilter.LengthFilter(64)" in frida or "saveScriptNameDraft.length() > 64" in frida:
    raise SystemExit("FAIL: legacy Frida saved-script name still has an arbitrary 64-character cap")
# AppEntry observer is now a Frida-tool subpage inside FX Hook, not a
# source-app migration-menu item in MainActivity.
if 'addNativeActionCard("Frida 环境与注入"' not in hook_hub:
    raise SystemExit("FAIL: Hook hub is missing the integrated Frida tool entry")
if "Activity 启动入口观察" not in frida:
    raise SystemExit("FAIL: Frida Activity is missing the AppEntry observer subpage")
if 'button("载入 Activity 创建入口观察", () -> loadDiaMonitorTemplate("appentry"))' not in frida:
    raise SystemExit("FAIL: AppEntry observer cannot be loaded manually")
if 'else if ("Activity 启动入口观察".equals(title))' not in frida:
    raise SystemExit("FAIL: AppEntry page does not preload its matching template")
for marker in ("Instrumentation.newActivity.overload", "Instrumentation.callActivityOnCreate.overload",
               "[DIA_APPENTRY]", "no Activity replacement", "Intent extras/data access"):
    if marker not in frida:
        raise SystemExit(f"FAIL: AppEntry observer contract missing {marker}")
start = frida.index('            case "appentry":')
end = frida.index('            case "intent":', start)
appentry = frida[start:end]
for forbidden in ("setClass(", "finish()", "startActivity(", "replace success", "getExtras(", "getData("):
    if forbidden in appentry:
        raise SystemExit(f"FAIL: observer has side-effect or payload access: {forbidden}")
print("PASS: Dia Frida pages retain a validated debug target, route AppEntry observer and keep Activity creation metadata-only")
PY
