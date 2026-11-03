#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaDexBrowserActivity.java"
INDEX="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaDexIndex.java"
UNIT_TEST="$ROOT/adhook/app/src/test/java/de/privacyguard/adhook/imported/dia/FxDiaDexIndexTest.java"
[ -s "$SOURCE" ] || { echo "FAIL: Dia DEX browser Activity is missing" >&2; exit 1; }
python3 - "$SOURCE" "$INDEX" "$UNIT_TEST" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
index = Path(sys.argv[2]).read_text(encoding="utf-8")
unit_test = Path(sys.argv[3]).read_text(encoding="utf-8")

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
assert "appLabels.getOrDefault(" in chooser, "application labels must come from the background inventory cache"
assert "getPackageManager().getApplicationLabel" not in chooser, "the chooser must not resolve labels on the UI thread"
assert "appLabels.putAll(loadedLabels)" in inventory, "background inventory labels must be published with app rows"
assert "正在后台读取已安装应用" in source

framework = section("private void loadFrameworkDex()", "private void loadDex()")
apk = section("private void loadDex()", "private void render()")
for body in (framework, apk):
    assert "worker.execute(() -> {" in body, "DEX parsing must remain on the bounded I/O worker"
    assert "request != dexGeneration" in body, "stale DEX parse results must not replace a newer selection"
assert "FxDiaDexIndex.readDex(input," in framework, "Framework DEX reads must pass a cancellation callback"
assert "FxDiaDexIndex.readApks(paths," in apk, "APK/split APK reads must pass a cancellation callback"
assert "Thread.currentThread().isInterrupted() || request != dexGeneration" in framework
assert "Thread.currentThread().isInterrupted() || request != dexGeneration" in apk
    assert "RejectedExecutionException" in body, "DEX queue saturation must be reported"

render = section("private void render()", "private void DexClassRow(")
assert "searchWorker.execute(() -> {" in render, "class/member filtering must run off the UI thread"
assert "new ArrayList<>(classes)" in render, "background search must use a stable UI-created snapshot"
assert "private static void checkCancellation(BooleanSupplier cancelled)" in index, "DEX indexer lacks a cancellation gate"
assert "checkCancellation(cancelled);" in index, "APK/DEX streams must check cancellation while reading"
assert "checkCancellation();" in index, "class/member parsing loops must observe cancellation"
assert "malformedCode instanceof InterruptedIOException" in index, "parser must not swallow cancellation as malformed code"
assert "cancellationIsObservedBeforeReadingDexOrApk" in unit_test, "cancellation unit test is missing"
assert "request != searchGeneration" in render, "stale search results must not replace the latest query"
assert "Thread.currentThread().isInterrupted()" in render, "superseded search work must stop early"
assert "request != searchGeneration) return;" in render, "running search must stop when a newer query is published"
assert render.count("request != searchGeneration) return;") >= 3, "search must check cancellation in class and member loops"
assert "private volatile int searchGeneration;" in source, "search cancellation generation must be visible across threads"
assert "results.removeAllViews()" in render, "results are committed only on the UI thread"
assert "for (FxDiaDexIndex.DexClass item : classes)" not in render, "DEX member scans must not execute on the UI thread"
assert "private void DexClassRow(SearchHit hit)" in source
assert "private static final class SearchHit" in source

export = section("private void exportMatches()", "private void showClassMembers(")
assert "exportWorker.execute(() -> {" in export, "signature export must run off the UI thread"
assert "new ArrayList<>(classes)" in export, "signature export must use a stable UI-created snapshot"
assert "Thread.currentThread().isInterrupted()" in export, "superseded exports must stop early"
assert "request != exportGeneration) return;" in export, "running export must stop when a newer export/query is published"
assert export.count("request != exportGeneration) return;") >= 4, "export must check cancellation in outer and member loops"
assert "private volatile int exportGeneration;" in source, "export cancellation generation must be visible across threads"
assert "runOnUiThread(() -> {" in export, "clipboard access must return to the UI thread"
assert "clipboard.setPrimaryClip(" in export, "exported signatures must still reach the system clipboard"
assert "for (FxDiaDexIndex.DexClass item : classes)" not in export, "DEX export must not scan the class graph on the UI thread"
assert "512 * 1024" in export and "12000" in export, "signature export size/count safeguards must remain"

assert 'new Thread(r, "fx-dia-dex-export")' in source, "DEX export worker must have a stable name"
assert 'new Thread(r, "fx-dia-dex-detail")' in source, "DEX detail worker must have a stable name"
detail = section("private void showClassMembers(", "private String buildClassDetail(")
assert "detailWorker.execute(() -> {" in detail, "member/call detail construction must run off the UI thread"
assert "runOnUiThread(() -> {" in detail, "member dialog must be displayed on the UI thread"
assert "buildClassDetail(item, q, request)" in detail
assert "request != detailGeneration" in detail, "class detail must pass its generation into the worker"
assert "for (FxDiaDexIndex.Member" not in detail, "the UI click handler must not scan class members"
builder = section("private String buildClassDetail(", "@Override protected void onDestroy()")
assert "Thread.currentThread().isInterrupted()" in builder, "superseded detail work must stop early"
assert "request != detailGeneration) return null;" in builder, "class detail must stop on a newer detail/query request"
assert builder.count("request != detailGeneration) return null;") >= 2, "detail must check cancellation in member and call loops"
assert "private volatile int detailGeneration;" in source, "detail cancellation generation must be visible across threads"
assert "count >= 400" in builder and "callCount >= 200" in builder, "member/call detail limits must remain"
assert "append('\\n')" in builder, "member detail output must use actual line breaks, not literal backslash-n text"

destroy_start = source.find("@Override protected void onDestroy()")
assert destroy_start >= 0, "Activity cleanup method is missing"
destroy = source[destroy_start:]
assert "destroyed = true;" in destroy
assert "private volatile int dexGeneration;" in source, "DEX load generation must be visible across threads"
assert "searchGeneration++;" in destroy and "exportGeneration++;" in destroy and "dexGeneration++;" in destroy
assert "worker.shutdownNow();" in destroy and "searchWorker.shutdownNow();" in destroy and "exportWorker.shutdownNow();" in destroy and "detailWorker.shutdownNow();" in destroy
assert "Executors.newSingleThreadExecutor" not in source, "unbounded DEX executor must not return"
print("PASS: Dia DEX parsing, search, export and detail work are bounded and generation-cancellable")
PY
