#!/usr/bin/env python3
"""Keep the VPN master switch honest when an external Android VPN pauses FX."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
html = root / "webroot/index.html"
if not html.is_file():
    raise SystemExit("FX WebUI source is missing")
source = html.read_text(encoding="utf-8")
old = """    var mode=pget('vpn_mode','direct'),configured=mode!=='direct',suspended=false;
"""
new = """    var mode=pget('vpn_mode','direct'),configured=mode!=='direct';
    /* Mirror the backend's fail-safe external-VPN gate in the master switch.
       A detected outer tunnel is compatible only when overlay is enabled and
       its owner UID is known; TUN never stacks with another Android VPN. */
    var compat=pget('vpn_external_compat','1')==='1';
    var externalUnknown=!!window.__pgExternalVpnProbeUnknown;
    var externalDetected=!!window.__pgExternalVpnDetected;
    var externalUid=String(window.__pgExternalVpnOwnerUid||'').replace(/[^0-9]/g,'');
    var suspended=configured&&(externalUnknown||(externalDetected&&(mode==='tun'||!compat||!externalUid)));
"""
if source.count(old) == 1:
    source = source.replace(old, new, 1)
elif new not in source:
    raise SystemExit("VPN master-switch suspended-state anchor changed; refusing patch")
html.write_text(source, encoding="utf-8")
test = root / "scripts/tests/v1.0.0-vpn-toggle-external-state-regression.sh"
test.parent.mkdir(parents=True, exist_ok=True)
test.write_text(r'''#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
grep -Fq "var externalUnknown=!!window.__pgExternalVpnProbeUnknown;" "$HTML"
grep -Fq "var externalDetected=!!window.__pgExternalVpnDetected;" "$HTML"
grep -Fq "var externalUid=String(window.__pgExternalVpnOwnerUid||'').replace(/[^0-9]/g,'');" "$HTML"
grep -Fq "var suspended=configured&&(externalUnknown||(externalDetected&&(mode==='tun'||!compat||!externalUid)));" "$HTML"
! grep -Fq "configured=mode!=='direct',suspended=false" "$HTML"
grep -Fq "b.classList.toggle('suspended',suspended)" "$HTML"
grep -Fq "b.setAttribute('aria-pressed',(configured&&!suspended)?'true':'false')" "$HTML"
echo 'FX VPN master switch external-tunnel state regression: PASS'
''', encoding="utf-8")
test.chmod(0o755)
print("Patched VPN master switch to reflect external-VPN fail-safe suspension.")
