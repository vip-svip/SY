#!/system/bin/sh
# Audit106: disabled custom DNS values must not become firewall RETURN exceptions.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
sh -n "$A"
awk '
  /(if|elif) \[ "\$\(pg_get block_plain_dns 0\)" = "1" \]/ { active=1 }
  active { print }
  active && /if \[ "\$\(pg_get block_ipv6 0\)" = "1" \]/ { exit }
' "$A" > "${TMPDIR:-/tmp}/fx-dns-custom-gate.$$.txt"
B="${TMPDIR:-/tmp}/fx-dns-custom-gate.$$.txt"
trap 'rm -f "$B"' EXIT HUP INT TERM
# The DNS list must start empty and custom config parsing must be nested behind the persisted switch.
grep -Fq 'DNSLIST=""' "$B"
grep -Fq 'if [ "$(pg_get custom_dns 0)" = "1" ]; then' "$B"
awk '
  /DNSLIST=""/ { empty=NR }
  /if \[ "\$\(pg_get custom_dns 0\)" = "1" \]; then/ { gate=NR }
  /DNSLIST=\$\(pg_conf custom_dns/ { parse=NR }
  /DNSLIST="\$DNSLIST \$DNS_SAFE"/ { safe=NR }
  END { if (!(empty && gate > empty && parse > gate && safe > parse)) exit 1 }
' "$B"
echo 'FX DNS disabled-custom exception regression: PASS'
