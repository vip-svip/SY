#!/system/bin/sh
# DNS exception list must reject malformed IPv4/IPv6 before feeding firewall rules.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
grep -Fq 'DNSLIST=$(pg_conf custom_dns 2>/dev/null | awk' "$A"
grep -Fq '非法地址塞进 iptables-restore 队列' "$A"
validate_list() {
  awk '
    /^[[:space:]]*#/ || NF == 0 { next }
    {
      ip=$NF
      if (ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
        n=split(ip, oct, "."); ok=(n == 4)
        for (i=1; i<=4; i++) if (oct[i] !~ /^[0-9]+$/ || length(oct[i]) > 3 || oct[i]+0 > 255) ok=0
        if (ip == "0.0.0.0" || ip == "255.255.255.255") ok=0
        if (ok) print ip
        next
      }
      if (ip !~ /^[0-9A-Fa-f:]+$/ || index(ip, ":") == 0) next
      d=ip; doubles=0; while (sub(/::/, ":", d)) doubles++
      if (doubles > 1) next
      n=split(ip, grp, ":"); ok=1; count=0
      for (i=1; i<=n; i++) if (grp[i] != "") {
        if (grp[i] !~ /^[0-9A-Fa-f]+$/ || length(grp[i]) > 4) ok=0
        count++
      }
      if (doubles == 0 && count != 8) ok=0
      if (doubles == 1 && count >= 8) ok=0
      if (ok) print ip
    }
  '
}
actual=$(printf '%s\n' \
  'nameserver 223.5.5.5' \
  'nameserver 999.1.1.1' \
  'nameserver 1.2.3.256' \
  'nameserver 0.0.0.0' \
  'nameserver 255.255.255.255' \
  'nameserver 2001:4860:4860::8888' \
  'nameserver 2001:::1' \
  'nameserver 12345::1' \
  'nameserver 2001:db8:0:0:0:0:0:1' | validate_list)
expected=$(printf '%s\n' '223.5.5.5' '2001:4860:4860::8888' '2001:db8:0:0:0:0:0:1')
[ "$actual" = "$expected" ] || { printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2; exit 1; }
sh -n "$A"
echo 'FX DNS exception address validation regression: PASS'
