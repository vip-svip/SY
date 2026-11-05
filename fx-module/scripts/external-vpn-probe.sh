#!/system/bin/sh
# Read-only Android external VPN probe. Generic tunnel names alone are not proof of
# the active app VPN; the same unique VpnInfo/owner UID query used by apply is required.
set -u
MODDIR=$(CDPATH= cd -- "$(dirname "$0")/.." 2>/dev/null && pwd)
. "$MODDIR/scripts/util.sh" 2>/dev/null || true
. "$MODDIR/scripts/vpncore.sh" 2>/dev/null || true
if ! command -v ip >/dev/null 2>&1; then
  printf '%s\n' '{"status":"unknown","reason":"ip-command-missing"}'
  exit 0
fi
_links=$(ip -o link show 2>/dev/null)
_rc=$?
if [ "$_rc" -ne 0 ] || [ -z "$_links" ]; then
  printf '%s\n' '{"status":"unknown","reason":"link-probe-failed-or-empty"}'
  exit 0
fi
_hit=$(vpncore_android_active_vpn_info 2>/dev/null || true)
if [ -n "$_hit" ]; then
  _if=${_hit%%|*}; _uid=${_hit#*|}
  printf '{"status":"tunnel","interface":"%s","owner_uid":"%s","source":"android-vpninfo"}\n' "$_if" "$_uid"
  exit 0
fi
_other=$(printf '%s\n' "$_links" | sed -n 's/^[0-9][0-9]*: \([^:@]*\).*/\1/p' | grep -E '^(tun[0-9]*|vpn[0-9]*|wg[0-9]*|ppp[0-9]*|ipsec[0-9]*|tap[0-9]*|utun[0-9]*|tailscale[0-9]*|zt[[:alnum:]_-]*)$' || true)
if [ -n "$_other" ]; then
  printf '%s\n' '{"status":"unknown","reason":"tunnel-link-without-unique-active-vpninfo"}'
else
  printf '%s\n' '{"status":"none"}'
fi
exit 0
