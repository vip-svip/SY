#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
DIA="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for name in FxDiaActivityBrowserActivity FxDiaBackupActivity FxDiaFridaActivity FxDiaInspectorActivity FxDiaJsonActivity FxDiaWifiProxyActivity FxDiaWifiProxyTileService; do
  file="$DIA/$name.java"
  [ -s "$file" ] || fail "missing migrated Dia source: $name"
  grep -Fq 'new ArrayBlockingQueue<>' "$file" || fail "$name worker queue must be bounded"
  grep -Fq 'new ThreadPoolExecutor.AbortPolicy()' "$file" || fail "$name must reject queue overflow instead of dropping work"
  grep -Fq 'RejectedExecutionException' "$file" || fail "$name must handle queue saturation"
  grep -Fq 'submitWorker(Runnable task)' "$file" || fail "$name must centralize worker saturation handling"
  grep -Fq 'worker.shutdownNow()' "$file" || fail "$name must stop its worker with Activity/service lifecycle"
  ! grep -Fq 'Executors.newSingleThreadExecutor' "$file" || fail "$name must not restore an unbounded executor"
done
echo "PASS: seven Dia browser/backup/monitor/inspector/JSON/proxy workers are bounded and report saturation"
