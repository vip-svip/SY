#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PROBE="$ROOT/scripts/external-vpn-probe.sh"
UI="$ROOT/webroot/index.html"
APPLY="$ROOT/scripts/apply.sh"
sh -n "$PROBE"
grep -Fq "scripts/external-vpn-probe.sh" "$UI"
grep -Fq 'window.__pgExternalVpnProbeUnknown=true' "$UI"
python3 - "$UI" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text(encoding='utf-8')
a=s.index('/* 外部 VPN 检测：用与后端一致的探测脚本')
b=s.index('/* 自动更新检查：配置加载完成后再跑', a)
block=s[a:b]
probe=block.index("if(VPN.mode!=='bridge'||typeof pgExec!=='function')return;")
race=block.index('window.__pgExternalVpnDetected=true;window.__pgExternalVpnProbeUnknown=true;', probe)
call=block.index('scripts/external-vpn-probe.sh', race)
assert probe < race < call, 'real-device UI must treat external VPN state as unknown until async probe completes'
PY
grep -Fq 'if(mode!==\x27direct\x27&&window.__pgExternalVpnProbeUnknown)' "$UI" || grep -Fq "if(mode!=='direct'&&window.__pgExternalVpnProbeUnknown)" "$UI"
grep -Fq 'vpn[0-9]*' "$PROBE"
grep -Fq 'vpn[0-9]*' "$APPLY"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-extvpn-probe.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/bin"
cat > "$T/bin/ip" <<'IP'
#!/bin/sh
case "${FX_IP_MODE:-empty}" in
  empty) exit 0 ;;
  error) exit 1 ;;
  tunnel|space) printf '%s\n' '1: lo: <LOOPBACK>' '8: vpn0: <POINTOPOINT,UP>' ;;
  none) printf '%s\n' '1: lo: <LOOPBACK>' '2: wlan0: <BROADCAST,UP>' ;;
  '-o link show dev vpn0') printf '%s\n' '8: vpn0: <POINTOPOINT,UP>' ;;
  none) printf '%s\n' '1: lo: <LOOPBACK>' '2: wlan0: <BROADCAST,UP>' ;;
  '-o link show dev vpn0') printf '%s\n' '8: vpn0: <POINTOPOINT,UP>' ;;
esac
IP
cat > "$T/bin/dumpsys" <<'DUMPSYS'
#!/bin/sh
case "${FX_IP_MODE:-empty}" in
  tunnel) printf '%s\n' 'VpnInfo{ownerUid=12345, vpnIface=vpn0, primaryUnderlyingIface=wlan0}' ;;
  space) printf '%s\n' 'VpnInfo{ownerUid = 12345, vpnIface = vpn0, primaryUnderlyingIface=wlan0}' ;;
  *) printf '%s\n' 'No active VpnInfo' ;;
esac
DUMPSYS
chmod 755 "$T/bin/ip" "$T/bin/dumpsys"
for mode in empty error; do
  out=$(PATH="$T/bin:/usr/bin:/bin" FX_IP_MODE="$mode" sh "$PROBE")
  printf '%s' "$out" | grep -Fq '"status":"unknown"'
done
out=$(PATH="$T/bin:/usr/bin:/bin" FX_IP_MODE=tunnel sh "$PROBE")
printf '%s' "$out" | grep -Fq '"status":"tunnel","interface":"vpn0"'
printf '%s' "$out" | grep -Fq '"owner_uid":"12345"'
out=$(PATH="$T/bin:/usr/bin:/bin" FX_IP_MODE=space sh "$PROBE")
printf '%s' "$out" | grep -Fq '"status":"tunnel","interface":"vpn0"'
printf '%s' "$out" | grep -Fq '"owner_uid":"12345"'
out=$(PATH="$T/bin:/usr/bin:/bin" FX_IP_MODE=none sh "$PROBE")
printf '%s' "$out" | grep -Fq '"status":"none"'
printf '%s\n' 'PASS: UI VPN probe distinguishes unknown, vpn0, and no tunnel'
