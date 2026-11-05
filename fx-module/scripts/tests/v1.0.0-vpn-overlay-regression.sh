#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
C="$ROOT/scripts/default.conf"
H="$ROOT/webroot/index.html"
E="$ROOT/scripts/vpn-overlay-check.sh"
# Coexistence is automatic by default; sing-box must bind node/direct/DNS sockets to the outer interface.
grep -Fq 'vpn_external_compat=1' "$C"
# Detection precedes DNS/NAT rule generation.
D=$(grep -n '^_PG_EXT_VPN_IF=""' "$A" | head -1 | cut -d: -f1)
G=$(grep -n '^# 全局 DNS 替换' "$A" | head -1 | cut -d: -f1)
[ -n "$D" ] && [ -n "$G" ] && [ "$D" -lt "$G" ]
# Safe mode pauses PGVPN; explicit compatibility mode keeps PGVPN enabled.
grep -Fq 'VPN_EXTERNAL_COMPAT=$(pg_get vpn_external_compat 1)' "$A"
grep -Fq '[ "$VPN_EXTERNAL_COMPAT" != "1" ]' "$A"
grep -Fq 'automatic guarded overlay allowed; external VPN UID is exempted from PGVPN' "$A"
grep -Fq 'every node/direct/DNS outbound to that interface' "$A"
grep -Fq 'vpncore_outer_tunnel_interface' "$ROOT/scripts/vpncore.sh"
grep -Fq 'bind_interface' "$ROOT/scripts/vpncore.sh"
grep -Fq 'VPNService owner UID is unknown; FX interception will pause safely' "$A"
grep -Fq 'overlay mode skips QUIC/UDP block' "$A"
grep -Fq 'overlay mode skips IPv6 fail-closed filter' "$A"
grep -Fq 'vpn_hide: suspended during external VPN overlay' "$A"
# Generic DNS/transparent proxy NAT remains disabled whenever an external tunnel is detected.
grep -Fq 'pg_get global_dns 0)" = "1" ] && [ "$_PG_VPN_INTERCEPTION_BLOCKED" = "0"' "$A"
grep -Fq 'pg_get transparent_proxy 0)" = "1" ] && [ "$_PG_VPN_INTERCEPTION_BLOCKED" = "0"' "$A"
# Generic output filtering must bypass the outer VPN UID, or remain detached when that UID is not trustworthy.
grep -Fq 'PGUARD bypasses detected external VPN owner UID' "$A"
grep -Fq 'PGUARD OUTPUT hook suppressed to preserve network/VPN' "$A"
# UI uses automatic coexistence status, has no manual compatibility mode switch, and distinguishes config binding from live egress.
! grep -Fq 'id="vpnExternalCompatToggle"' "$H"
grep -Fq 'selected FX node endpoint' "$A"
grep -Fq 'explicit outer-tunnel outbound/DNS binding not verified; forcing safe direct mode' "$A"
grep -Fq 'forcing safe direct mode instead of allowing FX node upstream to escape' "$A"
! grep -Fq 'id="vpnOverlayCheck"' "$H"
grep -Fq 'bind-interface-configured' "$E"
grep -Fq 'this does not prove end-to-end forwarding or public egress' "$E"
grep -Fq 'outer-binding-missing' "$E"
sh -n "$E"
! grep -Fq "vpn_external_compat" "$H"
! grep -Fq '外部 VPN 共存诊断' "$H"
for f in "$ROOT"/*.sh "$ROOT"/scripts/*.sh "$ROOT"/scripts/tests/*.sh; do [ ! -f "$f" ] || sh -n "$f"; done
echo 'FX 1.0.0 external VPN overlay regression: PASS'
