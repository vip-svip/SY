# -*- coding: utf-8 -*-
"""从 webroot/index.html 生成玻璃磨砂面板静态预览 ui-preview.html

用法: python tests/gen_preview.py
"""
import io, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "webroot", "index.html")
OUT = os.path.join(ROOT, "ui-preview.html")

s = io.open(SRC, encoding="utf-8").read()


def balanced(text, start_idx, tag):
    """从 start_idx（'<tag' 起始）返回配平的整段，含结束标签。"""
    open_re = re.compile(r"<%s\b" % tag, re.I)
    close_re = re.compile(r"</%s\s*>" % tag, re.I)
    depth = 0
    i = start_idx
    while i < len(text):
        mo = open_re.search(text, i)
        mc = close_re.search(text, i)
        if mc and (not mo or mc.start() < mo.start()):
            depth -= 1
            i = mc.end()
            if depth == 0:
                return text[start_idx:i]
            continue
        if mo:
            depth += 1
            i = mo.end()
            continue
        break
    return text[start_idx:]


def grab(text, marker, tag):
    p = text.index(marker)
    return balanced(text, p, tag)


style = s[s.index("<style>") + 7 : s.index("</style>")]

# 新骨架：<header class="header"> 内含 <nav class="nav-tabs" id="tabs">
header = grab(s, '<header class="header">', "header")
home = grab(s, '<section class="page" id="page-home">', "section")
dns = grab(s, '<section class="page hide" id="page-dns">', "section")
engine = grab(s, '<section class="page hide" id="page-engine">', "section")
# 预览里 dns / engine 保持 hide，靠导航点击切换（与真实面板行为一致）

# 去掉内嵌的“运行日志”大文本框与长日志列表（预览用示例数据填充）
log_list = """<div class="list" id="logList">
        <div class="row"><span class="mono">dns.log</span><span class="tagline">2.1 KB</span>
          <button class="btn sm" data-act="logs-view">查看</button></div>
        <div class="row"><span class="mono">mitm.log</span><span class="tagline">18.4 KB</span>
          <button class="btn sm" data-act="logs-view">查看</button></div>
        <div class="row"><span class="mono">proxy.log</span><span class="tagline">512 B</span>
          <button class="btn sm" data-act="logs-view">查看</button></div>
      </div>"""
home = re.sub(r'<div class="list" id="logList"></div>', log_list, home)

# DNS 页的规则源列表填示例数据
repo_list = """<div class="list" id="ruleRepoList">
        <div class="row"><span class="t">vip-svip/SY-Rules <span class="tagline">AdGuard + uBO 融合规则</span></span>
          <button class="btn sm primary" data-act="rule-use">选用</button></div>
        <div class="row"><span class="t">AdguardTeam/AdGuardSDNSFilter <span class="tagline">官方 DNS 过滤</span></span>
          <button class="btn sm" data-act="rule-use">选用</button></div>
      </div>"""
dns = re.sub(r'<div class="list" id="ruleRepoList"></div>', repo_list, dns)

dns = re.sub(
    r'<div class="list" id="dnsPreview"></div>',
    '<div class="list" id="dnsPreview">'
    '<div class="row"><span class="mono">doubleclick.net</span>'
    '<button class="del" data-act="dns-rule-del">✕</button></div>'
    '<div class="row"><span class="mono">ads.example.com</span>'
    '<button class="del" data-act="dns-rule-del">✕</button></div>'
    '<div class="row"><span class="mono">track.example.org</span>'
    '<button class="del" data-act="dns-rule-del">✕</button></div>'
    '<div class="row"><span class="mono">pagead2.googlesyndication.com</span>'
    '<button class="del" data-act="dns-rule-del">✕</button></div>'
    '</div>', dns)

