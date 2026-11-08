#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongFirewallActivity.java"
PARSER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongFirewallListParser.java"
[ -s "$PARSER" ] || { echo "FAIL: strict Yulong firewall list parser missing" >&2; exit 1; }
[ -s "$SOURCE" ] || { echo "FAIL: Yulong firewall Activity source missing" >&2; exit 1; }
python3 - "$SOURCE" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")


def require(value, message):
    if value not in source:
        raise SystemExit("FAIL: " + message)

require("private static final int APP_PAGE_SIZE = 50;", "app inventory page size is missing")
require("private final Map<Integer, List<String>> uidPackages", "full UID peer inventory is missing")
require("private int[] installedUidSnapshot", "UID snapshot for shared-app detection is missing")
require("loadedUidPackages.put(info.uid, uidGroup)", "all installed apps must be grouped before category filtering")
require("FxYulongFirewallAppFilterPolicy.countUidMembers(uid, installedUidSnapshot)", "shared UID detection is not backed by the tested policy")
require("private String uidScopeSummary(int uid)", "shared UID effect is not disclosed in the app row")
require("private void confirmSharedUidScope(", "shared UID changes require explicit confirmation")
require("继续（影响全部共享应用）", "shared UID confirmation must state the full impact")
require("最终阻断按全部成员当前生效规则合并", "shared UID list must disclose that active member policies are unioned")
require("任一成员生效的 Wi-Fi / 移动数据限制都会作用于全部共享应用", "shared UID row must explain aggregate network effects")
require("此防火墙使用 Android owner UID 匹配，无法只限制其中一个包", "the UI must not claim package isolation for a shared UID")
require("confirmSharedUidScope(pkg, info.uid, persist, revert)", "the quick rule switch must confirm shared UID scope")
require("showRuleDialogInternal(packageName, uid)", "the detailed rule form must only open after the shared UID warning")
require("FxYulongFirewallListParser.parse(output)", "Root list response is not parsed strictly")
require("private void rejectInvalidListResponse()", "malformed firewall state does not lock writes")
require("inventoryReady = false;", "invalid Root list must invalidate any previously loaded editable inventory")
require("if (!inventoryReady) {", "rule editor and persistence must reject writes while the list is invalid")
require("if (suppressRow[0] || !inventoryReady) return;", "already-rendered row switches must not write after list invalidation")
require("enabled.setEnabled(inventoryReady);", "existing row switches must be disabled until a complete list is restored")
require("configure.setEnabled(inventoryReady);", "existing rule detail buttons must be disabled until a complete list is restored")
if source.count("if (!parseList(result.output))") != 2:
    raise SystemExit("FAIL: initial and refresh list reads must both fail closed")
require("private void card(String title, String detail, View... children)", "firewall cards must support multiple child controls")
require("for (View child : children) if (child != null) card.addView(child);", "all card child controls must be attached")
for token in (
    'pageTitle.setTag("fx-title:18")',
    'intro.setTag("fx-card-body")',
    'status.setTag("fx-card-detail")',
    'master.setTag("fx-switch-row")',
    'query.setTag("fx-search-input")',
    'scopeStatus.setTag("fx-card-detail")',
    'item.setTag("fx-list-row")',
    'name.setTag("fx-list-title")',
    'packageText.setTag("fx-list-subtitle")',
    'traffic.setTag("fx-card-detail")',
    'detail.setTag("fx-card-detail")',
    'enabled.setTag("fx-switch-row")',
    'panel.setTag("fx-card")',
    'wifi.setTag("fx-switch-row")',
    'mobile.setTag("fx-switch-row")',
    'schedule.setTag("fx-switch-row")',
    'start.setTag("fx-card-detail")',
    'end.setTag("fx-card-detail")',
):
    require(token, "firewall page is missing six-mode component role: " + token)
require("showFxDialog(dialog);", "rule editor must retain the shared six-mode dialog presentation host")
require('return FxYulongRootModuleCommand.command("yulong-app-firewall.sh", args);',
        "firewall must delegate module lookup to the shared allowlisted resolver")
require("private final ThreadPoolExecutor appWorker =", "bounded app inventory worker is missing")
require("new ArrayBlockingQueue<>(1)", "app inventory queue must be bounded")
require("private final ThreadPoolExecutor worker =", "bounded Root operation worker is missing")
require("new ArrayBlockingQueue<>(8)", "Root operation queue must be bounded")
require("catch (RejectedExecutionException full)", "Root queue saturation must be handled")
require('RootAccess.Result rejected = RootAccess.failure(', "rejected Root tasks must use an explicit failure result without launching su")
assert 'RootAccess.execute("");' not in source, "queue saturation must not call RootAccess.execute with a fake empty command"
require('"后台任务繁忙，本次防火墙操作未执行。"', "queue saturation failure must explain that the firewall operation was not run")
require("private void loadAppsAsync()", "asynchronous app inventory entrypoint is missing")
require("private boolean appsLoaded;", "successfully loaded package snapshot is not tracked")
require("private final BroadcastReceiver packageChangeReceiver", "firewall app list has no package lifecycle receiver")
require("Intent.ACTION_PACKAGE_ADDED", "package install events are not observed")
require("Intent.ACTION_PACKAGE_REMOVED", "package removal events are not observed")
require("Intent.ACTION_PACKAGE_REPLACED", "package update completion is not observed")
require("Intent.ACTION_PACKAGE_FULLY_REMOVED", "full package removal is not observed")
require('filter.addDataScheme("package")', "package URI filter is missing")
require("Context.RECEIVER_NOT_EXPORTED", "modern Android receiver is not registered as not-exported")
require("intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)", "package update transitional events are not filtered")
require("private void refreshPackageInventory()", "Root package state is not re-read after package changes")
require("if (appsLoaded) refreshPackageInventory();", "missed package broadcasts are not reconciled on Activity resume")
require("unregisterPackageChangeReceiver();", "package receiver is not released on pause/destroy")
require("private void enqueueLatestAppLoad(Runnable task)", "latest app inventory refresh is not bounded")
require("appWorker.execute(task)", "PackageManager inventory is not dispatched off the UI thread")
require("appWorker.getQueue().poll();", "stale queued app inventory is not replaced")
require("final int generation = ++appLoadGeneration;", "app inventory refresh generation is missing")
require("generation != appLoadGeneration", "stale app inventory results are not discarded")
require('private static final String STATE_SUITE_PAGE = "fx_firewall_suite_page";', "selected firewall category state key is missing")
require("outState.putString(STATE_SUITE_PAGE, suitePage)", "selected firewall category is not saved")
require("state.getString(STATE_SUITE_PAGE, launchPage)", "selected firewall category is not restored")
for page in ("按应用设置", "用户应用", "系统应用"):
    require(f'button("{page}", () -> selectSuitePage("{page}"))', f"{page} category selector is missing")
