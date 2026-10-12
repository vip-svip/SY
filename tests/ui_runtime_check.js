/* 面板运行时校验：在 jsdom 里真实加载 index.html，执行内联 JS，
 * 模拟导航下拉 / 标签切换，捕获任何运行时异常。
 *
 * 用法: node tests/ui_runtime_check.js
 * 依赖: jsdom（已装在 WorkBuddy 托管 node workspace）
 */
"use strict";
const fs = require("fs");
const path = require("path");
const { JSDOM, VirtualConsole } = require("jsdom");

const ROOT = path.dirname(__dirname);
const FILE = path.join(ROOT, "webroot", "index.html");

let fail = 0, pass = 0;
const errs = [];
function ok(m) { pass++; console.log("  [ok] " + m); }
function bad(m) { fail++; console.log("  [X]  " + m); }

const html = fs.readFileSync(FILE, "utf8");

// 收集页面内部错误
const vc = new VirtualConsole();
vc.on("jsdomError", (e) => errs.push("jsdomError: " + (e && e.message || e)));
vc.on("error", (...a) => errs.push("console.error: " + a.join(" ")));

const dom = new JSDOM(html, {
  runScripts: "dangerously",
  pretendToBeVisual: true,
  url: "http://127.0.0.1:8080/?token=TESTTOKEN",
  virtualConsole: vc,
  beforeParse(win) {
    // 屏蔽网络：apiExec 走 fetch，这里让所有请求立即失败，避免挂起
    win.fetch = function () {
      return Promise.resolve({
        ok: false, status: 0,
        text: function () { return Promise.resolve(""); },
        json: function () { return Promise.resolve({}); }
      });
    };
    // 屏蔽 setInterval 的长轮询副作用
    win.__INTERVALS__ = [];
    const si = win.setInterval;
    win.setInterval = function (fn, ms) { win.__INTERVALS__.push(fn); return win.__INTERVALS__.length; };
    win.clearInterval = function () {};
    void si;
  }
});

const win = dom.window;
const doc = win.document;

