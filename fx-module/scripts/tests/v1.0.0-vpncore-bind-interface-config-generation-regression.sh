#!/system/bin/sh
# Exercises the actual sing-box config generator, not just the UI or diagnostic text.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-vpn-gen-bind.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/bin" "$T/cache"
cat > "$T/settings.conf" <<'CONF'
vpn_external_compat=1
vpn_mode=rule
vpn_node=vless://test@node.example:443
[list:vpn_node]
vless://test@node.example:443|Test node|1
[list:rule]
[list:fx]
[conf:vpn]
core_ver=1.14.3
local_ip=127.0.0.1
local_port=7890
mixed_port=7891
remote_dns=1.1.1.1
cn_dns=223.5.5.5
CONF
cat > "$T/bin/ip" <<'IP'
#!/bin/sh
case "$*" in
  '-o link show') printf '%s\n' '1: lo: <LOOPBACK>' '8: tun0: <POINTOPOINT,UP>' ;;
  '-o link show dev tun0')
    if [ "${FX_TEST_LINK_STATE:-up}" = down ]; then printf '%s\n' '8: tun0: <POINTOPOINT>'; else printf '%s\n' '8: tun0: <POINTOPOINT,UP>'; fi ;;
  *) exit 1 ;;
esac
IP
chmod 755 "$T/bin/ip"
cat > "$T/bin/dumpsys" <<'DUMPSYS'
#!/bin/sh
case "$*" in
  'connectivity') printf '%s\n' 'mVpnInfo=VpnInfo{ownerUid=12345, vpnIface=tun0, primaryUnderlyingIface=wlan0}' ;;
  *) exit 1 ;;
esac
DUMPSYS
chmod 755 "$T/bin/dumpsys"
export PG="$T" CONF="$T/settings.conf" MODDIR="$ROOT" PG_MODDIR="$ROOT" PATH="$T/bin:/usr/bin:/bin"
# Override only the URI-to-outbound converter and the real binary check. All config
# assembly, bind_interface selection, DNS generation and route compiler calls are real.
sh -c '
  . "$MODDIR/scripts/util.sh"
  . "$MODDIR/scripts/vpncore.sh"
  singbox_node_outbound() { printf "{\"type\":\"vless\",\"tag\":\"%s\",\"server\":\"node.example\",\"server_port\":443,\"uuid\":\"00000000-0000-4000-8000-000000000001\"}" "$2"; }
  vpncore_check_conf() { return 0; }
  vpncore_genconf "$PG/bin/sing-box"
'
python3 - "$T/singbox.json" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text())
assert d['dns']['servers'][0]['bind_interface']=='tun0'
assert d['dns']['servers'][1]['bind_interface']=='tun0'
assert d['outbounds'][-1]['bind_interface']=='tun0'
nodes=[x for x in d['outbounds'] if x.get('tag','').startswith('node-')]
assert nodes and all(x.get('bind_interface')=='tun0' for x in nodes)
assert d['route']['final']=='proxy'
print('PASS: actual config generator pins node, direct and both DNS servers to the detected outer tunnel')
PY
# With compatibility disabled, normal FX proxy mode must not inherit a stale tunnel pin.
sed 's/^vpn_external_compat=1$/vpn_external_compat=0/' "$T/settings.conf" > "$T/unbound.conf"
cp "$T/unbound.conf" "$T/settings.conf"
sh -c '
  . "$MODDIR/scripts/util.sh"
  . "$MODDIR/scripts/vpncore.sh"
  singbox_node_outbound() { printf "{\"type\":\"vless\",\"tag\":\"%s\",\"server\":\"node.example\",\"server_port\":443,\"uuid\":\"00000000-0000-4000-8000-000000000001\"}" "$2"; }
  vpncore_check_conf() { return 0; }
  vpncore_genconf "$PG/bin/sing-box"
