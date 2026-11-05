#!/system/bin/sh
# FX 1.0.0 UI regression: persistent bottom navigation, full-screen safe area and boot isolation.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$HTML" ] || fail 'webroot/index.html missing'
# Initial visual state and internal tab state must agree.
grep -Fq "var currentTab='vpn';" "$HTML" || fail 'initial currentTab is not vpn'
grep -Fq 'data-tab="vpn"' "$HTML" || fail 'VPN tab missing'
grep -Fq 'id="pageVpn"' "$HTML" || fail 'VPN page missing'
# Fixed flex layout allows the selected page to scroll without pushing the bottom bar away.
grep -Fq 'id="fx-v1-ui-shell-recovery"' "$HTML" || fail 'UI shell recovery stylesheet missing'
grep -Fq '#screen .page.on{display:block;flex:1 1 0%;height:0;min-height:0}' "$HTML" || fail 'page flex sizing regression'
grep -Fq '#screen .navbar{display:flex!important;visibility:visible!important' "$HTML" || fail 'navbar visibility safety missing'
grep -Fq 'pointer-events:auto!important' "$HTML" || fail 'navbar pointer-events recovery missing'
# Keyboard metrics must never shift the navbar below the clipped screen.
grep -Fq "root.style.setProperty('--pg-keyboard-shift','0px')" "$HTML" || fail 'keyboard nav shift is not pinned to zero'
grep -Fq "nav.setAttribute('aria-hidden','false')" "$HTML" || fail 'navbar should remain accessible during keyboard resize'
# Non-critical status/list errors should not take down all tabs during startup.
grep -Fq "return pgRenderLists().catch(function(e){" "$HTML" || fail 'list render failure is not isolated'
grep -Fq "return pgRefreshStatus().catch(function(e){" "$HTML" || fail 'status refresh failure is not isolated'
# Script syntax check (run by harness when node is available).
if command -v node >/dev/null 2>&1; then
  node - "$HTML" <<'NODE'
const fs=require('fs');
const file=process.argv[2], html=fs.readFileSync(file,'utf8');
const re=/<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi;
let m,n=0,bad=[];
while((m=re.exec(html))){n++;if(/\bsrc\s*=/.test(m[1]))continue;try{new Function(m[2]);}catch(e){bad.push('script '+n+': '+e.message)}}
if(bad.length){console.error(bad.join('\n'));process.exit(1)}
console.log('FX UI inline JavaScript syntax: '+n+' blocks PASS');
NODE
fi
echo 'FX UI shell/navigation recovery regression: PASS'
