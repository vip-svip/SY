#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
H="$ROOT/webroot/index.html"
grep -Fq 'id="vpnEnableToggle"' "$H"
grep -Fq "applyVpnModeSelection('global')" "$H"
grep -Fq "applyVpnModeSelection('direct')" "$H"
grep -Fq 'function applyVpnModeSelection(mode)' "$H"
! grep -Fq 'vpnApplyNow' "$H"
! grep -Fq 'vpn-apply-row' "$H"
grep -Fq "typeof applyRun==='function'" "$H"
grep -Fq 'id="vpnConflictNotice"' "$H"
grep -Fq 'vpn_mode=direct' "$ROOT/scripts/apply.sh"
echo 'FX 1.0.0 VPN mode toggle / external VPN warning regression: PASS'
