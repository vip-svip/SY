/* 用真实 Chromium 渲染面板预览并截图，用于人工视觉验收 + 渲染性能采样。
 *
 * 用法: node tests/ui_screenshot.js <输出目录>
 */
"use strict";
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const ROOT = path.dirname(__dirname);
const SRC = path.join(ROOT, "ui-preview.html");
const OUT = process.argv[2] || path.join(ROOT, "shots");
if (!fs.existsSync(OUT)) fs.mkdirSync(OUT, { recursive: true });

(async () => {
  const browser = await chromium.launch();
  const errs = [];

  async function shoot(name, opts) {
    const page = await browser.newPage({
      viewport: opts.viewport,
      deviceScaleFactor: opts.dsf || 2,
      colorScheme: opts.dark ? "dark" : "light",
    });
    page.on("pageerror", e => errs.push(name + ": " + e.message));
    page.on("console", m => { if (m.type() === "error") errs.push(name + " console: " + m.text()); });
    await page.goto("file:///" + SRC.replace(/\\/g, "/"));
    await page.waitForTimeout(400);
    if (opts.dark) {
      await page.evaluate(() => {
        document.documentElement.classList.remove("theme-light");
        document.documentElement.classList.add("theme-dark");
      });
      await page.waitForTimeout(200);
    }
    if (opts.click) {
      const seq = Array.isArray(opts.click) ? opts.click : [opts.click];
      for (const sel of seq) {
        await page.click(sel);
        await page.waitForTimeout(250);
      }
    }
    if (opts.scrollTo) {
      await page.evaluate((sel) => {
        const el = document.querySelector(sel);
        if (el) el.scrollIntoView({ block: "start" });
      }, opts.scrollTo);
      await page.waitForTimeout(200);
    }
    const file = path.join(OUT, name + ".png");
    await page.screenshot({ path: file, fullPage: !!opts.full });
    const h = await page.evaluate(() => document.body.scrollHeight);
    console.log("  -> " + name + ".png  (页面高 " + h + "px)");
    await page.close();
    return file;
  }

  console.log("渲染截图:");
  // 手机竖屏 —— 用户实际使用环境
  await shoot("01_mobile_home_light", { viewport: { width: 412, height: 900 }, full: true });
  await shoot("02_mobile_home_dark", { viewport: { width: 412, height: 900 }, dark: true });
  // 下拉菜单展开
  await shoot("03_mobile_dropdown", {
    viewport: { width: 412, height: 900 }, click: '.nav-link[data-dd="settings"]'
  });
  // 引擎页
  await shoot("04_mobile_engine", {
    viewport: { width: 412, height: 900 },
    click: ['.nav-link[data-dd="filters"]', '.dropdown-item[data-tab="engine"]'], full: true
  });
  // 桌面宽屏
  await shoot("05_desktop_home", { viewport: { width: 1280, height: 900 }, dsf: 1, full: true });
  await shoot("06_desktop_engine", {
    viewport: { width: 1280, height: 900 }, dsf: 1,
    click: ['.nav-link[data-dd="filters"]', '.dropdown-item[data-tab="engine"]'], full: true
  });
  // DNS 拦截列表（表单密集页）
  await shoot("07_desktop_dns", {
    viewport: { width: 1280, height: 900 }, dsf: 1,
    click: ['.nav-link[data-dd="filters"]', '.dropdown-item[data-tab="dns"]'], full: true
  });

  // ---- 布局断言：下拉菜单必须真实可见，不被祖先 overflow 裁切 ----
  console.log("\n布局断言:");
  let layFail = 0;
  function lay(cond, msg) { if (cond) console.log("  [ok] " + msg); else { layFail++; console.log("  [X]  " + msg); } }

  for (const vw of [360, 412, 768, 1280]) {
    const p = await browser.newPage({ viewport: { width: vw, height: 800 } });
    await p.goto("file:///" + SRC.replace(/\\/g, "/"));
    await p.waitForTimeout(300);
    for (const dd of ["filters", "settings"]) {
      await p.click('.nav-link[data-dd="' + dd + '"]');
      await p.waitForTimeout(180);
      const info = await p.evaluate((id) => {
        const m = document.querySelector('.dropdown-menu[data-dd-menu="' + id + '"]');
        if (!m) return { err: "no menu" };
        const r = m.getBoundingClientRect();
        const cs = getComputedStyle(m);
        // 逐级检查祖先是否裁切
        const clipped = [];
        let a = m.parentElement;
        while (a && a !== document.documentElement) {
          const acs = getComputedStyle(a);
          if (/hidden|auto|scroll|clip/.test(acs.overflowX + " " + acs.overflowY)) {
            const ar = a.getBoundingClientRect();
            if (r.right > ar.right + 0.5 || r.bottom > ar.bottom + 0.5 ||
                r.left < ar.left - 0.5 || r.top < ar.top - 0.5) {
              clipped.push(a.tagName.toLowerCase() + "." + (a.className || "").toString().split(" ")[0]
                + "(" + acs.overflowX + "/" + acs.overflowY + ")");
            }
          }
          a = a.parentElement;
        }
        // 命中测试：菜单中心点最上层元素必须属于该菜单
        const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
        const hit = document.elementFromPoint(cx, cy);
        return {
          display: cs.display, w: Math.round(r.width), h: Math.round(r.height),
          top: Math.round(r.top), left: Math.round(r.left),
          clipped, hitInside: !!(hit && m.contains(hit)),
        };
      }, dd);
      const good = info.display !== "none" && info.w > 100 && info.h > 40 &&
                   info.clipped.length === 0 && info.hitInside;
      lay(good, "视口 " + vw + "px · " + dd + " 下拉可见 (w=" + info.w + " h=" + info.h +
          " top=" + info.top + " 裁切=" + (info.clipped.join(",") || "无") +
          " 命中=" + (info.hitInside ? "菜单内" : "被遮挡"));
      await p.keyboard.press("Escape").catch(() => {});
    }
    // 头部不溢出视口
    const hdr = await p.evaluate(() => {
      const h = document.querySelector(".header");
      const r = h.getBoundingClientRect();
      return { right: Math.round(r.right), sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth };
    });
    lay(hdr.sw <= hdr.cw + 1, "视口 " + vw + "px · 无横向溢出 (scrollW=" + hdr.sw + " clientW=" + hdr.cw + ")");
    await p.close();
  }

  // ---- 渲染性能采样：统计合成层与长任务 ----
  const page = await browser.newPage({ viewport: { width: 412, height: 900 } });
  await page.goto("file:///" + SRC.replace(/\\/g, "/"));
  await page.waitForTimeout(500);
  const perf = await page.evaluate(() => {
    const all = document.querySelectorAll("*");
    let bf = 0;
    const bfSel = [];
    for (const el of all) {
      const cs = getComputedStyle(el);
      const v = cs.backdropFilter || cs.webkitBackdropFilter;
      if (v && v !== "none") {
        bf++;
        if (bfSel.length < 12) bfSel.push(el.tagName.toLowerCase() + "." + (el.className || "").toString().split(" ")[0]);
      }
    }
    return {
      nodes: all.length,
      backdropElements: bf,
      backdropSample: bfSel,
      hasSvgFilter: !!document.querySelector("filter, feTurbulence"),
      cssRules: (() => { let n = 0; for (const s of document.styleSheets) { try { n += s.cssRules.length; } catch (e) {} } return n; })(),
    };
  });
  console.log("\n渲染性能采样（412x900 视口）:");
  console.log("  DOM 节点数        : " + perf.nodes);
  console.log("  实际启用模糊的元素: " + perf.backdropElements + "  " + JSON.stringify(perf.backdropSample));
  console.log("  SVG 滤镜节点      : " + (perf.hasSvgFilter ? "有(需修复)" : "无"));
  console.log("  CSS 规则数        : " + perf.cssRules);

  await browser.close();
  const problems = errs.length + layFail;
  if (errs.length) {
    console.log("\n页面错误 " + errs.length + " 条:");
    errs.slice(0, 10).forEach(e => console.log("  " + e));
  }
  if (layFail) console.log("\n布局断言失败 " + layFail + " 项");
  if (!problems) console.log("\n无页面错误、布局断言全部通过。");
  process.exit(problems ? 1 : 0);
})();
