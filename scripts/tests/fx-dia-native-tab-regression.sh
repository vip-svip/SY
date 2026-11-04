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
assert "handleImportedNativeTabIntent(intent);" in main, "MainActivity must consume native tab intents onNewIntent"

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

# Dia Hook category must expose the independently migrated Dialog, Notification and Toast screens.
assert '{"Hook 功能", "方法 Hook", "对话框处理", "通知监听与权限提示", "Toast 文本过滤",' in main
assert 'case "对话框处理": case "对话框与通知":' in main
assert 'showAppList("Dialog处理");' in main
assert 'case "通知监听与权限提示":' in main
assert 'showAppList("通知保护");' in main
assert 'case "Toast 文本过滤": case "Toast 过滤":' in main
assert 'showAppList("Toast过滤");' in main
assert 'if ("Dialog处理".equals(activePrivacySection))' in main
assert 'if ("Toast过滤".equals(activePrivacySection))' in main
assert 'section("通知保护");' in main
assert 'toggle("阻止通知监听注册", "notification_listen_block", false);' in main
assert 'toggle("隐藏通知权限提示", "notification_permission_hide", false);' in main
route_start = main.index("private void handleNativeTabSelection(int index)")
route_end = main.index("private void styleBottomItem", route_start)
route = main[route_start:route_end]
assert "if (index < 0 || index > 5) return;" in route
assert "selectedBottomTab = 5;" in route and "showSettings();" in route
assert "selectedBottomTab = 4;" in route and "showAppList();" in route
assert "lastWebTabIndex = index;" in route and "renderNativePage(index);" in route
assert "Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP" in base
for page in pages:
    assert "extends de.privacyguard.adhook.FxNativeTabActivity" in page
    assert "setContentViewWithNativeTabs(root, 5);" in page
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
