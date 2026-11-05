#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
command -v node >/dev/null 2>&1 || { echo 'SKIP: node unavailable'; exit 0; }
node - "$HTML" <<'NODE'
'use strict';
const fs=require('fs'), vm=require('vm');
const html=fs.readFileSync(process.argv[2],'utf8');
const start=html.indexOf('function pgPersistNow(){');
const end=html.indexOf('/* ---------- 开关状态：conf → DOM ---------- */',start);
if(start<0||end<=start)throw new Error('pgPersistNow block missing');
const body=html.slice(start,end)+'\nthis.__persist=pgPersistNow;';
const PGB={mode:'bridge',loaded:true,ready:true,persistBusy:false,persistQueue:false,persistWaiters:[],model:{sw:{fx:'0'},lists:{fx:[]}},lastPersistText:''};
PGB.lastPersistText=JSON.stringify(PGB.model);
const writes=[];
const ctx={PGB,pgSerialize:m=>JSON.stringify(m),pgWriteConf:s=>new Promise(resolve=>writes.push({s,resolve})),pgLoad:()=>Promise.resolve(),pgApplySwitches:()=>{},pgRenderLists:()=>{},toast:()=>{},lt:s=>s,setTimeout,clearTimeout,Promise,Array,JSON,String};
vm.createContext(ctx); vm.runInContext(body,ctx,{timeout:2000});
const assert=(v,m)=>{if(!v)throw Error(m)};
(async()=>{
  PGB.model.sw.fx='1';
  const first=ctx.__persist();
  await Promise.resolve();
  assert(writes.length===1,'first config write did not start');
  PGB.model.lists.fx.push({v:'fxfile://anti_fraud_96110',on:true});
  const second=ctx.__persist();
  assert(PGB.persistBusy && PGB.persistQueue,'second request was not queued behind active write');
  writes[0].resolve(true);
  for(let i=0;i<30 && writes.length<2;i++)await new Promise(r=>setTimeout(r,0));
  assert(writes.length===2,'latest config was not flushed after first write');
  assert(writes[1].s.includes('anti_fraud_96110'),'queued write lost the FX rule source');
  writes[1].resolve(true);
  const result=await Promise.all([first,second]);
  assert(result.every(v=>v===true),'one of the concurrent callers was reported as failed');
  assert(PGB.persistBusy===false,'writer stayed busy after successful drain');
  assert(PGB.lastPersistText===JSON.stringify(PGB.model),'last persisted snapshot did not match newest model');
  console.log('PASS: concurrent config saves are serialized; FX switch and FX rules persist without false “not saved” rollback');
})().catch(e=>{console.error(e.stack||e);process.exitCode=1});
NODE
