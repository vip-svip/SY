#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
H="$ROOT/scripts/jsruntime/host.js"
node --check "$H"
grep -Fq 'function _fxReloadPrefs()' "$H"
grep -Fq 'valueForKey(k){const p=_fxReloadPrefs()' "$H"
grep -Fq "_fxStateDir+'/script-logs.jsonl'" "$H"
grep -Fq "globalThis.console={log:function(){_fxLog('info',arguments)" "$H"
if grep -Fq "globalThis.console={log:function(){},warn:function(){},error:function(){}}" "$H"; then
  echo 'FAIL: console methods silently discard script logs'; exit 1
fi
echo 'FX JS runtime diagnostics regression: PASS'
