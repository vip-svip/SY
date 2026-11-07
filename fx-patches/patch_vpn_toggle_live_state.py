#!/usr/bin/env python3
"""Make the VPN master switch reflect backend-confirmed state, not saved mode.

Three source generations reach this patcher:

* archives whose toggle only knows the saved mode (original anchors),
* WebUI sources that already track ``__pgVpnRuntimeKnown`` /
  ``__pgVpnRuntimeOn`` and expose ``data-effective`` (the current app source).

Both must end up with the same contract: the switch is only "on" when the
backend confirmed the tunnel, and the state producer must notify the switch.
The patcher therefore validates the source-driven model and only falls back to
text replacement for archives that predate it.
"""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
html = root / "webroot/index.html"
if not html.is_file():
    raise SystemExit("FX WebUI source is missing")
source = html.read_text(encoding="utf-8")

LIVE_MODEL_TOKENS = (
    "window.__pgVpnRuntimeKnown=true;",
    "window.__pgVpnRuntimeOn=!!(s&&(s.vpn_on===true||s.vpn_on===1));",
    "function markVpnRuntimePending(){window.__pgVpnRuntimeKnown=false;window.__pgVpnRuntimeOn=false;}",
    "var runtimeKnown=window.__pgVpnRuntimeKnown===true;",
    "var runtimeOn=window.__pgVpnRuntimeOn===true;",
    "var active=configured&&!waitingNode&&!suspended&&runtimeKnown&&runtimeOn;",
    "b.classList.toggle('active',active);b.classList.toggle('suspended',suspended);",
    "b.setAttribute('data-effective',active?'true':'false');",
)

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

if all(token in source for token in LIVE_MODEL_TOKENS):
    print("PASS: WebUI VPN master switch already derives its state from the backend live-status model.")
else:
    for old, new in replacements:
        if source.count(old) == 1:
            source = source.replace(old, new, 1)
        elif new in source:
            continue
        else:
            raise SystemExit("VPN live-state patch anchor missing or ambiguous: " + old[:90])
    missing = [token for token in LIVE_MODEL_TOKENS if token not in source]
    if missing:
        raise SystemExit("VPN live-state contract incomplete after patching: " + missing[0][:90])
    html.write_text(source, encoding="utf-8")

test = root / "scripts/tests/v1.0.0-vpn-toggle-live-state-regression.sh"
test.parent.mkdir(parents=True, exist_ok=True)
test.write_text(r'''#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
HTML="${1:-$ROOT/webroot/index.html}"
grep -Fq 'window.__pgVpnRuntimeKnown=true;' "$HTML"
grep -Fq 'window.__pgVpnRuntimeOn=!!(s&&(s.vpn_on===true||s.vpn_on===1));' "$HTML"
grep -Fq 'function markVpnRuntimePending(){window.__pgVpnRuntimeKnown=false;window.__pgVpnRuntimeOn=false;}' "$HTML"
grep -Fq 'var runtimeKnown=window.__pgVpnRuntimeKnown===true;' "$HTML"
grep -Fq 'var active=configured&&!waitingNode&&!suspended&&runtimeKnown&&runtimeOn;' "$HTML"
grep -Fq "b.setAttribute('data-effective',active?'true':'false');" "$HTML"
grep -Fq "vLt('已选择 · 等待生效','SELECTED · PENDING')" "$HTML"
! grep -Fq "b.classList.toggle('active',configured&&!suspended)" "$HTML"
echo 'FX VPN master switch backend-live-state regression: PASS'
''', encoding="utf-8")
test.chmod(0o755)
print("Patched VPN master switch to use backend-confirmed live state.")
