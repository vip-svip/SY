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
grep -Fq 'private void postUi(Runnable update)' "$VIRUS" || fail "Virus DB callbacks are not lifecycle guarded"
grep -Eq 'destroyed[[:space:]]*=[[:space:]]*true' "$VIRUS" || fail "Virus DB Activity teardown does not invalidate callbacks"
grep -Fq 'checkButton.setEnabled(false)' "$INTEGRITY" || fail "Integrity check does not prevent duplicate requests"
grep -Fq 'request != checkGeneration' "$INTEGRITY" || fail "late Integrity results are not generation guarded"
echo "PASS: Shield virus-database and integrity workers are bounded, reject overload and discard stale Activity callbacks"
