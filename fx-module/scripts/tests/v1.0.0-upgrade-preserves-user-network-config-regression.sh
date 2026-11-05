#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
C="$ROOT/customize.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
# User-selected networking keys must survive the exact helper used by customize.sh.
awk '/^pg_add_missing_network_defaults\(\) \{/ {copy=1} copy {print} copy && /^}/ {exit}' "$C" > "$T/helper.sh"
test -s "$T/helper.sh"
. "$T/helper.sh"
CFG="$T/settings.conf"
cat > "$CFG" <<'CONF'
hosts_block=1
vpn_mode=rule
vpn_dns_hijack=1
vpn_killswitch=1
vpn_udp_block=1
vpn_hide=2
vpn_leak=1
block_quic=1
block_stun=1
block_dot=1
block_multicast=1
custom_subscription=https://example.invalid/sub
CONF
pg_add_missing_network_defaults "$CFG"
for kv in 'hosts_block=1' 'vpn_mode=rule' 'vpn_dns_hijack=1' 'vpn_killswitch=1' 'vpn_udp_block=1' 'vpn_hide=2' 'vpn_leak=1' 'block_quic=1' 'block_stun=1' 'block_dot=1' 'block_multicast=1' 'custom_subscription=https://example.invalid/sub'; do
  grep -Fxq "$kv" "$CFG" || { echo "FAIL: upgrade overwrote or lost $kv" >&2; exit 1; }
done
# Missing compatibility defaults are appended once and only once.
grep -Fxq 'lsposed_enabled=0' "$CFG"
test "$(grep -Fc 'vpn_mode=' "$CFG")" -eq 1
test "$(grep -Fc 'hosts_block=' "$CFG")" -eq 1
# The install banner and runtime metadata use the fixed product version.
grep -Fq 'FX 1.0.0' "$C"
! grep -Fq 'v1.10.14' "$C"
grep -Fq 'pg_add_missing_network_defaults /data/adb/privacyguard/settings.conf' "$C"
echo 'PASS: upgrades preserve existing network settings and add only missing defaults; installer identifies FX 1.0.0'
