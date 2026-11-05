#!/bin/sh
# Verify the bottom tab bar remains a persistent, non-shrinking app-shell row.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$HTML" ] || fail 'webroot/index.html missing'
grep -q 'id="fx-v1-bottom-nav-persistence"' "$HTML" || fail 'bottom-nav persistence CSS missing'
grep -q 'id="fx-v1-bottom-nav-persistence-js"' "$HTML" || fail 'bottom-nav lifecycle recovery missing'
grep -q "if(!nav.isConnected||nav.parentNode!==liveScreen)liveScreen.appendChild(nav)" "$HTML" || fail 'detached navbar recovery missing'
grep -q "\['pageshow','resize','orientationchange'\]" "$HTML" || fail 'viewport lifecycle recovery hooks missing'
grep -q 'flex:0 0 auto!important' "$HTML" || fail 'navbar may shrink out of view'
node - "$HTML" <<'NODE'
const fs=require('fs'),html=fs.readFileSync(process.argv[2],'utf8');
const scripts=[...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi)];
for(let i=0;i<scripts.length;i++){if(/\bsrc\s*=/.test(scripts[i][1]))continue;try{new Function(scripts[i][2])}catch(e){throw new Error('inline script '+(i+1)+': '+e.message)}}
const nav=html.match(/<div class="navbar">([\s\S]*?)<\/div>/);
if(!nav||((nav[1].match(/class="nav-item/g)||[]).length)!==5)throw new Error('expected five bottom navigation tabs');
console.log('Bottom-nav structure and inline JS syntax: PASS');
NODE
echo 'FX bottom-nav persistence regression: PASS'
