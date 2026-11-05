#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
W="$ROOT/scripts/localdns-watchdog.sh"
A="$ROOT/scripts/apply.sh"
sh -n "$W"
sh -n "$A"
# Watch the filtering frontend too; Unbound can be healthy while AGH has died.
grep -Fq 'sh "$MODDIR/scripts/adguardhome.sh" status "$MODDIR" "$PG"' "$W"
grep -Fq 'AdGuard Home filtering front-end or uncached Unbound recursive probe failed' "$W"
! grep -Fq 'sh "$MODDIR/scripts/unbound.sh" status' "$W"
grep -Fq 'watchdog child could not prove liveness after PID publication' "$W"
grep -Fq '_remove_owned_pidfile()' "$W"
grep -Fq "trap '_watchdog_exit' HUP INT TERM" "$W"
grep -Fq '_watchdog_exit() {' "$W"
grep -Fq '_remove_owned_pidfile' "$W"
# Runtime loop exit paths must not unconditionally delete a replacement PID marker.
! grep -nE '^[[:space:]]*rm -f \"\$PIDFILE\"' "$W" | grep -E ':(9[0-9]|10[0-9]|11[0-9]):' >/dev/null
grep -Fq '本地递归 DNS 看门狗未能验证存活' "$A"
grep -Fq 'localdns-watchdog.sh" stop' "$A"
python3 - "$A" <<'PY_CHECK'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
start=s.index('本地递归 DNS 看门狗未能验证存活')
b=s[start:]
for x in ['iptables $FWWAIT -t nat -D OUTPUT -j PGNAT','ip6tables $FWWAIT -t nat -D OUTPUT -j PGNAT','iptables $FWWAIT -t nat -F PGNAT','ip6tables $FWWAIT -t nat -F PGNAT','adguardhome.sh" stop']:
    if x not in b: raise SystemExit('FAIL: watchdog failure rollback missing '+x)
if b.index('iptables $FWWAIT -t nat -D OUTPUT -j PGNAT') > b.index('iptables $FWWAIT -t nat -F PGNAT'):
    raise SystemExit('FAIL: chain flushed before its hook was detached')
# If policy intentionally disables the local recursive DNS chain (e.g. an
# external VPN is detected), the old watchdog must stop before the engine does.
branch=s[s.index('DNS_AGH_ACTIVE=0'):s.index('if [ -n "$DNS_SAFE" ]',s.index('DNS_AGH_ACTIVE=0'))]
if 'localdns-watchdog.sh" stop "$MODDIR" "$PG"' not in branch:
    raise SystemExit('FAIL: intentional local-DNS disable path does not stop its watchdog')
if branch.index('localdns-watchdog.sh" stop') > branch.index('adguardhome.sh" stop'):
    raise SystemExit('FAIL: watchdog is stopped after its DNS engine')
if 'DNS interception is intentionally disabled' not in branch:
    raise SystemExit('FAIL: watchdog stop failure is not logged')
# The IPv6 loopback-NAT failure path also abandons the local DNS engine and
# must stop its watcher before the engine's PID markers disappear.
ipv6=s[s.index('# Build IPv6 rules while the chain is unreferenced'):s.index('if [ -n "$DNS_FWD" ]',s.index('# Build IPv6 rules while the chain is unreferenced'))]
if 'localdns-watchdog.sh" stop' not in ipv6:
    raise SystemExit('FAIL: IPv6 loopback NAT fallback leaves local DNS watchdog running')
if ipv6.index('localdns-watchdog.sh" stop') > ipv6.index('adguardhome.sh" stop'):
    raise SystemExit('FAIL: IPv6 fallback stops DNS engine before its watchdog')
print('PASS: watchdog verifies full DNS chain; failed monitor start rolls back hooks; intentional DNS/VPN bypass and IPv6 fallback stop watchdog before stopping engines')
PY_CHECK
