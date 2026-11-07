#!/usr/bin/env python3
"""Keep the VPN master switch honest when an external Android VPN pauses FX.

The backend gate refuses to stack a TUN-mode FX VPN on an outer Android VPN and
requires both the compatibility switch and the outer tunnel owner UID before an
overlay is treated as compatible. The WebUI master switch must mirror exactly
that gate, otherwise the UI claims "active" while the tunnel is refused.

Recognized source generations:

* ``suspended=false`` stub (original anchor),
* a partial gate that only checks the compatibility switch,
* the full gate this patcher writes (idempotent no-op).
"""
from pathlib import Path
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
html = root / "webroot/index.html"
if not html.is_file():
    raise SystemExit("FX WebUI source is missing")
source = html.read_text(encoding="utf-8")

FULL_GATE = (
    "    var compat=pget('vpn_external_compat','1')==='1';\n"
    "    var externalUnknown=!!window.__pgExternalVpnProbeUnknown;\n"
    "    var externalDetected=!!window.__pgExternalVpnDetected;\n"
    "    var externalUid=String(window.__pgExternalVpnOwnerUid||'').replace(/[^0-9]/g,'');\n"
    "    var suspended=configured&&(externalUnknown||(externalDetected&&(mode==='tun'||!compat||!externalUid)));\n"
)

STUB = """    var mode=pget('vpn_mode','direct'),configured=mode!=='direct',suspended=false;
"""

PARTIAL = """    var suspended=configured&&(!!window.__pgExternalVpnProbeUnknown||
      (!!window.__pgExternalVpnDetected&&pget('vpn_external_compat','1')!=='1'));
"""

GATE_TOKENS = (
    "var externalUnknown=!!window.__pgExternalVpnProbeUnknown;",
    "var externalDetected=!!window.__pgExternalVpnDetected;",
    "var externalUid=String(window.__pgExternalVpnOwnerUid||'').replace(/[^0-9]/g,'');",
    "var suspended=configured&&(externalUnknown||(externalDetected&&(mode==='tun'||!compat||!externalUid)));",
    "b.classList.toggle('suspended',suspended)",
)

if all(token in source for token in GATE_TOKENS):
    print("PASS: WebUI VPN master switch already mirrors the external-tunnel gate.")
    patched = False
elif source.count(STUB) == 1:
    source = source.replace(
        STUB,
        """    var mode=pget('vpn_mode','direct'),configured=mode!=='direct';
    /* Mirror the backend's fail-safe external-VPN gate in the master switch.
       A detected outer tunnel is compatible only when overlay is enabled and
       its owner UID is known; TUN never stacks with another Android VPN. */
""" + FULL_GATE,
        1,
    )
    patched = True
elif source.count(PARTIAL) == 1:
    source = source.replace(PARTIAL, FULL_GATE, 1)
    patched = True
else:
    raise SystemExit("VPN master-switch suspended-state anchor changed; refusing patch")

if patched:
    missing = [token for token in GATE_TOKENS if token not in source]
    if missing:
        raise SystemExit("VPN external-tunnel gate incomplete after patching: " + missing[0])
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
! grep -Fq "var suspended=configured&&(!!window.__pgExternalVpnProbeUnknown||" "$HTML"
grep -Fq "b.classList.toggle('suspended',suspended)" "$HTML"
echo 'FX VPN master switch external-tunnel state regression: PASS'
''', encoding="utf-8")
test.chmod(0o755)
print("Patched VPN master switch to reflect external-VPN fail-safe suspension.")
