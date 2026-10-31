#!/system/bin/sh
# Regression: selector default must reference an outbound actually emitted.
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MODULE_ROOT=${FX_MODULE_ROOT:-"$REPO/fx-module"}
VPNCORE="$MODULE_ROOT/scripts/vpncore.sh"
[ -s "$VPNCORE" ]
SELECTED_URI=""
pg_get() {
  case "$1" in vpn_node) printf '%s' "$SELECTED_URI" ;; *) printf '%s' "${2:-}" ;; esac
}
pg_list_enabled() { return 0; }
pg_list() {
  printf '%s\n' 'invalid://broken|broken|1' 'vless://11111111-1111-4111-8111-111111111111@valid-two.example:443?security=tls|valid two|1' 'vless://22222222-2222-4222-8222-222222222222@valid-three.example:443?security=tls|valid three|1'
}
. "$VPNCORE"
SELECTED_URI="vless://22222222-2222-4222-8222-222222222222@valid-three.example:443?security=tls"
[ "$(vpncore_default_tag)" = "node-3" ] || { echo "FAIL: valid selected node was not retained" >&2; exit 1; }
SELECTED_URI="removed://stale"
[ "$(vpncore_default_tag)" = "node-2" ] || { echo "FAIL: stale selection did not fall back to first emitted outbound" >&2; exit 1; }
SELECTED_URI="invalid://broken"
[ "$(vpncore_default_tag)" = "node-2" ] || { echo "FAIL: invalid selected node did not fall back to first emitted outbound" >&2; exit 1; }
echo "PASS: VPN selector default always references a parseable emitted outbound"
