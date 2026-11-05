#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
H="$ROOT/webroot/index.html"
# Execute the actual mode-selection function with a no-node model and successful persistence.
if command -v node >/dev/null 2>&1; then
  node - "$H" <<'NODE'
const fs=require('fs'),vm=require('vm'),assert=require('assert');
const html=fs.readFileSync(process.argv[2],'utf8');
const start=html.indexOf('function applyVpnModeSelection(mode){');
const end=html.indexOf("\n(function(){\n  var seg=document.getElementById('vpnModeSeg')",start);
assert(start>=0 && end>start,'mode-selection function not found');
const src=html.slice(start,end);
const state={mode:'direct',node:'',saved:0,toasts:[]};
const ctx={window:{},PGB:{applyBusy:false},VPN:{mode:'demo'},
  pget:(k,d)=>k==='vpn_node'?state.node:(k==='vpn_mode'?state.mode:d),
  pset:(k,v)=>{if(k==='vpn_mode')state.mode=v},
  currentNodes:()=>[],nodeKey:n=>n.proto+':'+n.host+':'+n.port,
  renderMode:()=>{},vpnStatus:()=>{},pgPersistNow:()=>{state.saved++;return Promise.resolve(true)},
  vToast:m=>state.toasts.push(String(m)),vLt:(a,b)=>a,
  Promise,Error};
vm.runInNewContext(src+'; this.applyVpnModeSelection=applyVpnModeSelection;',ctx);
(async()=>{
  assert.strictEqual(await ctx.applyVpnModeSelection('global'),true);
  assert.strictEqual(state.mode,'global','Global mode must be selectable without a node');
  assert.strictEqual(state.toasts.length,0,'No-node state must not spam blocking-style warning toasts');
  assert.strictEqual(await ctx.applyVpnModeSelection('rule'),true);
  assert.strictEqual(state.mode,'rule','Rule mode must be selectable without a node');
  assert.strictEqual(state.toasts.length,0);
  assert.strictEqual(await ctx.applyVpnModeSelection('direct'),true);
  assert.strictEqual(state.mode,'direct','Direct mode must remain selectable without a node');
  state.node='vless:stale.example:443';
  assert.strictEqual(await ctx.applyVpnModeSelection('global'),true);
  assert.strictEqual(state.mode,'global','A stale saved node key must not block selecting Global mode');
  assert.strictEqual(state.saved,4,'each selected mode must be persisted');
  console.log('FX VPN mode switching without nodes regression: PASS');
})().catch(e=>{console.error(e);process.exit(1)});
NODE
else
  echo 'SKIP: node unavailable; static no-node mode-switch checks only'
  grep -Fq 'Mode selection is a user preference and must remain changeable without nodes.' "$H"
  ! sed -n '/function applyVpnModeSelection(mode){/,/代理总开关：/p' "$H" | grep -Fq 'no node is available, so proxy forwarding has not started'
fi
