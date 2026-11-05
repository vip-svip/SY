#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SYNC="$ROOT/scripts/jsruntime/sync-subs.sh"
SCHED="$ROOT/scripts/jsruntime/scheduler.sh"
ENGINE="$ROOT/scripts/mitm-engine.sh"
MAIN="$ROOT/mitm/main.go"
UI="$ROOT/webroot/index.html"
[ -x "$SYNC" ] && [ -x "$SCHED" ] || { echo 'FAIL: JS subscription lifecycle scripts missing'; exit 1; }
sh -n "$SYNC"
sh -n "$SCHED"
grep -Fq 'https://*)' "$SYNC"
grep -Fq 'sha256sum' "$SYNC"
grep -Fq 'FX-SCRIPT-TYPE' "$SYNC"
grep -Fq 'pg_list script' "$SYNC"
grep -Fq 'script_auto_update_h=24' "$ROOT/scripts/default.conf"
grep -Fq 'scheduler.sh' "$ROOT/service.sh"
grep -Fq 'scheduler.pid' "$ROOT/uninstall.sh"
grep -Fq 'e.refreshScripts()' "$MAIN"
grep -Fq 'validManagedScriptHash(path)' "$MAIN"
grep -Fq 'sync-subs.sh' "$UI"
echo 'FX JS subscription lifecycle regression: PASS'
