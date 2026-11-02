#!/usr/bin/env python3
"""Expose explicit native VPN actions/state without synthesizing WebView button clicks."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
html = root / "webroot/index.html"
if not html.is_file():
    raise SystemExit("FX WebUI source is missing")
source = html.read_text(encoding="utf-8")
marker = '<script id="fx-native-vpn-api">'
if marker in source:
    print("Native VPN API already installed")
    raise SystemExit(0)
anchor = "</body>"
if source.count(anchor) != 1:
    raise SystemExit("Cannot uniquely locate WebUI body end for native VPN API")
api = r"""
<script id="fx-native-vpn-api">
/* A narrow, explicit API for the Android-native VPN controls.
   It calls the existing validated configuration/apply transaction; it never clicks
   hidden WebUI buttons or reads their visual state as a substitute for backend state. */
(function(){
  /* Bridge the authoritative status.sh JSON callback into native snapshots.
     vpn_on is true only when status.sh confirms the firewall hooks and listener. */
  window.__pgVpnRuntimeStatus=window.__pgVpnRuntimeStatus||null;
  window.__fxNativeVpnLastResult=null;
  window.__fxNativeVpnBusy=false;
  window.__fxNativeVpnLastError='';
  if(typeof window.pgFillStatus==='function'&&!window.__fxNativeVpnStatusWrapped){
    var originalFillStatus=window.pgFillStatus;
    window.pgFillStatus=function(status){
      if(status&&typeof status.vpn_on==='boolean'){
        window.__pgVpnRuntimeStatus=status;
        window.__pgVpnLiveKnown=true;
        window.__pgVpnLiveOn=status.vpn_on===true;
      }
      return originalFillStatus.apply(this,arguments);
    };
    window.__fxNativeVpnStatusWrapped=true;
  }
  function refreshRuntimeStatus(){
    if(typeof window.pgRefreshStatus==='function'){
      return Promise.resolve(window.pgRefreshStatus()).then(function(status){
        if(status&&typeof status.vpn_on==='boolean'){
          window.__pgVpnRuntimeStatus=status;
          window.__pgVpnLiveKnown=true;
          window.__pgVpnLiveOn=status.vpn_on===true;
        }
        return status;
      }).catch(function(){return null;});
    }
    return Promise.resolve(window.__pgVpnRuntimeStatus);
  }
  function state(){
    var nodes=typeof currentNodes==='function'?currentNodes():[];
    var selected=String(pget('vpn_node','')||'');
    var runtime=window.__pgVpnRuntimeStatus;
    return JSON.stringify({
      mode:String(pget('vpn_mode','direct')||'direct'),
      liveKnown:window.__pgVpnLiveKnown===true,
      liveOn:window.__pgVpnLiveOn===true,
      runtimeMode:runtime&&runtime.vpn_mode?String(runtime.vpn_mode):'',
      coreOn:runtime&&runtime.vpn_core===1,
      node:selected,
      busy:window.__fxNativeVpnBusy===true,
      lastResult:window.__fxNativeVpnLastResult,
      lastError:String(window.__fxNativeVpnLastError||''),
      nodes:nodes.map(function(n,i){
        return {index:i,key:nodeKey(n),name:String(n._name||n.name||('节点 '+(i+1))),
          proto:String(n.proto||''),host:String(n.host||''),port:String(n.port||''),
          selected:nodeKey(n)===selected,enabled:n._on!==0,delay:n._delay===undefined?null:n._delay};
      })
    });
  }
  function setMode(mode){
    mode=String(mode||'');
    if(['direct','global','rule','tun'].indexOf(mode)<0)return false;
    if(typeof applyVpnModeSelection!=='function'||window.__fxNativeVpnBusy)return false;
    window.__fxNativeVpnBusy=true;
    window.__fxNativeVpnLastError='';
    window.__fxNativeVpnLastResult=null;
    Promise.resolve().then(function(){return applyVpnModeSelection(mode);}).then(function(ok){
      window.__fxNativeVpnLastResult=ok===true;
      if(ok!==true)window.__fxNativeVpnLastError='VPN_APPLY_FAILED';
      if(typeof vpnStatus==='function')vpnStatus();
      if(typeof window.__pgSyncVpnToggle==='function')window.__pgSyncVpnToggle();
      return refreshRuntimeStatus();
    }).catch(function(error){
      window.__fxNativeVpnLastResult=false;
      window.__fxNativeVpnLastError=String(error&&error.message||error||'VPN_APPLY_FAILED');
      return refreshRuntimeStatus();
    }).then(function(){
      window.__fxNativeVpnBusy=false;
    });
    return true;
  }
  function setEnabled(enabled){
    var current=String(pget('vpn_mode','direct')||'direct');
    return setMode(enabled?(current==='direct'?'global':current):'direct');
  }
  function selectNode(index){
    var nodes=typeof currentNodes==='function'?currentNodes():[];
    index=Number(index);
    if(!Number.isInteger(index)||index<0||index>=nodes.length)return false;
    var n=nodes[index];
    if(!n||n._on===0)return false;
    if(window.__fxNativeVpnBusy)return false;
    var previous=String(pget('vpn_node','')||'');
    var key=nodeKey(n);
    window.__fxNativeVpnBusy=true;
    window.__fxNativeVpnLastError='';
    window.__fxNativeVpnLastResult=null;
    pset('vpn_node',key);
    if(typeof renderNodes==='function')renderNodes();
    if(typeof vpnStatus==='function')vpnStatus();
    var mode=String(pget('vpn_mode','direct')||'direct');
    Promise.resolve(pgPersistNow()).then(function(saved){
      if(saved!==true)throw new Error('VPN_NODE_PERSIST_FAILED');
      return mode==='direct'?true:applyVpnModeSelection(mode);
    }).then(function(ok){
      window.__fxNativeVpnLastResult=ok===true;
      if(ok!==true)throw new Error('VPN_NODE_APPLY_FAILED');
      window.__fxNativeVpnLastError='';
      if(typeof renderNodes==='function')renderNodes();
      if(typeof vpnStatus==='function')vpnStatus();
      return refreshRuntimeStatus();
    }).catch(function(error){
      pset('vpn_node',previous);
      window.__fxNativeVpnLastResult=false;
      window.__fxNativeVpnLastError=String(error&&error.message||error||'VPN_NODE_APPLY_FAILED');
      return Promise.resolve(pgPersistNow()).catch(function(){return false;}).then(function(){
        if(typeof renderNodes==='function')renderNodes();
        if(typeof vpnStatus==='function')vpnStatus();
        return refreshRuntimeStatus();
      });
    }).then(function(){window.__fxNativeVpnBusy=false;},function(){window.__fxNativeVpnBusy=false;});
    return true;
  }
  window.FXNativeVpn={snapshot:state,setEnabled:setEnabled,setMode:setMode,selectNode:selectNode};
  refreshRuntimeStatus();
})();
</script>
"""
source = source.replace(anchor, api + "\n" + anchor, 1)
html.write_text(source, encoding="utf-8")
print("Installed explicit FXNativeVpn API.")
