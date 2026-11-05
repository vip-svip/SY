#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
DNS="$ROOT/scripts/dnscheck.sh"
# The resolver address alone must not make NXDOMAIN/timeout output successful.
grep -Fq 'NXDOMAIN|SERVFAIL|REFUSED|timed out|time out|no servers could be reached|can.t find|cannot find|not found|connection refused|network is unreachable|temporary failure in name resolution' "$DNS"
# Negative resolver results are classified before the generic IP-address match.
neg=$(grep -n 'NXDOMAIN|SERVFAIL' "$DNS" | cut -d: -f1)
pos=$(grep -n 'lookup returned an address' "$DNS" | head -1 | cut -d: -f1)
[ "$neg" -lt "$pos" ]
# The script must retain bounded lookup behavior and not report a probe as success without a timeout mechanism.
grep -Fq 'lookup tool found but no bounded timeout command is available; lookup not executed' "$DNS"
echo 'FX DNS negative-result classification regression: PASS'
