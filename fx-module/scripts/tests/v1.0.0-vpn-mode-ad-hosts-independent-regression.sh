#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
C="$ROOT/scripts/default.conf"
H="$ROOT/webroot/index.html"
# Ad/hosts compilation is controlled by enabled rules and FX master, not vpn_mode.
# VPN_MODE is assigned later in apply.sh; hosts selection/commit happens before it.
HOSTS_LINE=$(grep -n '^_hosts_block_on=' "$A" | head -1 | cut -d: -f1)
VPN_LINE=$(grep -n '^# ---------- 2. 防火墙' "$A" | head -1 | cut -d: -f1)
[ -n "$HOSTS_LINE" ] && [ -n "$VPN_LINE" ] && [ "$HOSTS_LINE" -lt "$VPN_LINE" ] || { echo 'FAIL: hosts/ad compilation must be independent of proxy mode' >&2; exit 1; }
grep -Fq '_fx_master_on=$(pg_get fx 0)' "$A"
grep -Fq 'if [ "$_hosts_block_on" = "1" ] || [ "$_fx_master_on" = "1" ]; then' "$A"
grep -Fq 'pg_commit_hosts_candidate' "$A"
# Direct mode remains node-free and uses quick apply; rule/global still require a node.
grep -Fq "if(mode!=='direct'&&!selectedNodeReady)" "$H"
grep -Fq "applyRun(mode==='direct'?'fast':null" "$H"
# Don't accidentally add a proxy-mode gate to the hosts compilation block.
BLOCK=$(sed -n "${HOSTS_LINE},${VPN_LINE}p" "$A")
if printf '%s\n' "$BLOCK" | grep -Eq 'VPN_MODE|vpn_mode'; then echo 'FAIL: hosts block is coupled to VPN mode' >&2; exit 1; fi
sh -n "$A"
echo 'PASS: direct/rule/global modes share the independent Hosts/ad-rule compilation path; proxy node requirement applies only to rule/global'
