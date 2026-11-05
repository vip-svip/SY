#!/system/bin/sh
# Regression: direct-mode cleanup must remove duplicate jumps and verify IPv4+IPv6
# across all module-owned netfilter tables before claiming zero interception.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
# The general cleanup path removes duplicate OUTPUT jumps, not just one occurrence.
grep -Fq 'while [ "$_dr" -lt 64 ] && iptables $FWWAIT -t "$_dt" -D OUTPUT -j "$_dc"' "$A"
grep -Fq 'while [ "$_dr" -lt 64 ] && ip6tables $FWWAIT -D OUTPUT -j "$_dc"' "$A"
# Direct-mode final verification must query both IP families and all touched tables.
grep -Fq 'for _fam in 4 6; do' "$A"
grep -Fq 'for _t in nat filter mangle raw; do' "$A"
grep -Fq 'IPv4/IPv6 各表仍有' "$A"
grep -Fq 'IPv4/IPv6 nat/filter/mangle/raw 接管链均已清除' "$A"
sh -n "$A"
echo 'FX VPN direct IPv6 residual/duplicate-jump regression: PASS'
