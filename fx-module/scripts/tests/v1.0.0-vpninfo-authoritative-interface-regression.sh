#!/system/bin/sh
# Active app-VPN binding must use Android VpnInfo, not the first tun/wg/tailscale device.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-vpninfo.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/bin" "$T/cache"
cat > "$T/settings.conf" <<'CONF'
vpn_external_compat=1
vpn_mode=rule
CONF
cat > "$T/bin/ip" <<'IP'
#!/bin/sh
case "$*" in
  '-o link show') printf '%s\n' '1: lo: <LOOPBACK>' '7: wg0: <POINTOPOINT,UP>' '8: tun0: <POINTOPOINT,UP>' ;;
  '-o link show dev tun0')
    if [ "${FX_TEST_LINK_STATE:-up}" = down ]; then printf '%s\n' '8: tun0: <POINTOPOINT>'; else printf '%s\n' '8: tun0: <POINTOPOINT,UP>'; fi ;;
  '-o link show dev wg0') printf '%s\n' '7: wg0: <POINTOPOINT,UP>' ;;
  *) exit 1 ;;
esac
IP
cat > "$T/bin/dumpsys" <<'DUMPSYS'
#!/bin/sh
case "${FX_TEST_VPNINFO_MODE:-one}" in
  one) printf '%s\n' 'mVpnInfo=VpnInfo{ownerUid = 12345, vpnIface = tun0, primaryUnderlyingIface=wlan0}' ;;
  multiple) printf '%s\n' 'VpnInfo{ownerUid = 12345, vpnIface = tun0, primaryUnderlyingIface=wlan0}' 'VpnInfo{ownerUid=23456, vpnIface=vpn1, primaryUnderlyingIface=rmnet_data0}' ;;
  missing) printf '%s\n' 'No active VPN info' ;;
esac
DUMPSYS
chmod 755 "$T/bin/ip" "$T/bin/dumpsys"
export PG="$T" CONF="$T/settings.conf" MODDIR="$ROOT" PG_MODDIR="$ROOT" PATH="$T/bin:/usr/bin:/bin"
selected=$(sh -c '. "$MODDIR/scripts/util.sh"; . "$MODDIR/scripts/vpncore.sh"; vpncore_android_active_vpn_info')
[ "$selected" = 'tun0|12345' ] || { echo "FAIL: expected exact VpnInfo pair, got $selected" >&2; exit 1; }
selected_if=$(sh -c '. "$MODDIR/scripts/util.sh"; . "$MODDIR/scripts/vpncore.sh"; vpncore_outer_tunnel_interface')
[ "$selected_if" = 'tun0' ] || { echo "FAIL: expected active VpnInfo interface tun0, got $selected_if" >&2; exit 1; }
if FX_TEST_VPNINFO_MODE=multiple sh -c '. "$MODDIR/scripts/util.sh"; . "$MODDIR/scripts/vpncore.sh"; vpncore_android_active_vpn_info'; then
  echo 'FAIL: multiple active VpnInfo rows must be rejected as ambiguous' >&2; exit 1
fi
if FX_TEST_VPNINFO_MODE=missing sh -c '. "$MODDIR/scripts/util.sh"; . "$MODDIR/scripts/vpncore.sh"; vpncore_android_active_vpn_info'; then
  echo 'FAIL: missing VpnInfo must not fall back to the first generic tunnel' >&2; exit 1
fi
if FX_TEST_LINK_STATE=down sh -c '. "$MODDIR/scripts/util.sh"; . "$MODDIR/scripts/vpncore.sh"; vpncore_android_active_vpn_info'; then
  echo 'FAIL: active VpnInfo with a DOWN tunnel must be rejected' >&2; exit 1
fi
# Production apply.sh passes a previously detected interface into the config
# generator. Simulate a VPN handover between that detection and config binding:
# the cached name must not bypass the live UP check.
if FX_TEST_LINK_STATE=down sh -c '_PG_EXT_VPN_IF=tun0; . "$MODDIR/scripts/util.sh"; . "$MODDIR/scripts/vpncore.sh"; vpncore_outer_tunnel_interface'; then
  echo 'FAIL: cached outer interface was accepted after the tunnel went DOWN' >&2; exit 1
fi
echo 'PASS: active outer interface and owner UID require unique VpnInfo plus a live UP tunnel; cached interface is revalidated at bind time'
