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
  function state(){
    var nodes=typeof currentNodes==='function'?currentNodes():[];
    var selected=String(pget('vpn_node','')||'');
    return JSON.stringify({
      mode:String(pget('vpn_mode','direct')||'direct'),
      liveKnown:window.__pgVpnLiveKnown===true,
      liveOn:window.__pgVpnLiveOn===true,
      node:selected,
      nodes:nodes.map(function(n,i){
        return {index:i,key:nodeKey(n),name:String(n._name||n.name||('节点 '+(i+1))),
          proto:String(n.proto||''),host:String(n.host||''),port:String(n.port||''),
          selected:nodeKey(n)===selected,enabled:n._on!==0,delay:n._delay===undefined?null:n._delay};
      })
    });
  }
  function setMode(mode){
    if(typeof applyVpnModeSelection!=='function')return false;
    Promise.resolve(applyVpnModeSelection(String(mode||''))).then(function(ok){
      window.__fxNativeVpnLastResult=ok===true;
      if(typeof vpnStatus==='function')vpnStatus();
      if(typeof window.__pgSyncVpnToggle==='function')window.__pgSyncVpnToggle();
    },function(){window.__fxNativeVpnLastResult=false;});
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
    var previous=String(pget('vpn_node','')||'');
    var key=nodeKey(n);
    pset('vpn_node',key);
    if(typeof renderNodes==='function')renderNodes();
    if(typeof vpnStatus==='function')vpnStatus();
    var mode=String(pget('vpn_mode','direct')||'direct');
    Promise.resolve(pgPersistNow()).then(function(saved){
      if(saved!==true)throw new Error('VPN_NODE_PERSIST_FAILED');
      return mode==='direct'?true:applyVpnModeSelection(mode);
    }).then(function(ok){
      window.__fxNativeVpnLastResult=ok===true;
      if(typeof renderNodes==='function')renderNodes();
      if(typeof vpnStatus==='function')vpnStatus();
    }).catch(function(){
      pset('vpn_node',previous);
      window.__fxNativeVpnLastResult=false;
      if(typeof renderNodes==='function')renderNodes();
      if(typeof vpnStatus==='function')vpnStatus();
    });
    return true;
  }
  window.FXNativeVpn={snapshot:state,setEnabled:setEnabled,setMode:setMode,selectNode:selectNode};
})();
</script>
"""
source = source.replace(anchor, api + "\n" + anchor, 1)
html.write_text(source, encoding="utf-8")
print("Installed explicit FXNativeVpn API.")
