#!/system/bin/sh
# Regression: custom DNS must redirect TCP as well as UDP when dns_forward is disabled.
set -eu
MODDIR=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
APPLY="$MODDIR/scripts/apply.sh"
[ -f "$APPLY" ] || { echo 'FAIL: apply.sh missing'; exit 1; }
# Pin the exact custom_dns branch, rather than relying on the separate dns_forward path.
awk '
  /# 自定义 DNS 重定向/ { in_custom=1 }
  in_custom && /# 外部 VPN 检测/ { in_custom=0 }
  in_custom { print }
' "$APPLY" > "${TMPDIR:-/tmp}/fx-custom-dns-branch.$$"
trap 'rm -f "${TMPDIR:-/tmp}/fx-custom-dns-branch.$$"' EXIT HUP INT TERM
B="${TMPDIR:-/tmp}/fx-custom-dns-branch.$$"
grep -F 'nat4 -A PGNAT -p udp --dport 53 -j DNAT --to-destination "$DNS1"' "$B" >/dev/null
grep -F 'nat4 -A PGNAT -p tcp --dport 53 -j DNAT --to-destination "$DNS1"' "$B" >/dev/null
grep -F 'redirect udp+tcp/53' "$B" >/dev/null
printf '%s\n' 'PASS: custom DNS branch redirects UDP and TCP port 53'
