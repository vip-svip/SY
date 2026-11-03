#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="$ROOT/adhook/app/src/main/java/roro/stellar/manager/authorization/FxStellarManagerActivity.java"
[ -s "$SOURCE" ] || { echo "FAIL: Stellar manager Activity source missing" >&2; exit 1; }
python3 - "$SOURCE" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")

worker_start = source.index("private final ThreadPoolExecutor worker")
worker_end = source.index("private final List<ApplicationInfo> apps", worker_start)
worker = source[worker_start:worker_end]
assert "new ArrayBlockingQueue<>(16)" in worker, "Root work queue must stay bounded"
assert "new ThreadPoolExecutor.AbortPolicy()" in worker, "queue saturation must be rejected, not silently discarded"

root_start = source.index("private void root(")
root_end = source.index("private String appLabel", root_start)
root = source[root_start:root_end]
assert "catch(RejectedExecutionException full)" in root, "Root queue rejection must be handled"
assert "RootAccess.failure(75," in root, "queue saturation must be surfaced as an explicit failure result"

load_start = source.index("private void loadApplications()")
load_end = source.index("private void updateTargetLabel()", load_start)
load = source[load_start:load_end]
assert "worker.execute(()->{" in load, "application inventory must run on the background worker"
assert "getInstalledApplications(0)" in load, "installed application inventory must not be replaced by a stub"
assert "loaded.sort(Comparator.comparing" in load, "application label sorting must remain available"
assert "runOnUiThread(()->{" in load, "application inventory may only update views on the UI thread"

create_start = source.index("@Override protected void onCreate")
create_end = source.index("private void render()", create_start)
create = source[create_start:create_end]
assert "getInstalledApplications" not in create, "onCreate must not enumerate packages on the main thread"
assert "loadApplications();" in create, "onCreate must schedule asynchronous inventory loading"
assert 'saved.getString("stellar_target_package","")' in create, "selected target package must be restored"

save_start = source.index("protected void onSaveInstanceState")
save_end = source.index("private void render()", save_start)
save = source[save_start:save_end]
assert 'out.putString("stellar_target_package",target)' in save, "selected target package must survive Activity recreation"
assert "worker.shutdownNow()" in source, "worker must be stopped with Activity lifecycle"
print("PASS: Stellar manager app inventory is off-main-thread, Root work is bounded, and target selection is restorable")
PY
