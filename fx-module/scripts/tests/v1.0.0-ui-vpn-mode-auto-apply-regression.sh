#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
node - "$ROOT/webroot/index.html" <<'NODE'
const fs = require('fs');
const vm = require('vm');
const html = fs.readFileSync(process.argv[2], 'utf8');
if (!html.includes("mode==='tun'?vLt('TUN 模式','TUN mode')")) {
  throw new Error('TUN mode must have its own label; it must not be presented as Global mode');
}
if (!html.includes("manager:lt('演示/离线模式','Demo/offline'),root:false")) {
  throw new Error('offline/demo UI must never claim root access');
}
const start = html.indexOf('function applyVpnModeSelection(mode){');
const end = html.indexOf('\n(function(){', start);
if (start < 0 || end < 0) throw new Error('auto-apply helper not found');
const source = html.slice(start, end) + '\nglobalThis.__applyMode = applyVpnModeSelection;';
function make(overrides={}) {
  const state = {mode:'direct', node:'', compat:'0', busy:false, external:false,
    toasts:[], apply:[], saved:0, rendered:0, status:0, ...overrides};
  const ctx = {
    window:{PGB:{get applyBusy(){return state.busy}}, __pgExternalVpnDetected:state.external},
    PGB:{get applyBusy(){return state.busy}},
    pget(k,d){return ({vpn_mode:state.mode,vpn_node:state.node,vpn_external_compat:state.compat})[k] ?? d;},
    pset(k,v){if(k==='vpn_mode')state.mode=v; if(k==='vpn_external_compat')state.compat=v;},
    pgSave(){state.saved++}, renderMode(){state.rendered++}, vpnStatus(){state.status++},
    vToast(x){state.toasts.push(String(x))}, vLt(a,b){return a},
    applyRun(sub,opts){state.apply.push({sub,opts});return Promise.resolve(state.applyResult===undefined?true:state.applyResult)},
    pgPersistNow(){return Promise.resolve(true)}, pgExec(){return Promise.resolve({out:'EXIT:0'})},
    currentNodes(){return state.node ? [{proto:state.node.split(':')[0],host:state.node.split(':')[1],port:Number(state.node.split(':')[2])}] : []},
    nodeKey(n){return n.proto+':'+n.host+':'+n.port},
    VPN:{mode:'bridge'}, MODP:'/module', Promise
  };
  vm.runInNewContext(source, ctx);
  return {state, run:ctx.__applyMode};
}
(async()=>{
  {
    const {state,run}=make(); const out=await run('global');
    if(out!==true || state.mode!=='global' || state.apply.length || state.saved!==0 || state.toasts.length)
      throw new Error('global preference without a node must persist quietly without starting interception');
  }
  {
    const {state,run}=make(); const out=await run('rule');
    if(out!==true || state.mode!=='rule' || state.apply.length || state.toasts.length)
      throw new Error('rule preference without a node must remain selectable and persist quietly');
  }
  {
    const {state,run}=make(); const out=await run('tun');
    if(out!==false || state.mode!=='direct' || state.apply.length || !state.toasts.some(x=>x.includes('TUN 模式需要先导入并选择可用节点')))
      throw new Error('TUN without a selected node must be rejected instead of persisted as a fake active mode');
  }
  {
    const {state,run}=make(); const out=await run('direct');
    if(out!==true || state.mode!=='direct' || state.apply.length!==1 || state.saved!==0)
      throw new Error('direct mode must apply without a node or a duplicate fire-and-forget save');
  }
  {
    const {state,run}=make({node:'vless:example:443'}); const out=await run('rule');
    if(out!==true || state.mode!=='rule' || state.apply.length!==1 || state.saved!==0)
      throw new Error('rule mode did not use the single guarded persistence/apply pipeline');
  }
  {
    const {state,run}=make({node:'vless:example:443',external:true,compat:'0'}); const out=await run('global');
    if(out!==false || state.mode!=='direct' || state.apply.length)
      throw new Error('external VPN without compatibility guard should not start interception');
  }
  {
    const {state,run}=make({node:'vless:example:443',busy:true}); const out=await run('rule');
    if(out!==false || state.mode!=='direct' || state.apply.length)
      throw new Error('mode changed while another apply task was running');
  }
  {
    const {state,run}=make({node:'vless:example:443',applyResult:false}); const out=await run('rule');
    if(out!==false || state.rendered<2 || state.status<2)
      throw new Error('failed apply did not refresh visible mode/status state');
  }
  console.log('FX VPN mode auto-apply runtime regression: PASS (8 scenarios)');
})().catch(e=>{console.error(e.stack||e);process.exit(1)});
NODE
