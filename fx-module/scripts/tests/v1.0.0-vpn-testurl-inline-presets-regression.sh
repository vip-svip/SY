#!/system/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
UI="$ROOT/webroot/index.html"
grep -Fq 'data-vpn-testurl="http://www.gstatic.com/generate_204"' "$UI"
grep -Fq 'data-vpn-testurl="https://cp.cloudflare.com/generate_204"' "$UI"
grep -Fq 'data-vpn-testurl="https://connectivitycheck.gstatic.com/generate_204"' "$UI"
grep -Fq 'data-vpn-testurl="https://www.google.com/generate_204"' "$UI"
grep -Fq "secSet('vpn','test_url',u);pgSave();vpnPanelSync()" "$UI"
grep -Fq 'data-vpn-testurl-custom="1"' "$UI"
grep -Fq "vpnEditOpen=cfg;document.getElementById('edTitle').textContent=cfg.t" "$UI"
grep -Fq "document.querySelectorAll('[data-vpn-testurl]').forEach" "$UI"
echo 'PASS: VPN test URL presets, persistence, selected-state sync, and custom editor path'
