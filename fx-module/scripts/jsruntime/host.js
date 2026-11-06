/* FX QuickJS-NG host prelude. Loaded with qjs -I before the user script. */
(function () {
  // Capture privileged host modules inside this closure, then hide them from the user script.
  const _fxSTD = std, _fxOS = os;
  const _fxEventPath = scriptArgs[1];
  const _fxStateDir = scriptArgs[2];
  const _fxHttp = scriptArgs[3];
  // A per-invocation result path prevents concurrent scripts from overwriting
  // one another. Older direct qjs callers retain the legacy shared-file fallback.
  const _fxResultPath = scriptArgs[4] || (_fxStateDir + '/last-result.json');
  if (!_fxEventPath || !_fxStateDir || !_fxHttp) throw new Error('invalid FX host arguments');

  function _fxRead(p, fallback='') {
    try { const f=_fxSTD.open(p,'r'); if(!f)return fallback; const s=f.readAsString(); f.close(); return s; }
    catch (_) { return fallback; }
  }
  function _fxWrite(p,s) {
    const tmp=p+'.tmp.'+_fxOS.getpid();
    const f=_fxSTD.open(tmp,'w'); if(!f) throw new Error('cannot write '+p);
    f.puts(String(s)); f.close();
    if(_fxOS.rename(tmp,p)!==0) { _fxOS.remove(tmp); throw new Error('cannot commit '+p); }
  }
  function _fxMkdir(p) { _fxOS.exec(['mkdir','-p',p]); _fxOS.exec(['chmod','700',p]); }
  _fxMkdir(_fxStateDir);
  const _fxEvent = (()=>{try{return JSON.parse(_fxRead(_fxEventPath,'{}'));}catch(_){return {};}})();
  const _fxPrefsPath = _fxStateDir + '/prefs.json';
  let _fxPrefs = (()=>{try{return JSON.parse(_fxRead(_fxPrefsPath,'{}'))||{};}catch(_){return {};}})();
  function _fxDirIsStale(path) {
    const owner=_fxRead(path+'/pid','').trim();
    if (/^[0-9]+$/.test(owner)) return _fxOS.exec(['kill','-0',owner])!==0;
    // Older FX builds created prefs.lock without an owner file. Recover only after
    // 60 seconds, avoiding a race with a process paused between mkdir and pid write.
    return _fxOS.exec(['sh','-c','[ -d "$1" ] && [ $(( $(date +%s) - $(stat -c %Y "$1" 2>/dev/null || echo 0) )) -ge 60 ]','sh',path])===0;
  }
  function _fxMoveAside(path) {
    const aside=path+'.stale.'+_fxOS.getpid()+'.'+Date.now();
    if (_fxOS.exec(['mv',path,aside])!==0) return false;
    _fxOS.exec(['rm','-rf',aside]);
    return true;
  }
  function _fxReapPrefsLock(lock) {
    const reap=lock+'.reap';
    if (_fxOS.exec(['mkdir',reap])!==0) {
      // A process killed while reaping must not permanently brick preferences.
      if (!_fxDirIsStale(reap) || !_fxMoveAside(reap)) return false;
      if (_fxOS.exec(['mkdir',reap])!==0) return false;
    }
    try {
      try { _fxWrite(reap+'/pid',String(_fxOS.getpid())); } catch (_) { return false; }
      if (!_fxDirIsStale(lock)) return false;
      return _fxMoveAside(lock);
    } finally {
      _fxOS.exec(['rm','-f',reap+'/pid']);
      _fxOS.exec(['rmdir',reap]);
    }
  }
  function _fxMutatePrefs(mutator) {
    const lock=_fxStateDir+'/prefs.lock'; let acquired=false;
    for(let i=0;i<100;i++){
      if(_fxOS.exec(['mkdir',lock])===0){
        acquired=true;
        try { _fxWrite(lock+'/pid',String(_fxOS.getpid())); }
        catch(e) { _fxOS.exec(['rmdir',lock]); throw e; }
        break;
      }
      if(i%10===9) _fxReapPrefsLock(lock);
      _fxOS.sleep(10);
    }
    if(!acquired) throw new Error('preferences lock timeout (live lock or storage unavailable)');
    try { try{_fxPrefs=JSON.parse(_fxRead(_fxPrefsPath,'{}'))||{};}catch(_){_fxPrefs={};} mutator(_fxPrefs); _fxWrite(_fxPrefsPath,JSON.stringify(_fxPrefs)); }
    finally { _fxOS.exec(['rm','-f',lock+'/pid']); _fxOS.exec(['rmdir',lock]); }
  }
  function _fxReloadPrefs(){try{const latest=JSON.parse(_fxRead(_fxPrefsPath,'{}'));if(latest&&typeof latest==='object'&&!Array.isArray(latest))_fxPrefs=latest;}catch(_){}return _fxPrefs;}
  globalThis.$prefs={
    valueForKey(k){const p=_fxReloadPrefs();return Object.prototype.hasOwnProperty.call(p,String(k))?p[String(k)]:null;},
    setValueForKey(v,k){_fxMutatePrefs(p=>{p[String(k)]=v;});return true;},
    removeValueForKey(k){_fxMutatePrefs(p=>{delete p[String(k)];});return true;},
    allValues(){return JSON.parse(JSON.stringify(_fxReloadPrefs()));}
  };

  let _fxDone=false, _fxDoneValue=null;
  function _fxSaveResult(ok,error) {
    const out={ok:!!ok,done:_fxDone,result:_fxDoneValue,request:globalThis.$request,response:globalThis.$response,prefs:globalThis.$prefs.allValues()};
    if(error) out.error=String(error);
    _fxWrite(_fxResultPath,JSON.stringify(out));
  }
  // Match common proxy-script semantics: the first $done wins. If no value is
  // supplied, return the mutable request/response object for the current hook.
  globalThis.$done=function(value){if(_fxDone)return;_fxDone=true;if(value!==undefined)_fxDoneValue=value;else if(_fxEvent.stage==='response')_fxDoneValue=globalThis.$response;else _fxDoneValue=globalThis.$request;_fxSaveResult(true,null);};

  function _fxRequest(options,cb) {
    if(typeof options==='string') options={url:options};
    options=options||{};
    const url=String(options.url||options.uri||'');
    const method=String(options.method||'GET').toUpperCase();
    if(!/^https?:\/\//i.test(url)) throw new Error('only http/https URLs are allowed');
    if(!/^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)$/.test(method)) throw new Error('unsupported HTTP method');
    const headers=options.headers||{}, headerLines=[];
    for(const k of Object.keys(headers)){
      const values=Array.isArray(headers[k])?headers[k]:[headers[k]];
      for(const rawValue of values){
        const v=String(rawValue);
        if(/[\r\n]/.test(k+v)||/^(host|content-length|transfer-encoding)$/i.test(k)) throw new Error('unsafe HTTP header: '+k);
        headerLines.push(k+': '+v);
      }
    }
    const tmp=_fxStateDir+'/http-'+_fxOS.getpid()+'-'+Date.now();
    _fxWrite(tmp+'.headers',headerLines.join('\n'));
    _fxWrite(tmp+'.body',options.body==null?'':(typeof options.body==='string'?options.body:JSON.stringify(options.body)));
    // The Go MITM stage has a 30-second aggregate deadline. Keep one HTTP call below
    // the per-script execution deadline so the bridge does not advertise a timeout
    // that the runner will kill first.
    const timeout=Math.max(1,Math.min(20,Number(options.timeout||globalThis.$httpClient.timeout||10)));
    const rc=_fxOS.exec([_fxHttp,url,method,tmp+'.body',tmp+'.response',tmp+'.headers',String(Math.floor(timeout))]);
    const statusText=_fxRead(tmp+'.headers.status','').trim();
    const rawHeaders=_fxRead(tmp+'.response.headers','');
    let responseHeaders={};
    for(const line of rawHeaders.split(/\r?\n/)){
      if(/^HTTP\//i.test(line)){responseHeaders={};continue;}
      const i=line.indexOf(':'); if(i>0){const k=line.slice(0,i).trim().toLowerCase(),v=line.slice(i+1).trim();responseHeaders[k]=responseHeaders[k]?responseHeaders[k]+', '+v:v;}
    }
    const body=_fxRead(tmp+'.response','');
    for(const p of [tmp+'.headers',tmp+'.headers.status',tmp+'.body',tmp+'.response',tmp+'.response.headers']) _fxOS.remove(p);
    const statusCode=Number(statusText||0);
    const result={status:statusCode,statusCode:statusCode,headers:responseHeaders,body:body,ok:rc===0&&statusCode>=200&&statusCode<400};
    result.statusText=statusCode===200?'OK':statusCode===204?'No Content':statusCode===301?'Moved Permanently':statusCode===302?'Found':statusCode===400?'Bad Request':statusCode===401?'Unauthorized':statusCode===403?'Forbidden':statusCode===404?'Not Found':statusCode===429?'Too Many Requests':statusCode>=500?'Server Error':'';
    if(rc!==0) result.error='HTTP bridge failed (exit '+rc+')';
    if(typeof cb==='function') cb(result.error?result.error:null,result,result.body);
    return result;
  }
  globalThis.$httpClient={};
  for(const m of ['get','post','put','patch','delete','head','options']) globalThis.$httpClient[m]=function(options,cb){if(typeof options==='string')options={url:options};options=Object.assign({},options||{},{method:m.toUpperCase()});return _fxRequest(options,cb);};
  // Promise is resolved after the synchronous native bridge finishes. This is
  // compatibility for promise-based scripts, not non-blocking network I/O.
  globalThis.$task={fetch(options){try{const r=_fxRequest(options);return Promise.resolve({statusCode:r.statusCode,status:r.status,headers:r.headers,body:r.body,ok:r.ok});}catch(e){return Promise.reject(e);}}};
  globalThis.$request=Object.assign({url:'',method:'GET',headers:{},body:''},_fxEvent.request||{});
  globalThis.$response=Object.assign({status:200,statusCode:200,headers:{},body:''},_fxEvent.response||{});
  if(_fxEvent.response&&_fxEvent.response.statusCode==null&&_fxEvent.response.status!=null) globalThis.$response.statusCode=Number(_fxEvent.response.status);
  globalThis.$environment=Object.assign({system:'android',version:'1.0.0',app:'FX QuickJS-NG',device:'Android',language:'zh-CN',"stash-version":"FX-1.0.0"},_fxEvent.environment||{});
  globalThis.$script=Object.assign({name:'FX Script',startTime:Date.now(),type:_fxEvent.stage||'manual'},_fxEvent.script||{});
  globalThis.$argument=String(_fxEvent.argument||'');
  globalThis.$input=String(_fxEvent.input||'');
  // Shared persistent storage aliases used by Surge/QuanX/Loon/Stash scripts.
  globalThis.$persistentStore={
    read(k){const v=globalThis.$prefs.valueForKey(String(k));return v==null?null:(typeof v==='string'?v:JSON.stringify(v));},
    write(v,k){try{return globalThis.$prefs.setValueForKey(v,String(k));}catch(_){return false;}},
    remove(k){try{return globalThis.$prefs.removeValueForKey(String(k));}catch(_){return false;}}
  };
  globalThis.$prefs.setValueForKey=function(v,k){try{_fxMutatePrefs(p=>{p[String(k)]=v;});return true;}catch(_){return false;}};
  globalThis.$prefs.removeValueForKey=function(k){try{_fxMutatePrefs(p=>{delete p[String(k)];});return true;}catch(_){return false;}};
  function _fxNotify(title,subtitle,body,options){
    const item={time:new Date().toISOString(),title:String(title||''),subtitle:String(subtitle||''),body:String(body||''),options:options||{}};
    const p=_fxStateDir+'/notifications.jsonl';
    try{const f=_fxSTD.open(p,'a');if(!f)return false;f.puts(JSON.stringify(item)+'\n');f.close();return true;}catch(_){return false;}
  }
  globalThis.$notify=function(title,subtitle,body,options){return _fxNotify(title,subtitle,body,options);};
  globalThis.$notification={post(title,subtitle,body,options){return _fxNotify(title,subtitle,body,options);}};
  // Script logs are persisted for WebUI diagnostics instead of being silently discarded.
  function _fxLog(level,args){
    const values=[];
    for(let i=0;i<args.length;i++){const v=args[i];try{values.push(typeof v==='string'?v:JSON.stringify(v));}catch(_){values.push(String(v));}}
    const line=JSON.stringify({time:new Date().toISOString(),level:String(level),message:values.join(' ')});
    try{const f=_fxSTD.open(_fxStateDir+'/script-logs.jsonl','a');if(f){f.puts(line+'\n');f.close();}}catch(_){}
  }
  globalThis.console={log:function(){_fxLog('info',arguments);},info:function(){_fxLog('info',arguments);},warn:function(){_fxLog('warn',arguments);},error:function(){_fxLog('error',arguments);},debug:function(){_fxLog('debug',arguments);}};
  // Select a compatibility profile explicitly per event. Do not advertise every
  // vendor version at once: scripts commonly branch on these fields, and false
  // vendor detection can select APIs that FX does not actually implement.
  const _fxCompat=String(_fxEvent.compatPlatform||_fxEvent.platform||'fx').toLowerCase();
  const _fxIsSurge=(_fxCompat==='surge');
  const _fxIsLoon=(_fxCompat==='loon');
  const _fxIsStash=(_fxCompat==='stash');
  const _fxIsRocket=(_fxCompat==='shadowrocket'||_fxCompat==='rocket');
  const _fxIsQuanX=(_fxCompat==='quantumult-x'||_fxCompat==='quantumultx'||_fxCompat==='quanx');
  globalThis.$loon={env:{version:_fxIsLoon?'FX-compat-1.0.0':'',build:'FX'},notify:(t,s,b)=>_fxNotify(t,s,b),log:(...a)=>console.log(...a),isLoon:_fxIsLoon};
  globalThis.$surge={version:_fxIsSurge?'FX-compat-1.0.0':'',isQuanX:_fxIsQuanX,isSurge:_fxIsSurge,notify:(t,s,b)=>_fxNotify(t,s,b)};
  globalThis.$stash={version:_fxIsStash?'FX-compat-1.0.0':'',isStash:_fxIsStash,notify:(t,s,b)=>_fxNotify(t,s,b)};
  globalThis.$rocket={version:_fxIsRocket?'FX-compat-1.0.0':'',isShadowrocket:_fxIsRocket,notify:(t,s,b)=>_fxNotify(t,s,b)};
  // Common convenience globals found in proxy scripts.
  if(typeof globalThis.atob!=='function') globalThis.atob=function(input){const alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';let str=String(input).replace(/[^A-Za-z0-9+/=]/g,'');let out='',buffer=0,bits=0;for(let i=0;i<str.length;i++){const c=str.charAt(i);if(c==='=')break;const n=alphabet.indexOf(c);if(n<0)continue;buffer=(buffer<<6)|n;bits+=6;if(bits>=8){bits-=8;out+=String.fromCharCode((buffer>>bits)&255);}}return out;};
  if(typeof globalThis.btoa!=='function') globalThis.btoa=function(input){const alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';const str=String(input);let out='';for(let i=0;i<str.length;i+=3){const a=str.charCodeAt(i)&255,b=i+1<str.length?str.charCodeAt(i+1)&255:0,c=i+2<str.length?str.charCodeAt(i+2)&255:0;out+=alphabet[a>>2]+alphabet[((a&3)<<4)|(b>>4)]+(i+1<str.length?alphabet[((b&15)<<2)|(c>>6)]:'=')+(i+2<str.length?alphabet[c&63]:'=');}return out;};
  globalThis.$httpClient.timeout=10;
  // Small, deterministic compatibility utilities used by common Surge/Loon/Stash scripts.
  globalThis.$utils={
    base64Encode(v){return globalThis.btoa(String(v));},
    base64Decode(v){return globalThis.atob(String(v));},
    urlEncode(v){return encodeURIComponent(String(v));},
    urlDecode(v){return decodeURIComponent(String(v));},
    uuid(){return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g,c=>{const r=Math.random()*16|0;return (c==='x'?r:(r&3|8)).toString(16);});},
    stringify(v){return JSON.stringify(v);},
    parse(v){return JSON.parse(String(v));},
    read(k){return globalThis.$persistentStore.read(k);},
    write(v,k){return globalThis.$persistentStore.write(v,k);}
  };
      // FX_EGERN_COMPAT_V2_BEGIN
  function _fxEgernHeaders(source) {
    const values=Object.create(null);
    Object.keys(source||{}).forEach(name=>{
      const key=String(name).toLowerCase(), raw=source[name];
      values[key]=Array.isArray(raw)?raw.map(v=>String(v)):[String(raw)];
    });
    const api={
      get(name){const v=values[String(name).toLowerCase()];return v&&v.length?v.join(', '):null;},
      getAll(name){const v=values[String(name).toLowerCase()];return v?v.slice():[];},
      has(name){return Object.prototype.hasOwnProperty.call(values,String(name).toLowerCase());},
      set(name,value){const key=String(name).toLowerCase();if(!/^[!#$%&'*+.^_\x60|~0-9A-Za-z-]+$/.test(key)||/[\r\n]/.test(String(value)))throw new Error('invalid header');values[key]=[String(value)];},
      append(name,value){const key=String(name).toLowerCase();if(!/^[!#$%&'*+.^_\x60|~0-9A-Za-z-]+$/.test(key)||/[\r\n]/.test(String(value)))throw new Error('invalid header');(values[key]||(values[key]=[])).push(String(value));},
      delete(name){delete values[String(name).toLowerCase()];},
      entries(){return Object.keys(values).map(k=>[k,values[k].join(', ')]);},
      keys(){return Object.keys(values)[Symbol.iterator]();},
      values(){return Object.keys(values).map(k=>values[k].join(', '))[Symbol.iterator]();},
      forEach(callback,thisArg){Object.keys(values).forEach(k=>callback.call(thisArg,values[k].join(', '),k,this));},
      toJSON(){const out={};Object.keys(values).forEach(k=>{out[k]=values[k].length===1?values[k][0]:values[k].slice();});return out;},
      [Symbol.iterator](){return this.entries()[Symbol.iterator]();}
    };
    return new Proxy(api,{
      get(target,key){if(typeof key!=='string'||Object.prototype.hasOwnProperty.call(target,key))return target[key];const v=values[key.toLowerCase()];return v?(v.length===1?v[0]:v.slice()):undefined;},
      set(target,key,value){if(typeof key!=='string'||Object.prototype.hasOwnProperty.call(target,key)){target[key]=value;return true;}values[key.toLowerCase()]=Array.isArray(value)?value.map(v=>String(v)):[String(value)];return true;},
      deleteProperty(target,key){if(typeof key==='string'&&!Object.prototype.hasOwnProperty.call(target,key)){delete values[key.toLowerCase()];return true;}return delete target[key];},
      ownKeys(target){return Array.from(new Set(Reflect.ownKeys(target).concat(Object.keys(values))));},
      getOwnPropertyDescriptor(target,key){if(Object.prototype.hasOwnProperty.call(target,key))return Object.getOwnPropertyDescriptor(target,key);const v=typeof key==='string'?values[key.toLowerCase()]:null;return v?{configurable:true,enumerable:true,writable:true,value:v.length===1?v[0]:v.slice()}:undefined;}
    });
  }
  function _fxEgernMessage(source,isResponse) {
    // Reuse the original request/response object so mutations are included in $done().
    const message=source&&typeof source==='object'?source:{};
    message.headers=_fxEgernHeaders(message.headers||{});
    message.text=function(){return Promise.resolve(message.body==null?'':(typeof message.body==='string'?message.body:JSON.stringify(message.body)));};
    message.json=function(){return Promise.resolve(JSON.parse(message.body==null?'':(typeof message.body==='string'?message.body:JSON.stringify(message.body))));};
    if(isResponse){
      message.status=Number(message.statusCode||message.status||200);
      message.statusCode=message.status;
    }
    return message;
  }
  function _fxEgernHttp(method,url,options) {
    const settings=Object.assign({},options||{},{url:String(url||''),method:method.toUpperCase()});
    if(settings.timeout!=null){
      const milliseconds=Number(settings.timeout);
      settings.timeout=Number.isFinite(milliseconds)?Math.max(1,Math.min(20000,milliseconds))/1000:10;
    }
    return globalThis.$task.fetch(settings).then(result=>{
      const response={
        status:Number(result.statusCode||result.status||0),
        statusCode:Number(result.statusCode||result.status||0),
        ok:!!result.ok,
        headers:_fxEgernHeaders(result.headers||{}),
        body:result.body==null?'':String(result.body)
      };
      response.text=function(){return Promise.resolve(response.body);};
      response.json=function(){return Promise.resolve(JSON.parse(response.body));};
      return response;
    });
  }
  function _fxEgernFetch(input,options) {
    let url='', settings={};
    if(typeof input==='string'){
      url=input;
      settings=Object.assign({},options||{});
    }else if(input&&typeof input==='object'){
      url=String(input.url||input.uri||'');
      settings=Object.assign({},input,options||{});
    }else{
      return Promise.reject(new Error('Egern HTTP input must be a URL or request object'));
    }
    const method=String(settings.method||'GET').toLowerCase();
    return _fxEgernHttp(method,url,settings);
  }
  const _fxEgernHttpApi={fetch:_fxEgernFetch,request:_fxEgernFetch};
  for(const method of ['get','post','put','patch','delete','head','options']){
    _fxEgernHttpApi[method]=function(url,options){return _fxEgernHttp(method,url,options);};
  }
  const _fxEgernEnv=(_fxEvent.env&&typeof _fxEvent.env==='object')?_fxEvent.env:{};
  const _fxEgernDevice=(_fxEvent.device&&typeof _fxEvent.device==='object')?_fxEvent.device:{};
  const _fxEgernStage=String(_fxEvent.stage||'').toLowerCase();
  const _fxEgernHasRequest=['request','response','http-request','http-response'].indexOf(_fxEgernStage)>=0;
  const _fxEgernHasResponse=['response','http-response'].indexOf(_fxEgernStage)>=0;
  const _fxEgernRequest=_fxEgernHasRequest?_fxEgernMessage(globalThis.$request,false):undefined;
  const _fxEgernResponse=_fxEgernHasResponse?_fxEgernMessage(globalThis.$response,true):undefined;
  globalThis.ctx={
    script:Object.assign({},globalThis.$script),
    env:Object.assign({},_fxEgernEnv),
    app:{version:String(globalThis.$environment.version||''),language:String(globalThis.$environment.language||'')},
    device:Object.assign({},_fxEgernDevice),
    cron:typeof _fxEvent.cron==='string'?_fxEvent.cron:undefined,
    widgetFamily:typeof _fxEvent.widgetFamily==='string'?_fxEvent.widgetFamily:undefined,
    request:_fxEgernRequest,
    response:_fxEgernResponse,
    http:_fxEgernHttpApi,
    storage:{
      get(key){const value=globalThis.$prefs.valueForKey(String(key));return value==null?null:(typeof value==='string'?value:JSON.stringify(value));},
      set(key,value){return globalThis.$prefs.setValueForKey(String(value),String(key));},
      getJSON(key){const value=this.get(key);if(value==null)return null;try{return JSON.parse(value);}catch(_){return null;}},
      setJSON(key,value){try{return globalThis.$prefs.setValueForKey(JSON.stringify(value),String(key));}catch(_){return false;}},
      delete(key){return globalThis.$prefs.removeValueForKey(String(key));}
    },
    notify(options){options=options||{};return _fxNotify(options.title||'',options.subtitle||'',options.body||'',options);},
    log(){console.log.apply(console,arguments);}
  };
  globalThis.__fxEgernFail=function(error){if(!_fxDone)_fxSaveResult(false,error);};
  // FX_EGERN_COMPAT_V2_END
  // Only publish the selected compatibility version key; absence means that
  // the native vendor runtime is not present. This is a compatibility profile,
  // not a claim that FX is the original client.
  if(_fxIsSurge) globalThis.$environment['surge-version']='FX-compat-1.0.0';
  if(_fxIsLoon) globalThis.$environment['loon-version']='FX-compat-1.0.0';
  if(_fxIsStash) globalThis.$environment['stash-version']='FX-compat-1.0.0';
  if(_fxIsQuanX) globalThis.$environment['quantumult-x-version']='FX-compat-1.0.0';
  if(_fxIsRocket) globalThis.$environment['shadowrocket-version']='FX-compat-1.0.0';
  // Do not pre-create a success result here: this prelude runs before the user's
  // script. Only $done() may publish a successful result, otherwise a hook that
  // forgot to finish would look like a successful no-op to the MITM engine.
  // The FX-hardened QuickJS-NG runner blocks dynamic imports of qjs:std/os/bjson
  // and native .so modules after this trusted prelude has captured its private
  // host references. This closes the known import-based privilege escalation.
  // It is NOT an OS/process sandbox: scripts can still use the HTTP/prefs APIs
  // intentionally exposed below, so only run scripts from trusted sources.
  globalThis.std=undefined; globalThis.os=undefined; globalThis.bjson=undefined;
  globalThis.scriptArgs=undefined; globalThis.argv0=undefined;
})();
