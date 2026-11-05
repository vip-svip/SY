#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
grep -Fq 'id="cardRules"' "$HTML"
grep -Fq 'id="adRuleOverview"' "$HTML"
grep -Fq "if(en.closest('#blockList')&&typeof pgUpdateAdRuleOverview==='function')pgUpdateAdRuleOverview();" "$HTML"
grep -Fq "if(listId==='blockList'&&typeof pgUpdateAdRuleOverview==='function')pgUpdateAdRuleOverview();" "$HTML"
grep -Fq "if(touched.blockList&&typeof pgUpdateAdRuleOverview==='function')pgUpdateAdRuleOverview();" "$HTML"
grep -Fq "if(scope==='blockList'&&typeof pgUpdateAdRuleOverview==='function')pgUpdateAdRuleOverview();" "$HTML"
if grep -Fq 'pgUpdateBlockMasterHint' "$HTML"; then echo 'FAIL: retired blacklist master hint remains' >&2; exit 1; fi
node -e "const fs=require('fs');const s=fs.readFileSync(process.argv[1],'utf8');const blocks=[...s.matchAll(/<script[^>]*>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).filter(x=>x.trim());for(const b of blocks)new Function(b);console.log('inline JS parse: PASS ('+blocks.length+' blocks)')" "$HTML"
echo 'Ad ↔ Rules live per-row overview sync regression: PASS'
