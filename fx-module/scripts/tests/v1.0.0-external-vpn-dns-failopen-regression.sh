#!/system/bin/sh
# DNS filtering must not reject the system resolver when FX deliberately suspends
# its own DNS/NAT redirection for a third-party VPN tunnel.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
sh -n "$A"
python3 - "$A" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text(encoding='utf-8')
def need(label, ok):
    if not ok: raise SystemExit('FAIL: '+label)
detect=s.index('_PG_EXT_VPN_IF=""')
resolver=s.index('DNS_SAFE=""')
lock=s.index('if [ "$_PG_VPN_INTERCEPTION_BLOCKED" = "1" ]; then', resolver)
plain=s.index('elif [ "$(pg_get block_plain_dns 0)" = "1" ] || [ "$(pg_get dns_leak 0)" = "1" ]; then', lock)
reject=s.index('fw4 -A PGUARD -p udp --dport 53 -j REJECT', plain)
need('external tunnel is detected before DNS filter construction', detect < resolver < lock < plain < reject)
branch=s[lock:plain]
need('external VPN branch explicitly fail-opens instead of merely logging a detected tunnel', 'skip local plaintext-DNS lockdown' in branch and 'fail-open' in branch)
need('DNS/NAT redirection requires a conclusive no-tunnel probe', '[ "$_PG_VPN_INTERCEPTION_BLOCKED" = "0" ]' in s[s.index('# DNS 兜底重定向'):])
print('PASS: external VPN + configured DNS cannot leave a filter-only plaintext DNS lockdown')
PY
