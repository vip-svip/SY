#!/system/bin/sh
# Regression: DNS lockdown must fail open without a trusted resolver, and
# uninstall must remove module-owned DNS/NAT chains for both IP families.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
U="$ROOT/uninstall.sh"
[ -f "$A" ] && [ -f "$U" ]
# DNS_SAFE is sourced only from explicitly enabled user-configured resolvers.
grep -Fq 'DNS_SAFE=""' "$A"
grep -Fq 'dns: 未配置可信 DNS，明文 DNS 不拦截（fail-open，防止整机没网）' "$A"
# Plain DNS is only rejected inside the trusted-resolver branch.
awk '
  /(if|elif) \[ "\$\(pg_get block_plain_dns 0\)" = "1" \]/ { active=1 }
  active { print }
  active && /if \[ "\$\(pg_get block_ipv6 0\)" = "1" \]/ { exit }
' "$A" > "${TMPDIR:-/tmp}/fx-dns-lifecycle.$$.txt"
trap 'rm -f "${TMPDIR:-/tmp}/fx-dns-lifecycle.$$.txt"' EXIT HUP INT TERM
B="${TMPDIR:-/tmp}/fx-dns-lifecycle.$$.txt"
grep -Fq 'fw4 -A PGUARD -p udp --dport 53 -j REJECT' "$B"
grep -Fq 'dns: 跳过明文 DNS 封锁（无可用可信 DNS，防止整机没网）' "$B"
# Redirection is explicitly suppressed when a third-party VPN tunnel is detected.
grep -Fq '[ "$_PG_VPN_INTERCEPTION_BLOCKED" = "0" ]' "$A"
# Uninstall covers the module-owned IPv4 and IPv6 NAT chains and verifies leftovers.
grep -Fq "'iptables|nat|PGNAT|OUTPUT|PGNAT'" "$U"
grep -Fq "'ip6tables|nat|PGNAT|OUTPUT|PGNAT'" "$U"
grep -Fq 'chain $_pf_chain still exists' "$U"
grep -Fq 'PG_FW_INCOMPLETE=1' "$U"
sh -n "$U"
sh -n "$A"
echo 'FX DNS lifecycle fail-open/uninstall regression: PASS'
