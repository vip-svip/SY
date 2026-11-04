#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MAIN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java"
EDITOR="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaCodeEditorActivity.java"
[ -s "$MAIN" ] && [ -s "$ACTIVITY" ] && [ -s "$EDITOR" ] || { echo "FAIL: Dia source files missing" >&2; exit 1; }
python3 - "$MAIN" "$ACTIVITY" "$EDITOR" <<'PY'
from pathlib import Path
import sys
main = Path(sys.argv[1]).read_text(encoding="utf-8")
frida = Path(sys.argv[2]).read_text(encoding="utf-8")
editor = Path(sys.argv[3]).read_text(encoding="utf-8")
route_start = main.index('case "运行日志":')
route = main[route_start:route_start + 500]
target_picker_start = frida.index("private void showTargetPicker(List<Target> targets)")
target_picker_end = frida.index("private void clearPendingProcessPickerState()", target_picker_start)
target_picker = frida[target_picker_start:target_picker_end]
if "FxDiaFridaActivity.class" not in route or '.putExtra("dia_page", page)' not in route:
    raise SystemExit("FAIL: Dia run-log page must open the Frida target-session log screen")
if "showNativeRuntimeLogs()" in route:
    raise SystemExit("FAIL: Dia run-log page is incorrectly routed to the FX module log viewer")
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
    "save-script name draft saved": "outState.putString(STATE_SAVE_SCRIPT_NAME_DRAFT, saveScriptNameDraft.length() > 64" in frida,
    "save-script dialog name restored": "name.setText(saveScriptNameDraft);" in frida,
    "save-script dialog reopens after page creation": "scroll.post(this::showSaveFridaScriptDialog)" in frida,
    "save-script name bounded": "new android.text.InputFilter.LengthFilter(64)" in frida,
    "rotation does not clear pending save dialog": "if (!isChangingConfigurations()) clearSaveScriptDialogState();" in frida,
    "run log page opens target log": 'body.post(() -> {\n                if (targetPackage == null) chooseTarget();\n                else showSessionLog();\n            });' in frida,
    "script editor page opens full-screen editor": 'else if ("脚本编辑器".equals(title)) {\n            body.post(this::openFullScreenCodeEditor);' in frida,
    "full-screen editor request records target identity": "pendingFullEditorTargetPackage = targetPackage;" in frida,
    "full-screen editor request records source fingerprint": "pendingFullEditorSourceSha256 = sourceFingerprint;" in frida,
    "full-screen editor pending state survives parent recreation": "outState.putBoolean(STATE_FULL_EDITOR_PENDING, fullEditorPending)" in frida and "state.getBoolean(STATE_FULL_EDITOR_PENDING, false)" in frida,
    "full-screen editor validates source fingerprint on return": "requestedFingerprint.equals(currentFingerprint)" in frida,
    "full-screen editor validates target on return": "Objects.equals(requestedTarget, targetPackage)" in frida,
    "stale full-screen editor return is rejected": "全屏编辑器的旧返回结果已丢弃" in frida,
    "editor page restores working source and baseline": "state.getString(STATE_SOURCE, intentSource)" in editor and "state.getString(STATE_BASELINE" in editor,
    "editor returns code only on successful save": "setResult(RESULT_CODE_EDITOR, result);" in editor and "private void saveAndReturn()" in editor,
    "editor enforces source byte limit": "utf8Length(source) > MAX_SOURCE_BYTES" in editor,
}
for label, ok in checks.items():
    if not ok:
        raise SystemExit(f"FAIL: {label}")
if "Activity 启动入口观察" not in main:
    raise SystemExit("FAIL: AppEntry observer page is missing from Dia migration menu")
if 'case "Activity 启动入口观察":' not in main:
    raise SystemExit("FAIL: AppEntry observer page is not routed to its native Frida screen")
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
