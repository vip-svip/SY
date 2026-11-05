#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"; CONF="$ROOT/scripts/default.conf"; APPLY="$ROOT/scripts/apply.sh"
for key in ad_filter_master dns_block hosts_block mitm_block ip_block waf_block; do
  if grep -Fq "data-key=\"$key\"" "$HTML"; then echo "FAIL: retired category switch remains: $key" >&2; exit 1; fi
done
if grep -Fq 'id="modStatusCard"' "$HTML" || grep -Fq 'id="btnApply"' "$HTML" || grep -Fq 'id="btnReload"' "$HTML"; then echo 'FAIL: module status/apply/reload remains in Ad UI' >&2; exit 1; fi
grep -Fq "if(en.closest('#blockList')&&typeof pgUpdateAdRuleOverview==='function')pgUpdateAdRuleOverview();" "$HTML"
grep -Fq "if(typeof pgQueueAutoApply==='function')pgQueueAutoApply('规则已更改，正在自动应用…',true);" "$HTML"
grep -Fq 'pg_list_enabled block 2>/dev/null | awk' "$APPLY"
grep -Fq 'hosts-config.cksum' "$APPLY"
grep -Fq 'effective hosts input fingerprint changed or unavailable' "$APPLY"
grep -Fq 'pg_hosts_input_signature' "$APPLY"
for key in ad_filter_master dns_block hosts_block mitm_block ip_block waf_block; do
  if grep -Eq "^${key}=" "$CONF"; then echo "FAIL: fresh defaults retain retired key $key" >&2; exit 1; fi
done
sh -n "$APPLY"; sh -n "$ROOT/scripts/util.sh"
echo 'Per-rule toggles / auto apply / backend parsing regression: PASS'
