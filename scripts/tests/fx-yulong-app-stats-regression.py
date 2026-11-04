#!/usr/bin/env python3
"""Static lifecycle and threading contract for Yulong per-app UID statistics."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAppStatsActivity.java").read_text(encoding="utf-8")
start = source.index("private void refresh()")
end = source.index("private void render()", start)
refresh = source[start:end]
assert "worker.submit(() -> {" in refresh, "package enumeration must run on the background executor"
assert refresh.index("worker.submit(() -> {") < refresh.index("getInstalledApplications(0)"), \
    "installed application enumeration still runs before background dispatch"
assert "TrafficStats.getUidRxBytes(app.uid)" in refresh and "TrafficStats.getUidTxBytes(app.uid)" in refresh
assert "totals.add(app.uid, rx, tx)" in refresh, "summary must aggregate shared UIDs once"
assert "runOnUiThread(() -> {" in refresh, "results must return to the UI thread"
assert "generation != refreshGeneration.get()" in refresh, "stale refresh results must be discarded"
assert "refreshTask.cancel(true)" in source and "worker.shutdownNow()" in source, \
    "Activity destruction must cancel work and close the executor"
assert "new ArrayBlockingQueue<>(1)" in source, "refresh queue must have a strict one-task bound"
assert "new ThreadPoolExecutor.AbortPolicy()" in source, "refresh overload must reject rather than accumulate unbounded work"
assert "RejectedExecutionException rejected" in refresh, "queue saturation must be surfaced"
assert "Executors.newSingleThreadExecutor()" not in source, "unbounded executor remains"
assert 'private static String bytes(long v)' in source
assert '"\\n累计接收（按唯一 UID）：" + bytes(totals.getRxBytes())' in source, \
    "summary must use a real newline and disclose unique-UID aggregation"

totals = (ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/UidTrafficTotals.java").read_text(encoding="utf-8")
for token in ("seenUids.add(uid)", "getUnavailableUidCount()", "saturatedAdd", "Long.MAX_VALUE"):
    assert token in totals, f"UID totals safety invariant missing: {token}"
print("PASS: Yulong app stats run off-main, cancel stale refreshes, close on destroy and aggregate unique UIDs")
