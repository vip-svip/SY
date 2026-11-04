#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxHookObservationLogsActivity.java"
[ -s "$ACTIVITY" ] || { echo "FAIL: Hook observation log Activity missing" >&2; exit 1; }
python3 - "$ACTIVITY" <<'PY'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text(encoding="utf-8")
required = [
    "private final AtomicBoolean refreshInFlight = new AtomicBoolean(false);",
    "refreshInFlight.compareAndSet(false, true)",
    "if (refreshButton != null) refreshButton.setEnabled(false);",
    "refreshInFlight.set(false);",
    "if (refreshButton != null) refreshButton.setEnabled(true);",
    "catch (RejectedExecutionException full)",
    "private static boolean isSafePackageName(String value)",
    'logcat -d -v threadtime -t 5000',
    'tail -n 300',
    'private static final int ROOT_OUTPUT_LIMIT = 64 * 1024;',
    'private static final int DISPLAY_LIMIT = 24 * 1024;',
    'generation++',
    'worker.shutdownNow();',
]
for token in required:
    assert token in s, f"missing Hook observation log lifecycle/bounds contract: {token}"
assert s.count("refreshInFlight.set(false);") >= 3, \
    "refresh guard must be released on completion, queue rejection, and teardown"
refresh = s[s.index("private void refresh() {"):s.index("private int countLines", s.index("private void refresh() {"))]
assert refresh.index("compareAndSet(false, true)") < refresh.index("worker.execute("), \
    "refresh guard must be acquired before submitting Root work"
assert "catch (RuntimeException failure)" in refresh, \
    "RootAccess runtime failures must not permanently strand the refresh guard"
assert "request != generation" in refresh, \
    "stale refresh completion must not overwrite a newer screen"
print("PASS: Hook observation log refresh is single-flight, bounded, stale-result guarded and lifecycle-safe")
PY
