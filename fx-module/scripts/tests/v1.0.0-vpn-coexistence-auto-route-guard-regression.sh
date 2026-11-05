#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
C="$ROOT/scripts/default.conf"
U="$ROOT/scripts/util.sh"
H="$ROOT/webroot/index.html"
E="$ROOT/scripts/vpn-overlay-check.sh"
grep -Fq 'vpn_external_compat=1' "$C"
grep -Fq 'VPN_EXTERNAL_COMPAT=$(pg_get vpn_external_compat 1)' "$A"
grep -Fq 'existing outer tunnel $_PG_BIND_IF' "$A"
grep -Fq 'endpoint host=$_PG_VPN_ROUTE_HOST' "$A"
grep -Fq 'selected FX node endpoint' "$A"
grep -Fq 'vpncore_outer_tunnel_interface' "$A"
if grep -Fq 'pg_vpn_node_endpoint_ip' "$A"; then echo 'FAIL: route guard resolves node domains through shell DNS' >&2; exit 1; fi
if grep -Fq 'ip route get 1.1.1.1' "$A"; then echo 'FAIL: generic public IP still used as FX node route proof' >&2; exit 1; fi
grep -Fq 'forcing safe direct mode instead of allowing FX node upstream to escape outside the outer tunnel' "$A"
grep -Fq 'vpn_external_compat_auto_v1.done' "$U"
grep -Fq 'vpn_external_compat=1' "$C"
grep -Fq 'compat=$(pg_get vpn_external_compat 1)' "$E"
if grep -Fq 'api.ipify.org' "$E"; then echo 'FAIL: diagnostic sends a separate public egress request before route confirmation' >&2; exit 1; fi
grep -Fq 'bind-interface-configured' "$E"
if grep -Fq 'pg_vpn_node_endpoint_ip' "$E"; then echo 'FAIL: diagnostic resolves node domain outside pinned DNS' >&2; exit 1; fi
if grep -Eq 'id="(vpnExternalCompatToggle|vpnOverlayCheck)"' "$H"; then echo 'FAIL: internal VPN diagnostic controls must not be exposed in the UI' >&2; exit 1; fi
grep -Fq 'automatic guarded overlay allowed' "$A"
# There must be no click listener that persists a manual overlay mode.
if sed -n '/External VPN coexistence is automatic/,/Probe the selected FX node route only/p' "$H" | grep -q 'addEventListener.*click'; then echo 'FAIL: external VPN coexistence remains a manual mode switch' >&2; exit 1; fi
sh -n "$A"; sh -n "$U"; sh -n "$E"
printf '%s\n' 'PASS: VPN coexistence is automatic when outer interface, UID and explicit node/direct/DNS binding are confirmed; diagnostic avoids shell DNS and public-IP probes'
