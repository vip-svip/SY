#!/system/bin/sh
# IPv4-only trusted resolver must not cause unconditional IPv6 DNS rejection.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
sh -n "$A"
awk '
  /DNSLIST_IPV6=0/ { active=1; found=1 }
  active { print }
  active && /else/ && /$/ { }
  active && /if \[ "\$DNSLIST_IPV6" = "1" \]; then/ { gate=1 }
  active && /fw6 -A PGUARD -p udp --dport 53 -j REJECT/ { if (!gate) bad=1; reject++ }
  active && /no validated IPv6 resolver exception/ { failopen=1 }
  active && /fi/ && gate { exit }
  END { if (!found || !gate || bad || reject != 1 || !failopen) exit 1 }
' "$A"
# Ensure the independent explicit DoT-enforcement policy was not silently weakened.
awk '
  /if \[ "\$\(pg_get dot_enforce 0\)" = "1" \]; then/ { active=1 }
  active { print }
  active && /pg_log "fw: dot_enforce/ { exit }
' "$A" | grep -Fq 'fw6 -A PGUARD -p udp --dport 53 -j REJECT'
echo 'FX IPv6 DNS fail-open with IPv4-only resolver regression: PASS'
