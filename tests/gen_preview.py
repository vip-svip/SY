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

appbar = grab(s, '<div class="appbar">', "div")
tabs = grab(s, '<div class="tabs" id="tabs">', "div")

home = grab(s, '<section class="page" id="page-home">', "section")
engine = grab(s, '<section class="page hide" id="page-engine">', "section")
engine = engine.replace('class="page hide"', 'class="page"', 1)

# 去掉内嵌的“运行日志”大文本框与长日志列表（预览用示例数据填充）
log_list = """<div class="list" id="logList">
        <div class="row"><span class="mono">dns.log</span><span class="tag">2.1 KB</span>
          <button class="btn small" data-act="logs-view">查看</button></div>
        <div class="row"><span class="mono">mitm.log</span><span class="tag">18.4 KB</span>
          <button class="btn small" data-act="logs-view">查看</button></div>
        <div class="row"><span class="mono">proxy.log</span><span class="tag">512 B</span>
          <button class="btn small" data-act="logs-view">查看</button></div>
      </div>"""
home = re.sub(r'<div class="list" id="logList"></div>', log_list, home)

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
<title>SY · 玻璃磨砂面板预览</title>
<style>
%s
</style>
</head>
<body>
%s
<div class="wrap">
%s
%s
%s
</div>
<script>
(function(){
  function $(s){return document.querySelector(s)}
  function set(id,v){var e=document.getElementById(id); if(e) e.textContent=v;}
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
  document.querySelectorAll('.tab').forEach(function(t){
    t.addEventListener('click', function(){
      document.querySelectorAll('.tab').forEach(function(x){x.classList.remove('on')});
      t.classList.add('on');
      var name = t.getAttribute('data-tab');
      document.querySelectorAll('.page').forEach(function(p){
        p.classList.toggle('hide', p.id !== 'page-'+name);
      });
    });
  });
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
<div class="toast" id="toast"></div>
</body>
</html>
""" % (style, appbar, tabs, home, engine, fill_js, repr(TEST_HTML))

io.open(OUT, "w", encoding="utf-8", newline="\n").write(html)
print("written %s (%d chars)" % (OUT, len(html)))
