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
vpncore_nodes() {
  printf '%s\n' 'invalid://broken|broken|1' 'vmess://valid-two|valid two|1' 'vless://valid-three|valid three|1'
}
singbox_node_outbound() {
  case "$1" in
    vmess://valid-two|vless://valid-three) printf '%s' '{"type":"mock"}' ;;
    *) return 0 ;;
  esac
}
. "$VPNCORE"
SELECTED_URI="vless://valid-three"
[ "$(vpncore_default_tag)" = "node-3" ] || { echo "FAIL: valid selected node was not retained" >&2; exit 1; }
SELECTED_URI="removed://stale"
[ "$(vpncore_default_tag)" = "node-2" ] || { echo "FAIL: stale selection did not fall back to first emitted outbound" >&2; exit 1; }
SELECTED_URI="invalid://broken"
[ "$(vpncore_default_tag)" = "node-2" ] || { echo "FAIL: invalid selected node did not fall back to first emitted outbound" >&2; exit 1; }
echo "PASS: VPN selector default always references a parseable emitted outbound"
