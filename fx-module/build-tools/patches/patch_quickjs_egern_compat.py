#!/usr/bin/env python3
"""Stage the Egern ctx compatibility subset into the restored FX QuickJS runtime."""
from pathlib import Path
import sys

HOST_BEGIN_V1 = "// FX_EGERN_COMPAT_V1_BEGIN"
HOST_END_V1 = "// FX_EGERN_COMPAT_V1_END"
HOST_BEGIN_V2 = "// FX_EGERN_COMPAT_V2_BEGIN"
HOST_END_V2 = "// FX_EGERN_COMPAT_V2_END"
RUNNER_BEGIN_V1 = "# FX_EGERN_SCRIPT_ENTRY_V1_BEGIN"
RUNNER_END_V1 = "# FX_EGERN_SCRIPT_ENTRY_V1_END"
RUNNER_BEGIN_V2 = "# FX_EGERN_SCRIPT_ENTRY_V2_BEGIN"
RUNNER_END_V2 = "# FX_EGERN_SCRIPT_ENTRY_V2_END"

HOST_BLOCK = r"""  // FX_EGERN_COMPAT_V2_BEGIN
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
"""
RUNNER_BLOCK = r"""# FX_EGERN_SCRIPT_ENTRY_V2_BEGIN
EXEC_SCRIPT=$SCRIPT
EGERN_SCRIPT="$STATE/egern-$$.js"
if grep -Eq '^[[:space:]]*export[[:space:]]+default[[:space:]]+(async[[:space:]]+)?function([[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*)?[[:space:]]*\(' "$SCRIPT"; then
  if ! sed -E \
      -e 's/^([[:space:]]*)export[[:space:]]+default[[:space:]]+async[[:space:]]+function([[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*)?[[:space:]]*\(/\1globalThis.__fxEgernMain = async function\2(/' \
      -e 's/^([[:space:]]*)export[[:space:]]+default[[:space:]]+function([[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*)?[[:space:]]*\(/\1globalThis.__fxEgernMain = function\2(/' \
      "$SCRIPT" > "$EGERN_SCRIPT"; then
    rm -f "$EGERN_SCRIPT"
    echo '{"ok":false,"error":"unable to prepare Egern script"}'
    exit 74
  fi
  cat >> "$EGERN_SCRIPT" <<'FX_EGERN_ENTRY'
if (typeof globalThis.__fxEgernMain !== 'function') throw new Error('Egern default function was not found');
try {
  const __fxEgernResult = globalThis.__fxEgernMain(globalThis.ctx);
  if (__fxEgernResult && typeof __fxEgernResult.then === 'function') {
    __fxEgernResult.then(function(value) { globalThis.$done(value); },
      function(error) { globalThis.__fxEgernFail(error); });
  } else {
    globalThis.$done(__fxEgernResult);
  }
} catch (error) {
  globalThis.__fxEgernFail(error);
}
FX_EGERN_ENTRY
  chmod 600 "$EGERN_SCRIPT" 2>/dev/null || :
  EXEC_SCRIPT=$EGERN_SCRIPT
fi
# FX_EGERN_SCRIPT_ENTRY_V2_END
"""
README_SECTION = """## Egern 脚本兼容入口（扩展子集）

运行器支持顶层默认导出的异步或同步函数，包括带名称的函数。提供 ctx.script、ctx.env、ctx.app、ctx.device、ctx.cron、ctx.widgetFamily、ctx.request、ctx.response、ctx.http、ctx.storage、ctx.notify 和 ctx.log。请求/响应对象只在对应 HTTP 事件中提供；对象修改会复用原始 Hook 对象，并通过 $done() 结果回传。

HTTP 支持 GET、POST、PUT、PATCH、DELETE、HEAD、OPTIONS，以及 fetch/request 入口；响应提供 status、headers、text()、json()。Headers 大小写不敏感并支持 get、getAll、has、set、append、delete、entries 和迭代。存储支持 get、set、getJSON、setJSON 和 delete。

环境、设备、cron 和 widget 字段只透传事件实际提供的值。通知写入 FX 脚本日志，不会调用 Android 通知栏。当前仍是兼容子集：不支持 ESM import、流与二进制正文 API、SSH、lookupIP、压缩、ctx.respond()、ctx.abort()、重定向控制、代理策略或 Egern 专属网络服务；HTTP 底层同步执行，仅提供 Promise 兼容层。
"""
def replace_marked(source: str, begin: str, end: str, block: str,
                   old_begin: str = "", old_end: str = "") -> str:
    if begin in source or end in source:
        if source.count(begin) != 1 or source.count(end) != 1:
            raise SystemExit("partial or duplicate Egern compatibility markers")
        start = source.index(begin)
        finish = source.index(end, start) + len(end)
        existing = source[start:finish]
        expected = block.rstrip("\n")
        if existing == expected:
            return source
        return source[:start] + expected + source[finish:]
    if old_begin and (old_begin in source or old_end in source):
        if source.count(old_begin) != 1 or source.count(old_end) != 1:
            raise SystemExit("partial or duplicate previous Egern compatibility markers")
        start = source.index(old_begin)
        finish = source.index(old_end, start) + len(old_end)
        return source[:start] + block.rstrip("\n") + source[finish:]
    return ""

