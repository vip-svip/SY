#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
HOOK="$ROOT/lsposed/app/src/main/java/de/privacyguard/hook/MainHook.java"
grep -Fq '应用进程枚举隐藏（LSPosed）' "$HTML"
grep -Fq '不是内核 task_struct 钩子' "$HTML"
! grep -Fq "if(k==='k_task')" "$HTML"
grep -Fq 'boolean taskHide = on("k_task")' "$HOOK"
grep -Fq 'getRunningAppProcesses' "$HOOK"
grep -Fq 'if (!taskHide) return;' "$HOOK"
echo 'FX k_task toggle/backend consistency regression: PASS'
