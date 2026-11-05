#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"; APPLY="$ROOT/scripts/apply.sh"; STATUS="$ROOT/scripts/status.sh"; CONF="$ROOT/scripts/default.conf"
for key in ad_filter_master dns_block hosts_block mitm_block ip_block waf_block; do
  if grep -Fq "data-key=\"$key\"" "$HTML"; then echo "FAIL: retired category switch is visible: $key" >&2; exit 1; fi
done
! grep -Fq 'data-key="dns_engine_adguardhome"' "$HTML"
grep -Fq '本地递归 DNS（自动安全启用）' "$HTML"
grep -Fq 'data-key="hook_block"' "$HTML"
grep -Fq 'pg_list_enabled "$_asect"' "$APPLY"
grep -Fq 'pg_list_enabled block 2>/dev/null | awk' "$APPLY"
grep -Fq 'fw: individually enabled [list:block] IP/CIDR rules applied' "$APPLY"
grep -Fq 'if [ "$(pg_get dns_forward 1)" = "1" ] && [ -n "$DNS_SAFE" ]' "$APPLY"
if grep -Fq 'pg_get dns_block 0' "$APPLY"; then echo 'FAIL: removed DNS category gate remains' >&2; exit 1; fi
grep -Fq '_dns_hook=$(iptables $FWWAIT -t nat -S OUTPUT' "$STATUS"
grep -Fq 'DNS_FORWARD_STATUS="partial"' "$STATUS"
for key in ad_filter_master dns_block hosts_block mitm_block ip_block waf_block; do
  if grep -Eq "^${key}=" "$CONF"; then echo "FAIL: fresh config seeds retired switch $key" >&2; exit 1; fi
done
grep -Fq "PGB.model.sw[k]=sw.classList.contains('on')?'1':'0';" "$HTML"
grep -Fq 'pgQueueAutoApply' "$HTML"
sh -n "$APPLY"
echo 'PASS: per-rule block + DNS/Hosts/IP auto-selection contract'