require("private void selectSuitePage(String page)", "category selector does not route to the real filter")
require('pageTitle.setText("FX Ad · " + suitePage)', "selected category does not update the page title")
require("appLoadGeneration++;", "Activity destruction must invalidate app inventory callbacks")
require("pm.getInstalledApplications(0)", "installed applications are not loaded")
require("pm.getApplicationLabel(info)", "application labels are not resolved")
require("apps.addAll(loaded);", "loaded applications are not committed on the UI thread")
require("master.setEnabled(false);", "firewall master switch must remain disabled while config/app inventory is unavailable")
require("limit = Math.max(1, appPage) * APP_PAGE_SIZE", "app rows are not bounded by the selected page")
require("if (matched > limit)", "overflow rows do not expose a load-more action")
require("appPage = 1;", "search changes must reset pagination")
require('private static final String STATE_APP_PAGE = "fx_firewall_app_page";', "firewall app page state key is missing")
require('private static final String STATE_QUERY = "fx_firewall_query";', "firewall search state key is missing")
require('private static final String STATE_SCROLL_Y = "fx_firewall_scroll_y";', "firewall scroll state key is missing")
require("outState.putInt(STATE_APP_PAGE, Math.max(1, appPage))", "firewall pagination is not saved on recreation")
require("outState.putString(STATE_QUERY, query.getText().toString())", "firewall search query is not saved on recreation")
require("outState.putInt(STATE_SCROLL_Y, Math.max(0, scroll.getScrollY()))", "firewall scroll position is not saved on recreation")
require("state.getInt(STATE_APP_PAGE, 1)", "firewall pagination is not restored")
require("state.getString(STATE_QUERY, \"\")", "firewall search query is not restored")
require("state.getInt(STATE_SCROLL_Y, 0)", "firewall scroll position is not restored")
require("private void restoreScrollIfNeeded()", "firewall scroll restoration helper is missing")
require("private int scrollRestoreGeneration;", "firewall scroll restoration needs a stale-callback generation")
require("generation != scrollRestoreGeneration", "older posted scroll callbacks must not override a newer search")
require("pendingScrollRestore = false;", "new search must cancel the previous scroll restore")
require("pendingScrollY = Math.max(0, scroll.getScrollY());", "package refresh does not preserve the current scroll position")
load_apps = source[source.index("private void loadAppsAsync()"):source.index("private String formatBytes")]
assert "appPage = 1;" not in load_apps, "package inventory refresh must not discard the current page"
require("restoreScrollIfNeeded();", "restored firewall list state is never applied after rendering")
require("appWorker.shutdownNow();", "background app worker is not released on Activity destruction")
destroy = source[source.index("@Override protected void onDestroy()"):]
assert "scrollRestoreGeneration++;" in destroy, "Activity destruction must invalidate pending scroll callbacks"
render = source[source.index("private void renderRows()"):source.index("@Override protected void onDestroy()")]
assert "getInstalledApplications(" not in render, "PackageManager inventory is still executed while rendering rows"
assert "getApplicationLabel(" not in render, "application labels are still loaded while rendering rows"
assert "for (ApplicationInfo info : apps)" in render, "paged renderer lost the application row loop"
print("PASS: Yulong firewall reloads apps, restores search/page/scroll state, pages rows and releases workers")
PY

POLICY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongFirewallAppFilterPolicy.java"
POLICY_HOST_TEST="$ROOT/scripts/tests/FxYulongFirewallAppFilterPolicyHostTest.java"
[ -s "$POLICY" ] && [ -s "$POLICY_HOST_TEST" ] || { echo "FAIL: firewall UID policy Host test sources missing" >&2; exit 1; }
if command -v javac >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/fx-firewall-uid-policy.XXXXXX")"
  trap 'rm -rf "$WORK"' EXIT HUP INT TERM
  javac -d "$WORK" "$POLICY" "$PARSER" "$POLICY_HOST_TEST"
  java -cp "$WORK" de.privacyguard.adhook.imported.ad.FxYulongFirewallAppFilterPolicyHostTest
else
  echo "SKIP: JDK unavailable; firewall policy and strict list parser assertions were not executed."
fi
