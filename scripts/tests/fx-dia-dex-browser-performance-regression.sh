#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaDexBrowserActivity.java"
[ -s "$SOURCE" ] || { echo "FAIL: Dia DEX browser Activity is missing" >&2; exit 1; }
python3 - "$SOURCE" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")

def section(start, end):
    first = source.find(start)
    last = source.find(end, first + len(start))
    assert first >= 0 and last > first, f"missing DEX browser source section: {start}"
    return source[first:last]

assert "new ArrayBlockingQueue<>(2)" in source, "DEX I/O queue must be bounded"
assert 'new Thread(r, "fx-dia-dex-io")' in source, "DEX I/O worker must have a stable name"
assert "new ArrayBlockingQueue<>(1)" in source, "DEX search queue must keep only one pending query"
assert 'new Thread(r, "fx-dia-dex-search")' in source, "DEX search worker must have a stable name"
assert "ThreadPoolExecutor.DiscardOldestPolicy()" in source, "new searches must replace stale queued queries"
assert "private void loadInstalledApps()" in source
inventory = section("private void loadInstalledApps()", "private void chooseApp()")
assert "worker.execute(() -> {" in inventory, "installed app enumeration must run off the UI thread"
assert "pm.getInstalledApplications(0)" in inventory
assert "pm.getApplicationLabel(app)" in inventory, "app labels must be resolved on the worker"
assert "runOnUiThread(() -> {" in inventory, "inventory results must return to the UI thread"
assert "appsLoading" in inventory
chooser = section("private void chooseApp()", "private void loadFrameworkDex()")
assert "if (appsLoading)" in chooser, "the chooser must not race the asynchronous app inventory"
assert "正在后台读取已安装应用" in source

framework = section("private void loadFrameworkDex()", "private void loadDex()")
apk = section("private void loadDex()", "private void render()")
for body in (framework, apk):
    assert "worker.execute(() -> {" in body, "DEX parsing must remain on the bounded I/O worker"
    assert "request != dexGeneration" in body, "stale DEX parse results must not replace a newer selection"
    assert "RejectedExecutionException" in body, "DEX queue saturation must be reported"

render = section("private void render()", "private void DexClassRow(")
assert "searchWorker.execute(() -> {" in render, "class/member filtering must run off the UI thread"
assert "new ArrayList<>(classes)" in render, "background search must use a stable UI-created snapshot"
assert "request != searchGeneration" in render, "stale search results must not replace the latest query"
assert "Thread.currentThread().isInterrupted()" in render, "superseded search work must stop early"
assert "results.removeAllViews()" in render, "results are committed only on the UI thread"
assert "for (FxDiaDexIndex.DexClass item : classes)" not in render, "DEX member scans must not execute on the UI thread"
assert "private void DexClassRow(SearchHit hit)" in source
assert "private static final class SearchHit" in source

destroy = section("@Override protected void onDestroy()", "")
assert "destroyed = true;" in destroy
assert "searchGeneration++;" in destroy and "dexGeneration++;" in destroy
assert "worker.shutdownNow();" in destroy and "searchWorker.shutdownNow();" in destroy
assert "Executors.newSingleThreadExecutor" not in source, "unbounded DEX executor must not return"
print("PASS: Dia DEX inventory and filtering run on bounded workers; stale searches are dropped and Activity teardown cancels workers")
PY
