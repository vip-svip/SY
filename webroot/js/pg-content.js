/* ============================================================
 *  SY 内置：内容脱敏与页面侧守卫
 *  来源: privacy-guard-extension v1.12.0 归档（并入 SY 模块，非原样照搬）
 *  用法: 由 MITM 注入到 HTML（需版面注入开启），或由 App 的 WebView 加载。
 *  注意: 这些脚本设计为**运行在页面上下文**，不要在模块 shell 里 source。
 * ============================================================ */
/* 隐私守护 · 内容脚本（ISOLATED 世界，全帧运行）  v14
 * 静默模式：不在页面注入任何可见元素——无浮层徽标、无气泡、无悬停 title、无 confirm 弹窗。
 * 状态与拦截计数上报后台，仅体现在扩展工具栏徽标（属扩展界面，不污染网页）。
 *
 * 职责：自动脱敏、敏感图模糊（点击可还原）、<a ping> 点击跟踪中和、外链加固（noopener/noreferrer）、
 *       本地审计计数、向 MAIN 世界下发配置。
 * 安全边界：不读取 Cookie/localStorage/令牌/密码字段；不把任何数据发往第三方。
 *
 * v14 变更：
 *  - 新增 <a ping> 中和与 target=_blank 外链加固（noopener/noreferrer），堵住点击跟踪与跳转泄露。
 *  - 复制审计改用「校验通过的」卡号/身份证判定，降低误报。
 *  - 静默上报去抖，避免频繁刷新与后台抖动。
 *  - 保留 v11/v12/v13 修复：DNS 预取开关与追踪域下发生效、脱敏与 geolocation 实时开关、
 *    敏感图精确匹配不误伤、私密页误判收紧、脱敏观察器去抖、无 body 崩溃保护、界面无显示。
 */