'
python3 - "$T/singbox.json" <<'PY'
import json, pathlib, sys
d=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert not any('bind_interface' in x for x in d['outbounds'])
assert not any('bind_interface' in x for x in d['dns']['servers'])
print('PASS: interface pinning is scoped to explicit external VPN compatibility mode')
PY
# A legacy core must not overwrite the last known config with unpinned DNS config.
sed 's/^vpn_external_compat=0$/vpn_external_compat=1/; s/^core_ver=1.14.3$/core_ver=1.11.0/' "$T/settings.conf" > "$T/old-core.conf"
cp "$T/old-core.conf" "$T/settings.conf"
printf '%s\n' '{"last_good":true}' > "$T/singbox.json"
if sh -c '
  . "$MODDIR/scripts/util.sh"
  . "$MODDIR/scripts/vpncore.sh"
  singbox_node_outbound() { printf "{\"type\":\"vless\",\"tag\":\"%s\",\"server\":\"node.example\",\"server_port\":443,\"uuid\":\"00000000-0000-4000-8000-000000000001\"}" "$2"; }
  vpncore_check_conf() { return 0; }
  vpncore_genconf "$PG/bin/sing-box"
'; then
  echo 'FAIL: legacy core allowed unsafe outer-VPN config' >&2; exit 1
fi
grep -Fq '"last_good":true' "$T/singbox.json"
echo 'PASS: unsupported legacy core fails closed and preserves the prior config'

# A handover can take the outer VPN down after the UI previously detected it.
# In explicit compatibility mode, config generation must refuse to fall back
# to unbound physical-network sockets and must preserve the last good config.
sed 's/^core_ver=1.11.0$/core_ver=1.14.3/' "$T/settings.conf" > "$T/handover.conf"
cp "$T/handover.conf" "$T/settings.conf"
printf '%s\n' '{"last_good_after_handover":true}' > "$T/singbox.json"
if FX_TEST_LINK_STATE=down sh -c '
  . "$MODDIR/scripts/util.sh"
  . "$MODDIR/scripts/vpncore.sh"
  singbox_node_outbound() { printf "{\"type\":\"vless\",\"tag\":\"%s\",\"server\":\"node.example\",\"server_port\":443,\"uuid\":\"00000000-0000-4000-8000-000000000001\"}" "$2"; }
  vpncore_check_conf() { return 0; }
  vpncore_genconf "$PG/bin/sing-box"
'; then
  echo 'FAIL: missing/down external VPN interface allowed unbound config generation' >&2; exit 1
fi
grep -Fq '"last_good_after_handover":true' "$T/singbox.json"
echo 'PASS: external VPN handover failure is fail-closed and preserves last good config'

# TUN mode must emit a real sing-box TUN inbound and auto-detect the underlying
# physical interface to prevent the proxy's own node connection from routing into fx0.
sed 's/^vpn_mode=rule$/vpn_mode=tun/' "$T/settings.conf" > "$T/tun.conf"
cp "$T/tun.conf" "$T/settings.conf"
sh -c '
  . "$MODDIR/scripts/util.sh"
  . "$MODDIR/scripts/vpncore.sh"
  singbox_node_outbound() { printf "{\"type\":\"vless\",\"tag\":\"%s\",\"server\":\"node.example\",\"server_port\":443,\"uuid\":\"00000000-0000-4000-8000-000000000001\"}" "$2"; }
  vpncore_check_conf() { return 0; }
  vpncore_genconf "$PG/bin/sing-box"
'
python3 - "$T/singbox.json" <<'PY'
import json, pathlib, sys
d=json.loads(pathlib.Path(sys.argv[1]).read_text())
tun=[x for x in d['inbounds'] if x.get('type')=='tun']
assert len(tun)==1, d['inbounds']
assert tun[0]['interface_name']=='fx0'
assert tun[0]['auto_route'] is True
assert tun[0]['strict_route'] is True
assert tun[0]['mtu']==1400
assert tun[0]['udp_timeout']=='5m'
assert tun[0]['exclude_uid']==[0]
assert '192.168.0.0/16' in tun[0]['route_exclude_address']
assert 'fc00::/7' in tun[0]['route_exclude_address']
assert tun[0]['stack']=='system'
assert d['route']['auto_detect_interface'] is True
assert not any('bind_interface' in x for x in d['outbounds'])
print('PASS: TUN config generation, automatic routes and outbound loop prevention')
PY

