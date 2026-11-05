#!/system/bin/sh
# The frontend must consume the same owner UID JSON result as the backend probe.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." 2>/dev/null && pwd)
UI="$ROOT/webroot/index.html"
PROBE="$ROOT/scripts/external-vpn-probe.sh"
sh -n "$PROBE"
grep -Fq 'window.__pgExternalVpnOwnerUid=hit?String(j&&j.owner_uid||' "$UI"
! grep -Fq 'dumpsys connectivity 2>/dev/null | grep -F' "$UI"
python3 - "$UI" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text(encoding='utf-8')
a=s.index('/* 外部 VPN 检测：用与后端一致的探测脚本')
b=s.index('/* 自动更新检查：配置加载完成后再跑', a)
block=s[a:b]
assert "String(j&&j.owner_uid||'').replace(/[^0-9]/g,'')" in block
assert block.count('scripts/external-vpn-probe.sh') == 1
assert 'pgExec("dumpsys connectivity' not in block
assert 'showExternalState();' in block
PY
printf '%s\n' 'PASS: UI and backend share the authoritative VPN owner UID; spacing variants do not cause false UID-missing diagnostics'