(function () {
  "use strict";

  const PG = self.PG;
  if (!PG) return;

  const MARK = "data-pg-redacted";
  const IMG_MARK = "data-pg-redacted-image";
  const PRINT_ID = "__privacyGuardExt___print";

  let CFG = PG.PG_DEFAULTS;
  let REGEXES = PG.pgBuildRegexes(CFG.patterns);
  let listenersReady = false;
  let domObserver = null;
  let redactTimer = null;
  let reportTimer = null;
  let pendingReport = {};

  function mask(v) { v = String(v); if (v.length <= 4) return "*".repeat(v.length); const k = Math.min(4, Math.floor(v.length / 4)); return "*".repeat(v.length - k) + v.slice(-k); }

  function redactNode(node) {
    if (!node || !node.nodeValue || !node.nodeValue.trim()) return 0;
    const parent = node.parentElement; if (!parent) return 0;
    const tag = (parent.tagName || "").toLowerCase();
    if (["script", "style", "noscript", "textarea"].includes(tag)) return 0;
    if (parent.type === "password") return 0;
    if (parent.closest && parent.closest("[data-pg-noblur]")) return 0;
    let text = node.nodeValue, changed = 0;
    for (const r of REGEXES) { r.re.lastIndex = 0; text = text.replace(r.re, (m) => { changed++; return mask(m); }); }
    if (changed) { parent.setAttribute(MARK, "1"); node.nodeValue = text; }
    return changed;
  }

  function redactPage() {
    let changed = 0;
    const root = document.body || document.documentElement; // 无 body 时回退，避免抛错
    if (!root) return 0;
    try {
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
        acceptNode(n) {
          if (!n.nodeValue || !n.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
          if (n.parentElement && n.parentElement.closest("[" + MARK + "]")) return NodeFilter.FILTER_REJECT;
          return NodeFilter.FILTER_ACCEPT;
        }
      });
      let n; while ((n = walker.nextNode())) changed += redactNode(n);
    } catch (_) {}
    return changed;
  }

  function ensurePrintStyle() {
    if (document.getElementById(PRINT_ID)) return;
    const s = document.createElement("style");
    s.id = PRINT_ID;
    // 仅影响打印，不影响屏幕显示
    s.textContent = "@media print{[" + MARK + "],[" + IMG_MARK + "]{filter:blur(8px)!important;}}";
    (document.head || document.documentElement).appendChild(s);
  }

  /* ---------- 隐私加固：<a ping> 中和 + 外链 noopener/noreferrer ---------- */
  function hardenLinks(root) {
    if (!CFG.enabled) return;
    const scope = root && root.querySelectorAll ? root : document;
    try {
      if (CFG.stripPing) scope.querySelectorAll("a[ping]").forEach(function (a) { a.removeAttribute("ping"); });
    } catch (_) {}
    try {
      if (CFG.hardenLinks) scope.querySelectorAll('a[target="_blank"]').forEach(function (a) {
        const rel = (a.getAttribute("rel") || "").toLowerCase();
        if (!/noopener/.test(rel) || !/noreferrer/.test(rel)) {
          const set = new Set(rel.split(/\s+/).filter(Boolean));
          set.add("noopener"); set.add("noreferrer");
          a.setAttribute("rel", Array.from(set).join(" "));
        }
      });
    } catch (_) {}
  }

  function bumpAudit(field) {
    try { chrome.storage.local.get({ audit: {} }, function (d) { const a = d.audit || {}; a[field] = (a[field] || 0) + 1; chrome.storage.local.set({ audit: a }); }); } catch (_) {}
  }

  // 静默上报去抖：合并短时间内的多次事件
  function reportStatus(payload) {
    pendingReport = Object.assign(pendingReport, payload || {});
    if (reportTimer) return;
    reportTimer = setTimeout(function () {
      reportTimer = null;
      const body = Object.assign({ type: "pg-status" }, pendingReport);
      pendingReport = {};
      try { chrome.runtime.sendMessage(body); } catch (_) {}
    }, 300);
  }

  /* ---------- 敏感图模糊（精确匹配，不影响普通图片；无悬停提示） ---------- */
  function isSensitiveImage(img) {
    if (!img || img.tagName !== "IMG") return false;
    if (img.closest && img.closest("[data-pg-noblur]")) return false;
    const w = img.naturalWidth || img.width || 0;
    if (w && w < 96) return false; // 小图/图标一律不模糊
    const hint = ((img.alt || "") + " " + (img.className || "") + " " + (img.id || "") + " " + (img.getAttribute ? (img.getAttribute("aria-label") || "") : "")).toLowerCase();
    return PG.pgIsSensitiveImageHint(hint);
  }
  function blurSensitiveImages() {
    let n = 0;
    document.querySelectorAll("img").forEach(function (img) {
      if (img.getAttribute(IMG_MARK) === "1") return;
      if (isSensitiveImage(img)) {
        img.style.filter = "blur(10px)";
        img.style.cursor = "pointer";
        img.setAttribute(IMG_MARK, "1");
        n++;
      }
    });
    return n;
  }
  function revealImage(img) { img.style.filter = ""; img.style.cursor = ""; img.removeAttribute(IMG_MARK); }

  function listenEgress() {
    window.addEventListener("message", function (e) {
      if (e.source !== window || !e.data) return;
      if (e.data.__pg === "egress") { bumpAudit("blockedEgress"); reportStatus({ egress: 1, kind: e.data.kind }); }
      if (e.data.__pg === "rtc" && e.data.type === "candidate") {
        try { window.__pgLastCandidates = window.__pgLastCandidates || []; window.__pgLastCandidates.push(e.data.candidate); if (window.__pgLastCandidates.length > 50) window.__pgLastCandidates.shift(); } catch (_) {}
      }
    });
  }

  // 监听器只注册一次；全部静默，不弹窗、不阻断。
  function ensureListeners() {
    if (listenersReady) return;
    listenersReady = true;
    listenEgress();

    document.addEventListener("click", function (e) {
      const t = e.target;
      if (t && t.tagName === "IMG" && t.getAttribute(IMG_MARK) === "1" && CFG.enabled) revealImage(t);
    }, true);

    document.addEventListener("submit", function (e) {
      if (!CFG.enabled || !CFG.guard) return;
      const form = e.target; if (!form || form.tagName !== "FORM") return;
      const target = (form.getAttribute("action") || "").toLowerCase();
      if (!target || target.startsWith("#")) return;
      let sameOrigin = true; try { sameOrigin = new URL(target, location.href).origin === location.origin; } catch (_) {}
      if (!sameOrigin) { bumpAudit("blockedForm"); reportStatus({ crossOriginForm: 1 }); }
    }, true);

    document.addEventListener("copy", function () {
      if (!CFG.enabled || !CFG.redact) return;
      const sel = String(window.getSelection ? window.getSelection() : "");
      // 高置信判定：仅校验通过的卡号/身份证才算敏感（减少误报）
      if (PG.pgSensitiveScan(sel)) { bumpAudit("blockedCopy"); reportStatus({ copySensitive: 1 }); }
    }, true);

    document.addEventListener("paste", function (e) {
      if (!CFG.enabled || !CFG.guard) return;
      const t = (e.clipboardData && e.clipboardData.getData && e.clipboardData.getData("text")) || "";
      const active = document.activeElement;
      const isSensitiveField = active && /password|card|身份证|银行卡|账号|account|security|code/i.test((active.name || "") + (active.id || "") + (active.autocomplete || "") + (active.type || ""));
      if (t && isSensitiveField) { bumpAudit("warnedPaste"); reportStatus({ pasteSensitive: 1 }); }
    }, true);
  }

  function pushCfg() {
    try {
      window.postMessage({
        __pg: "cfg", enabled: CFG.enabled, strictRTC: CFG.strictRTC, preserveSrflx: CFG.preserveSrflx,
        blockGeolocation: CFG.blockGeolocation, blockDnsPrefetch: CFG.blockDnsPrefetch, trackers: CFG.trackerDomains,
        antiFingerprint: CFG.antiFingerprint, antiFingerprintCanvas: CFG.antiFingerprintCanvas, trimReferrer: CFG.trimReferrer
      }, "*");
    } catch (_) {}
  }

  function scheduleRedact() {
    if (redactTimer) return;
    redactTimer = setTimeout(function () { redactTimer = null; if (CFG.enabled && CFG.redact) { try { redactPage(); } catch (_) {} } }, 400);
  }

  function refresh() {
    REGEXES = PG.pgBuildRegexes(CFG.patterns);
    pushCfg();

    // 始终执行隐私加固（不依赖是否私密页）
    if (CFG.enabled) { ensureListeners(); hardenLinks(document); }

    if (domObserver) { try { domObserver.disconnect(); } catch (_) {} domObserver = null; }

    if (!CFG.enabled) { reportStatus({ disabled: 1 }); return; }

    const root = document.body || document.documentElement;
    if (root) {
      try {
        domObserver = new MutationObserver(function (muts) {
          if (!CFG.enabled) return;
          for (const m of muts) {
            if (!m.addedNodes || !m.addedNodes.length) continue;
            for (const node of m.addedNodes) {
              if (node && node.nodeType === 1) hardenLinks(node);
            }
          }
          if (CFG.redact) scheduleRedact();
        });
        domObserver.observe(root, { childList: true, subtree: true });
      } catch (_) {}
    }

    if (CFG.redact) ensurePrintStyle();

    const host = location.hostname;
    const path = location.pathname.toLowerCase();
    // 收紧误判：仅当路径中出现独立关键词段（前后为分隔符/边界）时视为私密页
    const isSensitive = PG.pgHostMatches(host, CFG.sensitiveHosts) || /(?:^|[/._-])(bank|payment|gov|mail|login|account|wallet)(?:[/._-]|$)/i.test(path);
    if (!isSensitive) { reportStatus({ active: 1, changed: 0, blurred: 0, host: host }); return; }

    let changed = 0, blurred = 0;
    if (CFG.redact) { try { changed = redactPage(); } catch (_) {} }
    if (CFG.blur) { try { blurred = blurSensitiveImages(); } catch (_) {} }
    reportStatus({ active: 1, changed: changed, blurred: blurred, host: host, strict: CFG.strictRTC });
  }

  PG.pgLoad(function (cfg) {
    CFG = cfg;
    refresh();
    try {
      chrome.storage.onChanged.addListener(function (changes, area) {
        if (area !== "local") return;
        PG.pgLoad(function (next) { CFG = next; refresh(); });
      });
    } catch (_) {}
  });
})();