for lid, rows in (
    ("wlList", [("example.com", "wl-del"), ("bank.example.cn", "wl-del")]),
    ("blList", [("ads.example.com", "bl-del"), ("ad.doubleclick.net", "bl-del")]),
    ("dnsCustomList", [("my-own-rule.example.com", "dns-custom-del")]),
    ("srcList", [("https://example.com/ag-rules.txt", "dns-src-del")]),
    ("fltList", [("AdGuard Base", "lists-del")]),
):
    html_rows = "".join(
        '<div class="row"><span class="mono">%s</span>'
        '<button class="del" data-act="%s">✕</button></div>' % (t, a) for t, a in rows)
    dns = re.sub(r'<div class="list" id="%s"></div>' % lid,
                 '<div class="list" id="%s">%s</div>' % (lid, html_rows), dns)

chips = """<div class="chips" id="engSyntax">
        <span class="chip">adblock <b>31842</b></span>
        <span class="chip">modifiers <b>9157</b></span>
        <span class="chip">元素隐藏 <b>8420</b></span>
        <span class="chip">脚本注入 <b>1265</b></span>
        <span class="chip">CSS 注入 <b>412</b></span>
        <span class="chip">扩展 CSS <b>286</b></span>
        <span class="chip">HTML 过滤 <b>174</b></span>
        <span class="chip">JS 注入 <b>63</b></span>
        <span class="chip">hosts <b>51204</b></span>
        <span class="chip">dnsmasq <b>980</b></span>
        <span class="chip">正则 <b>221</b></span>
        <span class="chip">DNS 重写 <b>37</b></span>
        <span class="chip">纯域名 <b>18660</b></span>
      </div>"""
engine = re.sub(r'<div class="chips" id="engSyntax">.*?</div>\s*</div>',
                chips, engine, count=1, flags=re.S)

VALUES = {
    "sysline": "内核运行中 · AdGuard Home 融合引擎 v1.0.0",
    "ovTime": "更新于 12:36:45",
    "ovDns": "51,204",
    "ovBlocked": "1,284,930",
    "ovMitm": "运行中",
    "ovSplash": "376",
    "ovMem": "42.6 MB",
    "ovCpu": "1.8%",
    "ovUp": "3 天 07:12",
    "ovPanel": "运行中",
    "pnRun": "运行中",
    "pnPort": "8080",
    "pnUrl": "http://192.168.1.23:8080",
    "logView": "$ tail -n 3 dns.log\n[12:36:41] query ads.doubleclick.net -> BLOCKED (||doubleclick.net^)\n"
               "[12:36:42] query cdn.example.com -> PASS\n"
               "[12:36:44] engine reloaded: 68,711 rules",
    "engBlock": "58,132",
    "engBlockImp": "1,204",
    "engAllow": "486",
    "engAllowImp": "39",
    "engRegex": "221",
    "engRewrite": "37",
    "engCosmetic": "8,420 / 1,860",
    "engScriptlet": "1,265",
    "engHosts": "51,204 行",
    "engRecords": "68,711",
    "engPattern": "3,082",
    "engLists": "14 张规则表",
    "engVRecords": "68,711",
    "engVInvalid": "42",
    "engVBadf": "118",
    "engVRedB": "0",
    "engVRedA": "0",
    "engVConf": "1",
    "hostsMount": "已挂载",
    "hostsCount": "51,204",
    "hostsMode": "订阅 + 自定义",
    "hostsTag": "更新于 12:36:45 · 共 51,204 条",
    "fltBlock": "58,132",
    "fltBlockImp": "1,204",
    "fltAllow": "486",
    "fltAllowImp": "39",
    "fltReRw": "221 / 37",
    "fltTestOut": "ads.example.com → 拦截（命中 ||ads.example.com^）",
    "dnsPreviewInfo": "当前生效规则 51,204 条（含 3 条排除）",
    "dnsCustomText": "my-own-rule.example.com",
    "hostsText": "0.0.0.0 ads.example.com\n0.0.0.0 ad.doubleclick.net",
    "myRulesText": "||ads.example.com^\n@@||good.example.com^\n||track.com^$important",
}

TEST_HTML = (
    '<span class="mono">域名: ads.doubleclick.net</span><br>'
    '<b>结果: 拦截</b> &nbsp; 优先级: important-block<br>'
    '<span class="mono">命中规则: ||doubleclick.net^$important</span><br>'
    '<span class="mono">修饰符: important</span>'
    '<br><span class="mono">浏览器侧规则: 3 条（H:.ad-banner | S:set-constant, adFlag, false | …）</span>'
)

