/* 用真实 Chromium 渲染「线上真实面板」webroot/index.html 并逐页截图。
 *
 * 与 ui_screenshot.js 的区别：
 *   ui_screenshot.js 拍的是 ui-preview.html（静态样板），
 *   这里拍的是要真的发给用户的 webroot/index.html，
 *   并且把 KernelSU 桥接注入成假数据，让极客控制台各页都渲染出内容。
 *
 * 用法: node tests/ui_shot_panel.js [输出目录]
 */
"use strict";
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const ROOT = path.dirname(__dirname);
const SRC = path.join(ROOT, "webroot", "index.html");
const OUT = process.argv[2] || path.join(ROOT, "shots");
if (!fs.existsSync(OUT)) fs.mkdirSync(OUT, { recursive: true });

/* ---------- 假数据 ---------- */
const STATUS = {
  profile: true, profile_size: 18342, config: true, config_size: 4096,
  core: "/data/adb/modules/SY/bin/sing-box", core_version: "1.14.3", core_size: 9843200,
  arch: "arm64-v8a", ruleset_dir: "/data/adb/SY/rules/proxy/rulesets", ruleset_count: 16,
  builtin_dir: "/data/adb/modules/SY/rulesets", running: "yes", pid: "24817",
  mirror: "testingcf", mixed_port: 2080, clash_port: 9090
};
const SUMMARY = {
  nodes: [
    { name: "香港 IEPL 01", type: "vmess", server: "hk1.example.net", port: 443 },
    { name: "日本 软银", type: "trojan", server: "jp1.example.net", port: 8443 },
    { name: "新加坡 直连", type: "shadowsocks", server: "sg1.example.net", port: 8388 },
    { name: "美国 CN2 GIA", type: "vless", server: "us1.example.net", port: 443 }
  ],
  groups: [
    { name: "PROXY", type: "select", members: ["auto", "香港 IEPL 01", "日本 软银", "DIRECT"] },
    { name: "auto", type: "url-test", members: ["香港 IEPL 01", "日本 软银", "新加坡 直连"] }
  ],
  rules: [
    { line: 1, kind: "GEOSITE", payload: "category-ads-all", policy: "REJECT", enabled: true },
    { line: 2, kind: "DOMAIN-SUFFIX", payload: "openai.com", policy: "PROXY", enabled: true },
    { line: 3, kind: "DOMAIN-KEYWORD", payload: "track", policy: "REJECT", enabled: true },
    { line: 4, kind: "GEOSITE", payload: "private", policy: "DIRECT", enabled: true },
    { line: 5, kind: "GEOSITE", payload: "cn", policy: "DIRECT", enabled: true },
    { line: 6, kind: "GEOIP", payload: "cn", policy: "DIRECT", enabled: true },
    { line: 7, kind: "IP-CIDR", payload: "10.0.0.0/8", policy: "DIRECT", enabled: true },
    { line: 8, kind: "DST-PORT", payload: "8080", policy: "DIRECT", enabled: true },
    { line: 9, kind: "PROCESS-NAME", payload: "com.tencent.mm", policy: "DIRECT", enabled: true },
    { line: 10, kind: "MATCH", payload: "*", policy: "PROXY", enabled: true }
  ],
  counts: { nodes: 4, groups: 2, rules: 10, rule_sets: 16, errors: 0, warnings: 1 },
  node_types: { vmess: 1, trojan: 1, shadowsocks: 1, vless: 1 },
  general: {
    log_level: "warn", mixed_port: 2080, tun_enabled: true, tun_stack: "mixed",
    strict_route: true, clash_api: true, clash_api_port: 9090, sing_box_version: "1.14.3"
  },
  source: "panel"
};
const RULESETS = {
  dir: "/data/adb/modules/SY/rulesets",
  builtin: "/data/adb/modules/SY/rulesets",
  items: [
    { name: "geoip-cn.srs", size: 34185, from: "builtin" },
    { name: "geosite-category-ads-all.srs", size: 8121, from: "builtin" },
    { name: "geosite-cn.srs", size: 56189, from: "builtin" },
    { name: "geosite-geolocation-!cn.srs", size: 168357, from: "builtin" },
    { name: "geosite-google.srs", size: 22140, from: "builtin" },
    { name: "geosite-openai.srs", size: 4210, from: "builtin" },
    { name: "geosite-private.srs", size: 980, from: "builtin" },
    { name: "geosite-telegram.srs", size: 15320, from: "builtin" },
    { name: "geosite-youtube.srs", size: 11240, from: "builtin" }
  ]
};
const PROFILE = {
  nodes: SUMMARY.nodes,
  groups: SUMMARY.groups,
  rules: SUMMARY.rules,
  rule_sets: [],
  dns: {
    enabled: true,
    servers: [
      { tag: "local", address: "223.5.5.5" },
      { tag: "cn-doh", address: "https://dns.alidns.com/dns-query" },
      { tag: "remote", address: "https://1.1.1.1/dns-query", detour: "proxy" }
    ],
    final: "cn-doh", strategy: "prefer_ipv4", fake_ip: false,
    rules: [
      { kind: "GEOSITE", payload: "geolocation-!cn", policy: "remote", enabled: true },
      { kind: "GEOSITE", payload: "cn", policy: "cn-doh", enabled: true }
    ]
  },
  general: SUMMARY.general
};
const LINT = {
  rules: 10, nodes: 4, groups: 2,
  issues: [
    { level: "warn", line: 3, rule: "DOMAIN-KEYWORD,track,REJECT", code: "broad-keyword", msg: "关键词过宽，可能误伤正常域名" },
    { level: "info", line: 8, rule: "DST-PORT,8080,DIRECT", code: "port-only", msg: "仅按端口分流，建议配合域名规则" },
    { level: "warn", code: "no-fallback-note", msg: "第 10 行为 MATCH 兜底，其后规则不会生效" }
  ]
};
const DIAG = {
  matched: true, policy: "PROXY", rule_line: 2, rule_raw: "DOMAIN-SUFFIX,openai.com,PROXY",
  final: "PROXY",
  steps: [
    { line: 1, rule: "GEOSITE,category-ads-all,REJECT", matched: false, detail: "域名不在规则集内" },
    { line: 2, rule: "DOMAIN-SUFFIX,openai.com,PROXY", matched: true, detail: "后缀命中 openai.com" }
  ],
  notes: []
};
const CLASH_STATUS = {
  ok: true, version: "1.14.3", mode: "rule", up: 184320, down: 2841600,
  conn_count: 37, upload_total: 184320000, download_total: 3419200000, memory: 41_000_000
};
const PROXIES = (() => {
  const px = {};
  const lat = { "香港 IEPL 01": 38, "日本 软银": 96, "新加坡 直连": 214, "美国 CN2 GIA": 486, "DIRECT": 0 };
  Object.keys(lat).forEach((n, i) => {
    px[n] = { type: i === 4 ? "Direct" : "Vmess", now: "", all: [], udp: true, alive: true,
      history: [{ time: "now", delay: lat[n] }] };
  });
  px["PROXY"] = { type: "Selector", now: "香港 IEPL 01", all: ["auto", "香港 IEPL 01", "日本 软银", "新加坡 直连", "美国 CN2 GIA", "DIRECT"], udp: true };
  px["auto"] = { type: "URLTest", now: "香港 IEPL 01", all: ["香港 IEPL 01", "日本 软银", "新加坡 直连"], udp: true };
  return px;
})();
const CONNS = {
  ok: true, upload_total: 184320000, download_total: 3419200000, memory: 41000000,
  connections: [
    { id: "c1", upload: 12040, download: 1843200, start: "", chains: ["PROXY", "香港 IEPL 01"], rule: "GEOSITE", rulePayload: "geolocation-!cn",
      metadata: { network: "tcp", type: "HTTPS", host: "www.youtube.com", destinationIP: "142.250.66.110", destinationPort: "443", sourcePort: "41022", process: "com.google.android.youtube", sniffHost: "www.youtube.com" } },
    { id: "c2", upload: 3020, download: 924100, start: "", chains: ["PROXY", "香港 IEPL 01"], rule: "DOMAIN-SUFFIX", rulePayload: "openai.com",
      metadata: { network: "tcp", type: "HTTPS", host: "chat.openai.com", destinationIP: "104.18.12.123", destinationPort: "443", process: "com.openai.chatgpt" } },
    { id: "c3", upload: 820, download: 62400, start: "", chains: ["DIRECT"], rule: "GEOSITE", rulePayload: "cn",
      metadata: { network: "tcp", type: "HTTP", host: "upos-sz-mirrorcos.bilivideo.com", destinationIP: "118.89.200.1", destinationPort: "80", process: "tv.danmaku.bili" } },
    { id: "c4", upload: 310, download: 0, start: "", chains: ["REJECT"], rule: "GEOSITE", rulePayload: "category-ads-all",
      metadata: { network: "tcp", type: "HTTPS", host: "ad.doubleclick.net", destinationIP: "142.250.1.1", destinationPort: "443", process: "com.tencent.mm" } },
    { id: "c5", upload: 15400, download: 402110, start: "", chains: ["PROXY", "日本 软银"], rule: "MATCH", rulePayload: "",
      metadata: { network: "udp", type: "QUIC", host: "cdn.jsdelivr.net", destinationIP: "151.101.1.229", destinationPort: "443", process: "org.mozilla.firefox" } }
  ]
};
const LOGS = [
  { type: "info", payload: "[24817] inbound/mixed[0]: inbound connection from 127.0.0.1:41230" },
  { type: "info", payload: "[24817] outbound/vmess[香港 IEPL 01]: outbound connection to www.youtube.com:443" },
  { type: "info", payload: "[24817] router: match[2] geosite-cn => direct" },
  { type: "warning", payload: "[24817] dns: lookup failed for ad.doubleclick.net: context deadline exceeded" },
  { type: "info", payload: "[24817] router: match[1] geosite-category-ads-all => reject" },
  { type: "error", payload: "[24817] outbound/vmess[美国 CN2 GIA]: connection reset by peer" },
  { type: "debug", payload: "[24817] dns: cached A www.baidu.com -> 39.156.70.239" }
];
const DNSPROBE = {
  domain: "www.baidu.com",
  results: [
    { server: "223.5.5.5", kind: "udp", ok: true, millis: 29, answers: ["39.156.70.239", "39.156.70.46"] },
    { server: "119.29.29.29", kind: "udp", ok: true, millis: 31, answers: ["39.156.70.46"] },
    { server: "180.76.76.76", kind: "udp", ok: true, millis: 33, answers: ["39.156.70.239"] },
    { server: "114.114.114.114", kind: "udp", ok: true, millis: 29, answers: ["39.156.70.239"] },
    { server: "1.1.1.1", kind: "udp", ok: true, millis: 206, answers: ["103.235.47.188"] },
    { server: "8.8.8.8", kind: "udp", ok: true, millis: 61, answers: ["103.235.46.96"] },
    { server: "https://dns.alidns.com/dns-query", kind: "doh", ok: true, millis: 164, answers: ["39.156.70.46"] },
    { server: "https://1.1.1.1/dns-query", kind: "doh", ok: false, millis: 0, error: "dial tcp 1.1.1.1:443: i/o timeout" },
    { server: "tls://dns.google:853", kind: "dot", ok: false, millis: 0, error: "dial tcp 8.8.4.4:853: i/o timeout" }
  ]
};
const CTL = { dns: { rule_count: 184320, blocked_total: 27410 }, mitm: { running: "yes" }, splash: { skip_total: 128 }, panel: { running: "yes", port: 8848, lan_ip: "192.168.1.23" }, sys: { mem_used_mb: 1832, cpu_pct: 3.4, uptime: "2 天 06:41" } };
const LOGLIST = [
  { name: "action.log", mtime: "2026-10-12 17:41", size: 184320 },
  { name: "proxy.log", mtime: "2026-10-12 17:44", size: 41280 },
  { name: "dns.log", mtime: "2026-10-12 17:45", size: 98304 }
];
const APPST = { bundled: true, installed: true, package: "com.syfusion.manager", version: "1.0.0 (1)", size: 54677, sha256: "9f2c4a7b18de3f5061728394a5b6c7d8e9f0a1b2c3d4e5f60718293a4b5c6d7e" };

