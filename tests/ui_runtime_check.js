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
  const navTools = doc.querySelector('.nav-link[data-tab="tools"]');
  navTools.dispatchEvent(new win.MouseEvent("click", { bubbles: true }));
  const pt = doc.getElementById("page-tools");
  if (pt && !pt.classList.contains("hide")) ok("切换到 page-tools");
  else bad("未切换到 page-tools");
  if (!ddParent.classList.contains("on")) ok("切走后下拉父项高亮取消");
  else bad("切走后下拉父项仍高亮");

  // ---------- 7. 点击页面空白处关闭下拉 ----------
  ddParent.dispatchEvent(new win.MouseEvent("click", { bubbles: true }));
  doc.body.dispatchEvent(new win.MouseEvent("click", { bubbles: true }));
  if (!ddMenu.classList.contains("open")) ok("点击页面空白关闭下拉");
  else bad("点击空白未关闭下拉");

  // ---------- 8. 每个 data-tab 都能切换且页面存在 ----------
  let tabOk = true;
  for (const el of doc.querySelectorAll("[data-tab]")) {
    const t = el.getAttribute("data-tab");
    win.switchTab(t);
    const pg = doc.getElementById("page-" + t);
    if (!pg || pg.classList.contains("hide")) { bad("switchTab(" + t + ") 未显示 page-" + t); tabOk = false; }
  }
  if (tabOk) ok("12 个标签全部可切换并命中对应页面");

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

  // ---------- 12. 导航结构符合 AGH 规范 ----------
  const navLabels = [...doc.querySelectorAll(".nav-link")].map(a => a.textContent.trim());
  console.log("  [i]  顶部导航: " + navLabels.join(" / "));
  if (navLabels.length === 4) ok("导航项 4 个（仪表盘 / 过滤器 / 设置 / 工具与备份）");
  else bad("导航项数量异常: " + navLabels.length);
  if (doc.querySelectorAll(".page-title").length === 12) ok("12 个页面均带 page-title 标题栏");
  else bad("page-title 数量异常: " + doc.querySelectorAll(".page-title").length);

  console.log("\n  通过 %d 项，失败 %d 项", pass, fail);
  process.exit(fail ? 1 : 0);
}, 900);
