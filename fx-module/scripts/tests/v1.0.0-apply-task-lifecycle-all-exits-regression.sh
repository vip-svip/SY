#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
UI="$ROOT/webroot/index.html"
python3 - "$UI" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
assert 'var cancel=document.getElementById(\'applyCancel\')' in s
assert "cancel.disabled=!on||!PGB.applyPid" in s
# A click during preflight/synchronous fallback must not clear the busy lock without a PID.
start=s.index('function applyCancel(){')
end=s.index('\nwindow.applyCancel=applyCancel;', start)
block=s[start:end]
assert "if(!pid){toast(lt('应用仍在准备或同步执行" in block
no_pid=block.split('if(!pid){',1)[1].split('}',1)[0]
assert 'PGB.applyBusy=false' not in no_pid and 'PGB.applyPid=0' not in no_pid
assert 'function pgApplyFinish(ok,label,why)' in s
finish=s[s.index('function pgApplyFinish(ok,label,why)'):s.index('function applyRun(sub,opts)')]
assert "window.__pgFeOnApplyFinish==='function'" in finish
# Sync-fallback success and failure both release the lock and notify a queued editor apply.
sync=s[s.index("if(pid===-1){",s.index('function applyRun(sub,opts)')):s.index('pgApplyPollStart(pid,label,timeout);',s.index('function applyRun(sub,opts)'))]
assert sync.count("window.__pgFeOnApplyFinish==='function'") >= 2
assert 'PGB.applyBusy=false;PGB.applyPid=0;' in sync
assert 'Synchronous apply command failed; task lock released, check logs' in sync
# Spawn/persist failure also drains a queued follow-up instead of leaving it stranded.
apply=s[s.index('function applyRun(sub,opts)'):s.index('window.applyRun=applyRun;')]
assert "if(typeof window.__pgFeOnApplyFinish==='function')window.__pgFeOnApplyFinish()" in apply
print('apply task lifecycle all-exits regression: PASS')
PY
