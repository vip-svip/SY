#!/system/bin/sh
# DNS status must not claim forwarding is active when PGNAT is not hooked to OUTPUT.
set -eu
S="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/status.sh"
grep -Fq '_dns_hook=$(iptables $FWWAIT -t nat -S OUTPUT' "$S"
grep -Fq 'DNS_FORWARD_STATUS="inactive"' "$S"
grep -Fq 'A populated chain without an OUTPUT jump is not active forwarding.' "$S"
printf '%s\n' 'PASS: DNS status requires live OUTPUT hook'
