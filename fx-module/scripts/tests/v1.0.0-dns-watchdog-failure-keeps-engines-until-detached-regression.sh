#!/system/bin/sh
# Regression: if local DNS watchdog startup fails, never stop AdGuard/Unbound
# while either IPv4 or IPv6 OUTPUT may still redirect to PGNAT.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
[ -f "$A" ]
sh -n "$A"
B="${TMPDIR:-/tmp}/fx-dns-watchdog-failopen.$$.txt"
trap 'rm -f "$B"' EXIT HUP INT TERM
awk '
  /if ! sh "\$MODDIR\/scripts\/localdns-watchdog\.sh" start/ { active=1 }
  active { print }
  active && /^  fi$/ { exit }
' "$A" > "$B"
grep -Fq '_pg_dns_v4_detached=0' "$B"
grep -Fq '_pg_dns_v6_detached=0' "$B"
grep -Fq 'iptables $FWWAIT -t nat -S OUTPUT' "$B"
grep -Fq 'ip6tables $FWWAIT -t nat -S OUTPUT' "$B"
grep -Fq 'if [ "$_pg_dns_v4_detached" = 1 ] && [ "$_pg_dns_v6_detached" = 1 ]; then' "$B"
grep -Fq 'leaving local DNS engines running to avoid black-holing redirected traffic' "$B"
# Both engine stops must be in the confirmed-detached branch, not the failure branch.
awk '
  /if \[ "\$_pg_dns_v4_detached" = 1 \] && \[ "\$_pg_dns_v6_detached" = 1 \]; then/ { safe=1 }
  safe && /adguardhome\.sh" stop/ { agh=1 }
  safe && /else/ { unsafe=1 }
  unsafe && /adguardhome\.sh" stop/ { bad=1 }
  END { exit !(safe && agh && !bad) }
' "$B"
echo 'FX DNS watchdog rollback fail-open regression: PASS'
