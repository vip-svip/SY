#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAppWhitelistActivity.java"
[ -s "$SOURCE" ] || { echo "FAIL: Yulong ad whitelist Activity source missing" >&2; exit 1; }
python3 - "$SOURCE" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")

def require(value, message):
    if value not in source:
        raise SystemExit("FAIL: " + message)

require("private static final int APP_PAGE_SIZE = 50;", "whitelist app page size is missing")
require("private final ThreadPoolExecutor appWorker =", "bounded application inventory worker is missing")
require("new ArrayBlockingQueue<>(1)", "application inventory queue must be bounded")
require("private final ThreadPoolExecutor worker =", "bounded Root operation worker is missing")
require("new ArrayBlockingQueue<>(8)", "Root operation queue must be bounded")
require("catch (RejectedExecutionException full)", "Root queue saturation must be handled")
require("private void loadAppsAsync()", "application inventory must run asynchronously")
require("appWorker.execute(() -> {", "application enumeration is not dispatched to a worker")
require("getApplicationContext().getPackageManager()", "background loader must use application context")
require("pm.getInstalledApplications(0)", "installed application inventory is missing")
require("pm.getApplicationLabel(info)", "application labels must be resolved off the UI thread")
require("loaded.sort(Comparator.comparing(info ->", "labels must be sorted before UI publication")
require("apps.addAll(loaded);", "loaded app snapshot must be published to the Activity")
require("int limit = Math.max(1, appPage) * APP_PAGE_SIZE;", "application rows are not paged")
require("if (matched > limit)", "a load-more action is required for additional applications")
require("appPage = 1;", "search/filter changes must restart at page one")
require("final boolean[] suppress = {false};", "failed whitelist changes must suppress rollback listener recursion")
require("callback.accept(RootAccess.execute(\"\"));", "saturated Root queue must complete UI callbacks with an explicit failure")
require("destroyed = true;", "Activity teardown must reject late callbacks")
require("worker.shutdownNow();", "Root worker must be released")
require("appWorker.shutdownNow();", "application inventory worker must be released")
require("ACTION_PACKAGE_ADDED", "whitelist UI must observe application install broadcasts")
require("ACTION_PACKAGE_REMOVED", "whitelist UI must observe application removal broadcasts")
require("ACTION_PACKAGE_REPLACED", "whitelist UI must observe application update broadcasts")
require("filter.addDataScheme(\"package\")", "package broadcasts must be limited to package data")
require("Context.RECEIVER_NOT_EXPORTED", "dynamic package receiver must not be externally callable")
require("private boolean appReloadPending;", "single-flight inventory reload state is missing")
require("if (appLoading) {\n            appReloadPending = true;\n            return;", "package-change bursts must be coalesced into a single pending refresh")
require("if (appReloadPending) {\n                        appReloadPending = false;\n                        loadAppsAsync();", "a package change during scanning must trigger one follow-up scan")
require("unregisterPackageChanges();", "package receiver must be unregistered when the Activity stops/destroys")
render = source[source.index("private void renderRows()"):source.index("@Override protected void onDestroy()")]
assert "getInstalledApplications(" not in render, "PackageManager enumeration still runs inside row rendering"
assert "getApplicationLabel(" not in render, "label loading still runs inside row rendering"
print("PASS: Yulong ad whitelist loads asynchronously, pages results, bounds Root work and cleans up both workers")
PY
