#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
JAVA="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFileActivity.java"
[ -s "$JAVA" ] || { echo "FAIL: Dia file browser is missing" >&2; exit 1; }
python3 - "$JAVA" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")

def section(start, end):
    first = source.find(start)
    last = source.find(end, first + len(start))
    assert first >= 0 and last > first, f"missing source section: {start}"
    return source[first:last]

assert "new ThreadPoolExecutor(2, 2, 30L" in source, "file browser must use a small bounded worker pool"
assert "new ArrayBlockingQueue<>(8)" in source, "file browser I/O queue must be bounded"
assert "new Thread(r, \"fx-dia-file-io\")" in source, "worker threads must be named"
assert source.count("new Thread(") == 1, "raw per-action Threads must be removed"
assert "private void submitIo(String operation, Runnable task)" in source
assert "private void postUi(Runnable action)" in source

directory = section("private void loadDirectory()", "private void appendDirectoryPage()")
assert "submitIo(\"读取目录\"" in directory, "SAF directory query is not on a worker"
assert "getContentResolver().query(children" in directory
assert "directoryRequestId" in directory and "request != directoryRequestId" in directory,     "stale directory responses must not overwrite the latest location"
assert "MAX_DIRECTORY_ENTRIES = 5000" in source
assert "DIRECTORY_PAGE_SIZE = 100" in source
assert "final int maxSoEntries = 2000;" in source, "SO inventory must be capped"
assert "if (count >= maxSoEntries)" in source, "SO inventory cap must be enforced"
assert "Native Library Dir 不可读取" in source, "native library directory exceptions must be reported"

# The new Java methods must use real Java escape sequences, not literal backslash text.
preview_so = section("private void preview(Entry entry)", "private String bytes(long n)")
assert r"content.indexOf('\uFFFD')" in preview_so, "UTF-8 replacement marker must be a valid Java char literal"
assert r"append('\n')" in preview_so, "SO report must use valid Java newline char literals"
assert r'append("\n\n")' in preview_so, "SO report must use actual newlines, not visible backslash-n text"
assert r'+ "\n"' in preview_so, "debug target labels must use an actual line break"
assert r'.setMessage("仅删除所选授权目录中的文件：\n"' in preview_so, "delete confirmation must contain an actual newline"
assert r"content.indexOf('\\\\uFFFD')" not in preview_so, "double-escaped replacement character is invalid"
pages = section("private void appendDirectoryPage()", "private Uri docUri")
assert "DIRECTORY_PAGE_SIZE" in pages and "加载更多" in pages
assert "directoryTruncated" in pages and "只读取前" in pages

for name, end in (
    ("private void createFolder()", "private void pickImport()"),
    ("private void importFile(Uri uri)", "private void preview(Entry entry)"),
    ("private void preview(Entry entry)", "private void beginExport(Entry e)"),
    ("private void exportFile(Uri destination)", "private void confirmDelete(Entry entry)"),
    ("private void confirmDelete(Entry entry)", "private void chooseDebugTarget()"),
    ("private void chooseDebugTarget()", "private void inspectSo(ApplicationInfo app)"),
    ("private void inspectSo(ApplicationInfo app)", "private String bytes(long n)"),
):
    body = section(name, end)
    assert "submitIo(" in body, f"{name} still performs file/APK work without the bounded executor"
    assert "new Thread(" not in body, f"{name} still creates its own thread"

assert "final Uri destinationParent = parentUri();" in source, "import must capture the selected SAF parent before async work"
assert "private void onDestroy()" in source or "@Override protected void onDestroy()" in source
assert "destroyed = true;" in source and "directoryRequestId++;" in source
assert "ioWorker.shutdownNow();" in source, "Activity must release its worker pool"
assert "if (!destroyed && !isFinishing() && !isDestroyed()) action.run();" in source,     "worker callbacks must not update a destroyed Activity"
print("PASS: Dia file I/O bounded, SAF directory loading paged/off-main, SO inspection off-main, Activity cleanup")
PY
