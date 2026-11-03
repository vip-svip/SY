#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongFirewallActivity.java"
[ -s "$SOURCE" ] || { echo "FAIL: Yulong firewall Activity source missing" >&2; exit 1; }
python3 - "$SOURCE" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")

def require(value, message):
    if value not in source:
        raise SystemExit("FAIL: " + message)

require("private static final int APP_PAGE_SIZE = 50;", "app inventory page size is missing")
require("private void card(String title, String detail, View... children)", "firewall cards must support multiple child controls")
require("for (View child : children) if (child != null) card.addView(child);", "all card child controls must be attached")
require("private final ThreadPoolExecutor appWorker =", "bounded app inventory worker is missing")
require("new ArrayBlockingQueue<>(1)", "app inventory queue must be bounded")
require("private final ThreadPoolExecutor worker =", "bounded Root operation worker is missing")
require("new ArrayBlockingQueue<>(8)", "Root operation queue must be bounded")
require("catch (RejectedExecutionException full)", "Root queue saturation must be handled")
require('RootAccess.Result rejected = RootAccess.execute("");', "rejected Root tasks must produce a callback result without launching su")
require("private void loadAppsAsync()", "asynchronous app inventory entrypoint is missing")
require("appWorker.execute(() -> {", "PackageManager inventory is not dispatched off the UI thread")
require("pm.getInstalledApplications(0)", "installed applications are not loaded")
require("pm.getApplicationLabel(info)", "application labels are not resolved")
require("apps.addAll(loaded);", "loaded applications are not committed on the UI thread")
require("master.setEnabled(false);", "firewall master switch must remain disabled while config/app inventory is unavailable")
require("int limit = Math.max(1, appPage) * APP_PAGE_SIZE;", "app rows are not bounded by the selected page")
require("if (matched > limit)", "overflow rows do not expose a load-more action")
require("appPage = 1;", "search changes must reset pagination")
require("appWorker.shutdownNow();", "background app worker is not released on Activity destruction")
render = source[source.index("private void renderRows()"):source.index("@Override protected void onDestroy()")]
assert "getInstalledApplications(" not in render, "PackageManager inventory is still executed while rendering rows"
assert "getApplicationLabel(" not in render, "application labels are still loaded while rendering rows"
assert "for (ApplicationInfo info : apps)" in render, "paged renderer lost the application row loop"
print("PASS: Yulong firewall accepts multi-control cards, loads applications off-main-thread, pages rows and releases workers")
PY