# A listener alone must not pass readiness in TUN mode: require the managed
# fx0 interface to exist and carry the UP flag, but do not require fx0 in legacy modes.
if sh -c '
  . "$MODDIR/scripts/util.sh"
  . "$MODDIR/scripts/vpncore.sh"
  pg_get() { [ "$1" = "vpn_mode" ] && { echo tun; return 0; }; return 1; }
  ip() { [ "$*" = "-o link show dev fx0" ] && printf "%s\\n" "9: fx0: <POINTOPOINT,UP>"; }
  vpncore_tun_interface_ready
'; then
  echo 'PASS: TUN readiness accepts an UP fx0 interface'
else
  echo 'FAIL: TUN readiness rejected an UP fx0 interface' >&2; exit 1
fi
if sh -c '
  . "$MODDIR/scripts/util.sh"
  . "$MODDIR/scripts/vpncore.sh"
  pg_get() { [ "$1" = "vpn_mode" ] && { echo tun; return 0; }; return 1; }
  ip() { [ "$*" = "-o link show dev fx0" ] && printf "%s\\n" "9: fx0: <POINTOPOINT>"; }
  vpncore_tun_interface_ready
'; then
  echo 'FAIL: TUN readiness accepted a down fx0 interface' >&2; exit 1
else
  echo 'PASS: TUN readiness rejects a down fx0 interface'
fi
if sh -c '
  . "$MODDIR/scripts/util.sh"
  . "$MODDIR/scripts/vpncore.sh"
  pg_get() { [ "$1" = "vpn_mode" ] && { echo rule; return 0; }; return 1; }
  vpncore_tun_interface_ready
'; then
  echo 'PASS: legacy modes do not require the fx0 interface'
else
  echo 'FAIL: legacy mode unexpectedly requires fx0' >&2; exit 1
fi

# TUN owns DNS routing through sing-box. The legacy iptables DNS DNAT path must
# stay disabled for this mode, otherwise packets can bypass the TUN DNS policy.
grep -Fq '&& [ "$(pg_get vpn_mode direct)" != "tun" ]; then' "$ROOT/scripts/apply.sh" || {
  echo 'FAIL: legacy DNS forwarding lacks a TUN-mode guard' >&2; exit 1;
}
grep -Fq 'data-mode="tun"' "$ROOT/webroot/index.html" || {
  echo 'FAIL: TUN mode is not exposed in the existing VPN selector' >&2; exit 1;
}
grep -Fq "indexOf(mode)<0" "$ROOT/webroot/index.html" && grep -Fq "'direct','global','rule','tun'" "$ROOT/webroot/index.html" || {
  echo 'FAIL: VPN mode handler does not accept TUN mode' >&2; exit 1;
}
echo 'PASS: TUN mode UI is wired and legacy DNS NAT is guarded'

# TUN owns packet capture and routing. The legacy NAT REDIRECT chain must not
# be installed in TUN mode; otherwise packets can bypass or loop around sing-box.
grep -Fq 'if [ "$VPN_ON" = "1" ] && [ "$VPN_MODE" != "tun" ]; then' "$ROOT/scripts/apply.sh" || {
  echo 'FAIL: legacy PGVPN REDIRECT chain is not excluded for TUN mode' >&2; exit 1;
}
grep -Fq 'if [ "$(pg_get transparent_proxy 0)" = "1" ] && [ "$_PG_VPN_INTERCEPTION_BLOCKED" = "0" ] && [ "$(pg_get vpn_mode direct)" != "tun" ]; then' "$ROOT/scripts/apply.sh" || {
  echo 'FAIL: generic transparent-proxy hook is not excluded for TUN mode' >&2; exit 1;
}
# TUN mode must fail safe when an external VPN is active or its state is uncertain.
grep -Fq 'if [ "$VPN_MODE" = "tun" ] && { [ "$_PG_VPN_INTERCEPTION_BLOCKED" = "1" ] || [ -n "$_PG_EXT_VPN_IF" ]; }; then' "$ROOT/scripts/apply.sh" || {
  echo 'FAIL: TUN external-VPN conflict guard missing' >&2; exit 1;
}
echo 'PASS: TUN avoids legacy REDIRECT hooks and guards external-VPN conflicts'