def update_host(path: Path) -> bool:
    if path.is_symlink() or not path.is_file():
        raise SystemExit(f"QuickJS host is missing or unsafe: {path}")
    source = path.read_text(encoding="utf-8")
    updated = replace_marked(source, HOST_BEGIN_V2, HOST_END_V2, HOST_BLOCK,
                             HOST_BEGIN_V1, HOST_END_V1)
    if not updated:
        anchor = "  // Only publish the selected compatibility version key; absence means that\n"
        if source.count(anchor) != 1:
            raise SystemExit("QuickJS Egern host insertion anchor is missing or ambiguous")
        updated = source.replace(anchor, HOST_BLOCK + anchor, 1)
    if updated != source:
        path.write_text(updated, encoding="utf-8")
        return True
    return False

def update_runner(path: Path) -> bool:
    if path.is_symlink() or not path.is_file():
        raise SystemExit(f"QuickJS runner is missing or unsafe: {path}")
    source = path.read_text(encoding="utf-8")
    updated = replace_marked(source, RUNNER_BEGIN_V2, RUNNER_END_V2, RUNNER_BLOCK,
                             RUNNER_BEGIN_V1, RUNNER_END_V1)
    if not updated:
        anchor = 'chmod 600 "$EV" 2>/dev/null || :\n'
        if source.count(anchor) != 1:
            raise SystemExit("QuickJS runner Egern insertion anchor is missing or ambiguous")
        updated = source.replace(anchor, anchor + RUNNER_BLOCK, 1)
    old_exec = '"$QJS" --std --memory-limit 65536 --stack-size 1024 -C -I "$HOST" "$SCRIPT" "$EV" "$STATE" "$HTTP" "$RESULT"'
    new_exec = '"$QJS" --std --memory-limit 65536 --stack-size 1024 -C -I "$HOST" "$EXEC_SCRIPT" "$EV" "$STATE" "$HTTP" "$RESULT"'
    if old_exec in updated:
        if updated.count(old_exec) != 1:
            raise SystemExit("QuickJS runner execution anchor is ambiguous")
        updated = updated.replace(old_exec, new_exec, 1)
    elif updated.count(new_exec) != 1:
        raise SystemExit("QuickJS runner does not use the Egern-aware execution path")
    old_cleanup = 'rm -f "$EV" "$OUT" "$ERR" "$RESULT"'
    new_cleanup = 'rm -f "$EV" "$OUT" "$ERR" "$RESULT" "$EGERN_SCRIPT"'
    if old_cleanup in updated:
        if updated.count(old_cleanup) != 1:
            raise SystemExit("QuickJS runner cleanup anchor is ambiguous")
        updated = updated.replace(old_cleanup, new_cleanup, 1)
    elif updated.count(new_cleanup) != 1:
        raise SystemExit("QuickJS runner does not clean its Egern temporary source")
    if updated != source:
        path.write_text(updated, encoding="utf-8")
        return True
    return False

def update_readme(path: Path) -> bool:
    if path.is_symlink() or not path.is_file():
        raise SystemExit(f"QuickJS README is missing or unsafe: {path}")
    source = path.read_text(encoding="utf-8")
    begin = "## Egern 脚本兼容入口"
    end = "## 明确的能力边界"
    section = README_SECTION
    if begin in source:
        start = source.index(begin)
        finish = source.find(end, start)
        if finish < 0:
            raise SystemExit("QuickJS Egern README section terminator is missing")
        updated = source[:start] + section + "\n" + source[finish:]
    else:
        if source.count(end) != 1:
            raise SystemExit("QuickJS Egern README insertion anchor is missing or ambiguous")
        updated = source.replace(end, section + "\n" + end, 1)
    if updated != source:
        path.write_text(updated, encoding="utf-8")
        return True
    return False

def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch_quickjs_egern_compat.py MODULE_DIR")
    runtime = Path(sys.argv[1]).resolve() / "scripts/jsruntime"
    host_changed = update_host(runtime / "host.js")
    runner_changed = update_runner(runtime / "runner.sh")
    docs_changed = update_readme(runtime / "README-zh-CN.md")
    print("Egern compatibility host=" + str(host_changed).lower()
          + " runner=" + str(runner_changed).lower()
          + " docs=" + str(docs_changed).lower())

if __name__ == "__main__":
    main()
