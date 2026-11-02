#!/usr/bin/env python3
"""Make the FX VPN master switch transparent and keep its white thumb inside the track."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
html = root / "webroot/index.html"
if not html.is_file():
    raise SystemExit("FX WebUI source is missing")
source = html.read_text(encoding="utf-8")
marker = '<style id="fx-vpn-toggle-transparent-v2">'
css = r"""
<style id="fx-vpn-toggle-transparent-v2">
/* Transparent FX switch: no pink card, no orange/pink track; white thumb stays inside. */
#vpnStatusCard #vpnEnableToggle.vpn-master-switch{
  background:transparent!important;
  border:1px solid transparent!important;
  box-shadow:none!important;
  color:var(--text-primary,#263238)!important;
}
#vpnStatusCard #vpnEnableToggle.vpn-master-switch::before{
  box-sizing:border-box!important;
  border:1px solid rgba(255,255,255,.58)!important;
  background:rgba(255,255,255,.16)!important;
  box-shadow:inset 0 1px 3px rgba(0,0,0,.08)!important;
}
#vpnStatusCard #vpnEnableToggle.vpn-master-switch.active::before,
#vpnStatusCard #vpnEnableToggle.vpn-master-switch.suspended::before{
  border-color:rgba(255,255,255,.72)!important;
  background:rgba(255,255,255,.28)!important;
}
#vpnStatusCard #vpnEnableToggle.vpn-master-switch::after{
  box-sizing:border-box!important;
  position:relative!important;
  grid-column:2!important;
  grid-row:2!important;
  justify-self:start!important;
  align-self:center!important;
  left:auto!important;
  right:auto!important;
  top:auto!important;
  margin:0 0 0 6px!important;
  z-index:1!important;
  background:#fff!important;
  border:1px solid rgba(0,0,0,.08)!important;
  box-shadow:0 2px 6px rgba(0,0,0,.18)!important;
}
#vpnStatusCard #vpnEnableToggle.vpn-master-switch.active::after,
#vpnStatusCard #vpnEnableToggle.vpn-master-switch.suspended::after{
  justify-self:end!important;
  margin:0 6px 0 0!important;
}
@media(max-width:520px){
  #vpnStatusCard #vpnEnableToggle.vpn-master-switch{display:block!important;min-height:252px!important;}
  #vpnStatusCard #vpnEnableToggle.vpn-master-switch::before{
    position:absolute!important;left:16px!important;right:16px!important;top:166px!important;
    width:auto!important;height:52px!important;
  }
  #vpnStatusCard #vpnEnableToggle.vpn-master-switch::after{
    position:absolute!important;left:22px!important;right:auto!important;top:192px!important;
    width:38px!important;height:38px!important;margin:-19px 0 0 0!important;
  }
  #vpnStatusCard #vpnEnableToggle.vpn-master-switch.active::after,
  #vpnStatusCard #vpnEnableToggle.vpn-master-switch.suspended::after{
    left:auto!important;right:22px!important;
  }
}
</style>
"""
if marker in source:
    if source.count(marker) != 1:
        raise SystemExit("transparent switch patch marker is duplicated")
else:
    if source.count("</head>") != 1:
        raise SystemExit("WebUI head closing anchor is ambiguous")
    source = source.replace("</head>", css + "\n</head>", 1)
html.write_text(source, encoding="utf-8")
print("Patched transparent FX VPN switch and thumb geometry.")