/* ---------- KernelSU 桥接桩 ---------- */
const KSU_STUB = `
window.ksu = {
  exec: function(cmd, opts, cbName){
    var name = (typeof opts === "string" && cbName) ? cbName : (typeof opts === "string" ? opts : null);
    var out = __syStub(cmd);
    setTimeout(function(){
      if(name && typeof window[name] === "function") window[name](0, out, "");
    }, 8);
    return "";
  }
};
`;

function makeStubScript() {
  return `
function __syStub(cmd){
  // 面板的 runScript 会把参数包上单引号（route.sh 'status-json'），
  // 因此先剥掉引号再做子串匹配，否则 ' summary' 这类带前导空格的判定会失效。
  var s = String(cmd).replace(/['"]/g, "");
  function has(x){ return s.indexOf(x) >= 0; }
  if(has("route.sh")){
    if(has("status-json")) return JSON.stringify(${JSON.stringify(STATUS)});
    if(has(" summary")) return JSON.stringify(${JSON.stringify(SUMMARY)}, null, 2);
    if(has("rulesets")) return JSON.stringify(${JSON.stringify(RULESETS)}, null, 2);
    if(has(" profile")) return JSON.stringify(${JSON.stringify(PROFILE)}, null, 2);
    if(has(" lint")) return JSON.stringify(${JSON.stringify(LINT)}, null, 2);
    if(has(" dnsprobe")) return JSON.stringify(${JSON.stringify(DNSPROBE)}, null, 2);
    if(has(" test")) return JSON.stringify(${JSON.stringify(DIAG)}, null, 2);
    if(has(" clash")){
      if(has(" status")) return JSON.stringify(${JSON.stringify(CLASH_STATUS)});
      if(has(" proxies")) return JSON.stringify(${JSON.stringify(PROXIES)});
      if(has(" conn")) return JSON.stringify(${JSON.stringify(CONNS)});
      if(has(" logs")) return JSON.stringify(${JSON.stringify(LOGS)});
      if(has(" delay")) return JSON.stringify({ name: "香港 IEPL 01", delay: 41 });
      return "OK: done";
    }
    if(has(" compile")) return "OK: 内核配置已生成";
    if(has(" reload")) return "OK: 配置已重载";
    if(has(" mirrors")) return JSON.stringify([
      {name:"testingcf",url:"https://testingcf.jsdelivr.net/gh/SagerNet/sing-geosite@rule-set/geosite-cn.srs",ok:true,millis:298,size:56189,default:true},
      {name:"fastly",url:"https://fastly.jsdelivr.net/gh/SagerNet/sing-geosite@rule-set/geosite-cn.srs",ok:true,millis:874,size:56189},
      {name:"ghproxy",url:"https://gh-proxy.com/https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs",ok:true,millis:1052,size:56189},
      {name:"jsdelivr",url:"https://cdn.jsdelivr.net/gh/SagerNet/sing-geosite@rule-set/geosite-cn.srs",ok:false,millis:12000,error:"timeout"}
    ]);
    return "OK: 完成";
  }
  if(has("installapp.sh")){
    if(has(" status")) return JSON.stringify(${JSON.stringify(APPST)});
    if(has(" install")) return "OK: 内置 App 已安装（pm install 会话式）";
    if(has(" launch")) return "OK: 已拉起 com.syfusion.manager";
    return "OK: 完成";
  }
  if(has("proxynode.sh")){
    if(has(" status")) return JSON.stringify({running:"yes",pid:"24817",core:"sing-box",nodes:4,selected:"香港 IEPL 01",port:2080,subs:2,config:"yes"});
    if(has(" config-get")) return JSON.stringify({log:{level:"warn"},inbounds:[{type:"mixed",listen:"127.0.0.1",listen_port:2080}],outbounds:[{type:"selector",tag:"PROXY"}],route:{rules:[{action:"sniff"}]}}, null, 2);
    if(has(" logs")) return "[24817] router: match[2] geosite-cn => direct";
    return "OK: 完成";
  }
  if(has("ctl.sh")){
    if(has(" status")) return JSON.stringify(${JSON.stringify(CTL)});
    return "OK: 完成";
  }
  if(has("logs.sh")){
    if(has(" list")) return JSON.stringify(${JSON.stringify(LOGLIST)});
    if(has(" cat")) return "[2026-10-12 17:44:02] route compile: OK 目标内核 1.14.3，规则 10 条\\n[2026-10-12 17:44:02] proxy up: pid=24817 port=2080";
    return "OK: 完成";
  }
  if(has("panel.sh")){
    if(has(" url")) return "http://192.168.1.23:8848/?token=demo";
    if(has(" status")) return JSON.stringify({running:"yes",port:8848,lan_ip:"192.168.1.23"});
    return "OK: 完成";
  }
  if(has("selfcheck.sh")) return "== SY-Fusion 自检 ==\\n  [ok] 内核可执行\\n  [ok] 规则集完整 (16 个)\\n  [ok] 内置 App 已安装\\n  [ok] 面板服务运行中\\n全部通过";
  if(has("backup.sh")) return "OK: 诊断包已导出 /data/adb/SY/backup/diag-20261012.zip";
  if(has("dns.sh")) return "OK: 完成";
  return "OK: 完成";
}
`;
}

