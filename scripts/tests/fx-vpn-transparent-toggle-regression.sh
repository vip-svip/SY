#!/system/bin/sh
set -eu
HTML="${1:?usage: fx-vpn-transparent-toggle-regression.sh path/to/index.html}"
grep -Fq '<style id="fx-vpn-toggle-transparent-v2">' "$HTML"
grep -Fq 'background:transparent!important' "$HTML"
grep -Fq 'box-shadow:none!important' "$HTML"
grep -Fq 'background:rgba(255,255,255,.16)!important' "$HTML"
grep -Fq 'background:#fff!important' "$HTML"
grep -Fq 'top:192px!important' "$HTML"
grep -Fq 'margin-top:-19px!important' "$HTML"
grep -Fq 'right:22px!important' "$HTML"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
awk '/<style id="fx-vpn-toggle-transparent-v2">/{inside=1} inside{print} inside && index($0, "</style>"){exit}' "$HTML" > "$TMP"
! grep -Fq 'background:#d98743' "$TMP"
! grep -Fq 'background:linear-gradient(135deg,#f8e9ef' "$TMP"
echo 'FX transparent VPN switch geometry regression: PASS'
