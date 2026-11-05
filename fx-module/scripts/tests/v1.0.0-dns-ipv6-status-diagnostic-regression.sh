#!/system/bin/sh
# IPv6 DNS status is diagnostic-only and requires both PGNAT rules and OUTPUT hook.
set -eu
S="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/status.sh"
grep -Fq 'DNS_FORWARD_V6_STATUS="unknown"' "$S"
grep -Fq '_dns6_hook=$(ip6tables $FWWAIT -t nat -S OUTPUT' "$S"
grep -Fq 'DNS_FORWARD_V6_STATUS="inactive"' "$S"
grep -Fq 'DNS_FORWARD_V6_STATUS="partial"' "$S"
grep -Fq 'DNS_FORWARD_V6_STATUS="active"' "$S"
grep -Fq '"dns_forward_v6_status":"%s"' "$S"
grep -Fq 'DNS 明文转发规则(IPv6，仅状态诊断)' "$S"
printf '%s\n' 'PASS: IPv6 DNS forwarding status is independent, hook-aware, and diagnostic-only'
