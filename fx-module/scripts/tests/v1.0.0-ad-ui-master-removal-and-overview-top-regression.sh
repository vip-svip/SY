#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
if grep -Eq 'id="adProtectionMasterRow"|data-key="ad_protection_master"|data-key="ad_filter_master"|data-key="dns_block"|data-key="hosts_block"|data-key="mitm_block"|data-key="ip_block"|data-key="waf_block"|id="modStatusCard"|id="btnApply"|id="btnReload"' "$HTML"; then
  echo 'FAIL: retired Ad category/master/status controls remain' >&2; exit 1
fi
! grep -Fq 'data-key="dns_engine_adguardhome"' "$HTML"
grep -Fq '本地递归 DNS（自动安全启用）' "$HTML"
grep -Fq 'data-key="hook_block"' "$HTML"
grep -Fq 'id="btnLogs"' "$HTML"
grep -Fq 'id="btnCrash"' "$HTML"
node - "$HTML" <<'NODE'
const s=require('fs').readFileSync(process.argv[2],'utf8');
const page=s.indexOf('<div class="page" id="pageHosts">');
const overview=s.indexOf('<div class="card" id="adRuleOverview"');
const rules=s.indexOf('<div class="card" id="cardRules"');
if(page<0||overview<0||rules<0||!(page<overview&&overview<rules))throw Error('coverage overview must lead the Rules page');
if((s.match(/id="adRuleOverview"/g)||[]).length!==1)throw Error('duplicate coverage overview');
if(s.indexOf('function pgQueueAutoApply(')<0||s.indexOf('function pgDrainAutoApply(')<0)throw Error('auto-apply queue missing');
if(!s.includes("if(typeof pgQueueAutoApply==='function')pgQueueAutoApply('规则已更改，正在自动应用…',true)"))throw Error('per-rule toggle does not auto apply');
const more=s.indexOf('<div class="page" id="pageMore">');
const logs=s.indexOf('id="btnLogs"'); const crash=s.indexOf('id="btnCrash"');
if(more<0||logs<more||crash<more)throw Error('diagnostics should live under Settings, not Ad controls');
const blocks=[...s.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map(x=>x[1]).filter(x=>x.trim());
for(const b of blocks)new Function(b);
console.log('retired controls + auto apply + overview + JS parse: PASS ('+blocks.length+' inline blocks)');
NODE
sh -n "$ROOT/scripts/apply.sh"
echo 'Ad UI rule-toggle auto-apply / overview regression: PASS'
