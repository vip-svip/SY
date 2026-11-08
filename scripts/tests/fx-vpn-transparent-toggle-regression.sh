#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="${1:-$ROOT/fx-module/webroot/index.html}"
if [ ! -s "$HTML" ]; then
  echo "SKIP: canonical FX WebUI is not staged in this Host-only checkout; the release-staging build lane runs this test."
  exit 0
fi
grep -Fq '<style id="fx-vpn-toggle-transparent-v2">' "$HTML"
grep -Fq 'background:transparent!important' "$HTML"
grep -Fq 'box-shadow:none!important' "$HTML"
grep -Fq 'background:rgba(255,255,255,.16)!important' "$HTML"
grep -Fq 'background:#fff!important' "$HTML"
grep -Fq 'top:192px!important' "$HTML"
grep -Fq 'margin:-19px 0 0 0!important' "$HTML"
grep -Fq 'position:relative!important' "$HTML"
grep -Fq 'grid-column:2!important' "$HTML"
grep -Fq 'justify-self:start!important' "$HTML"
grep -Fq 'margin:0 0 0 6px!important' "$HTML"
grep -Fq 'justify-self:end!important' "$HTML"
grep -Fq 'margin:0 6px 0 0!important' "$HTML"
grep -Fq 'left:22px!important' "$HTML"
grep -Fq 'right:22px!important' "$HTML"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
awk '/<style id="fx-vpn-toggle-transparent-v2">/{inside=1} inside{print} inside && index($0, "</style>"){exit}' "$HTML" > "$TMP"
! grep -Fq 'background:#d98743' "$TMP"
! grep -Fq 'background:linear-gradient(135deg,#f8e9ef' "$TMP"
# Prove reruns replace stale generated CSS instead of preserving the first version.
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMPROOT="$(mktemp -d)"
trap 'rm -f "$TMP"; rm -rf "$TMPROOT"' EXIT
mkdir -p "$TMPROOT/webroot"
cp "$HTML" "$TMPROOT/webroot/index.html"
python3 - "$TMPROOT/webroot/index.html" <<'PY'
from pathlib import Path
import re
import sys
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
old = '<style id="fx-vpn-toggle-transparent-v2">#vpnStatusCard #vpnEnableToggle.vpn-master-switch::after{right:194px!important;background:#fff7fb}</style>'
s, count = re.subn(r'<style id="fx-vpn-toggle-transparent-v2">.*?</style>', old, s, count=1, flags=re.S)
if count != 1:
    raise SystemExit("could not seed a stale transparent-switch stylesheet")
p.write_text(s, encoding="utf-8")
PY
python3 "$ROOT/fx-patches/patch_vpn_toggle_transparent.py" "$TMPROOT"
awk '/<style id="fx-vpn-toggle-transparent-v2">/{inside=1} inside{print} inside && index($0, "</style>"){exit}' "$TMPROOT/webroot/index.html" > "$TMP"
grep -Fq 'position:relative!important' "$TMP"
grep -Fq 'background:#fff!important' "$TMP"
! grep -Fq 'right:194px!important' "$TMP"
test "$(grep -o '<style id="fx-vpn-toggle-transparent-v2">' "$TMPROOT/webroot/index.html" | wc -l)" -eq 1
echo 'FX transparent VPN switch geometry and stale-style replacement regression: PASS'
