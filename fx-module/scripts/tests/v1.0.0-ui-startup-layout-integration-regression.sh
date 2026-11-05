#!/system/bin/sh
# FX 1.0.0 UI structure regression: styles must be metadata, not rendered body text.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$HTML" ] || fail 'webroot/index.html missing'
node - "$HTML" <<'NODE'
const fs=require('fs');
const html=fs.readFileSync(process.argv[2],'utf8');
const head=html.match(/<head\b[^>]*>([\s\S]*?)<\/head\s*>/i);
const body=html.match(/<body\b[^>]*>([\s\S]*?)<\/body\s*>/i);
if(!head||!body) throw new Error('document head/body missing');
if(!/<style\b/i.test(head[1])) throw new Error('CSS is not in document head');
if(/<style\b/i.test(body[1])) throw new Error('style blocks are still in body');
if(/\/\*\s*FX v1\.0\.0 UI polish/i.test(body[1])) throw new Error('CSS comment leaked into rendered body text');
if(!/id="pgBootFailure"/.test(html)||! /id="pgBootRetry"/.test(html)) throw new Error('actionable boot error/retry UI missing');
if(!/PGB\.bootPhase='读取配置'/.test(html)||! /初始化失败：/.test(html)) throw new Error('boot failure stage diagnostics missing');
if(!/html\.pg-full\.pg-keyboard-open \.navbar,html\.pg-keyboard-open \.navbar\{pointer-events:auto;transform:none\}/.test(html)) throw new Error('keyboard rule still disables navbar');
const scripts=[...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi)];
const errors=[];
for(let i=0;i<scripts.length;i++){
  if(/\bsrc\s*=/.test(scripts[i][1])) continue;
  try{new Function(scripts[i][2]);}catch(e){errors.push(`script ${i+1}: ${e.message}`)}
}
if(errors.length) throw new Error(errors.join('\n'));
console.log(`UI document structure and ${scripts.length} inline-script syntax: PASS`);
NODE
echo 'FX UI startup/layout integration regression: PASS'
