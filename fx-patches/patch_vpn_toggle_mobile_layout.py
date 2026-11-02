#!/usr/bin/env python3
"""Prevent the VPN master switch labels and track from overlapping on phones."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
html = root / "webroot/index.html"
if not html.is_file():
    raise SystemExit("FX WebUI source is missing")
source = html.read_text(encoding="utf-8")
marker = '<style id="fx-vpn-toggle-mobile-layout-v1">'
css = r"""
<style id="fx-vpn-toggle-mobile-layout-v1">
/* Keep the master switch's text column separate from its track on narrow phones. */
@media(max-width:520px){
  #vpnStatusCard #vpnEnableToggle.vpn-master-switch{
    display:block;
    min-height:252px;
    padding:16px;
  }
  #vpnStatusCard #vpnEnableToggle.vpn-master-switch::before{
    position:absolute;
    left:16px;
    right:16px;
    top:166px;
    width:auto;
    height:52px;
  }
  #vpnStatusCard #vpnEnableToggle.vpn-master-switch::after{
    position:absolute;
    left:22px;
    right:auto;
    top:192px;
    width:38px;
    height:38px;
    margin-top:-19px;
  }
  #vpnStatusCard #vpnEnableToggle.vpn-master-switch.active::after{
    left:auto;
    right:22px;
  }
  #vpnStatusCard #vpnEnableToggle.vpn-master-switch .vpn-toggle-heading{
    left:16px;top:14px;
  }
  #vpnStatusCard #vpnEnableToggle.vpn-master-switch .vpn-toggle-caption{
    left:16px;top:43px;
  }
  #vpnStatusCard #vpnEnableToggle.vpn-master-switch .vpn-toggle-main{
    left:16px;top:78px;
  }
  #vpnStatusCard #vpnEnableToggle.vpn-master-switch .vpn-toggle-detail{
    left:16px;top:110px;
    max-width:calc(100% - 32px);
  }
  #vpnStatusCard #vpnEnableToggle.vpn-master-switch .vpn-toggle-exit-label{
    left:16px;bottom:12px;
  }
  #vpnStatusCard #vpnEnableToggle.vpn-master-switch .vpn-toggle-exit{
    right:16px;bottom:12px;max-width:62%;
  }
}
@media(max-width:360px){
  #vpnStatusCard #vpnEnableToggle.vpn-master-switch .vpn-toggle-detail{
    font-size:12px;
  }
  #vpnStatusCard #vpnEnableToggle.vpn-master-switch .vpn-toggle-exit{
    font-size:13px;max-width:58%;
  }
}
</style>
"""
if source.count("</head>") != 1:
    raise SystemExit("WebUI head closing anchor is ambiguous")
if marker in source:
    if source.count(marker) != 1:
        raise SystemExit("VPN mobile layout patch marker is duplicated")
else:
    source = source.replace("</head>", css + "\\n</head>", 1)
html.write_text(source, encoding="utf-8")

test = root / "scripts/tests/v1.0.0-vpn-toggle-mobile-layout-regression.sh"
test.parent.mkdir(parents=True, exist_ok=True)
test.write_text(r'''#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
HTML="${1:-$ROOT/webroot/index.html}"
grep -Fq '<style id="fx-vpn-toggle-mobile-layout-v1">' "$HTML"
grep -Fq '@media(max-width:520px)' "$HTML"
grep -Fq 'min-height:252px' "$HTML"
grep -Fq 'left:16px;top:110px' "$HTML"
grep -Fq 'max-width:calc(100% - 32px)' "$HTML"
grep -Fq 'left:22px' "$HTML"
grep -Fq 'right:22px' "$HTML"
echo 'FX VPN narrow-screen master switch layout regression: PASS'
''', encoding="utf-8")
test.chmod(0o755)
print("Patched narrow-screen VPN master switch layout.")
