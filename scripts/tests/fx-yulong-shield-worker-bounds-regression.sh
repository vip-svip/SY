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
  grep -Eq 'new ThreadPoolExecutor\([[:space:]]*1,[[:space:]]*1,' "$source" || fail "worker must remain single-threaded in $source"
  grep -Fq 'TimeUnit.SECONDS' "$source" || fail "worker keep-alive unit is missing in $source"
  ! grep -Eq 'CallerRunsPolicy|DiscardPolicy|DiscardOldestPolicy' "$source" || fail "worker must not silently run/drop tasks in $source"
  grep -Fq 'catch (RejectedExecutionException' "$source" || fail "queue saturation must be handled at submission in $source"
done

grep -Fq 'private void postUi(Runnable update)' "$VIRUS" || fail "Virus DB callbacks are not lifecycle guarded"
grep -Fq 'if (destroyed || isFinishing() || isDestroyed()) return;' "$VIRUS" || fail "Virus DB UI callbacks can outlive the Activity"
grep -Eq 'destroyed[[:space:]]*=[[:space:]]*true;[[:space:]]*worker\.shutdownNow\(\)' "$VIRUS" || fail "Virus DB teardown must invalidate callbacks before stopping its worker"
grep -Fq 'checkButton.setEnabled(false)' "$INTEGRITY" || fail "Integrity check does not prevent duplicate requests"
grep -Fq 'request != checkGeneration' "$INTEGRITY" || fail "late Integrity results are not generation guarded"
grep -Eq 'destroyed[[:space:]]*=[[:space:]]*true;[[:space:]]*checkGeneration\+\+;[[:space:]]*worker\.shutdownNow\(\)' "$INTEGRITY" || fail "Integrity teardown must invalidate generation before stopping its worker"
echo "PASS: Shield workers are single-threaded and bounded, reject overload explicitly, and invalidate UI callbacks before teardown"
