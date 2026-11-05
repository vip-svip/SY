#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
H="$ROOT/webroot/index.html"
# Static guards for the fix that previously returned success before settings.conf was written.
grep -Fq "return pgPersistNow().then(function(saved)" "$H"
grep -Fq "if(saved!==true)throw new Error('配置未能写入 settings.conf" "$H"
grep -Fq "vSafeSubUrl(s.url)" "$H"
grep -Fq 'id="vpnSubFeedback"' "$H"
grep -Fq 'fx-subscription-import-ui-fix-v1' "$H"
grep -Fq 'importFromText(s.url,body).then(function(ok)' "$H"
if command -v node >/dev/null 2>&1; then
  node - "$H" <<'NODE'
const fs=require('fs'),vm=require('vm'),assert=require('assert');
const html=fs.readFileSync(process.argv[2],'utf8');
const start=html.indexOf('function vpnSubWaitForPersistIdle(tries){');
const end=html.indexOf('/* v1.10.5：导出导入链路',start);
assert(start>=0 && end>start,'could not locate import function');
const src=html.slice(start,end);
const state={nodes:[],subs:[],renderCount:0,feedback:{state:'',message:''},mode:'fail',injectBusy:false,subsAtPersist:[]};
const VPN={persistTimer:null,model:{lists:{vpn_sub:[],vpn_node:[]},sw:{}}};
const ctx={VPN,Promise,String,Array,Object,RegExp,Error,clearTimeout,setTimeout,
  pgStripBom:x=>String(x||'').replace(/^\uFEFF/,''),b64d:()=>null,
  parseSub:()=>[{proto:'vless',host:'edge.example',port:443,_name:'Tokyo',name:'Tokyo'}],
  parseUri:()=>null,nodeKey:n=>n.proto+':'+n.host+':'+n.port,hostOf:()=> 'sub.example',
  vSetSubFeedback:(st,msg)=>state.feedback={state:st,message:msg},vToast:()=>{},vLt:x=>x,
  pgWaitForPersistIdle:()=>{if(state.injectBusy){state.injectBusy=false;VPN.persistBusy=true;setTimeout(()=>{VPN.persistBusy=false},10)}return Promise.resolve(true)},
  subsLoad:()=>state.subs.map(x=>({...x})),
  subsSave:a=>{state.subs=a.map(x=>({...x}));VPN.model.lists.vpn_sub=state.subs},
  currentNodes:()=>state.nodes.slice(),
  saveNodes:a=>{state.nodes=a.slice();VPN.model.lists.vpn_node=state.nodes},
  pgPersistNow:()=>{
    state.subsAtPersist.push(state.subs.length);
    if(state.mode==='fail'){state.subs=[];state.nodes=[];VPN.model.lists.vpn_sub=[];VPN.model.lists.vpn_node=[];return Promise.resolve(false)}
    return Promise.resolve(true)
  },renderSubs:()=>state.renderCount++,renderNodes:()=>state.renderCount++,vpnStatus:()=>{},
};
vm.runInNewContext(src+'\nthis.__importFromText=importFromText;',ctx);
(async()=>{
  const failed=await ctx.__importFromText('https://sub.example/link?token=redacted','valid-test-body');
  assert.strictEqual(failed,false,'failed commit must not report success');
  assert.strictEqual(state.renderCount,0,'failed commit must not render success state');
  assert.strictEqual(state.feedback.state,'error','failed commit should show error feedback');
  assert.strictEqual(state.subs.length,0,'failed config commit must not publish a subscription row');
  assert.strictEqual(state.subsAtPersist[0],0,'subscription metadata must not be saved before config commit');
  state.mode='ok';
  state.injectBusy=true;
  const ok=await ctx.__importFromText('https://sub.example/link?token=redacted','valid-test-body');
  assert.strictEqual(ok,true,'confirmed commit should report success');
  assert.strictEqual(state.nodes.length,1,'node should be stored on successful commit');
  assert.strictEqual(state.subs.length,1,'subscription should be stored on successful commit');
  assert.strictEqual(state.subsAtPersist[1],0,'subscription metadata is committed only after the node config');
  assert.strictEqual(state.feedback.state,'success','successful commit should show success feedback');
  console.log('FX subscription import persistence transaction regression: PASS');
})().catch(e=>{console.error(e);process.exit(1)});
NODE
fi
echo 'FX subscription transaction static guards: PASS'
