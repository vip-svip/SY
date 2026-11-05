#!/system/bin/sh
# Read-only check of FX external-VPN coexistence binding.
# This verifies config/interface binding only; it cannot prove the other VPN's live egress.
set -u
MODDIR=$(CDPATH= cd -- "$(dirname "$0")/.." 2>/dev/null && pwd)
. "$MODDIR/scripts/util.sh"
. "$MODDIR/scripts/vpncore.sh"
PG=${PG:-/data/adb/privacyguard}
compat=$(pg_get vpn_external_compat 1)
mode=$(pg_get vpn_mode direct)

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r/ /g; s/\n/ /g'; }

if ! command -v ip >/dev/null 2>&1; then
  printf '{"ok":false,"status":"interface-probe-unknown","error":"ip tool unavailable; cannot confirm an outer VPN interface","mode":"%s"}\n' "$(json_escape "$mode")"
  exit 2
fi
_links=$(ip -o link show 2>/dev/null)
_rc=$?
if [ "$_rc" -ne 0 ] || [ -z "$_links" ]; then
  printf '{"ok":false,"status":"interface-probe-unknown","error":"interface listing failed or returned empty output","mode":"%s"}\n' "$(json_escape "$mode")"
  exit 2
fi
ifaces=$(printf '%s\n' "$_links" | sed -n 's/^[0-9][0-9]*: \([^:@]*\).*/\1/p' | grep -E '^(tun[0-9]*|vpn[0-9]*|wg[0-9]*|ppp[0-9]*|ipsec[0-9]*|tap[0-9]*|utun[0-9]*|tailscale[0-9]*|zt[[:alnum:]_-]*)$' || true)
_if_json=$(printf '%s' "$ifaces" | tr '\n' ',' | sed 's/,$//')
if [ "$compat" != 1 ]; then
  printf '{"ok":false,"status":"overlay-disabled","error":"vpn_external_compat is disabled","mode":"%s","tunnel":"%s"}\n' "$(json_escape "$mode")" "$(json_escape "$_if_json")"
  exit 1
fi
if [ -z "$ifaces" ]; then
  printf '{"ok":false,"status":"no-external-tunnel-detected","error":"no known outer tunnel interface detected","mode":"%s"}\n' "$(json_escape "$mode")"
  exit 1
fi
iface=$(vpncore_outer_tunnel_interface 2>/dev/null || true)
case " $ifaces " in *" $iface "*) ;; *) iface="" ;; esac
if [ -z "$iface" ]; then
  printf '{"ok":false,"status":"outer-interface-unvalidated","error":"selected outer tunnel interface could not be validated","mode":"%s","tunnel":"%s"}\n' "$(json_escape "$mode")" "$(json_escape "$_if_json")"
  exit 1
fi
node_host=$(pg_vpn_node_endpoint_host 2>/dev/null || true)
if [ -z "$node_host" ]; then
  printf '{"ok":false,"status":"node-endpoint-unavailable","error":"selected FX node is missing or malformed","mode":"%s","tunnel":"%s"}\n' "$(json_escape "$mode")" "$(json_escape "$iface")"
  exit 1
fi
# Need the modern DNS server Dial Fields as well as outbound bind_interface. Never
# resolve the node hostname here: a shell-side lookup could leak via the physical DNS.
_bin=$(vpncore_bin 2>/dev/null || true)
_ver=$(vpncore_core_version "$_bin" 2>/dev/null || true)
if ! vpncore_ver_ge "$_ver" "1.12"; then
  printf '{"ok":false,"status":"core-version-too-old","error":"sing-box >=1.12 required for pinned DNS and outbound dial fields","mode":"%s","tunnel":"%s","core_version":"%s"}\n' "$(json_escape "$mode")" "$(json_escape "$iface")" "$(json_escape "$_ver")"
  exit 1
fi
cfg=$(vpncore_cfg)
if [ ! -s "$cfg" ]; then
  printf '{"ok":false,"status":"config-missing","error":"sing-box config missing; apply proxy mode after the outer VPN is active","mode":"%s","tunnel":"%s","route_target":"%s"}\n' "$(json_escape "$mode")" "$(json_escape "$iface")" "$(json_escape "$node_host")"
  exit 1
fi
# Each proxy node plus direct outbound and two DNS servers are pinned. Count fields,
# not lines, because the generated outbound list is serialized on one line.
count=$(awk -v needle="\"bind_interface\":\"$iface\"" '{s=$0; while ((p=index(s,needle)) > 0) {n++; s=substr(s,p+length(needle))}} END{print n+0}' "$cfg")
case "$count" in ''|*[!0-9]*) count=0 ;; esac
if [ "$count" -lt 4 ]; then
  printf '{"ok":false,"status":"outer-binding-missing","error":"expected node/direct plus both DNS sockets to be bound to the outer tunnel; found %s bind fields","mode":"%s","tunnel":"%s","route_target":"%s","core_version":"%s"}\n' "$count" "$(json_escape "$mode")" "$(json_escape "$iface")" "$(json_escape "$node_host")" "$(json_escape "$_ver")"
  exit 1
fi
# A missing VPNService UID means outer app sockets cannot be safely exempted from
# FX's own redirect chain; keep the diagnostic fail-closed even if the config is pinned.
uid=""
_vpn_info=$(vpncore_android_active_vpn_info 2>/dev/null || true)
case "$_vpn_info" in *"$iface|"*) uid=${_vpn_info#*|} ;; *) uid="" ;; esac
case "$uid" in ''|*[!0-9]*|0)
  printf '{"ok":false,"status":"vpn-owner-uid-unknown","error":"cannot identify the outer VPN owner UID; redirect-loop exemption is not verifiable","mode":"%s","tunnel":"%s","route_target":"%s","bind_count":%s}\n' "$(json_escape "$mode")" "$(json_escape "$iface")" "$(json_escape "$node_host")" "$count"
  exit 1 ;;
esac
note="sing-box config pins node, direct and DNS sockets to the detected outer tunnel; this does not prove end-to-end forwarding or public egress. Verify with a real app while both services run."
printf '{"ok":true,"status":"bind-interface-configured","configured":true,"effective":"unverified","ready":false,"dataplane_verified":false,"verification":"config-only","verification_required":"live-app-traffic","mode":"%s","tunnel":"%s","owner_uid":"%s","route_target":"%s","bind_count":%s,"core_version":"%s","note":"%s"}\n' "$(json_escape "$mode")" "$(json_escape "$iface")" "$uid" "$(json_escape "$node_host")" "$count" "$(json_escape "$_ver")" "$(json_escape "$note")"
