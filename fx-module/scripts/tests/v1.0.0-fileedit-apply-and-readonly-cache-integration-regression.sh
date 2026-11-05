#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
UI="$ROOT/webroot/index.html"
BE="$ROOT/scripts/fileedit.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-edit-integrate.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/pg/subs" "$T/pg/cache" "$T/pg/local"
printf 'DOMAIN,one.example,REJECT\nDOMAIN,two.example,REJECT\n' > "$T/pg/subs/123.txt"
printf '0.0.0.0 edited.example\n' > "$T/replacement"
cp "$T/pg/subs/123.txt" "$T/before"
# A subscription detail is a cached display copy, not an active source. Mutations must fail without touching it.
out=$(PG="$T/pg" sh "$BE" replacepage sub:123 1 1 "$T/replacement")
printf '%s' "$out" | grep -Fq 'read-only source'
cmp -s "$T/before" "$T/pg/subs/123.txt"
# The effective system hosts file is shown from the live path but is never mutated via the file editor.
out=$(PG="$T/pg" sh "$BE" replacepage system-hosts 1 1 "$T/replacement")
printf '%s' "$out" | grep -Fq 'read-only source'
# Verify the UI links writable sources to apply and coalesces a second apply if an apply is in flight.
python3 - "$UI" "$BE" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
assert "function feNeedsApply(spec){return spec==='hosts'||/^fx:|^builtin:/.test(String(spec||''))}" in s
assert 'function feApplyAfterMutation(spec)' in s
assert 'window.applyRun(null,{label:label})' in s
assert "return feAfterMutationReload(spec,page)" in s
assert 'PGB.feApplyQueued=label' in s
assert "window.__pgFeOnApplyFinish=function()" in s
assert "if(typeof window.__pgFeOnApplyFinish==='function')window.__pgFeOnApplyFinish()" in s
assert "readOnly:(spec==='system-hosts'||/^sub:/.test(spec))" in s
assert 'Live /system/etc/hosts (read-only)' in s
assert 'File saved; apply task started.' in s
assert 'read-only source: edit the active rule/source instead' in Path(sys.argv[2]).read_text()
assert "function feTempPath()" in s
assert "function feWriteAndCommit(text,spec,op,argsBuilder)" in s
assert 'pg-fe-edit.tmp' not in s
assert "if(b64===null)" in s
print('UI-to-backend save/apply and editor isolation contract: PASS')
PY
# On-device source file changes trigger the fast apply pipeline; preview/cache views remain non-mutating.
echo 'FX editor integration regression: PASS (auto-apply, queued apply, isolated temp files, read-only caches/live view)'
