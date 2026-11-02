#!/usr/bin/env python3
"""Make the VPN master switch reflect backend-confirmed state, not saved mode."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
html = root / "webroot/index.html"
if not html.is_file():
    raise SystemExit("FX WebUI source is missing")
source = html.read_text(encoding="utf-8")

replacements = [
    (
        "  var b=document.getElementById('vpnEnableToggle'); if(!b)return;\n  function sync(){\n    var mode=pget('vpn_mode','direct'),configured=mode!=='direct';",
        "  var b=document.getElementById('vpnEnableToggle'); if(!b)return;\n  window.__pgVpnLiveKnown=false;window.__pgVpnLiveOn=false;\n  function sync(){\n    var mode=pget('vpn_mode','direct'),configured=mode!=='direct';\n    var liveKnown=window.__pgVpnLiveKnown===true,liveOn=window.__pgVpnLiveOn===true;"
    ),
    (
        "    b.classList.toggle('active',configured&&!suspended);b.classList.toggle('suspended',suspended);\n    b.setAttribute('aria-pressed',(configured&&!suspended)?'true':'false');",
        "    b.classList.toggle('active',configured&&liveKnown&&liveOn&&!suspended);b.classList.toggle('suspended',suspended);\n    b.setAttribute('aria-pressed',(configured&&liveKnown&&liveOn&&!suspended)?'true':'false');"
    ),
    (
        "    if(detail)detail.textContent=configured?(nodeName?vLt('节点已就绪 · '+nodeName,'Node ready · '+nodeName):vLt('代理模式已选，等待节点','Proxy mode selected; waiting for node')):vLt('直连模式','Direct mode');",
        "    if(detail)detail.textContent=!configured?vLt('直连模式','Direct mode'):(!liveKnown?vLt('代理模式已选，等待后端确认','Proxy mode selected; waiting for backend confirmation'):(!liveOn?vLt('代理模式已选，但尚未生效','Proxy mode selected but not active'):(nodeName?vLt('节点已就绪 · '+nodeName,'Node ready · '+nodeName):vLt('代理已生效','Proxy active'))));"
    ),
    (
        "window.__vpnFillStatus=function(s){\n  var m=document.getElementById('vsMode');",
        "window.__vpnFillStatus=function(s){\n  window.__pgVpnLiveKnown=!!s;window.__pgVpnLiveOn=!!(s&&(s.vpn_on===true||s.vpn_on===1));\n  if(window.__pgSyncVpnToggle)window.__pgSyncVpnToggle();\n  var m=document.getElementById('vsMode');"
    )
]
for old, new in replacements:
    if source.count(old) == 1:
        source = source.replace(old, new, 1)
    elif source.count(new) == 1:
        continue
    else:
        raise SystemExit("VPN live-state patch anchor missing or ambiguous: " + old[:90])
html.write_text(source, encoding="utf-8")

test = root / "scripts/tests/v1.0.0-vpn-toggle-live-state-regression.sh"
test.parent.mkdir(parents=True, exist_ok=True)
test.write_text(r'''#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
HTML="${1:-$ROOT/webroot/index.html}"
grep -Fq 'window.__pgVpnLiveKnown=false;window.__pgVpnLiveOn=false;' "$HTML"
grep -Fq "liveKnown=window.__pgVpnLiveKnown===true,liveOn=window.__pgVpnLiveOn===true" "$HTML"
grep -Fq "configured&&liveKnown&&liveOn&&!suspended" "$HTML"
grep -Fq "window.__pgVpnLiveOn=!!(s&&(s.vpn_on===true||s.vpn_on===1))" "$HTML"
grep -Fq "代理模式已选，但尚未生效" "$HTML"
echo 'FX VPN master switch backend-live-state regression: PASS'
''', encoding="utf-8")
test.chmod(0o755)
print("Patched VPN master switch to use backend-confirmed live state.")
