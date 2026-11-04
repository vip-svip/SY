#!/usr/bin/env python3
"""Regression for the Frida target picker main-thread responsiveness contract."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java").read_text(encoding="utf-8")

def body(signature, next_signature):
    start = source.index(signature)
    end = source.index(next_signature, start)
    return source[start:end]

choose = body("private void chooseTarget()", "private void showTargetPicker(")
picker = body("private void showTargetPicker(", "private void chooseTargetProcesses()")
destroy = body("@Override protected void onDestroy()", "\n    }")

assert "targetLoading" in choose, "repeated taps must not enqueue duplicate PackageManager scans"
assert "worker.execute(() -> {" in choose, "Frida target enumeration must use the bounded worker"
assert choose.index("worker.execute(() -> {") < choose.index("pm.getInstalledApplications(0)"), \
    "PackageManager installed-app enumeration still runs on the UI thread"
assert "pm.getApplicationLabel(info)" in choose, "application labels must also load off-main"
assert "targets.sort(Comparator.comparing(" in choose, "target labels must be sorted off-main"
assert "runOnUiThread(() -> {" in choose, "target picker result must return to the UI thread"
assert "request != targetLoadGeneration" in choose, "late target-load callbacks must be discarded"
assert "targetLoading = false" in choose, "target loading state must reset on completion and queue rejection"
assert "RejectedExecutionException full" in choose, "bounded queue saturation must be reported"
assert "showTargetPicker(result)" in choose, "successful async load must continue into the picker"
assert "getInstalledApplications" not in picker and "getApplicationLabel" not in picker, \
    "showTargetPicker must not perform PackageManager work on the UI thread"
assert "targetPackage = targets.get(which).packageName" in picker
assert 'putString("target_package", targetPackage)' in picker and 'putString("target_name", targetName)' in picker
assert "targetLoadGeneration++" in destroy and "worker.shutdownNow()" in destroy, \
    "Activity destruction must invalidate pending picker callbacks and close the worker"
assert "new ArrayBlockingQueue<>(12)" in source and "new ThreadPoolExecutor.AbortPolicy()" in source, \
    "Frida background work must remain bounded"
print("PASS: Frida target picker enumerates/sorts off-main, rejects duplicate scans, discards stale callbacks and preserves target selection")
