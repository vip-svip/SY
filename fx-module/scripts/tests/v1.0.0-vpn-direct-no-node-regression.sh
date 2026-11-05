#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
UI="$ROOT/webroot/index.html"
CORE="$ROOT/scripts/vpncore.sh"
APPLY="$ROOT/scripts/apply.sh"
# The UI must only require a selected node for global/rule modes.
grep -Fq "if(mode!=='direct'&&!selectedNodeReady)" "$UI"
grep -Fq '直连无需节点；全局/规则代理需要先选择节点' "$UI"
if grep -Fq 'Direct mode does not intercept traffic' "$UI"; then echo 'FAIL: stale direct-mode disclaimer remains in node-empty UI' >&2; exit 1; fi
grep -Fq "return applyRun(mode==='direct'?'fast':null,{label:label})" "$UI"
# Fast is a real apply.sh dispatch, not a UI-only label or unknown argument.
grep -Eq 'fast\|--quick\|-q\|full' "$APPLY"
# Execute the actual backend entry points with a direct-mode config stub. They
# must return successfully without resolving/installing/starting a proxy core.
OUT=$(sh -c '
  . "$1/scripts/util.sh"
  . "$1/scripts/vpncore.sh"
  pg_conf() { [ "$1" = vpn ] && printf "vpn_mode=direct\\n"; }
  pg_log() { :; }
  vpncore_bin() { echo "FAIL: core binary lookup attempted in direct mode" >&2; return 99; }
  vpncore_start
  vpn_core_ensure
' sh "$ROOT" 2>&1) || { echo "$OUT"; echo 'FAIL: direct mode backend entry points returned failure'; exit 1; }
case "$OUT" in *'FAIL: core binary lookup attempted'*) echo "$OUT"; exit 1 ;; esac
# Firewall apply contract: direct mode bypasses node validation and removes interception chains.
grep -Fq 'if [ "$VPN_MODE" != "direct" ]; then' "$APPLY"
grep -Fq 'vpn: direct mode verified — IPv4/IPv6 nat/filter/mangle/raw 接管链均已清除' "$APPLY"
echo 'FX VPN direct mode no-node regression: PASS'
