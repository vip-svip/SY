#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
# Counts are enabled rule entries and English category terms must be token-bounded.
grep -Fq 'Count enabled rule entries, not matches or blocked requests.' "$HTML"
grep -Fq '(^|[^a-z0-9])(ad|ads|advert|advertising|mobads|doubleclick|adservice|adsystem)([^a-z0-9]|$)' "$HTML"
grep -Fq '(^|[^a-z0-9])(track|tracking|analytics|telemetry|adlog|measurement)([^a-z0-9]|$)' "$HTML"
grep -Fq '分类可重叠，不代表已拦截请求数或完整覆盖率' "$HTML"
grep -Fq '广告 / 推广条目' "$HTML"
node - "$HTML" <<'NODE'
const fs=require('fs');
const s=fs.readFileSync(process.argv[2],'utf8');
const blocks=[...s.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map(x=>x[1]).filter(x=>x.trim());
for(const b of blocks)new Function(b);
const ad=/(^|[^a-z0-9])(ad|ads|advert|advertising|mobads|doubleclick|adservice|adsystem)([^a-z0-9]|$)/;
if(ad.test('address.example'))throw Error('false positive: address');
if(!ad.test('ads.example'))throw Error('missed ads domain');
console.log('inline JS parse + category boundary cases: PASS ('+blocks.length+' blocks)');
NODE
echo 'Ad rule overview boundary regression: PASS'
