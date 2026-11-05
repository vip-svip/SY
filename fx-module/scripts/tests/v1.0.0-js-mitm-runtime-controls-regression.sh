#!/system/bin/sh
# Regression for current MITM runtime status diagnostics and explicit opt-in.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
ENGINE="$ROOT/scripts/mitm-engine.sh"
REDIRECT="$ROOT/scripts/mitm-redirect.sh"
python3 - "$HTML" "$ENGINE" "$REDIRECT" <<'PY'
from pathlib import Path
import sys
html=Path(sys.argv[1]).read_text()
engine=Path(sys.argv[2]).read_text()
redirect=Path(sys.argv[3]).read_text()
# The current UI reports runtime state based on actual bridge status; it must not
# depend on the obsolete mitmRuntimeStatus button IDs from the earlier UI.
for token in (
    'function pgSyncThirdPartyRuntime(opts)',
    'function pgThirdPartyRuntimeMessage(r,hasScripts)',
    'scripts/sync-mitm-hosts.sh',
    'scripts/sync-urlrewrite.sh',
    'scripts/jsruntime/sync-subs.sh',
    'mitm-engine.sh" status',
    '配置已导入，但运行时同步未完全成功',
    '被跳过的脚本未生效',
    'MITM 引擎未运行，因此尚未执行',
    'CA 系统信任状态未确认',
    'HTTPS 流量重定向未启用',
    'MITM 主机白名单为空',
    'HTTPS 脚本已生效',
):
    assert token in html, f'missing current runtime status behavior: {token}'
assert "if(PGB.mode!=='bridge')return Promise.resolve({ok:false,error:'KernelSU 后端未连接'})" in html
assert "PGB.scriptRuntimeDirty=false" in html
assert "pgSyncThirdPartyRuntime({syncScripts:true})" in html
assert 'ca_system_trust' in engine and 'traffic_redirect' in engine
assert 'listener_pid' in engine
# Enabling transparent redirect is a separate explicit action, not a side effect
# of importing/syncing scripts; the redirect layer must fail closed on unknown CA.
assert 'case "${1:-status}" in' in redirect
assert 'enable)' in redirect
assert 'has_vpn_jump' in redirect
assert 'MITM CA is not confirmed active in the system trust store' in redirect
assert 'MITM listener failed; no redirect installed' in redirect
print('JS MITM runtime status and explicit-opt-in regression: PASS')
PY
