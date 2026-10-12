/* ============================================================
   =============  极客控制台（代理路由层）  =============
   设计说明：
     · KernelSU WebUI 里的页面不是 http(s) 同源，fetch("/api/...")
       打不到 127.0.0.1:8848，所以两种运行环境各走一条通道：
         KSU 模式 → ksu.exec("sh route.sh …") 拿 JSON 文本
         局域网   → fetch("/api/clash|/api/route")
       UI 只认归一化后的对象，屏蔽两边字段名差异。
     · 实时数据（速率/连接）在 KSU 模式下每次都要 fork，
       所以刷新间隔按运行环境自适应，别把手机 CPU 打满。
   ============================================================ */

var CLASH_PORT = 9090;
var CUR_TAB = "home";
var PROXY_TABS = { "home":1, "route-home":1, "route-proxy":1, "route-conn":1, "route-logs":1 };
var LIVE_MS = 0;            /* 由 init 按运行环境决定 */
var KSU_LONG_MS = 600000;   /* KSU 模式下长任务的超时（下载规则集等） */

/* ---------- 结果解析 ---------- */
function extractJson(t){
  t = String(t == null ? "" : t).replace(/\r/g, "").trim();
  if(!t) return null;
  var direct = parseJSON(t);
  if(direct !== null) return direct;
  var i = t.search(/[[{]/);
  if(i < 0) return null;
  var s = t.slice(i);
  var lastB = s.lastIndexOf("}");
  var lastK = s.lastIndexOf("]");
  var last = Math.max(lastB, lastK);
  if(last < 0) return null;
  return parseJSON(s.slice(0, last + 1));
}
function looksOk(t){ return /(^|\n)\s*OK[:：]/.test(String(t||"")) || /"ok"\s*:\s*true/.test(String(t||"")); }
function num(v, d){ var x = Number(v); return isFinite(x) ? x : (d == null ? 0 : d); }
function fmtBytes(n){
  n = num(n, 0);
  if(n < 1024) return n + " B";
  var u = ["KB","MB","GB","TB","PB"], i = -1;
  do { n /= 1024; i++; } while(n >= 1024 && i < u.length - 1);
  return n.toFixed(n < 10 ? 2 : 1) + " " + u[i];
}
function fmtSpeed(n){ return fmtBytes(n) + "/s"; }
function fmtPct(v){ return (num(v,0)).toFixed(v < 10 ? 1 : 0) + " %"; }
function clip(s, n){ s = String(s == null ? "" : s); return s.length > n ? s.slice(0, n - 1) + "…" : s; }

/* ---------- 数据通道：Clash API ---------- */
function clashUrl(sub, params){
  var qs = "sub=" + q(sub);
  if(params) for(var k in params){
    if(params[k] === null || params[k] === undefined || params[k] === "") continue;
    qs += "&" + k + "=" + q(String(params[k]));
  }
  return "/api/clash?" + qs + "&token=" + q(TOKEN);
}
var CLASH_FLAG = [["name","-name"],["group","-group"],["to","-to"],["mode","-mode"],
                  ["level","-level"],["lines","-lines"],["url","-url"],
                  ["timeout","-timeout"],["id","-close"],["port","-port"]];

function clashRaw(sub, params, timeoutMs){
  if(hasKSU()){
    var args = [sub];
    if(params) for(var i = 0; i < CLASH_FLAG.length; i++){
      var v = params[CLASH_FLAG[i][0]];
      if(v === null || v === undefined || v === "") continue;
      args.push(CLASH_FLAG[i][1], String(v));
    }
    args.push("-json");
    return runScript("route.sh", ["clash"].concat(args), timeoutMs || 40000);
  }
  var ctl = new AbortController();
  var t = setTimeout(function(){ ctl.abort(); }, timeoutMs || 40000);
  return fetch(clashUrl(sub, params), { headers: { "X-Auth-Token": TOKEN }, signal: ctl.signal })
    .then(function(r){ return r.text(); })
    .then(function(x){ clearTimeout(t); return x; })
    .catch(function(e){ clearTimeout(t); return "ERR: " + ((e && e.name === "AbortError") ? "请求超时" : ((e && e.message) || e)); });
}
function clashGet(sub, params, timeoutMs){
  return clashRaw(sub, params, timeoutMs).then(function(t){
    var j = extractJson(t);
    if(j === null) return { ok:false, err: clip(String(t||"无返回").trim(), 160) };
    return j;
  });
}
function clashDo(sub, params, timeoutMs){
  return clashRaw(sub, params, timeoutMs).then(function(t){ return looksOk(t) || extractJson(t) !== null && /"ok"\s*:\s*true/.test(t); });
}

/* 归一化：把 KSU / HTTP 两种返回揉成同一个形状 */
function normStatus(j){
  if(!j || j.ok === false) return null;
  var c = j.connections;
  return {
    ok: true,
    version: j.version || "",
    mode: j.mode || "",
    up: num(j.up, 0), down: num(j.down, 0),
    conn: num(j.conn_count != null ? j.conn_count : (c ? c.length : 0), 0),
    upTotal: num(j.upload_total != null ? j.upload_total : j.uploadTotal, 0),
    downTotal: num(j.download_total != null ? j.download_total : j.downloadTotal, 0),
    memory: num(j.memory, 0)
  };
}
function normTraffic(j){
  if(!j || j.ok === false) return null;
  return { ok:true, up: num(j.up,0), down: num(j.down,0) };
}
function normProxies(j){
  if(!j || j.ok === false) return null;
  return j.proxies || (typeof j === "object" ? j : null);
}
function normConns(j){
  if(!j || j.ok === false) return null;
  var list = j.connections || [];
  return {
    ok: true, list: list,
    upTotal: num(j.upload_total != null ? j.upload_total : j.uploadTotal, 0),
    downTotal: num(j.download_total != null ? j.download_total : j.downloadTotal, 0),
    memory: num(j.memory, 0)
  };
}
function normLogs(j){
  if(!j) return null;
  if(Object.prototype.toString.call(j) === "[object Array]") return j;
  if(j.ok === false) return null;
  return j.logs || [];
}

/* ---------- 数据通道：route.sh ---------- */
function routeRaw(sub, args, timeoutMs){
  args = args || [];
  if(hasKSU()){
    return runScript("route.sh", [sub].concat(args), timeoutMs || 60000);
  }
  var ctl = new AbortController();
  var t = setTimeout(function(){ ctl.abort(); }, timeoutMs || 60000);
  return fetch("/api/route?sub=" + q(sub) + "&token=" + q(TOKEN), {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Auth-Token": TOKEN },
    signal: ctl.signal,
    body: JSON.stringify({ args: args })
  }).then(function(r){ return r.text(); })
    .then(function(x){ clearTimeout(t); var j = parseJSON(x); return (j && typeof j.out === "string") ? j.out : x; })
    .catch(function(e){ clearTimeout(t); return "ERR: " + ((e && e.name === "AbortError") ? "请求超时" : ((e && e.message) || e)); });
}
function routeJson(sub, args, timeoutMs){
  return routeRaw(sub, args, timeoutMs).then(function(t){ return extractJson(t); });
}

/* ---------- 主题色取值（给 canvas 用） ---------- */
function cssVar(name, fb){
  try{
    var v = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
    return v || fb;
  }catch(e){ return fb; }
}
function withAlpha(col, a){
  col = String(col || "").trim();
  var m6 = /^#([0-9a-f]{6})$/i.exec(col);
  if(m6){ var n = parseInt(m6[1], 16); return "rgba(" + ((n >> 16) & 255) + "," + ((n >> 8) & 255) + "," + (n & 255) + "," + a + ")"; }
  var m3 = /^#([0-9a-f]{3})$/i.exec(col);
  if(m3){ var s = m3[1]; return "rgba(" + parseInt(s[0]+s[0],16) + "," + parseInt(s[1]+s[1],16) + "," + parseInt(s[2]+s[2],16) + "," + a + ")"; }
  return col;
}
function niceMax(v){
  v = num(v, 0);
  if(v <= 1024) return 1024;
  var p = Math.pow(10, Math.floor(Math.log(v) / Math.LN10));
  var n = v / p;
  var f = n <= 1 ? 1 : (n <= 2 ? 2 : (n <= 5 ? 5 : 10));
  return f * p;
}

/* ============================================================
   实时曲线（canvas，2Hz，只在页面可见时重绘）
   ============================================================ */
function Spark(id){
  this.el = document.getElementById(id);
  this.up = [];
  this.down = [];
  this.N = 60;
}
Spark.prototype.push = function(u, d){
  this.up.push(num(u, 0));
  this.down.push(num(d, 0));
  while(this.up.length > this.N){ this.up.shift(); this.down.shift(); }
};
Spark.prototype.reset = function(){ this.up = []; this.down = []; };
Spark.prototype.draw = function(){
  var c = this.el;
  if(!c || !c.getContext) return;
  try{
    this._draw(c);
  }catch(e){ /* canvas 不可用（如无 GPU 的 WebView）时静默降级，绝不能拖垮整个面板 */ }
};
Spark.prototype._draw = function(c){
  var w = c.clientWidth, h = c.clientHeight;
  if(!w || !h) return;
  var dpr = Math.min(window.devicePixelRatio || 1, 2);
  var cw = Math.round(w * dpr), chh = Math.round(h * dpr);
  if(c.width !== cw || c.height !== chh){ c.width = cw; c.height = chh; }
  var g = c.getContext("2d");
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  g.clearRect(0, 0, w, h);

  var gridCol = cssVar("--border-color", "rgba(255,255,255,.07)");
  g.strokeStyle = gridCol;
  g.lineWidth = 1;
  for(var i = 1; i < 4; i++){
    var y = Math.round(h * i / 4) + .5;
    g.beginPath(); g.moveTo(0, y); g.lineTo(w, y); g.stroke();
  }
  var max = 1, k;
  for(k = 0; k < this.up.length; k++){ if(this.up[k] > max) max = this.up[k]; }
  for(k = 0; k < this.down.length; k++){ if(this.down[k] > max) max = this.down[k]; }
  max = niceMax(max);

  var colDown = cssVar("--green", "#3fb950");
  var colUp = cssVar("--accent", "#58a6ff");
  function line(arr, col, fillA){
    if(arr.length < 2) return;
    var n = arr.length, step = w / (n - 1), x, y;
    g.beginPath();
    for(var i = 0; i < n; i++){
      x = i * step;
      y = h - (arr[i] / max) * (h - 8) - 4;
      if(i === 0) g.moveTo(x, y); else g.lineTo(x, y);
    }
    g.strokeStyle = col; g.lineWidth = 1.6; g.lineJoin = "round"; g.lineCap = "round";
    g.stroke();
    if(fillA){
      g.lineTo(w, h); g.lineTo(0, h); g.closePath();
      g.fillStyle = withAlpha(col, fillA); g.fill();
    }
  }
  line(this.down, colDown, .14);
  line(this.up, colUp, .12);

  g.fillStyle = cssVar("--scolor", "#8b949e");
  g.font = "10px ui-monospace,Menlo,monospace";
  g.fillText(fmtSpeed(max), 4, 11);
};

/* ============================================================
   状态容器
   ============================================================ */
var RH = { status:null, summary:null, general:null, spark:new Spark("rhSpark"), last:null };
var RP = { proxies:null, fold:{}, filter:"", sort:"order" };
var RC = { list:[], filter:"", timer:0, last:null };
var RL = { lines:[], timer:0 };
var RR = { rules:[], lint:null };
var RK = { profile:null, profileRaw:"" };
var AP = {};

/* ============================================================
   代理总览
   ============================================================ */
function latPill(ms){
  if(ms == null || ms <= 0) return '<span class="lat p4">超时</span>';
  return '<span class="lat ' + latClass(ms) + '">' + ms + 'ms</span>';
}
function latClass(ms){
  if(ms == null || ms <= 0) return "p4";
  if(ms < 100) return "p0";
  if(ms < 200) return "p1";
  if(ms < 400) return "p2";
  if(ms < 800) return "p3";
  return "p4";
}
var GROUP_TYPES = { Selector:1, URLTest:1, Fallback:1, LoadBalance:1, Relay:1 };

function loadRouteStatus(){
  return routeJson("status-json").then(function(j){
    if(!j){ setText("rhSub", "无法读取路由状态"); return null; }
    RH.status = j;
    setText("rhSub", (j.running === "yes" ? "内核运行中" : "内核未运行") + " · " +
      (j.core_version ? ("v" + j.core_version) : "内核未安装") + " · " +
      (j.ruleset_count || 0) + " 个规则集 · 端口 " + (j.mixed_port || "-"));
    setText("rhVer", j.core_version ? ("sing-box v" + j.core_version) : "未安装内核");
    setText("rhCore", j.core ? (String(j.core).split("/").pop()) : "-");
    setText("rhPid", j.pid ? j.pid : "-");
    setText("rhMport", j.mixed_port || "-");
    setText("rhApi", "127.0.0.1:" + (j.clash_port || 9090));
    setText("rhRS", (j.ruleset_count || 0) + " 个");
    setText("rhCfg", j.config ? ("已生成 " + fmtBytes(j.config_size)) : "未生成");
    setText("hmRS", (j.ruleset_count || 0) + " 个规则集");
    setText("hmCore", j.core_version ? ("sing-box v" + j.core_version) : "未安装内核");
    setText("hmMix", "端口 " + (j.mixed_port || "-"));
    setText("rkPath", j.core || "未找到内核");
    setText("rkVer", j.core_version ? ("sing-box v" + j.core_version) : "-");
    setText("rkArch", j.arch || "-");
    setText("rkSize", j.core_size ? fmtBytes(j.core_size) : "-");
    setText("rkRun", j.running === "yes" ? "运行中" : "已停止");
    setText("rkPid", j.pid || "-");
    setText("rkProfile", j.profile ? ("存在 " + fmtBytes(j.profile_size)) : "未生成");
    setText("rkCfg", j.config ? ("存在 " + fmtBytes(j.config_size)) : "未生成");
    setText("rkRsDir", j.ruleset_dir || "未找到");
    setText("rkRsCount", (j.ruleset_count || 0) + " 个");
    setText("rkMport", j.mixed_port || "-");
    setText("rkApi", "127.0.0.1:" + (j.clash_port || 9090));
    setText("rkMirror", j.mirror || "testingcf");
    var tg = document.getElementById("tgProxy");
    if(tg){
      tg.textContent = j.running === "yes" ? "代理 已开启" : "代理 已关闭";
      tg.className = "btn " + (j.running === "yes" ? "ok" : "");
    }
    return j;
  });
}

function loadRouteSummary(){
  return routeJson("summary").then(function(j){
    if(!j){ setText("rrSub", "无法读取 profile（请先添加节点）"); return null; }
    RH.summary = j;
    var c = j.counts || {};
    setText("rhRules", c.rules || 0);
    setText("rhNodes", c.nodes || 0);
    setText("rrRules", c.rules || 0);
    setText("rrNodes", c.nodes || 0);
    setText("rrGroups", c.groups || 0);
    setText("rrRS", c.rule_sets || 0);
    setText("rrErr", (c.errors || 0) + " / " + (c.warnings || 0));
    setText("rrRuleTag", "共 " + (c.rules || 0) + " 条");
    setText("rrSub", "节点 " + (c.nodes||0) + " · 策略组 " + (c.groups||0) + " · 规则 " + (c.rules||0) + " · 规则集 " + (c.rule_sets||0));
    setText("hmRules", (c.rules || 0) + " 条");
    var g = j.general || {};
    RH.general = g;
    setText("rhTun", g.tun_enabled ? "已开启" : "未开启");
    setText("rhPriv", g.private_direct === false ? "已关闭" : "已开启");
    setText("rhModeTxt", modeLabel(g.default_mode || "rule"));
    RR.rules = j.rules || [];
    renderRules();
    return j;
  });
}

function loadRouteLive(){
  return clashGet("status").then(function(j){
    applyStatus(normStatus(j));
    return LAST_STATUS;
  });
}
var LAST_STATUS = null, LAST_STATUS_AT = 0;
/* 内核运行模式 -> 中文标签（面板其余文案已中文化，避免出现「模式 rule」这类中英混排） */
var MODE_LABEL = { rule: "规则分流", global: "全局代理", direct: "全部直连" };
function modeLabel(m){
  if(m == null || m === "") return "-";
  return MODE_LABEL[String(m).toLowerCase()] || String(m);
}
function renderSysline(s){
  var el = document.getElementById("sysline");
  if(!el) return;
  if(!s){ el.innerHTML = '<span class="dot off"></span>内核未运行'; return; }
  el.innerHTML = '<span class="dot on"></span>↑' + fmtSpeed(s.up) + ' ↓' + fmtSpeed(s.down) +
    ' · ' + s.conn + ' 连接 · ' + modeLabel(s.mode);
}
function applyStatus(s){
  LAST_STATUS = s;
  LAST_STATUS_AT = Date.now();
  renderSysline(s);
  if(!s){
    setText("rhUp", "-"); setText("rhDown", "-");
    setText("rhConn", "0"); setText("rhMem", "-");
    setText("hmRun", "已停止"); setText("hmMode", "内核未运行");
    setText("rhDelay", "-"); setText("hmDelay", "-");
    setText("hmUp", "-"); setText("hmDown", "-");
    $$("#rhModes .seg-btn").forEach(function(b){ b.classList.remove("on"); });
    return;
  }
  setText("rhUp", fmtSpeed(s.up));
  setText("rhDown", fmtSpeed(s.down));
  setText("rhConn", s.conn);
  setText("rhMem", s.memory ? fmtBytes(s.memory) : "-");
  setText("rhUpT", fmtBytes(s.upTotal));
  setText("rhDownT", fmtBytes(s.downTotal));
  setText("rhModeTxt", modeLabel(s.mode));
  setText("hmRun", "运行中");
  setText("hmMode", "模式 " + modeLabel(s.mode));
  setText("hmUp", fmtSpeed(s.up));
  setText("hmDown", fmtSpeed(s.down));
  setText("hmUpT", "累计 " + fmtBytes(s.upTotal));
  setText("hmDownT", "累计 " + fmtBytes(s.downTotal));
  setText("hmConn", s.conn);
  setText("hmMem", s.memory ? ("内核 " + fmtBytes(s.memory)) : "-");
  setText("rcUp", fmtSpeed(s.up));
  setText("rcDown", fmtSpeed(s.down));
  setText("rcMem", s.memory ? fmtBytes(s.memory) : "-");
  setText("rcCount", s.conn);
  RH.spark.push(s.up, s.down);
  if(CUR_TAB === "route-home" || CUR_TAB === "home") RH.spark.draw();
  $$("#rhModes .seg-btn").forEach(function(b){
    b.classList.toggle("on", b.getAttribute("data-v") === String(s.mode || "").toLowerCase());
  });
}

function loadRouteCurrent(){
  return clashGet("proxies").then(function(j){
    var px = normProxies(j);
    if(!px) return null;
    var mainName = null, i;
    var names = Object.keys(px);
    for(i = 0; i < names.length; i++){
      if(names[i] === "PROXY" || names[i] === "Proxy" || names[i] === "GLOBAL"){ mainName = names[i]; break; }
    }
    if(!mainName) for(i = 0; i < names.length; i++){
      if(GROUP_TYPES[px[names[i]].type]){ mainName = names[i]; break; }
    }
    if(!mainName) return null;
    var g = px[mainName];
    setText("rhGroup", mainName + " (" + g.type + ")");
    setText("hmGroup", mainName);
    var now = g.now || "-";
    setText("rhNow", now);
    setText("hmNode", clip(now, 18));
    var d = null;
    if(px[now] && px[now].history && px[now].history.length){
      d = px[now].history[px[now].history.length - 1].delay;
    }
    setText("rhDelay", (d == null || d <= 0) ? "未测速" : (d + " ms"));
    setText("hmDelay", (d == null || d <= 0) ? "-" : (d + " ms"));
    RH.last = { group: mainName, now: now, px: px };
    return RH.last;
  });
}

function loadRouteHome(){
  return Promise.all([loadRouteStatus(), loadRouteSummary(), loadRouteLive(), loadRouteCurrent()]);
}

/* ============================================================
   策略组与节点
   ============================================================ */
function renderProxyGroups(){
  var box = document.getElementById("rpGroups");
  if(!box) return;
  var px = RP.proxies;
  if(!px){ box.innerHTML = '<div class="empty">内核未运行或 API 不可达</div>'; return; }
  var groups = [], names = Object.keys(px), i, j;
  for(i = 0; i < names.length; i++){
    if(GROUP_TYPES[px[names[i]].type]) groups.push(names[i]);
  }
  groups.sort();
  var kw = RP.filter.toLowerCase();
  var out = [];
  for(i = 0; i < groups.length; i++){
    var gn = groups[i], g = px[gn];
    var members = (g.all || []).slice();
    if(kw) members = members.filter(function(m){ return m.toLowerCase().indexOf(kw) >= 0; });
    if(RP.sort === "delay"){
      members.sort(function(a, b){ return delayOf(px, a) - delayOf(px, b); });
    } else if(RP.sort === "name"){
      members.sort(function(a, b){ return a.localeCompare(b); });
    }
    var folded = !!RP.fold[gn];
    var rows = members.map(function(m, idx){
      var mv = px[m] || {};
      var d = delayOf(px, m);
      var isNow = (m === g.now);
      var sub = GROUP_TYPES[mv.type];
      return '<div class="nrow' + (isNow ? ' on' : '') + '" data-act="rp-pick" data-g="' + esc(gn) + '" data-n="' + esc(m) + '">' +
        '<span class="idx">' + (idx + 1) + '</span>' +
        '<span class="dotbar ' + (d > 0 ? 'on' : (d === 0 ? 'off' : '')) + '"></span>' +
        '<span class="nm">' + esc(m) + '<span class="p">' + esc(mv.type || (sub ? "组" : "-")) + '</span></span>' +
        '<span class="act">' +
          '<button class="btn xs ghost" data-act="rp-ping" data-n="' + esc(m) + '">测速</button>' +
          latPill(d) +
        '</span></div>';
    }).join("");
    if(!members.length) rows = '<div class="empty">无匹配成员</div>';
    out.push('<div class="grp' + (folded ? ' fold' : '') + '" data-g="' + esc(gn) + '">' +
      '<div class="grp-head" data-act="rp-fold">' +
        '<span class="caret2">▼</span>' +
        '<span class="gname">' + esc(gn) + '</span>' +
        '<span class="pill info">' + esc(g.now || "-") + '</span>' +
        '<span class="gtype">' + esc(g.type) + '</span>' +
        '<span class="gtype">' + (g.all || []).length + ' 项</span>' +
      '</div>' +
      '<div class="grp-body">' + rows + '</div>' +
    '</div>');
  }
  box.innerHTML = out.length ? out.join("") : '<div class="empty">没有策略组，请先在「节点与订阅」里添加节点</div>';
  setText("rpSub", groups.length + " 个策略组 · 共 " + Object.keys(px).length + " 个对象");
}
function delayOf(px, name){
  var v = px[name];
  if(!v || !v.history || !v.history.length) return -1;
  var d = v.history[v.history.length - 1].delay;
  return d > 0 ? d : 0;
}
function loadRouteProxy(){
  return clashGet("proxies").then(function(j){
    RP.proxies = normProxies(j);
    renderProxyGroups();
    return RP.proxies;
  });
}
function rpPing(names){
  var url = ($("#rpUrl") && $("#rpUrl").value) || "http://www.gstatic.com/generate_204";
  var queue = names.slice(), running = 0, done = 0, max = 4;
  return new Promise(function(resolve){
    if(!queue.length){ resolve(); return; }
    function next(){
      if(!queue.length && running === 0){ resolve(); return; }
      while(running < max && queue.length){
        (function(name){
          running++;
          clashGet("delay", { name: name, url: url, timeout: 5000 }, 20000).then(function(j){
            var d = j && j.delay != null ? num(j.delay, 0) : 0;
            if(RP.proxies && RP.proxies[name]){
              RP.proxies[name].history = [{ time: new Date().toISOString(), delay: d }];
            }
            running--; done++;
            setText("rpSub", "测速中… " + done + "/" + names.length);
            renderProxyGroups();
            next();
          });
        })(queue.shift());
      }
    }
    next();
  }).then(function(){ toast("测速完成（" + done + " 个）"); return loadRouteProxy(); });
}

/* ============================================================
   实时连接
   ============================================================ */
function renderConns(){
  var box = document.getElementById("rcList");
  if(!box) return;
  var kw = RC.filter.toLowerCase();
  var list = RC.list || [];
  if(kw){
    list = list.filter(function(c){
      var m = c.metadata || {};
      var hay = [m.host, m.destinationIP, m.process, m.processPath, c.rule, c.rulePayload, (c.chains || []).join(" "), m.network].join(" ").toLowerCase();
      return hay.indexOf(kw) >= 0;
    });
  }
  list = list.slice().sort(function(a, b){ return (num(b.download,0)+num(b.upload,0)) - (num(a.download,0)+num(a.upload,0)); });
  var cap = list.slice(0, 150);
  box.innerHTML = cap.length ? cap.map(function(c){
    var m = c.metadata || {};
    var host = m.host || m.sniffHost || m.destinationIP || "-";
    if(m.destinationPort) host += ":" + m.destinationPort;
    var rule = (c.rule || "") + (c.rulePayload ? " " + c.rulePayload : "");
    return '<div class="cr">' +
      '<span class="c1" title="' + esc(host) + '">' + esc(clip(host, 42)) + '</span>' +
      '<span class="c2" title="' + esc(m.process || m.processPath || "") + '">' + esc(clip(m.process || m.processPath || "-", 22)) + '</span>' +
      '<span class="c3" title="' + esc(rule) + '">' + esc(clip(rule || "-", 26)) + '</span>' +
      '<span class="c4">' + esc(fmtBytes(c.upload || 0)) + '</span>' +
      '<span class="c5">' + esc(fmtBytes(c.download || 0)) + '</span>' +
      '<span class="c6"><button class="del" data-act="rc-close" data-v="' + esc(c.id) + '">✕</button></span>' +
    '</div>';
  }).join("") : '<div class="empty">' + (RC.list.length ? "没有匹配的连接" : "暂无活动连接") + '</div>';
  setText("rcTime", "更新于 " + new Date().toLocaleTimeString() + " · 显示 " + cap.length + "/" + list.length);
}
function loadRouteConn(){
  return clashGet("conn", null, 25000).then(function(j){
    var c = normConns(j);
    if(!c){ RC.list = []; setText("rcSub", "内核未运行或 API 不可达"); renderConns(); return null; }
    RC.list = c.list;
    setText("rcCount", c.list.length);
    setText("rcSub", c.list.length + " 条活动连接 · 累计 ↑ " + fmtBytes(c.upTotal) + " ↓ " + fmtBytes(c.downTotal));
    renderConns();
    return c;
  });
}

/* ============================================================
   规则与分流
   ============================================================ */
var KIND_CLASS = [
  [/^DOMAIN$/, "k-domain"], [/^DOMAIN-SUFFIX|^DOMAIN-KEYWORD|^DOMAIN-WILDCARD|^DOMAIN-REGEX/, "k-suffix"],
  [/^GEOSITE|^RULE-SET|^GEOIP|^IP-ASN/, "k-geo"], [/^IP-CIDR|^SRC-IP-CIDR|^SUBNET/, "k-ip"],
  [/PORT$/, "k-port"], [/^MATCH|^FINAL/, "k-match"], [/^AND$|^OR$|^NOT$/, "k-logical"],
  [/^PROCESS|^USER-AGENT|^URL-REGEX|^HEADER|^DEVICE/, "k-domain"]
];
function kindClass(k){
  for(var i = 0; i < KIND_CLASS.length; i++){ if(KIND_CLASS[i][0].test(k)) return KIND_CLASS[i][1]; }
  return "";
}
function polClass(p){
  p = String(p || "").toUpperCase();
  if(p === "DIRECT" || p === "PASS") return "p-direct";
  if(p === "REJECT" || p === "REJECT-DROP") return "p-reject";
  return "p-proxy";
}
function renderRules(){
  var box = document.getElementById("rrRuleList");
  if(!box) return;
  var kw = (($("#rrRuleSearch") || {}).value || "").toLowerCase();
  var kind = (($("#rrRuleFilter") || {}).value || "").toUpperCase();
  var list = (RR.rules || []).filter(function(r){
    if(kind){
      if(kind === "DOMAIN"){ if(!/^DOMAIN/.test(r.kind)) return false; }
      else if(kind === "IP-CIDR"){ if(!/^IP-CIDR|^SRC-IP-CIDR|^SUBNET/.test(r.kind)) return false; }
      else if(kind === "DST-PORT"){ if(!/PORT$/.test(r.kind)) return false; }
      else if(kind === "PROCESS"){ if(!/^PROCESS/.test(r.kind)) return false; }
      else if(r.kind !== kind) return false;
    }
    if(kw){
      var hay = (r.kind + " " + r.payload + " " + r.policy).toLowerCase();
      if(hay.indexOf(kw) < 0) return false;
    }
    return true;
  });
  var cap = list.slice(0, 300);
  box.innerHTML = cap.length ? cap.map(function(r, i){
    return '<div class="rrow' + (r.enabled ? '' : ' off') + '">' +
      '<span class="idx">' + (i + 1) + '</span>' +
      '<span class="kind ' + kindClass(r.kind) + '">' + esc(r.kind) + '</span>' +
      '<span class="pay" title="' + esc(r.payload) + '">' + esc(r.payload) + '</span>' +
      '<span class="pol ' + polClass(r.policy) + '">' + esc(r.policy || "-") + '</span>' +
    '</div>';
  }).join("") : '<div class="empty">没有匹配的规则</div>';
  if(list.length > cap.length){
    box.innerHTML += '<div class="empty">仅显示前 ' + cap.length + ' 条，共 ' + list.length + ' 条（用筛选缩小范围）</div>';
  }
}
function renderLint(issues, meta){
  var box = document.getElementById("rrLintList");
  if(!box) return;
  if(!issues || !issues.length){
    box.innerHTML = '<div class="empty">没有发现问题 ✓</div>';
    setText("rrLintTag", "全部通过");
    return;
  }
  var order = { error:0, warn:1, info:2 };
  issues.sort(function(a, b){ return (order[a.level] == null ? 3 : order[a.level]) - (order[b.level] == null ? 3 : order[b.level]); });
  box.innerHTML = issues.map(function(it){
    var cls = it.level === "error" ? "err" : (it.level === "warn" ? "warn" : "info");
    var mark = it.level === "error" ? "错误" : (it.level === "warn" ? "警告" : "提示");
    return '<div class="row"><span class="t">' +
      '<span class="pill ' + cls + '">' + mark + '</span> ' + esc(it.msg) +
      (it.rule ? '<br><span class="mono">' + esc(clip(it.rule, 80)) + '</span>' : '') +
      (it.line ? '<span class="mono"> · 第' + it.line + '行</span>' : '') +
      '</span></div>';
  }).join("");
  var e = 0, w = 0;
  issues.forEach(function(i){ if(i.level === "error") e++; else if(i.level === "warn") w++; });
  setText("rrLintTag", "错误 " + e + " · 警告 " + w + " · 提示 " + (issues.length - e - w));
}
function renderDiag(res, verbose){
  var box = document.getElementById("rrDiagOut");
  if(!box) return;
  box.classList.remove("hide");
  if(!res){ box.className = "diag err"; box.textContent = "推演失败"; return; }
  var steps = "";
  if(verbose && res.steps){
    steps = '<div style="margin-top:8px;border-top:1px solid var(--border-color);padding-top:6px">' +
      res.steps.map(function(s){
        return '<div class="step"><span class="i">' + (s.matched ? "✓" : "·") + '</span>' +
          '<span>' + esc(clip(s.rule || "", 64)) + (s.detail ? ' <span style="color:var(--scolor)">← ' + esc(s.detail) + '</span>' : '') + '</span></div>';
      }).join("") + '</div>';
  }
  if(res.matched){
    box.className = "diag hit";
    box.innerHTML = '<b>命中第 ' + res.rule_line + ' 行</b> → 策略 <b>' + esc(res.policy) + '</b>' +
      '<br><span class="mono">' + esc(res.rule_raw || "") + '</span>' + steps;
  } else {
    box.className = "diag no";
    box.innerHTML = '<b>未命中任何规则</b> → 兜底策略 <b>' + esc(res.policy) + '</b>' + steps;
  }
  if(res.notes && res.notes.length){
    box.innerHTML += '<div class="mono" style="margin-top:6px;color:var(--scolor)">' +
      res.notes.map(function(n){ return "· " + esc(n); }).join("<br>") + '</div>';
  }
}
function renderRulesets(j){
  var box = document.getElementById("rrRsList");
  if(!box) return;
  if(!j || !j.items || !j.items.length){ box.innerHTML = '<div class="empty">没有可用规则集</div>'; return; }
  var items = j.items.slice().sort(function(a, b){ return a.name.localeCompare(b.name); });
  box.innerHTML = items.map(function(x){
    return '<div class="row"><span class="t">' + esc(x.name) + '</span>' +
      '<span class="pill ' + (x.from === "local" ? "info" : "") + '">' + (x.from === "local" ? "本地缓存" : "模块内置") + '</span>' +
      '<span class="tiny">' + fmtBytes(x.size) + '</span></div>';
  }).join("");
  setText("rrRsTag", items.length + " 个 · 目录 " + (j.dir || "-"));
}
function loadRouteRules(){
  return Promise.all([
    loadRouteSummary(),
    routeJson("rulesets").then(function(j){ renderRulesets(j); return j; })
  ]);
}
function rrLint(){
  return routeRaw("lint", ["-json"]).then(function(t){
    var j = extractJson(t);
    if(!j){ toast("体检失败：" + clip(String(t||"").trim(), 80)); return; }
    RR.lint = j.issues || [];
    renderLint(RR.lint, j);
    toast(RR.lint.length ? ("发现 " + RR.lint.length + " 条问题") : "规则体检通过");
  });
}
function rrDiag(verbose){
  var d = (($("#rrDiagDomain") || {}).value || "").trim();
  var ip = (($("#rrDiagIp") || {}).value || "").trim();
  var port = (($("#rrDiagPort") || {}).value || "").trim();
  var proc = (($("#rrDiagProc") || {}).value || "").trim();
  if(!d && !ip){ toast("至少填域名或 IP"); return Promise.resolve(); }
  var args = ["-json"];
  if(d) args.push("-domain", d);
  if(ip) args.push("-ip", ip);
  if(port) args.push("-port", port);
  if(proc) args.push("-process", proc);
  if(verbose) args.push("-v");
  busy("正在推演…");
  return routeRaw("test", args).then(function(t){
    var j = extractJson(t);
    if(!j){ renderDiag(null); toast("推演失败：" + clip(String(t||"").trim(), 80)); return; }
    renderDiag(j, verbose);
  });
}

/* ============================================================
   DNS
   ============================================================ */
var RD = { profile:null };
function rdLoad(){
  return routeRaw("profile").then(function(t){
    var p = extractJson(t);
    if(!p){ setText("rdSub", "profile 不可读"); return null; }
    RD.profile = p;
    var d = p.dns || {};
    setText("rdEnabled", d.enabled ? "已开启" : "已关闭");
    setText("rdFinal", d.final || "(未设置)");
    setText("rdStrategy", d.strategy || "prefer_ipv4");
    setText("rdFakeip", d.fake_ip ? ("已开启" + (d.fake_ip_range ? " " + d.fake_ip_range : "")) : "未开启");
    setText("rdSub", (d.servers || []).length + " 个上游 · 兜底 " + (d.final || "-"));
    var e = document.getElementById("rdRaw");
    if(e) e.value = JSON.stringify(d, null, 2);
    var box = document.getElementById("rdSrvList");
    var srvs = d.servers || [];
    box.innerHTML = srvs.length ? srvs.map(function(s, i){
      return '<div class="row"><span class="t">' + esc(s.tag || ("#" + (i + 1))) +
        '<br><span class="mono">' + esc(s.address) + '</span>' +
        (s.detour ? '<span class="tagline"> · 出口 ' + esc(s.detour) + '</span>' : '') +
        (s.domains && s.domains.length ? '<span class="tagline"> · 仅 ' + esc(s.domains.join(",")) + '</span>' : '') +
        '</span>' +
        '<button class="del" data-act="rd-srv-del" data-v="' + i + '">✕</button></div>';
    }).join("") : '<div class="empty">没有 DNS 上游</div>';
    setText("rdSrvTag", srvs.length + " 个");
    var leak = p.general && p.general.private_direct === false ? "未启用私网直连" : "正常";
    setText("rdLeak", leak);
    return p;
  });
}
function rdSaveProfile(next){
  var p = next || RD.profile;
  if(!p){ toast("没有可保存的内容"); return Promise.resolve(); }
  busy("正在保存…");
  return routeRaw("set-profile", [b64(JSON.stringify(p))], 90000).then(function(t){
    toast(msg(t));
    if(looksOk(t)) return routeRaw("reload", [], 180000).then(function(){ return rdLoad(); });
  });
}
function rdPreset(name){
  if(!RD.profile){ toast("profile 未载入"); return Promise.resolve(); }
  var d = RD.profile.dns || (RD.profile.dns = {});
  d.enabled = true;
  if(name === "cn"){
    d.servers = [
      { tag:"local", address:"223.5.5.5" },
      { tag:"remote", address:"https://1.1.1.1/dns-query", detour:"proxy" }
    ];
    d.final = "local";
    d.strategy = "prefer_ipv4";
    d.rules = [
      { kind:"GEOSITE", payload:"geolocation-!cn", policy:"remote", enabled:true },
      { kind:"GEOSITE", payload:"cn", policy:"local", enabled:true }
    ];
  } else if(name === "secure"){
    d.servers = [
      { tag:"ali", address:"https://dns.alidns.com/dns-query" },
      { tag:"cf", address:"https://1.1.1.1/dns-query", detour:"proxy" }
    ];
    d.final = "ali";
    d.strategy = "prefer_ipv4";
    d.rules = [];
  } else {
    d.servers = [
      { tag:"local", address:"223.5.5.5" },
      { tag:"cn-doh", address:"https://dns.alidns.com/dns-query" },
      { tag:"remote", address:"tls://1.1.1.1:853", detour:"proxy" }
    ];
    d.final = "cn-doh";
    d.strategy = "prefer_ipv4";
    d.rules = [
      { kind:"GEOSITE", payload:"geolocation-!cn", policy:"remote", enabled:true },
      { kind:"GEOSITE", payload:"cn", policy:"cn-doh", enabled:true }
    ];
  }
  return rdSaveProfile();
}
function rdProbe(){
  var d = (($("#rdProbeDomain") || {}).value || "www.baidu.com").trim();
  var box = document.getElementById("rdProbeList");
  box.innerHTML = '<div class="empty">正在并发查询…</div>';
  return routeRaw("dnsprobe", ["-domain", d, "-timeout", "4", "-json"], 60000).then(function(t){
    var j = extractJson(t);
    if(!j || !j.results){ box.innerHTML = '<div class="empty">探测失败：' + esc(clip(String(t||"").trim(), 100)) + '</div>'; return; }
    var rs = j.results.slice().sort(function(a, b){
      if(a.ok !== b.ok) return a.ok ? -1 : 1;
      return a.millis - b.millis;
    });
    box.innerHTML = rs.map(function(r){
      return '<div class="row"><span class="t">' + esc(r.server) +
        '<br><span class="mono">' + esc(r.kind.toUpperCase()) + ' · ' + esc(r.ok ? (r.answers || []).join(", ") : r.error) + '</span></span>' +
        (r.ok ? latPill(r.millis) : '<span class="lat p4">失败</span>') + '</div>';
    }).join("");
  });
}

/* ============================================================
   内核日志
   ============================================================ */
function rlRender(){
  var box = document.getElementById("rlTerm");
  if(!box) return;
  if(!RL.lines.length){ box.innerHTML = '<span class="empty">暂无日志</span>'; return; }
  var cap = RL.lines.slice(-260);
  box.innerHTML = cap.map(function(l){
    var lv = String(l.type || "info").toLowerCase();
    return '<span class="tl ' + esc(lv) + '"><span class="ts">' + esc(new Date().toLocaleTimeString()) +
      '</span> <span class="lv">[' + esc(lv.toUpperCase()) + ']</span> <span class="msg">' + esc(l.payload) + '</span></span>';
  }).join("");
  box.scrollTop = box.scrollHeight;
  setText("rlStat", RL.lines.length + " 行");
}
function rlPull(){
  var level = ($("#rlLevel") && $("#rlLevel").value) || "info";
  var lines = num(($("#rlLines") && $("#rlLines").value), 60);
  return clashGet("logs", { level: level, lines: lines }, 25000).then(function(j){
    var ls = normLogs(j);
    if(ls === null){ setText("rlStat", "内核未运行或 API 不可达"); return; }
    if(ls.length){
      RL.lines = RL.lines.concat(ls).slice(-400);
      rlRender();
    } else {
      setText("rlStat", "本轮无新日志（" + new Date().toLocaleTimeString() + "）");
    }
  });
}

/* ============================================================
   内核与配置
   ============================================================ */
function rkLoadProfile(){
  return routeRaw("profile").then(function(t){
    RK.profileRaw = String(t || "{}").trim();
    var p = extractJson(RK.profileRaw);
    RK.profile = p;
    var e = document.getElementById("rkProfileText");
    if(e) e.value = p ? JSON.stringify(p, null, 2) : RK.profileRaw;
    setText("rkProfileTag", p ? ((RK.profileRaw.length) + " 字节") : "解析失败");
    return p;
  });
}
function rkLoadCfg(){
  return runScript("proxynode.sh", ["config-get"], 40000).then(function(t){
    var e = document.getElementById("rkCfgView");
    var s = String(t || "").trim();
    if(!s){ e.textContent = "（尚未生成 config.json，先点「编译并重载」）"; return; }
    var j = extractJson(s);
    e.textContent = j ? JSON.stringify(j, null, 2) : s;
    setText("rkSub", "编译产物 " + fmtBytes(s.length));
  });
}
function loadRouteCore(){
  return Promise.all([loadRouteStatus(), rkLoadProfile(), loadRouteSummary()]);
}

/* ============================================================
   内置 App
   ============================================================ */
function loadApp(){
  return runScript("installapp.sh", ["status"], 60000).then(function(t){
    var j = extractJson(t) || {};
    AP = j;
    setText("apInstalled", j.installed ? "已安装 ✓" : (j.bundled ? "未安装" : "模块未打包"));
    setText("apVersion", j.version || "-");
    setText("apPkg", j.package || "com.syfusion.manager");
    setText("apApk", j.bundled ? "app/SYManager.apk" : "缺失");
    setText("apSize", j.size ? fmtBytes(j.size) : "-");
    setText("apSig", j.sha256 ? (j.sha256.slice(0, 16) + "…") : "-");
    setText("apSub", j.installed ? ("已安装 " + (j.version || "") + " · " + (j.package || "")) : "尚未安装");
    var lg = document.getElementById("apLog");
    if(lg && lg.textContent === "-") lg.textContent = "点上方按钮执行安装 / 卸载";
    return j;
  });
}

/* ============================================================
   系统与日志
   ============================================================ */
function loadSysInfo(){
  return runScript("ctl.sh", ["status"]).then(function(s){
    var d = parseJSON(s) || {};
    var sys = d.sys || {}, panel = d.panel || {};
    setText("siMem", sys.mem_used_mb != null ? sys.mem_used_mb + " MB" : "-");
    setText("siCpu", sys.cpu_pct != null ? sys.cpu_pct + " %" : "-");
    setText("siUp", sys.uptime || "-");
    setText("siPanel", panel.running === "yes" ? "运行中" : "已停止");
    setText("siVer", "v1.0.0");
    setText("siEnv", KSU_LABEL);
    setText("siSub", new Date().toLocaleString());
    return d;
  });
}
function siLoadLogs(){
  return runScript("logs.sh", ["list"]).then(function(s){
    var arr = parseJSON(s) || [];
    var box = document.getElementById("siLogList");
    if(!box) return;
    box.innerHTML = arr.length ? arr.map(function(x){
      return '<div class="row"><span class="t">' + esc(x.name) +
        '<br><span class="mono">' + esc(x.mtime || "") + ' · ' + esc(String(x.size || 0)) + 'B</span></span>' +
        '<button class="btn sm" data-act="si-log-view" data-v="' + esc(x.name) + '">查看</button>' +
        '<button class="del" data-act="log-clear" data-v="' + esc(x.name) + '">✕</button></div>';
    }).join("") : '<div class="empty">暂无日志</div>';
  });
}

/* ============================================================
   动作表扩展
   ============================================================ */
Object.assign(actions, {
  "tab-go": function(el){
    var t = el.getAttribute("data-v");
    if(t) switchTab(t);
  },

  /* ---- 总览 ---- */
  "refresh-home": function(){
    return Promise.all([loadHome(), loadPanel(), loadLogs(), loadRouteLive(), loadRouteCurrent(), loadRouteStatus()])
      .then(function(){ toast("已刷新"); });
  },
  "px-toggle": function(){
    return routeJson("status-json").then(function(j){
      var up = j && j.running === "yes";
      busy(up ? "正在停止内核…" : "正在启动内核…");
      return runScript("proxynode.sh", [up ? "down" : "up"], 120000);
    }).then(function(o){
      toast(msg(o));
      return Promise.all([loadRouteStatus(), loadRouteLive(), loadRouteCurrent(), loadHome()]);
    });
  },

  /* ---- 代理总览 ---- */
  "px-up": function(){
    busy("正在启动内核…");
    return runScript("proxynode.sh", ["up"], 150000).then(function(o){
      toast(msg(o)); return Promise.all([loadRouteStatus(), loadRouteLive(), loadRouteCurrent()]);
    });
  },
  "px-down": function(){
    if(!confirm("确定停止代理内核？停止后所有流量将直连。")) return Promise.resolve();
    busy("正在停止…");
    return runScript("proxynode.sh", ["down"], 90000).then(function(o){
      toast(msg(o)); return Promise.all([loadRouteStatus(), loadRouteLive()]);
    });
  },
  "px-restart": function(){
    busy("正在重启内核…");
    return runScript("proxynode.sh", ["restart"], 180000).then(function(o){
      toast(msg(o)); return Promise.all([loadRouteStatus(), loadRouteLive(), loadRouteCurrent()]);
    });
  },
  "rh-mode": function(el){
    var m = el.getAttribute("data-v");
    busy("正在切换为 " + m + "…");
    return clashDo("mode", { mode: m }, 25000).then(function(ok){
      toast(ok ? ("已切换为 " + m + " 模式") : "切换失败（内核可能未运行）");
      return loadRouteLive();
    });
  },
  "rh-ping-all": function(){
    if(!RP.proxies) return loadRouteProxy().then(function(){ return actions["rh-ping-all"](); });
    var g = RH.last && RH.last.group;
    var px = RP.proxies;
    var names = [];
    if(g && px[g] && px[g].all) names = px[g].all.slice();
    else names = Object.keys(px).filter(function(k){ return !GROUP_TYPES[px[k].type]; });
    names = names.filter(function(n){ return px[n] && !GROUP_TYPES[px[n].type]; });
    if(!names.length){ toast("没有可测速的节点"); return Promise.resolve(); }
    toast("开始测速 " + names.length + " 个节点…");
    return rpPing(names);
  },
  "rh-reload": function(){
    busy("正在重编译并重载…");
    return routeRaw("reload", [], 300000).then(function(t){
      toast(msg(t));
      return Promise.all([loadRouteStatus(), loadRouteLive(), loadRouteCurrent(), loadRouteSummary()]);
    });
  },
  "rh-fetchrules": function(){
    busy("正在更新规则集（可能需要几分钟）…");
    return routeRaw("fetch-rules", [], 600000).then(function(t){
      toast(clip(String(t || "").trim().split("\n").pop() || "完成", 100));
      return Promise.all([loadRouteStatus(), routeJson("rulesets").then(renderRulesets)]);
    });
  },
  "rh-mirrors": function(){
    busy("正在实测镜像…");
    return routeRaw("mirrors", ["-probe"], 120000).then(function(t){
      var box = document.getElementById("rrRsList");
      var j = extractJson(t);
      if(j && Object.prototype.toString.call(j) === "[object Array]"){
        if(box) box.innerHTML = j.map(function(m){
          return '<div class="row"><span class="t">' + esc(m.name) +
            '<br><span class="mono">' + esc(m.url) + '</span></span>' +
            (m.ok ? latPill(m.millis) : '<span class="lat p4">失败</span>') +
            (m.default ? '<span class="pill info">默认</span>' : '') + '</div>';
        }).join("");
        setText("rrRsTag", "镜像实测结果");
        switchTab("route-rules");
      } else {
        toast(clip(String(t || "").trim(), 100));
      }
    });
  },

  /* ---- 策略组 ---- */
  "rp-refresh": function(){ return loadRouteProxy().then(function(){ toast("已刷新"); }); },
  "rp-fold": function(el){
    var grp = el.closest(".grp");
    if(!grp) return;
    var name = grp.getAttribute("data-g");
    RP.fold[name] = !RP.fold[name];
    grp.classList.toggle("fold", !!RP.fold[name]);
  },
  "rp-collapse": function(){
    var anyOpen = false;
    Object.keys(RP.fold).forEach(function(k){ if(!RP.fold[k]) anyOpen = true; });
    Object.keys(RP.fold).forEach(function(k){ RP.fold[k] = true; });
    if(!anyOpen){
      RP.fold = {};
      toast("已全部展开");
    } else toast("已全部折叠");
    renderProxyGroups();
  },
  "rp-pick": function(el){
    var g = el.getAttribute("data-g"), n = el.getAttribute("data-n");
    busy("正在切换到 " + n + "…");
    return clashDo("select", { group: g, to: n }, 25000).then(function(ok){
      toast(ok ? (g + " → " + n) : "切换失败");
      return Promise.all([loadRouteProxy(), loadRouteCurrent()]);
    });
  },
  "rp-ping": function(el){
    var n = el.getAttribute("data-n");
    var url = ($("#rpUrl") && $("#rpUrl").value) || "http://www.gstatic.com/generate_204";
    return clashGet("delay", { name: n, url: url, timeout: 5000 }, 20000).then(function(j){
      var d = j && j.delay != null ? num(j.delay, 0) : 0;
      if(RP.proxies && RP.proxies[n]) RP.proxies[n].history = [{ time: new Date().toISOString(), delay: d }];
      renderProxyGroups();
      toast(n + " → " + (d > 0 ? (d + " ms") : "测速失败"));
    });
  },
  "rp-ping-all": function(){ return actions["rh-ping-all"](); },

  /* ---- 连接 ---- */
  "rc-refresh": function(){ return loadRouteConn().then(function(){ toast("已刷新"); }); },
  "rc-close-all": function(){
    if(!confirm("确定关闭全部活动连接？")) return Promise.resolve();
    return clashDo("close", { id: "" }, 25000).then(function(ok){
      toast(ok ? "已关闭全部连接" : "操作失败");
      return loadRouteConn();
    });
  },
  "rc-close": function(el){
    var id = el.getAttribute("data-v");
    return clashDo("close", { id: id }, 25000).then(function(){ return loadRouteConn(); });
  },

  /* ---- 规则 ---- */
  "rr-lint": function(){ return rrLint(); },
  "rr-compile": function(){
    busy("正在编译内核配置…");
    return routeRaw("compile", [], 180000).then(function(t){
      toast(msg(t));
      return Promise.all([loadRouteStatus(), rkLoadCfg(), loadRouteSummary()]);
    });
  },
  "rr-diag": function(){ return rrDiag(false); },
  "rr-diag-verbose": function(){ return rrDiag(true); },
  "rr-add-toggle": function(){
    var b = document.getElementById("rrAddBox");
    if(b) b.classList.toggle("fold");
  },
  "rr-add-open": function(){
    var b = document.getElementById("rrAddBox");
    if(b) b.classList.remove("fold");
  },
  "rr-add-close": function(){
    var b = document.getElementById("rrAddBox");
    if(b) b.classList.add("fold");
  },
  "rr-add-save": function(){
    var t = (($("#rrAddText") || {}).value || "").trim();
    if(!t){ toast("请输入规则"); return Promise.resolve(); }
    var lines = t.split("\n").map(function(x){ return x.trim(); }).filter(Boolean);
    var args = [];
    lines.forEach(function(l){ args.push("-rule", l); });
    busy("正在追加 " + lines.length + " 条规则…");
    return routeRaw("add-rule", args, 120000).then(function(o){
      toast(msg(o));
      var box = document.getElementById("rrAddText");
      if(box) box.value = "";
      return routeRaw("compile", [], 180000).then(function(){
        return Promise.all([loadRouteSummary(), loadRouteStatus()]);
      });
    });
  },
  "rr-fetchrules": function(){ return actions["rh-fetchrules"](); },
  "rr-mirrors": function(){ return actions["rh-mirrors"](); },

  /* ---- DNS ---- */
  "rd-refresh": function(){ return rdLoad().then(function(){ toast("已刷新"); }); },
  "rd-save": function(){
    var e = document.getElementById("rdRaw");
    if(!RD.profile){ toast("profile 未载入"); return Promise.resolve(); }
    if(e && e.value.trim()){
      var d = parseJSON(e.value);
      if(!d){ toast("DNS 配置不是合法 JSON"); return Promise.resolve(); }
      RD.profile.dns = d;
    }
    return rdSaveProfile();
  },
  "rd-raw-save": function(){ return actions["rd-save"](); },
  "rd-raw-reload": function(){ return rdLoad().then(function(){ toast("已重新载入"); }); },
  "rd-preset": function(el){ return rdPreset(el.getAttribute("data-v")); },
  "rd-probe": function(){ return rdProbe(); },
  "rd-add-toggle": function(){
    var b = document.getElementById("rdAddBox");
    if(b) b.classList.toggle("fold");
  },
  "rd-add-save": function(){
    if(!RD.profile) return Promise.resolve();
    var tag = (($("#rdAddTag") || {}).value || "").trim();
    var addr = (($("#rdAddAddr") || {}).value || "").trim();
    var det = (($("#rdAddDetour") || {}).value || "").trim();
    if(!addr){ toast("请填写地址"); return Promise.resolve(); }
    var d = RD.profile.dns || (RD.profile.dns = {});
    if(!d.servers) d.servers = [];
    var o = { address: addr };
    if(tag) o.tag = tag;
    if(det) o.detour = det;
    d.servers.push(o);
    return rdSaveProfile();
  },
  "rd-srv-del": function(el){
    if(!RD.profile) return Promise.resolve();
    var i = num(el.getAttribute("data-v"), -1);
    var d = RD.profile.dns;
    if(!d || !d.servers || i < 0) return Promise.resolve();
    d.servers.splice(i, 1);
    return rdSaveProfile();
  },

  /* ---- 内核日志 ---- */
  "rl-pull": function(){ return rlPull(); },
  "rl-clear": function(){ RL.lines = []; rlRender(); toast("已清空窗口"); },
  "rl-copy": function(){
    var txt = RL.lines.map(function(l){ return "[" + l.type + "] " + l.payload; }).join("\n");
    copyText(txt);
  },

  /* ---- 内核与配置 ---- */
  "rk-check": function(){
    busy("正在校验内核配置…");
    return runScript("proxynode.sh", ["config-get"], 40000).then(function(t){
      var box = document.getElementById("rkCfgView");
      var s = String(t || "").trim();
      if(box) box.textContent = s ? (extractJson(s) ? JSON.stringify(extractJson(s), null, 2) : s) : "（尚未生成 config.json）";
      toast(s ? "配置已载入，见下方预览" : "尚未生成 config.json");
    });
  },
  "rk-reload": function(){ return actions["rh-reload"](); },
  "rk-profile-save": function(){
    var e = document.getElementById("rkProfileText");
    if(!e) return Promise.resolve();
    var p = parseJSON(e.value);
    if(!p){ toast("profile 不是合法 JSON"); return Promise.resolve(); }
    RK.profile = p;
    RD.profile = p;
    busy("正在保存 profile…");
    return routeRaw("set-profile", [b64(JSON.stringify(p))], 90000).then(function(t){
      toast(msg(t));
      if(!looksOk(t)) return;
      return routeRaw("compile", [], 180000).then(function(){
        return Promise.all([loadRouteStatus(), loadRouteSummary(), rkLoadCfg()]);
      });
    });
  },
  "rk-profile-reload": function(){ return rkLoadProfile().then(function(){ toast("已重新载入"); }); },
  "rk-profile-format": function(){
    var e = document.getElementById("rkProfileText");
    if(!e) return;
    var p = parseJSON(e.value);
    if(!p){ toast("不是合法 JSON，无法格式化"); return; }
    e.value = JSON.stringify(p, null, 2);
    toast("已格式化");
  },
  "rk-cfg-load": function(){ return rkLoadCfg().then(function(){ toast("已载入编译产物"); }); },
  "rk-cfg-copy": function(){ copyText(($("#rkCfgView") || {}).textContent || ""); },
  "rk-cfg-download": function(){
    var t = ($("#rkCfgView") || {}).textContent || "";
    if(!t){ toast("先点「载入」"); return; }
    downloadText("config.json", t);
  },
  "rk-proxy-logs": function(){
    switchTab("route-logs");
    setTimeout(function(){ rlPull(); }, 200);
  },

  /* ---- 内置 App ---- */
  "ap-status": function(){ return loadApp().then(function(){ toast("状态已刷新"); }); },
  "ap-install": function(){
    busy("正在安装内置 App…");
    return runScript("installapp.sh", ["install"], 180000).then(function(t){
      var box = document.getElementById("apLog");
      if(box) box.textContent = t || "(无输出)";
      toast(msg(t));
      return loadApp();
    });
  },
  "ap-reinstall": function(){
    if(!confirm("强制重装会先卸载再安装，确定继续？")) return Promise.resolve();
    busy("正在强制重装…");
    return runScript("installapp.sh", ["reinstall"], 180000).then(function(t){
      var box = document.getElementById("apLog");
      if(box) box.textContent = t || "(无输出)";
      toast(msg(t));
      return loadApp();
    });
  },
  "ap-remove": function(){
    if(!confirm("确定卸载内置管理器 App？")) return Promise.resolve();
    busy("正在卸载…");
    return runScript("installapp.sh", ["remove"], 120000).then(function(t){
      var box = document.getElementById("apLog");
      if(box) box.textContent = t || "(无输出)";
      toast(msg(t));
      return loadApp();
    });
  },
  "ap-open": function(){
    return runScript("installapp.sh", ["status"], 60000).then(function(t){
      var j = extractJson(t) || {};
      if(!j.installed){ toast("请先安装"); return; }
      return runScript("installapp.sh", ["launch"], 60000).then(function(o){
        toast(looksOk(o) ? "已启动" : msg(o));
      }).catch(function(){ toast("启动失败，请从桌面图标打开"); });
    });
  },

  /* ---- 系统 ---- */
  "si-refresh": function(){ return Promise.all([loadSysInfo(), siLoadLogs()]).then(function(){ toast("已刷新"); }); },
  "si-selfcheck": function(){
    busy("正在自检…");
    return runScript("selfcheck.sh", ["all"], 240000).then(function(t){
      var box = document.getElementById("siOut");
      if(box) box.textContent = t || "(无输出)";
      toast("自检完成");
    });
  },
  "si-export": function(){
    busy("正在生成诊断包…");
    return runScript("backup.sh", ["export"], 240000).then(function(t){
      var box = document.getElementById("siOut");
      if(box) box.textContent = t || "(无输出)";
      toast(msg(t));
    });
  },
  "si-log-view": function(el){
    return runScript("logs.sh", ["cat", el.getAttribute("data-v"), "500"], 60000).then(function(t){
      var box = document.getElementById("siLogView");
      if(box) box.textContent = (t && t.trim()) ? t : "(空)";
    });
  }
});

/* ---------- 剪贴板 / 下载（无第三方库） ---------- */
function copyText(t){
  if(!t){ toast("没有可复制的内容"); return; }
  try{
    if(navigator.clipboard && navigator.clipboard.writeText){
      navigator.clipboard.writeText(t).then(function(){ toast("已复制 " + t.length + " 字符"); },
        function(){ legacyCopy(t); });
      return;
    }
  }catch(e){}
  legacyCopy(t);
}
function legacyCopy(t){
  try{
    var ta = document.createElement("textarea");
    ta.value = t; ta.style.position = "fixed"; ta.style.left = "-9999px";
    document.body.appendChild(ta); ta.select();
    document.execCommand("copy");
    document.body.removeChild(ta);
    toast("已复制");
  }catch(e){ toast("复制失败，请手动选择"); }
}
function downloadText(name, t){
  try{
    var blob = new Blob([t], { type: "application/json" });
    var url = URL.createObjectURL(blob);
    var a = document.createElement("a");
    a.href = url; a.download = name;
    document.body.appendChild(a); a.click();
    setTimeout(function(){ document.body.removeChild(a); URL.revokeObjectURL(url); }, 500);
    toast("已下载 " + name);
  }catch(e){ copyText(t); }
}

/* ============================================================
   事件绑定：筛选 / 自动刷新 / 定时器
   ============================================================ */
document.addEventListener("input", function(ev){
  var id = ev.target && ev.target.id;
  if(id === "rpSearch"){ RP.filter = ev.target.value; renderProxyGroups(); }
  else if(id === "rcSearch"){ RC.filter = ev.target.value; renderConns(); }
  else if(id === "rrRuleSearch"){ renderRules(); }
});
document.addEventListener("change", function(ev){
  var id = ev.target && ev.target.id;
  if(id === "rpSort"){ RP.sort = ev.target.value; renderProxyGroups(); }
  else if(id === "rrRuleFilter"){ renderRules(); }
  else if(id === "rlAuto" || id === "rcAuto") syncLiveTimers();
  else if(id === "rlLevel"){ RL.lines = []; rlRender(); }
});

/* 定时器统一管理：只在对应页面可见时跑，避免后台空转烧 CPU */
function syncLiveTimers(){
  var t;
  if(RL.timer){ clearInterval(RL.timer); RL.timer = 0; }
  if(RC.timer){ clearInterval(RC.timer); RC.timer = 0; }
  var rlAuto = document.getElementById("rlAuto");
  if(CUR_TAB === "route-logs" && rlAuto && rlAuto.checked){
    RL.timer = setInterval(function(){ rlPull(); }, LIVE_MS * 3);
  }
  var rcAuto = document.getElementById("rcAuto");
  if(CUR_TAB === "route-conn" && (!rcAuto || rcAuto.checked)){
    RC.timer = setInterval(function(){ loadRouteConn(); }, LIVE_MS);
  }
  t = 0;
}
function tickLive(){
  if(CUR_TAB === "home" || CUR_TAB === "route-home" || CUR_TAB === "route-proxy"){
    loadRouteLive();
  } else if(Date.now() - LAST_STATUS_AT > 20000){
    /* 其它页面只维持顶部状态条，且降频到 20s 一次，避免后台空转 */
    loadRouteLive();
  }
}
