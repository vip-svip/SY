#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
JAVA="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
[ -s "$JAVA" ] || { echo "FAIL: MainActivity missing" >&2; exit 1; }
grep -Fq 'private final BroadcastReceiver packageChangeReceiver = new BroadcastReceiver()' "$JAVA"
grep -Fq 'Intent.ACTION_PACKAGE_ADDED' "$JAVA"
grep -Fq 'Intent.ACTION_PACKAGE_REMOVED' "$JAVA"
grep -Fq 'Intent.ACTION_PACKAGE_REPLACED' "$JAVA"
grep -Fq 'Intent.ACTION_PACKAGE_FULLY_REMOVED' "$JAVA"
grep -Fq 'filter.addDataScheme("package");' "$JAVA"
grep -Fq 'Context.RECEIVER_NOT_EXPORTED' "$JAVA"
grep -Fq 'intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)' "$JAVA"
grep -Fq 'if (replacing && (added || removed)) return;' "$JAVA"
grep -Fq 'private boolean isHookAppListVisible()' "$JAVA"
grep -Fq 'private void refreshHookAppList()' "$JAVA"
grep -Fq 'if (isHookAppListVisible()) refreshHookAppList();' "$JAVA"
grep -Fq 'unregisterPackageChangeReceiver();' "$JAVA"
python3 - "$JAVA" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")

def body(signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 0
    for i in range(opening, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[start:i + 1]
    raise AssertionError("unterminated method: " + signature)

resume = body("@Override protected void onResume()")
pause = body("@Override protected void onPause()")
destroy = body("@Override protected void onDestroy()")
refresh = body("private void refreshHookAppList()")
receiver = body("private void registerPackageChangeReceiver()")
unregister = body("private void unregisterPackageChangeReceiver()")
assert "registerPackageChangeReceiver();" in resume
assert "isHookAppListVisible() && appsLoaded && appLoaderThread == null" in resume
assert "getApplicationInfo(selectedPackage, 0)" in resume
assert "unregisterPackageChangeReceiver();" in pause and "unregisterPackageChangeReceiver();" in destroy
assert "loadAppsAsync();" in refresh and "isHookAppListVisible()" in refresh
assert "Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU" in receiver
assert "Context.RECEIVER_NOT_EXPORTED" in receiver
assert "packageChangeReceiverRegistered = true;" in receiver
assert "packageChangeReceiverRegistered = false;" in unregister
assert "showAppList(activePrivacySection);" in source
print("PASS: Hook package install/update/uninstall events, lifecycle cleanup and resume revalidation")
PY
