#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
# Both safe-skip and rollback paths must preserve iptables -S failure status.
[ "$(grep -Fc 'if _PGHKS_RULES4=$(iptables $FWWAIT -S 2>/dev/null); then' "$A")" -ge 2 ]
[ "$(grep -Fc 'if _PGHKS_RULES6=$(ip6tables $FWWAIT -S 2>/dev/null); then' "$A")" -ge 2 ]
[ "$(grep -Fc '_PGHKS_REF4=1' "$A")" -ge 2 ]
[ "$(grep -Fc '_PGHKS_REF6=1' "$A")" -ge 2 ]
[ "$(grep -Fc 'if [ "$_PGHKS_REF4" = "0" ]; then' "$A")" -ge 2 ]
[ "$(grep -Fc 'if [ "$_PGHKS_REF6" = "0" ]; then' "$A")" -ge 2 ]
! grep -Fq '_PGHKS_REF4=$(iptables $FWWAIT -S 2>/dev/null | grep -cE' "$A"
! grep -Fq '_PGHKS_REF6=$(ip6tables $FWWAIT -S 2>/dev/null | grep -cE' "$A"
sh -n "$A"
echo 'PGHKS referenced-chain safety regression: PASS'
