#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
VIRUS="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongVirusDatabaseActivity.java"
INTEGRITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongIntegrityActivity.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$VIRUS" ] && [ -s "$INTEGRITY" ] || fail "Shield source missing"
for source in "$VIRUS" "$INTEGRITY"; do
  ! grep -Fq 'Executors.newSingleThreadExecutor()' "$source" || fail "unbounded ExecutorService remains in $source"
  grep -Fq 'new ArrayBlockingQueue<>(1)' "$source" || fail "worker queue is not bounded in $source"
  grep -Fq 'new ThreadPoolExecutor.AbortPolicy()' "$source" || fail "queue saturation must reject visibly in $source"
  grep -Fq 'RejectedExecutionException' "$source" || fail "queue rejection is not handled in $source"
  grep -Fq 'worker.shutdownNow()' "$source" || fail "worker is not stopped on Activity teardown in $source"
done

# Both workers are UI-triggered single-thread executors: keep one active job and
# at most one pending job, and never use a caller-runs policy on the main thread.
for source in "$VIRUS" "$INTEGRITY"; do
  grep -Fq 'new ThreadPoolExecutor(' "$source" || fail "bounded ThreadPoolExecutor missing in $source"
  grep -Eq '^[[:space:]]*1,[[:space:]]*1,' "$source" || fail "worker must remain single-threaded in $source"
  grep -Fq 'TimeUnit.SECONDS' "$source" || fail "worker keep-alive unit is missing in $source"
  ! grep -Eq 'CallerRunsPolicy|DiscardPolicy|DiscardOldestPolicy' "$source" || fail "worker must not silently run/drop tasks in $source"
  grep -Fq 'catch (RejectedExecutionException' "$source" || fail "queue saturation must be handled at submission in $source"
done

grep -Fq 'private void postUi(Runnable update)' "$VIRUS" || fail "Virus DB callbacks are not lifecycle guarded"
grep -Fq 'if (destroyed || isFinishing() || isDestroyed()) return;' "$VIRUS" || fail "Virus DB UI callbacks can outlive the Activity"
python3 - "$VIRUS" "$INTEGRITY" <<'PY'
from pathlib import Path
import sys

virus, integrity = (Path(path).read_text(encoding="utf-8") for path in sys.argv[1:])
def ordered(source, before, after, label):
    first, second = source.find(before), source.find(after)
    if first < 0 or second < 0 or first >= second:
        raise SystemExit(f"FAIL: {label}")

ordered(virus, "destroyed=true;", "worker.shutdownNow();",
        "Virus DB teardown must invalidate callbacks before stopping its worker")
ordered(integrity, "destroyed = true;", "checkGeneration++;",
        "Integrity teardown must invalidate pending generations")
ordered(integrity, "checkGeneration++;", "worker.shutdownNow();",
        "Integrity teardown must invalidate generation before stopping its worker")
PY
grep -Fq 'checkButton.setEnabled(false)' "$INTEGRITY" || fail "Integrity check does not prevent duplicate requests"
grep -Fq 'request != checkGeneration' "$INTEGRITY" || fail "late Integrity results are not generation guarded"
grep -Fq 'catch (Throwable error)' "$INTEGRITY" || fail "Root worker exceptions are not converted to a UI result"
grep -Fq 'checkButton.setEnabled(true)' "$INTEGRITY" || fail "Integrity check button is not restored after worker completion/failure"
grep -Fq 'moduleStatus.setText(report)' "$INTEGRITY" || fail "Integrity worker failure/result is not reported on the UI thread"
python3 - "$INTEGRITY" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
required = (
    r'[ ! -L \"$d\" ]',
    r'[ ! -L \"$d/module.prop\" ]',
    r'[ ! -L \"$MP/$f\" ]',
    r'[ ! -L \"$MP/bin/arm64/qjs\" ]',
)
for token in required:
    if token not in source:
        raise SystemExit(f"FAIL: module integrity check follows symlink input; missing {token}")
PY

echo "PASS: Shield workers are single-threaded and bounded, reject overload explicitly, and invalidate UI callbacks before teardown"
