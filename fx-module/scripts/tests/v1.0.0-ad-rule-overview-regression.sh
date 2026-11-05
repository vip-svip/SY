#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
grep -Fq 'id="adRuleOverview"' "$HTML"
grep -Fq 'function pgUpdateAdRuleOverview()' "$HTML"
grep -Fq 'Array.isArray(lists.block)?lists.block:[]' "$HTML"
grep -Fq 'r&&r.on===true' "$HTML"
grep -Fq '分类可重叠，不代表已拦截请求数或完整覆盖率' "$HTML"
grep -Fq 'DNS/Hosts 不能去除已嵌入图片或视频中的水印' "$HTML"
grep -Fq "if(typeof pgUpdateAdRuleOverview==='function')pgUpdateAdRuleOverview();" "$HTML"
if grep -Fq 'pgUpdateBlockMasterHint' "$HTML"; then echo 'FAIL: retired master hint remains' >&2; exit 1; fi
node - "$HTML" <<'NODE'
const fs=require('fs'); const s=fs.readFileSync(process.argv[2],'utf8');
const page=s.indexOf('<div class="page" id="pageHosts">'), overview=s.indexOf('<div class="card" id="adRuleOverview"'), first=s.indexOf('<div class="card" id="cardRules"');
if(page<0||overview<0||first<0||!(page<overview&&overview<first))throw Error('overview not at Rules-page top');
const blocks=[...s.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map(x=>x[1]).filter(x=>x.trim());for(const b of blocks)new Function(b);
console.log('inline JS parse + rules-page-top placement: PASS ('+blocks.length+' blocks)');
NODE
echo 'Ad rule overview regression: PASS'
