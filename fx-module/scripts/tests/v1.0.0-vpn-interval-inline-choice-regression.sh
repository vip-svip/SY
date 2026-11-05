#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
UI="$ROOT/webroot/index.html"
grep -Fq 'id="vpnIntervalOptions"' "$UI"
for n in 6 12 24 48; do grep -Fq "data-vpn-interval=\"$n\"" "$UI"; done
grep -Fq "secSet('vpn','auto_update_h',v)" "$UI"
grep -Fq "document.querySelectorAll('[data-vpn-interval]')" "$UI"
grep -Fq 'data-vpn-interval-custom="1"' "$UI"
echo 'FX VPN interval inline choice regression: PASS'
