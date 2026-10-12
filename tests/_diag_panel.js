/* 诊断：抓取真实面板在 KernelSU 桩环境下发出的全部命令与其返回，定位 UI 取数断点。
 * 用法: node tests/_diag_panel.js [tab]
 */
"use strict";
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const ROOT = path.dirname(__dirname);
const SRC = path.join(ROOT, "webroot", "index.html");
const TAB = process.argv[2] || "route-home";

const STATUS = { profile: true, profile_size: 18342, config: true, config_size: 4096,
  core: "/data/adb/modules/SY/bin/sing-box", core_version: "1.14.3", core_size: 9843200,
  arch: "arm64-v8a", ruleset_dir: "/data/adb/SY/rules/proxy/rulesets", ruleset_count: 16,
  builtin_dir: "/data/adb/modules/SY/rulesets", running: "yes", pid: "24817",
  mirror: "testingcf", mixed_port: 2080, clash_port: 9090 };

(async () => {
  const browser = await chromium.launch();
  let html = fs.readFileSync(SRC, "utf8");
  const inject = `
window.__LOG = [];
window.ksu = { exec: function(cmd, opts, cbName){
  var name = (typeof opts === "string" && cbName) ? cbName : (typeof opts === "string" ? opts : null);
  window.__LOG.push(String(cmd));
  var out = "";
  try { out = window.__REAL ? window.__REAL(String(cmd)) : ""; } catch(e){ out = "ERR " + e.message; }
  setTimeout(function(){ if(name && typeof window[name] === "function") window[name](0, out, ""); }, 5);
  return "";
}};
window.__REAL = function(cmd){
  var s = String(cmd).replace(/['"]/g, "");
  function has(x){ return s.indexOf(x) >= 0; }
  if(has("route.sh")){
    if(has("status-json")) return JSON.stringify(${JSON.stringify(STATUS)});
    if(has(" summary")) return JSON.stringify({nodes:[{name:"香港 IEPL 01",type:"vmess",server:"hk1.example.net",port:443}],groups:[{name:"PROXY",type:"select",members:["auto","香港 IEPL 01","DIRECT"]},{name:"auto",type:"url-test",members:["香港 IEPL 01"]}],rules:[{line:1,kind:"MATCH",payload:"*",policy:"PROXY",enabled:true}],counts:{nodes:1,groups:2,rules:1,rule_sets:16,errors:0,warnings:0},general:{mixed_port:2080,tun_enabled:true,clash_api:true,clash_api_port:9090,sing_box_version:"1.14.3"},source:"panel"}, null, 2);
    if(has("rulesets")) return JSON.stringify({dir:"/data/adb/modules/SY/rulesets",items:[{name:"geoip-cn.srs",size:34185,from:"builtin"}]});
    if(has(" lint")) return JSON.stringify({rules:1,nodes:1,groups:2,issues:[]});
    if(has(" profile")) return JSON.stringify({nodes:[],groups:[],rules:[]});
    if(has(" dnsprobe")) return JSON.stringify({domain:"www.baidu.com",results:[]});
    if(has(" clash")){
      if(has(" status")) return JSON.stringify({ok:true,version:"1.14.3",mode:"rule",up:184320,down:2841600,conn_count:37,upload_total:184320000,download_total:3419200000,memory:41000000});
      if(has(" proxies")) return JSON.stringify({PROXY:{type:"Selector",now:"香港 IEPL 01",all:["auto","香港 IEPL 01","DIRECT"]},"香港 IEPL 01":{type:"Vmess",history:[{time:"now",delay:38}]}});
      if(has(" conn")) return JSON.stringify({ok:true,connections:[]});
      if(has(" logs")) return JSON.stringify([{type:"info",payload:"hello"}]);
      return "OK: done";
    }
    if(has(" compile")) return "OK: 内核配置已生成";
    if(has(" reload")) return "OK: 配置已重载";
    if(has(" mirrors")) return JSON.stringify([{name:"testingcf",ok:true,millis:298,default:true}]);
    return "OK: 完成";
  }
  if(has("installapp.sh")) return JSON.stringify({bundled:true,installed:true,package:"com.syfusion.manager",version:"1.0.0",size:54677});
  if(has("proxynode.sh")){
    if(has(" status")) return JSON.stringify({running:"yes",pid:"24817",core:"sing-box",nodes:1,selected:"香港 IEPL 01",port:2080});
    if(has(" config-get")) return "{}";
    return "OK: 完成";
  }
  if(has("ctl.sh")) return JSON.stringify({dns:{rule_count:1,blocked_total:1},mitm:{running:"yes"},splash:{skip_total:1},panel:{running:"yes",port:8848},sys:{mem_used_mb:1832,cpu_pct:3.4,uptime:"2 天"}});
  if(has("logs.sh")) return "[]";
  if(has("panel.sh")) return "{}";
  if(has("selfcheck.sh")) return "ok";
  return "OK: 完成";
};
`;
  html = html.replace("</head>", "<script>" + inject + "</script></head>");

  const ctx = await browser.newContext({ viewport: { width: 412, height: 900 }, colorScheme: "dark" });
  const page = await ctx.newPage();
  const errs = [];
  page.on("pageerror", e => errs.push("pageerror: " + e.message));
  page.on("console", m => { if (m.type() === "error") errs.push("console: " + m.text()); });

  await page.setContent(html, { waitUntil: "load" });
  await page.waitForTimeout(600);
  await page.evaluate(t => { window.__LOG.length = 0; return window.switchTab(t); }, TAB);
  await page.waitForTimeout(3000);

  const log = await page.evaluate(() => window.__LOG);
  console.log("=== 标签页 " + TAB + " 发出的命令 (" + log.length + ") ===");
  log.forEach(c => console.log("  " + c.replace(/\s+/g, " ").slice(0, 200)));

  const dump = await page.evaluate(() => {
    const ids = ["rhUp","rhDown","rhConn","rhMem","rhPid","rhGroup","rhNode","rhDelay","rhTun","rhInbound","rhApi","rrSummary","rrProfile","rrGroups","rrSets","rrErrors","rrWarn",
      "hmRun","hmMode","hmNode","hmGroup","hmUp","hmDown","hmConn","hmMem","hmRules","hmRS","hmDelay","hmMix","hmSys","hmUptime","hmCore"];
    const o = {};
    ids.forEach(i => { const e = document.getElementById(i); if (e) o[i] = (e.textContent || "").trim().slice(0, 60); });
    return o;
  });
  console.log("=== 关键字段 ===");
  Object.keys(dump).forEach(k => console.log("  " + k + " = " + JSON.stringify(dump[k])));
  if (errs.length) { console.log("=== 错误 ==="); errs.slice(0, 10).forEach(e => console.log("  " + e)); }
  await browser.close();
})();
