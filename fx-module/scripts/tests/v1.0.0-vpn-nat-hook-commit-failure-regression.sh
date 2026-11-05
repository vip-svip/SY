#!/system/bin/sh
# Regression: VPN/DNS interception hooks must only be attached after queued NAT
# rules and buffered firewall rules commit successfully.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
[ -f "$A" ]
# IPv4 VPN hook: the commit checks and hook installation must share one success branch.
grep -Fq 'if fw_flush 2>/dev/null && nat_flush 2>/dev/null && nat4 -I OUTPUT -j PGVPN; then' "$A"
grep -Fq 'PGVPN 规则提交或 OUTPUT 挂载失败；未启用透明代理接管' "$A"
# IPv6 VPN hook must also gate the OUTPUT jump on successful queue commits.
grep -Fq 'if fw_flush 2>/dev/null && nat_flush 2>/dev/null && nat6 -I OUTPUT -j PGVPN6; then' "$A"
grep -Fq 'PGVPN6 规则提交或 OUTPUT 挂载失败；IPv6 代理接管未启用' "$A"
# DNS-hiding hook must not be attached when the DNAT chain failed to commit.
grep -Fq 'if fw_flush 2>/dev/null && nat_flush 2>/dev/null && nat4 -I OUTPUT -j PGHIDE; then' "$A"
grep -Fq 'PGHIDE DNS 规则提交或 OUTPUT 挂载失败；已尝试回滚 DNS 劫持链' "$A"
sh -n "$A"
echo 'FX VPN NAT hook commit-failure regression: PASS'
