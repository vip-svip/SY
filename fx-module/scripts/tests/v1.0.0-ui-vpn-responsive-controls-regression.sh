#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
node - "$HTML" <<'NODE'
const fs = require('fs');
const html = fs.readFileSync(process.argv[2], 'utf8');
const fail = (m) => { throw new Error(m); };
const status = html.match(/<div class="card" id="vpnStatusCard"[\s\S]*?<\/div>\s*<div class="card"><div class="cardhead"><span class="ct">代理模式<\/span>[\s\S]*?<\/div>\s*<div class="card" id="vpnSubCard"/);
if (!status) fail('VPN status and mode cards are malformed or misplaced');
const statusHtml = status[0];
const header = statusHtml.match(/<div class="cardhead"><span class="ct">VPN 状态<\/span>([\s\S]*?)<\/div>/);
if (!header) fail('VPN status header missing');
if (/id="vpnApplyNow"/.test(header[1])) fail('Apply action still crowds the VPN status header');
const modeCard = html.match(/<div class="card"><div class="cardhead"><span class="ct">代理模式<\/span>[\s\S]*?<\/div>\s*<div class="card" id="vpnSubCard"/);
if (!modeCard) fail('proxy-mode card missing or malformed');
if (/vpnApplyNow|vpn-apply-row|应用当前模式/.test(modeCard[0])) fail('separate Apply row/button should be absent; mode changes apply automatically');
if (!/function applyVpnModeSelection\(mode\)/.test(html)) fail('mode auto-apply handler missing');
if (!/if\(mode!==\'direct\'&&!selectedNodeReady\)/.test(html)) fail('proxy mode does not validate the selected node against enabled nodes');
if (!/if\(typeof applyRun===\'function\'\)return Promise\.resolve\(\)\.then\(function\(\)\{return applyRun\(mode===\'direct\'\?\'fast\':null,\{label:label\}\)\}\)/.test(html)) fail('mode selection must force the no-subscription fast path for Direct mode');
if (!/if\(saved!==true\)throw new Error\(\'PG_CONFIG_PERSIST_FAILED\'\)/.test(html)) fail('mode apply does not gate execution on confirmed config persistence');
const mhStart=html.indexOf('function applyVpnModeSelection(mode){'), mhEnd=html.indexOf('\n(function(){',mhStart);
if (/\bpgSave\(\)\s*;/.test(html.slice(mhStart,mhEnd))) fail('mode selection must not fire-and-forget a second config save');
if (/id="vpnApplyNow"|vpn-apply-row/.test(html)) fail('obsolete Apply UI remnants found');
if (/class="vpn-external-row"/.test(html) || /class="vpn-external-actions"/.test(html) || /外部 VPN 共存诊断/.test(html)) fail('external VPN coexistence diagnosis UI should be hidden; coexistence is automatic by default');
if (!/#vpnStatusCard \.headtools\{flex:1 0 100%;width:100%;display:grid;grid-template-columns:minmax\(118px,1\.2fr\) repeat\(2,minmax\(0,1fr\)\)/.test(html)) fail('mobile VPN control grid missing');
if (!/#vpnStatusCard>\.confov\{grid-template-columns:repeat\(2,minmax\(0,1fr\)\)!important\}/.test(html)) fail('narrow-screen status grid does not collapse to two columns');
const head = html.match(/<head\b[^>]*>([\s\S]*?)<\/head>/i), body=html.match(/<body\b[^>]*>([\s\S]*?)<\/body>/i);
if (!head || !body || /<style\b/i.test(body[1])) fail('style metadata leaked into body');
const scripts=[...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi)];
for (let i=0;i<scripts.length;i++) {
  if (/\bsrc\s*=/.test(scripts[i][1])) continue;
  try { new Function(scripts[i][2]); } catch (e) { fail(`inline script ${i+1} syntax: ${e.message}`); }
}
console.log(`VPN responsive UI regression: PASS (${scripts.length} inline scripts parse)`);
NODE
