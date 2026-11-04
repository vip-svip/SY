#!/usr/bin/env bash
set -eu
# bounded Frida Gadget session source checks and one local lifecycle fixture
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java"
SESSION_LOG="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaSessionLogActivity.java"
[ -s "$ACTIVITY" ] || { echo "FAIL: Dia Frida Activity source missing" >&2; exit 1; }
[ -s "$SESSION_LOG" ] || { echo "FAIL: Dia Frida session log Activity source missing" >&2; exit 1; }
python3 - "$ACTIVITY" "$SESSION_LOG" <<'PY'
from pathlib import Path
import re, sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
session_log = Path(sys.argv[2]).read_text(encoding="utf-8")
assert re.search(r"new ThreadPoolExecutor\\(\\s*1,\\s*1,\\s*30L,\\s*TimeUnit\\.SECONDS,\\s*new ArrayBlockingQueue<>\\(1\\)", session_log)
assert "new ThreadPoolExecutor.AbortPolicy()" in session_log
assert "catch (RejectedExecutionException full)" in session_log
assert "worker.shutdownNow();" in session_log
assert "FX_GADGET_LOG_TYPE_REJECTED" in source
print("PASS: bounded Gadget/session log worker and file guards")
PY
