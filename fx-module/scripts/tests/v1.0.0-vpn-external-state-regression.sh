#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"; H="$ROOT/webroot/index.html"
D=$(grep -n '^_PG_EXT_VPN_IF=""' "$A" | head -1 | cut -d: -f1); F=$(grep -n '^DNS_FWD=""' "$A" | head -1 | cut -d: -f1); G=$(grep -n '^# 全局 DNS 替换' "$A" | head -1 | cut -d: -f1)
[ -n "$D" ] && [ -n "$F" ] && [ -n "$G" ] && [ "$D" -lt "$F" ] && [ "$D" -lt "$G" ]
grep -Fq 'dns_forward 1)' "$A"; grep -Fq 'custom_dns 0)' "$A"
if grep -Fq 'dns_block 0)' "$A"; then echo 'FAIL: retired DNS switch still gates external VPN state' >&2; exit 1; fi
grep -Fq 'window.__pgExternalVpnDetected=!!hit||!!unknown' "$H"
grep -Fq 'window.__pgExternalVpnProbeUnknown=true;window.__pgExternalVpnDetected=true' "$H"
grep -Fq '为避免断网，FX 透明接管保持暂停' "$H"
grep -Fq 'External VPN detection failed; FX interception remains paused' "$H"
echo 'FX 1.0.0 external VPN state / DNS guard regression: PASS'
