#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
patch_ui.py — 把极客控制台的 CSS / 导航 / 页面 / JS 拼进 webroot/index.html

做成脚本而不是手改，是为了这次以及以后每次改版都能一键复现，
避免在 2500 行的单文件里反复肉眼定位。
"""
import io
import os
import re
import sys

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(BASE, "tools")
TARGET = os.path.join(BASE, "webroot", "index.html")


def read(p):
    with io.open(p, "r", encoding="utf-8", newline="") as f:
        return f.read()


def write(p, s):
    with io.open(p, "w", encoding="utf-8", newline="") as f:
        f.write(s)


def cut(s, start_marker, end_marker, replacement, label):
    """用起止标记替换一段文本（end_marker 保留）"""
    i = s.find(start_marker)
    if i < 0:
        raise SystemExit("找不到起始标记 [%s]: %s" % (label, start_marker[:60]))
    j = s.find(end_marker, i)
    if j < 0:
        raise SystemExit("找不到结束标记 [%s]: %s" % (label, end_marker[:60]))
    return s[:i] + replacement + s[j:]


def main():
    html = read(TARGET)
    css = read(os.path.join(TOOLS, "_ui_css.html")).rstrip()
    # cut() 会保留结束标记 </style>，这里把自带的那个去掉，避免出现两个
    if css.endswith("</style>"):
        css = css[: -len("</style>")].rstrip()
    css += "\n"
    nav = read(os.path.join(TOOLS, "_ui_nav.html")).rstrip() + "\n"
    secs = read(os.path.join(TOOLS, "_ui_sections.html")).rstrip() + "\n"
    js = read(os.path.join(TOOLS, "_ui_js.js")).rstrip() + "\n"

    orig_len = len(html)

    # ---- 1) 样式表整体替换 ----
    html = cut(html, "<style>", "</style>", css, "css")

    # ---- 2) 顶部导航替换 ----
    html = cut(html, '    <nav class="nav-tabs" id="tabs">', "    </nav>\n", nav, "nav")

    # ---- 3) 总览页替换 + 新增页面 ----
    html = cut(
        html,
        "  <!-- ================= 仪表盘 ================= -->",
        "  <!-- ================= DNS 拦截列表 ================= -->",
        secs,
        "sections",
    )

    # ---- 4) ksuExec 支持自定义超时 ----
    html = html.replace(
        "function ksuExec(cmdStr){\n  return new Promise(function(resolve){",
        "function ksuExec(cmdStr,timeoutMs){\n  return new Promise(function(resolve){",
        1,
    )
    html = html.replace(
        'var timer=setTimeout(function(){ fin(-1,"","timeout"); },30000);',
        'var timer=setTimeout(function(){ fin(-1,"","timeout"); },timeoutMs||30000);',
        1,
    )

    # ---- 5) runScript 透传超时 ----
    html = html.replace(
        "function runScript(name,args){\n  args=args||[];",
        "function runScript(name,args,timeoutMs){\n  args=args||[];",
        1,
    )
    html = html.replace(
        "    return ksuExec(cmd).then(function(res){",
        "    return ksuExec(cmd,timeoutMs).then(function(res){",
        1,
    )

    # ---- 6) loadTab 增加新页面 ----
    old_loadtab = '    case "settings": return loadSettings();\n  }\n}'
    new_loadtab = (
        '    case "settings": return loadSettings();\n'
        '    /* ---- 极客控制台 ---- */\n'
        '    case "route-home":  return loadRouteHome();\n'
        '    case "route-proxy": return loadRouteProxy();\n'
        '    case "route-conn":  return loadRouteConn();\n'
        '    case "route-rules": return loadRouteRules();\n'
        '    case "route-dns":   return rdLoad();\n'
        '    case "route-logs":  return rlPull();\n'
        '    case "route-core":  return loadRouteCore();\n'
        '    case "app":         return loadApp();\n'
        '    case "sysinfo":     return Promise.all([loadSysInfo(), siLoadLogs()]);\n'
        '  }\n}'
    )
    if old_loadtab not in html:
        raise SystemExit("loadTab 锚点未找到")
    html = html.replace(old_loadtab, new_loadtab, 1)

    # ---- 7) switchTab 记录当前页并同步定时器 ----
    old_sw = '  syncNavParent(tab);\n  closeDropdowns();\n  loadTab(tab)'
    new_sw = '  syncNavParent(tab);\n  closeDropdowns();\n  CUR_TAB = tab;\n  syncLiveTimers();\n  loadTab(tab)'
    if old_sw not in html:
        raise SystemExit("switchTab 锚点未找到")
    html = html.replace(old_sw, new_sw, 1)

    # ---- 8) 注入极客控制台 JS（放在 actions 表之后、点击代理之前） ----
    anchor = 'document.addEventListener("click",function(ev){\n  var el=ev.target.closest("[data-act]");'
    if anchor not in html:
        raise SystemExit("actions 锚点未找到")
    html = html.replace(anchor, js + "\n" + anchor, 1)

    # ---- 9) init 调整刷新节奏 ----
    old_init = (
        '(function init(){\n'
        '  if(TOKEN){ try{ localStorage.setItem("ab_token",TOKEN); }catch(e){} }\n'
        '  if(hasKSU()) KSU_LABEL="KSU"; else KSU_LABEL="LAN";\n'
        '  switchTab("home");\n'
        '  setInterval(function(){\n'
        '    var cur=document.querySelector(".nav-link.on, .dropdown-item.on"); \n'
        '    if(cur&&cur.getAttribute("data-tab")==="home") { loadHome(); loadPanel(); }\n'
        '  }, 15000);\n'
        '})();'
    )
    new_init = (
        '(function init(){\n'
        '  if(TOKEN){ try{ localStorage.setItem("ab_token",TOKEN); }catch(e){} }\n'
        '  if(hasKSU()) KSU_LABEL="KSU"; else KSU_LABEL="LAN";\n'
        '  /* KSU 模式下每次取数都要 fork 进程，刷新间隔必须放宽，\n'
        '     否则光刷新就能把手机 CPU 吃满（与上一版卡顿同源）。 */\n'
        '  LIVE_MS = hasKSU() ? 2500 : 1200;\n'
        '  switchTab("home");\n'
        '  setInterval(function(){\n'
        '    if(CUR_TAB==="home"){ loadHome(); loadPanel(); }\n'
        '    tickLive();\n'
        '  },6000);\n'
        '  /* 曲线单独按 1s 重绘，只在可见页面画 */\n'
        '  setInterval(function(){\n'
        '    if(CUR_TAB==="route-home"||CUR_TAB==="home") RH.spark.draw();\n'
        '  },1000);\n'
        '  window.addEventListener("resize",function(){ setTimeout(function(){ RH.spark.draw(); },150); });\n'
        '})();'
    )
    if old_init not in html:
        raise SystemExit("init 锚点未找到")
    html = html.replace(old_init, new_init, 1)

    # ---- 10) loadHome：补总览页磁贴，并把代理数据链挂上去 ----
    # 10a) 让 ctl.sh 的 then 结果先落到变量 p，便于和代理数据一起 Promise.all
    old_home_head = 'function loadHome(){\n  return runScript("ctl.sh",["status"]).then(function(s){\n'
    new_home_head = 'function loadHome(){\n  var p=runScript("ctl.sh",["status"]).then(function(s){\n'
    if old_home_head not in html:
        raise SystemExit("loadHome 头部锚点未找到")
    html = html.replace(old_home_head, new_home_head, 1)

    # 10b) 尾部：补 hmUptime/hmSys，并挂上代理状态 / 当前出口 / 规则统计
    old_home = (
        '    setText("abVer","v1.0.0");\n'
        '    setText("abKsu", KSU_LABEL);\n'
        '  });\n'
        '}'
    )
    new_home = (
        '    setText("abVer","v1.0.0");\n'
        '    setText("abKsu", KSU_LABEL);\n'
        '    setText("hmUptime", sys.uptime||"-");\n'
        '    setText("hmSys", KSU_LABEL);\n'
        '  });\n'
        '  // 总览页的「代理内核」磁贴网格需要内核实时状态 / 当前出口 / 规则统计，\n'
        '  // 之前只取了 ctl.sh status，导致整片磁贴恒为 "-"。这里补齐同一条数据链。\n'
        '  var q=Promise.all([loadRouteStatus(),loadRouteSummary(),loadRouteLive(),loadRouteCurrent()]);\n'
        '  return Promise.all([p,q]);\n'
        '}'
    )
    if old_home not in html:
        raise SystemExit("loadHome 锚点未找到")
    html = html.replace(old_home, new_home, 1)

    write(TARGET, html)
    print("OK: %s -> %s 字节 (%+d)" % (os.path.basename(TARGET), len(html), len(html) - orig_len))


if __name__ == "__main__":
    main()