const PAGES = [
  ["home", "总览"],
  ["route-home", "代理总览"],
  ["route-proxy", "策略组与节点"],
  ["route-conn", "实时连接"],
  ["route-rules", "规则与分流"],
  ["route-dns", "DNS 与查询"],
  ["route-logs", "内核日志"],
  ["route-core", "内核与配置"],
  ["app", "内置管理器 App"],
  ["sysinfo", "系统与日志"],
  ["dns", "DNS 拦截列表"],
  ["mitm", "加密过滤"]
];

(async () => {
  const browser = await chromium.launch();
  const errs = [];
  let html = fs.readFileSync(SRC, "utf8");
  // 在主题脚本之后、主脚本之前注入桩
  html = html.replace("</head>", "<script>" + KSU_STUB + makeStubScript() + "</script></head>");

  const ctx = await browser.newContext({
    viewport: { width: 412, height: 900 },
    deviceScaleFactor: 2,
    colorScheme: "dark"
  });
  const page = await ctx.newPage();
  page.on("pageerror", e => errs.push("pageerror: " + e.message));
  page.on("console", m => { if (m.type() === "error") errs.push("console: " + m.text()); });

  await page.setContent(html, { waitUntil: "load" });
  await page.waitForTimeout(900);

  for (const [tab, label] of PAGES) {
    await page.evaluate(t => window.switchTab(t), tab);
    await page.waitForTimeout(650);
    const file = path.join(OUT, "panel-" + tab + ".png");
    await page.screenshot({ path: file, fullPage: true });
    console.log("  拍下 " + label + " -> " + path.basename(file));
  }

  // 桌面宽度整屏（验证响应式栅格）
  const wide = await ctx.newPage();
  await wide.setViewportSize({ width: 1280, height: 1400 });
  await wide.setContent(html, { waitUntil: "load" });
  await wide.waitForTimeout(900);
  await wide.evaluate(() => window.switchTab("route-home"));
  await wide.waitForTimeout(700);
  await wide.screenshot({ path: path.join(OUT, "panel-wide-route-home.png") });
  console.log("  拍下 桌面宽度 -> panel-wide-route-home.png");

  await browser.close();

  if (errs.length) {
    console.log("\n  渲染期错误 " + errs.length + " 条:");
    errs.slice(0, 10).forEach(e => console.log("   - " + e));
    process.exit(1);
  }
  console.log("\n  OK: 面板逐页渲染无 JS 错误");
})();
