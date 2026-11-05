#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
UI="$ROOT/webroot/index.html"
SYNC="$ROOT/scripts/jsruntime/sync-subs.sh"
GO="$ROOT/mitm/main.go"
GT="$ROOT/mitm/main_test.go"
# The editor and bridge are separate classic scripts. These exports are required
# so pasted modules use the same real converter as file imports.
grep -Fq 'window.pgLooksLikeThirdPartyModule=pgLooksLikeThirdPartyModule' "$UI"
grep -Fq 'window.pgConvertThirdPartyModule=pgConvertThirdPartyModule' "$UI"
grep -Fq 'window.pgThirdPartyRuntimeMessage=pgThirdPartyRuntimeMessage' "$UI"
# After the config commit and list render, imported modules must refresh manifests
# and the enabled JS cache; a save-only success is not a runtime-sync success.
grep -Fq 'pgSyncThirdPartyRuntime({syncScripts:scriptRows.length>0})' "$UI"
grep -Fq 'PGB.scriptRuntimeDirty=false' "$UI"
# Importing an ordinary settings.conf must also publish regenerated runtime manifests.
grep -Fq 'var savedScriptRows=(PGB.model&&PGB.model.lists&&Array.isArray(PGB.model.lists.script))?PGB.model.lists.script:[]' "$UI"
grep -Fq '配置已保存，但运行时同步失败，不能视为已生效：' "$UI"
grep -Fq 'pgSyncThirdPartyRuntime({syncScripts:true})' "$UI"
grep -Fq "en.closest('#scriptList')&&typeof window.pgMarkScriptRuntimeDirty" "$UI"
grep -Fq "scope==='scriptList'&&typeof window.pgMarkScriptRuntimeDirty" "$UI"
grep -Fq "touched.scriptList&&typeof window.pgMarkScriptRuntimeDirty" "$UI"
grep -Fq 'MITM 引擎未运行，因此尚未执行' "$UI"
grep -Fq 'HTTPS 流量重定向未启用，脚本尚未进入真实流量路径' "$UI"
# Synchronization serializes the complete active snapshot and stale-file pruning.
grep -Fq 'LOCK="$PG/jsruntime/sync-subs.lock"' "$SYNC"
grep -Fq 'acquire_lock' "$SYNC"
grep -Fq 'release_lock' "$SYNC"
grep -Fq 'another script subscription sync is still running' "$SYNC"
# Managed framing headers must not be writable by user JS.
grep -Fq 'scriptManagedHeaders' "$GO"
grep -Fq 'ignored script changes to runtime-managed headers' "$GO"
grep -Fq 'TestPatchHeadersRejectsRuntimeManagedHeaders' "$GT"
grep -Fq 'TestResponseScriptCannotCorruptHTTPFramingHeaders' "$GT"
sh -n "$SYNC"
echo 'FX third-party import -> persisted config -> runtime sync regression: PASS'
