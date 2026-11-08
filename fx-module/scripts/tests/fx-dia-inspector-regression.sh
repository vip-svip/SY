#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaInspectorActivity.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$SOURCE" ] || fail "Dia inspector Activity missing"
python3 - "$SOURCE" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
load_start = source.index("private void loadApps(Runnable whenReady)")
load_end = source.index("private void chooseTarget()", load_start)
load = source[load_start:load_end]
assert "worker.execute(() -> {" in load, "installed app enumeration must run in the bounded background worker"
assert load.index("worker.execute(() -> {") < load.index("packageManager.getInstalledApplications(0)"), \
    "PackageManager enumeration still runs on the Activity main thread"
assert "packageManager.getApplicationLabel(app)" in load, "application labels must be loaded off-main too"
assert "loaded.sort(Comparator.comparing(" in load, "label sorting must remain off-main"
assert "runOnUiThread(() -> {" in load, "app list results must return to main thread"
assert "generation != appLoadGeneration" in load, "stale app enumeration must not update a destroyed Activity"
assert "appsReadyCallback" in load and "RejectedExecutionException full" in load, \
    "app picker must resume after async load and report bounded-queue saturation"
choose_start = source.index("private void chooseTarget()")
choose_end = source.index("private void showTargetPicker()", choose_start)
choose = source[choose_start:choose_end]
picker_start = source.index("private void showTargetPicker()")
picker_end = source.index("private void inspect()", picker_start)
picker = source[picker_start:picker_end]
assert "loadApps(this::showTargetPicker)" in choose, "picker must wait for asynchronous enumeration"
assert "getApplicationLabel" not in picker and "getInstalledApplications" not in picker, \
    "picker must not perform PackageManager work on the UI thread"
assert "appLoadGeneration++" in source and "worker.shutdownNow()" in source, \
    "Activity teardown must invalidate callbacks and close the worker"
assert "new ArrayBlockingQueue<>(4)" in source and "new ThreadPoolExecutor.AbortPolicy()" in source
print("PASS: Dia inspector app picker enumerates/sorts off-main, resumes after loading, discards stale callbacks and bounds worker queue")
PY
