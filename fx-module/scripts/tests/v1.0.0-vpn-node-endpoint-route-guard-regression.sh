#!/system/bin/sh
# Coexistence must pin sing-box sockets to the actual outer tunnel; root UID route
# probes and side-effect DNS/public-IP probes are not evidence of Android VPN routing.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
U="$ROOT/scripts/util.sh"
C="$ROOT/scripts/vpncore.sh"
E="$ROOT/scripts/vpn-overlay-check.sh"
for f in "$A" "$U" "$C" "$E"; do sh -n "$f"; done
grep -Fq 'vpncore_outer_tunnel_interface' "$A"
grep -Fq 'vpncore_ver_ge "$_PG_SB_VER" "1.12"' "$A"
grep -Fq 'vpncore_add_bind_interface' "$C"
grep -Fq '"bind_interface":"%s"' "$C"
grep -Fq 'pins node/direct/DNS outbound sockets to $_gc_bind_iface' "$C"
if grep -Eq 'pg_vpn_node_endpoint_ip|ip -6? route get .*uid 0' "$A" "$E"; then
  echo 'FAIL: coexistence still depends on root route lookup/DNS resolution' >&2; exit 1
fi
if grep -Fq 'api.ipify.org' "$E"; then echo 'FAIL: diagnostic sends unrelated public egress request' >&2; exit 1; fi
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-vpn-bind.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/bin"
cat > "$T/settings.conf" <<'CONF'
vpn_external_compat=1
vpn_mode=rule
vpn_node=vless:203.0.113.7:443
[conf:vpn]
core_ver=1.14.3
local_port=7890
CONF
cat > "$T/singbox.json" <<'JSON'
{"outbounds":[{"type":"vless","server":"203.0.113.7","server_port":443,"bind_interface":"tun0"},{"type":"direct","tag":"direct","bind_interface":"tun0"}],"dns":{"servers":[{"type":"udp","tag":"remote","server":"1.1.1.1","bind_interface":"tun0"},{"type":"udp","tag":"local","server":"223.5.5.5","bind_interface":"tun0"}]}}
JSON
cat > "$T/bin/ip" <<'IP'
#!/bin/sh
printf '%s\n' "$*" >> "$FX_IP_CALL_LOG"
case "$*" in
  '-o link show') printf '%s\n' '1: lo: <LOOPBACK>' '8: tun0: <POINTOPOINT,UP>' ;;
  '-o link show dev tun0') printf '%s\n' '8: tun0: <POINTOPOINT,UP>' ;;
  *'route get'*) echo 'FAIL-route-query-should-not-run' >&2; exit 99 ;;
  *) exit 1 ;;
esac
IP
cat > "$T/bin/dumpsys" <<'DUMP'
#!/bin/sh
printf '%s\n' 'VpnInfo{ownerUid=12345, vpnIface=tun0, primaryUnderlyingIface=wlan0}'
DUMP
chmod 755 "$T/bin/ip" "$T/bin/dumpsys"
: > "$T/ip.log"
PATH="$T/bin:/usr/bin:/bin" PG="$T" CONF="$T/settings.conf" FX_IP_CALL_LOG="$T/ip.log" sh "$E" > "$T/out"
grep -q '"status":"bind-interface-configured"' "$T/out"
grep -q '"configured":true' "$T/out"
grep -q '"effective":"unverified"' "$T/out"
grep -q '"verification":"config-only"' "$T/out"
grep -q '"ready":false' "$T/out"
grep -q '"dataplane_verified":false' "$T/out"
grep -q '"verification_required":"live-app-traffic"' "$T/out"
grep -q '"owner_uid":"12345"' "$T/out"
grep -q '"bind_count":4' "$T/out"
! grep -q 'route get' "$T/ip.log"
# Removing even one required pin must fail the check, not report verified coexistence.
sed '0,/"bind_interface":"tun0"/s//"bind_interface":"wlan0"/' "$T/singbox.json" > "$T/bad.json"
cp "$T/bad.json" "$T/singbox.json"
if PATH="$T/bin:/usr/bin:/bin" PG="$T" CONF="$T/settings.conf" FX_IP_CALL_LOG="$T/ip.log" sh "$E" > "$T/out2"; then
  echo 'FAIL: mismatched interface binding passed' >&2; exit 1
fi
grep -q 'outer-binding-missing' "$T/out2"
# The endpoint parser stays deterministic and does not issue a DNS lookup.
printf '%s\n' 'vpn_node=vless:[2001:db8::7]:443' > "$T/settings.conf"
PG="$T" CONF="$T/settings.conf" sh -c '. "$1"; pg_vpn_node_endpoint_host' sh "$U" > "$T/host"
grep -qx '2001:db8::7' "$T/host"
printf '%s\n' 'PASS: FX overlays bind node/direct/DNS sockets to the outer tunnel; diagnostics avoid root-route and public-egress probes'
