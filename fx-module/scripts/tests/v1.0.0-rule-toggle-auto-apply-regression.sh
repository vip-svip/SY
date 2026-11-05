#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"; APPLY="$ROOT/scripts/apply.sh"; UTIL="$ROOT/scripts/util.sh"
# User-facing toggles are rows, not additional category gates.
for key in ad_filter_master dns_block hosts_block mitm_block ip_block waf_block; do
  if grep -Fq "data-key=\"$key\"" "$HTML"; then echo "FAIL: deleted category control $key remains" >&2; exit 1; fi
done
grep -Fq 'placeholder="订阅 URL / 域名 / IP-CIDR / MITM 主机规则；每条独立启停"' "$HTML"
grep -Fq 'placeholder="域名 / IP / CIDR；每条规则单独启停"' "$HTML"
grep -Fq 'function pgQueueAutoApply(label,forceFull)' "$HTML"
grep -Fq 'function pgDrainAutoApply()' "$HTML"
grep -Fq "closest('#blockList')" "$HTML"
grep -Fq '规则已更改，正在自动应用' "$HTML"
grep -Fq 'pg_list_enabled block 2>/dev/null | awk' "$APPLY"
grep -Fq 'pg_list_enabled rule' "$APPLY"
# Simulate queueing, coalescing and retry after an in-flight apply. The actual functions
# are evaluated from the shipped UI source with deterministic timer/apply stubs.
node - "$HTML" <<'NODE'
const fs=require('fs'),vm=require('vm');
const s=fs.readFileSync(process.argv[2],'utf8');
const a=s.indexOf("PGB.applyCmd='fast'"); const b=s.indexOf('function pgApplyProgress(',a);
if(a<0||b<0)throw Error('auto-apply source segment missing');
let next=1; const timers=new Map(), calls=[], notices=[];
const ctx={PGB:{ready:true,rendering:false,applyBusy:false},lt:x=>x,toast:x=>notices.push(x),applyRun:(sub,opts)=>calls.push({sub,opts}),setTimeout:(fn,ms)=>{const id=next++;timers.set(id,{fn,ms});return id},clearTimeout:id=>timers.delete(id)};
vm.createContext(ctx); vm.runInContext(s.slice(a,b),ctx);
ctx.pgQueueAutoApply('first change',false); ctx.pgQueueAutoApply('IP rule change',true);
if(timers.size!==1)throw Error('burst of changes should collapse into one timer');
let item=[...timers.entries()][0]; timers.delete(item[0]); item[1].fn();
if(calls.length!==1||!calls[0].opts.forceFull)throw Error('coalesced change did not run a full apply exactly once');
ctx.PGB.applyBusy=true; ctx.pgQueueAutoApply('change while busy',true);
if(timers.size!==0)throw Error('must not launch competing apply while busy');
ctx.PGB.applyBusy=false; ctx.pgDrainAutoApply();
if(timers.size!==1)throw Error('queued change was not drained after current apply');
item=[...timers.entries()][0];timers.delete(item[0]);item[1].fn();
if(calls.length!==2||calls[1].opts.label!=='change while busy'||!calls[1].opts.forceFull)throw Error('queued change did not reapply after busy task');
console.log('auto apply coalescing / full apply / busy-drain simulation: PASS');
NODE
sh -n "$APPLY"; sh -n "$UTIL"
echo 'per-rule auto-apply regression: PASS'