fill_lines = []
for k, v in VALUES.items():
    fill_lines.append("  set(%s, %s);" % (repr(k), repr(v)))
fill_js = "\n".join(fill_lines)

html = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>SY · AdGuard Home 融合面板预览</title>
<style>
%s
</style>
</head>
<body>
%s
<div class="container">
%s
%s
%s
</div>
<script>
(function(){
  function $(s){return document.querySelector(s)}
  function set(id,v){
    var e=document.getElementById(id); if(!e) return;
    if(e.tagName==='INPUT'||e.tagName==='TEXTAREA') e.value=v; else e.textContent=v;
  }
  function esc(s){return String(s).replace(/[&<>]/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;'}[c]})}

%s

  var to = document.getElementById('engTestOut');
  if(to){ to.innerHTML = %s; to.style.display=''; to.className='alert ok'; }

  document.querySelectorAll('[data-act="theme"]').forEach(function(b){
    b.addEventListener('click', function(){
      var el=document.documentElement;
      if(el.classList.contains('theme-dark')){ el.classList.remove('theme-dark'); el.classList.add('theme-light'); }
      else { el.classList.remove('theme-light'); el.classList.add('theme-dark'); }
    });
  });
  /* 顶部导航：下拉开合 + 页面切换 */
  function closeDD(){ document.querySelectorAll('.dropdown-menu.open').forEach(function(m){m.classList.remove('open')}); }
  function openDD(dd, menu){
    if(!menu) return;
    var host = dd.parentNode;
    menu.style.left='0'; menu.style.right='auto';
    menu.classList.add('open');
    var vw = document.documentElement.clientWidth;
    var w = menu.offsetWidth;
    var hr = host.getBoundingClientRect();
    var left = hr.left;
    if(left + w > vw - 8) left = vw - 8 - w;
    if(left < 8) left = 8;
    menu.style.left = (left - hr.left) + 'px';
  }
  document.getElementById('tabs').addEventListener('click', function(ev){
    var dd = ev.target.closest('.nav-link[data-dd]');
    if(dd){
      var menu = dd.parentNode.querySelector('.dropdown-menu');
      var was = !!(menu && menu.classList.contains('open'));
      closeDD();
      if(menu && !was) openDD(dd, menu);
      ev.preventDefault();
      return;
    }
    var t = ev.target.closest('[data-tab]');
    if(!t) return;
    document.querySelectorAll('[data-tab]').forEach(function(x){x.classList.remove('on')});
    t.classList.add('on');
    document.querySelectorAll('.nav-link[data-dd]').forEach(function(p){
      var m = p.parentNode.querySelector('.dropdown-menu');
      var hit = false;
      if(m) m.querySelectorAll('[data-tab]').forEach(function(x){
        if(x.getAttribute('data-tab')===t.getAttribute('data-tab')) hit = true;
      });
      p.classList.toggle('on', hit);
    });
    closeDD();
    var name = t.getAttribute('data-tab');
    document.querySelectorAll('.page').forEach(function(p){
      p.classList.toggle('hide', p.id !== 'page-'+name);
    });
  });
  document.addEventListener('click', function(ev){
    if(ev.target.closest('.nav-tabs')) return;
    closeDD();
  });
  window.addEventListener('resize', closeDD);
  document.querySelectorAll('[data-act]').forEach(function(b){
    var a = b.getAttribute('data-act');
    if(a==='theme') return;
    b.addEventListener('click', function(){
      var el=$('#toast'); if(el){ el.textContent='预览模式：按钮 '+a+' 不产生实际动作'; el.classList.add('show');
        clearTimeout(el._t); el._t=setTimeout(function(){el.classList.remove('show')},2200); }
    });
  });
})();
</script>
<div id="toast"></div>
</body>
</html>
""" % (style, header, home, dns, engine, fill_js, repr(TEST_HTML))

io.open(OUT, "w", encoding="utf-8", newline="\n").write(html)
print("written %s (%d chars)" % (OUT, len(html)))