setTimeout(() => {
  // ---------- 1. 运行时错误 ----------
  const real = errs.filter(e => !/Not implemented|Could not parse CSS|fetch/i.test(e));
  if (real.length) { bad("运行时报错 " + real.length + " 条: " + real.slice(0, 5).join(" | ")); }
  else ok("加载与初始化无运行时异常");

  // ---------- 2. 关键函数已挂载 ----------
  for (const fn of ["switchTab", "closeDropdowns", "openDropdown", "syncNavParent", "loadTab", "setToggle", "runScript"]) {
    if (typeof win[fn] === "function") ok("函数 " + fn + "() 可调用");
    else bad("函数 " + fn + "() 未定义");
  }

  // ---------- 3. 初始状态：仪表盘高亮、其余页面隐藏 ----------
  const navHome = doc.querySelector('.nav-link[data-tab="home"]');
  if (navHome && navHome.classList.contains("on")) ok("初始 nav-link[data-tab=home] 高亮");
  else bad("初始仪表盘未高亮");

  const shown = [...doc.querySelectorAll(".page")].filter(p => !p.classList.contains("hide"));
  if (shown.length === 1 && shown[0].id === "page-home") ok("初始仅 page-home 可见");
  else bad("初始可见页面异常: " + shown.map(p => p.id).join(","));

  // ---------- 4. 下拉开合 ----------
  const ddParent = doc.querySelector('.nav-link[data-dd="filters"]');
  const ddMenu = doc.querySelector('.dropdown-menu[data-dd-menu="filters"]');
  if (!ddParent || !ddMenu) { bad("找不到「过滤器」下拉"); }
  else {
    ddParent.dispatchEvent(new win.MouseEvent("click", { bubbles: true }));
    if (ddMenu.classList.contains("open")) ok("点击「过滤器」展开下拉");
    else bad("点击「过滤器」未展开下拉");
    // 再点一次应关闭
    ddParent.dispatchEvent(new win.MouseEvent("click", { bubbles: true }));
    if (!ddMenu.classList.contains("open")) ok("再次点击收起下拉");
    else bad("再次点击未收起下拉");
  }

  // ---------- 5. 点下拉项切页 + 父项高亮 ----------
  const item = doc.querySelector('.dropdown-item[data-tab="engine"]');
  if (!item) bad("找不到「自定义过滤规则」下拉项");
  else {
    ddParent.dispatchEvent(new win.MouseEvent("click", { bubbles: true })); // 先展开
    item.dispatchEvent(new win.MouseEvent("click", { bubbles: true }));
    const p = doc.getElementById("page-engine");
    if (p && !p.classList.contains("hide")) ok("点击下拉项切换到 page-engine");
    else bad("点击下拉项未切换页面");
    if (item.classList.contains("on")) ok("下拉项自身高亮");
    else bad("下拉项未高亮");
    if (ddParent.classList.contains("on")) ok("下拉父项「过滤器」同步高亮");
    else bad("下拉父项未同步高亮");
    if (!ddMenu.classList.contains("open")) ok("切换后下拉自动收起");
    else bad("切换后下拉未收起");
  }

  // ---------- 6. 普通 nav-link 切页，下拉父项应取消高亮 ----------
  const navHome2 = doc.querySelector('.nav-link[data-tab="home"]');
  navHome2.dispatchEvent(new win.MouseEvent("click", { bubbles: true }));
  const ph = doc.getElementById("page-home");
  if (ph && !ph.classList.contains("hide")) ok("切换回 page-home");
  else bad("未切换到 page-home");
  if (!ddParent.classList.contains("on")) ok("切走后下拉父项高亮取消");
  else bad("切走后下拉父项仍高亮");

  // ---------- 7. 点击页面空白处关闭下拉 ----------
  ddParent.dispatchEvent(new win.MouseEvent("click", { bubbles: true }));
  doc.body.dispatchEvent(new win.MouseEvent("click", { bubbles: true }));
  if (!ddMenu.classList.contains("open")) ok("点击页面空白关闭下拉");
  else bad("点击空白未关闭下拉");

  // ---------- 8. 每个 data-tab 都能切换且页面存在 ----------
  let tabOk = true, tabCount = 0;
  for (const el of doc.querySelectorAll("[data-tab]")) {
    const t = el.getAttribute("data-tab");
    tabCount++;
    win.switchTab(t);
    const pg = doc.getElementById("page-" + t);
    if (!pg || pg.classList.contains("hide")) { bad("switchTab(" + t + ") 未显示 page-" + t); tabOk = false; }
  }
  if (tabOk) ok(tabCount + " 个标签全部可切换并命中对应页面");

  // ---------- 8b. 极客控制台各页面渲染不抛错 ----------
  const geek = ["route-home", "route-proxy", "route-conn", "route-rules", "route-dns", "route-logs", "route-core", "app", "sysinfo"];
  let geekOk = true;
  const before = errs.length;
  for (const t of geek) {
    win.switchTab(t);
    const pg = doc.getElementById("page-" + t);
    if (!pg || pg.classList.contains("hide")) { bad("极客页 page-" + t + " 未显示"); geekOk = false; }
  }
  const newErrs = errs.slice(before).filter(e => !/Not implemented|Could not parse CSS|fetch/i.test(e));
  if (newErrs.length) { bad("极客页产生运行时异常: " + newErrs.slice(0, 3).join(" | ")); geekOk = false; }
  if (geekOk) ok(geek.length + " 个极客控制台页面均可切换且无异常");

  // ---------- 8c. 新增 actions 处理器已挂到全局 ----------
  const wantActs = ["tab-go", "px-toggle", "rh-mode", "rp-pick", "rc-close", "rr-diag", "rd-preset", "rl-pull", "rk-profile-save", "ap-install"];
  const missAct = wantActs.filter(a => typeof win.actions[a] !== "function");
  if (missAct.length) bad("actions 缺少处理器: " + missAct.join(","));
  else ok(wantActs.length + " 个极客动作处理器已注册");

  // ---------- 8d. 格式化工具输出正确 ----------
  const fmtCases = [[0, "0 B"], [512, "512 B"], [1536, "1.50 KB"], [1048576, "1.00 MB"]];
  const fmtBad = fmtCases.filter(([i, o]) => win.fmtBytes(i) !== o);
  if (fmtBad.length) bad("fmtBytes 输出异常: " + JSON.stringify(fmtBad));
  else ok("fmtBytes 单位换算正确");

  // ---------- 8e. 延迟色阶分档 ----------
  const latCases = [[50, "p0"], [150, "p1"], [300, "p2"], [600, "p3"], [1200, "p4"], [0, "p4"]];
  const latBad = latCases.filter(([i, o]) => win.latClass(i) !== o);
  if (latBad.length) bad("latClass 分档异常: " + JSON.stringify(latBad));
  else ok("latClass 延迟色阶分档正确");

  // ---------- 8f. JSON 抽取能跳过前导非 JSON 文本 ----------
  const ex1 = win.extractJson("route compile: ok\n{\"a\":1}\n");
  const ex2 = win.extractJson("ERR: 内核不可达");
  if (ex1 && ex1.a === 1 && ex2 === null) ok("extractJson 容错解析正确");
  else bad("extractJson 解析异常: " + JSON.stringify(ex1) + " / " + JSON.stringify(ex2));

  // ---------- 8g. 运行模式中文标签 ----------
  const modeCases = [["rule", "规则分流"], ["global", "全局代理"], ["direct", "全部直连"],
                     ["RULE", "规则分流"], [null, "-"], ["weird", "weird"]];
  const modeBad = modeCases.filter(([i, o]) => win.modeLabel(i) !== o);
  if (modeBad.length) bad("modeLabel 映射异常: " + JSON.stringify(modeBad));
  else ok("modeLabel 运行模式中文映射正确");

  // ---------- 8h. 总览页必须挂载代理数据链（否则代理内核磁贴恒为 "-"）----------
  const homeSrc = String(win.loadHome || "");
  const needCall = ["loadRouteLive()", "loadRouteCurrent()", "loadRouteSummary()", "loadRouteStatus()"];
  const missCall = needCall.filter(c => homeSrc.indexOf(c) < 0);
  if (missCall.length) bad("loadHome 未挂载: " + missCall.join(","));
  else ok("loadHome 已挂载代理状态 / 当前出口 / 规则统计数据链");

  // ---------- 9. 子标签切换 ----------
  win.switchTab("dns");
  const st = doc.querySelector('.subtab[data-sub="dns-black"]');
  st.dispatchEvent(new win.MouseEvent("click", { bubbles: true }));
  const sb = doc.getElementById("sub-dns-black");
  if (sb && !sb.classList.contains("hide")) ok("子标签切换到 sub-dns-black");
  else bad("子标签切换失败");

  // ---------- 10. setToggle 不抛错且切换 primary/ok ----------
  try {
    win.setToggle({ classList: { toggle() {}, add() {}, remove() {}, contains() { return false; } } }, false);
    ok("setToggle() 调用无异常");
  } catch (e) { bad("setToggle() 抛错: " + e.message); }

  // ---------- 11. 主题切换 ----------
  try {
    win.switchTheme();
    const isDark = doc.documentElement.classList.contains("theme-dark");
    win.switchTheme();
    const isLight = !doc.documentElement.classList.contains("theme-dark");
    if (isDark && isLight) ok("主题切换 dark/light 正常");
    else bad("主题切换异常");
  } catch (e) { bad("switchTheme() 抛错: " + e.message); }

  // ---------- 12. 导航结构 ----------
  const navLabels = [...doc.querySelectorAll(".nav-link")].map(a => a.textContent.replace(/[▼\s]+$/g, "").trim());
  console.log("  [i]  顶部导航: " + navLabels.join(" / "));
  const wantNav = ["总览", "代理路由", "过滤", "工具", "设置"];
  if (navLabels.length === wantNav.length && wantNav.every((n, i) => navLabels[i] === n)) {
    ok("导航分组为 " + wantNav.join(" / "));
  } else bad("导航分组异常: " + navLabels.join(","));

  const pageCount = doc.querySelectorAll(".page").length;
  if (doc.querySelectorAll(".page-title").length === pageCount) ok(pageCount + " 个页面均带 page-title 标题栏");
  else bad("page-title 数量异常: " + doc.querySelectorAll(".page-title").length + " / 页面 " + pageCount);

  console.log("\n  通过 %d 项，失败 %d 项", pass, fail);
  process.exit(fail ? 1 : 0);
}, 900);
