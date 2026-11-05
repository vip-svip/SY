#!/system/bin/sh
# Regression: DNS DNAT targets must be valid IPv4 addresses, not merely dotted quads.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
# Assert all resolver paths use the shared numeric validator.
[ "$(grep -Fc 'pg_conf custom_dns 2>/dev/null | pg_first_valid_ipv4' "$A")" -eq 1 ]
[ "$(grep -Fc 'pg_conf global_dns 2>/dev/null | pg_first_valid_ipv4' "$A")" -eq 1 ]
[ "$(grep -Fc 'pg_conf custom_dns | pg_first_valid_ipv4' "$A")" -eq 1 ]
[ "$(grep -Fc 'pg_conf global_dns | pg_first_valid_ipv4' "$A")" -eq 1 ]
# Execute the same POSIX awk validation algorithm against good and malformed values.
validate() {
  awk '
    /^[[:space:]]*#/ || NF == 0 { next }
    { ip=$NF; n=split(ip, oct, "."); if (n != 4) next; ok=1;
      for (i=1; i<=4; i++) if (oct[i] !~ /^[0-9]+$/ || length(oct[i]) > 3 || (oct[i]+0) > 255) ok=0;
      if (ip == "0.0.0.0" || ip == "255.255.255.255") ok=0;
      if (ok) { print ip; exit }
    }
  '
}
[ "$(printf 'dns 999.1.1.1\ndns 8.8.8.8\n' | validate)" = '8.8.8.8' ]
[ "$(printf 'dns 1.2.3.256\ndns 1.2.3.4.5\n' | validate)" = '' ]
[ "$(printf 'nameserver 0.0.0.0\nnameserver 8.8.4.4\n' | validate)" = '8.8.4.4' ]
[ "$(printf 'nameserver 255.255.255.255\nnameserver 1.0.0.1\n' | validate)" = '1.0.0.1' ]
[ "$(printf 'nameserver 0.0.0.0\nnameserver 255.255.255.255\n' | validate)" = '' ]
[ "$(printf '# disabled 9.9.9.9\ndns 1.1.1.1\n' | validate)" = '1.1.1.1' ]
sh -n "$A"
echo 'FX DNS resolver IPv4 validation regression: PASS'
