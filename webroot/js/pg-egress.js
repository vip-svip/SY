/* ============================================================
 *  SY 内置：敏感数据外发拦截（fetch/XHR/beacon/WebSocket/图片信标）
 *  来源: privacy-guard-extension v1.12.0 归档（并入 SY 模块，非原样照搬）
 *  用法: 由 MITM 注入到 HTML（需版面注入开启），或由 App 的 WebView 加载。
 *  注意: 这些脚本设计为**运行在页面上下文**，不要在模块 shell 里 source。
 * ============================================================ */
/* 隐私守护 · 第三方数据外发拦截器（MAIN 世界）  v14
 * 拦截 fetch / XMLHttpRequest / navigator.sendBeacon / WebSocket / Image 信标，
 * 阻止把**高置信**敏感数据（校验通过的身份证、银行卡）发往第三方来源或已知追踪域。
 * 诚实边界：本模块对抗"页面把数据发给第三方"，不改变系统 DNS/VPN 路由（那是网络层能力）。
 * 安全边界：不读取 Cookie/localStorage/令牌/密码；不把数据发往任何地方，仅做放行判断。
 *
 * v14 修复：
 *  - 【误拦】改为 Luhn/身份证校验位判定；此前任何 16-19 位数字（订单号、CDN 数字路径、雪花 ID）
 *          都会被当敏感数据拦截，导致正常图片/接口被拦。现仅校验通过才拦截。
 * v12 修复：追踪域匹配加入主机名左边界 (^|.)，修复 evilfacebook.com 误报。
 * v10 修复：追踪域正则正确转义；配置下发的追踪域名单真正生效。
 */
(function () {
  "use strict";

  if (window.__pgEgressInit === true) return;
  window.__pgEgressInit = true;

  let enabled = true;
  let trackers = [
    /(^|\.)google-analytics\.com$/, /(^|\.)googletagmanager\.com$/, /(^|\.)doubleclick\.net$/,
    /(^|\.)facebook\.com$/, /(^|\.)facebook\.net$/, /(^|\.)hotjar\.com$/, /(^|\.)mixpanel\.com$/,
    /(^|\.)segment\.(io|com)$/, /(^|\.)sentry\.io$/, /(^|\.)umeng\.[a-z.]+$/, /(^|\.)cnzz\.com$/,
    /(^|\.)talkingdata\.com$/, /(^|\.)adjust\.com$/, /(^|\.)appsflyer\.com$/, /(^|\.)bugly\.qq\.com$/
  ];

  function escapeRe(s) { return String(s).replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }
  function buildTrackers(list) {
    if (!Array.isArray(list)) return;
    if (!list.length) { trackers = []; return; }
    trackers = list.map(function (d) { return new RegExp("(^|\\.)" + escapeRe(String(d).trim().toLowerCase()) + "$"); });
  }

  // —— 高置信校验器（内联，因为 MAIN 世界不加载 shared/config.js）——
  function luhn(num) {
    const s = String(num).replace(/\D/g, "");
    if (s.length < 12 || s.length > 19) return false;
    let sum = 0, alt = false;
    for (let i = s.length - 1; i >= 0; i--) { let d = s.charCodeAt(i) - 48; if (alt) { d *= 2; if (d > 9) d -= 9; } sum += d; alt = !alt; }
    return sum % 10 === 0;
  }
  function validIdCard(v) {
    v = String(v || "").trim().toUpperCase();
    if (!/^\d{17}[\dX]$/.test(v)) return false;
    const w = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2];
    const chk = ["1", "0", "X", "9", "8", "7", "6", "5", "4", "3", "2"];
    let s = 0;
    for (let i = 0; i < 17; i++) s += (v.charCodeAt(i) - 48) * w[i];
    return chk[s % 11] === v[17];
  }
  function sensitive(text) {
    if (!text) return false;
    const s = String(text);
    let m;
    const idRe = /\d{17}[\dXx]/g;
    while ((m = idRe.exec(s))) { if (validIdCard(m[0])) return true; }
    const cardRe = /(?<!\d)\d{12,19}(?!\d)/g;
    while ((m = cardRe.exec(s))) { if (luhn(m[0])) return true; }
    return false;
  }

  window.addEventListener("message", function (e) {
    if (e.source !== window || !e.data || e.data.__pg !== "cfg") return;
    if (typeof e.data.enabled === "boolean") enabled = e.data.enabled;
    if (Array.isArray(e.data.trackers)) buildTrackers(e.data.trackers);
  });

  function hostOf(url) { try { return new URL(url, location.href).hostname; } catch (_) { return ""; } }
  function isCross(url) { try { return new URL(url, location.href).origin !== location.origin; } catch (_) { return false; } }
  function isTracker(url) { const h = hostOf(url); return !!h && trackers.some(function (r) { return r.test(h); }); }

  function bodyString(body) {
    if (body == null) return "";
    if (typeof body === "string") return body;
    if (typeof URLSearchParams !== "undefined" && body instanceof URLSearchParams) return body.toString();
    if (typeof FormData !== "undefined" && body instanceof FormData) { let s = ""; try { body.forEach(function (v) { if (typeof v === "string") s += " " + v; }); } catch (_) {} return s; }
    if (typeof Blob !== "undefined" && body instanceof Blob) return ""; // 不读取二进制
    if (typeof ArrayBuffer !== "undefined" && (body instanceof ArrayBuffer || ArrayBuffer.isView(body))) return "";
    try { return String(body); } catch (_) { return ""; }
  }

  function blocked(url, body) {
    if (!enabled) return false;
    if (!(isCross(url) || isTracker(url))) return false;
    return sensitive(bodyString(body));
  }

  function notify(kind, target) { try { window.postMessage({ __pg: "egress", kind: kind, target: hostOf(target), ts: Date.now() }, "*"); } catch (_) {} }

  if (typeof window.fetch === "function") {
    const _fetch = window.fetch;
    window.fetch = function (input, init) {
      try {
        const url = typeof input === "string" ? input : (input && input.url) || "";
        const body = init && init.body;
        if (blocked(url, body)) { notify("fetch", url); return Promise.reject(new Error("隐私守护：已阻止向第三方发送敏感数据")); }
      } catch (_) {}
      return _fetch.apply(this, arguments);
    };
  }

  const _open = XMLHttpRequest.prototype.open, _send = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (m, u) { this.__pgUrl = u; return _open.apply(this, arguments); };
  XMLHttpRequest.prototype.send = function (body) {
    try { if (blocked(this.__pgUrl, body)) { notify("xhr", this.__pgUrl); try { this.abort(); } catch (_) {} return; } } catch (_) {}
    return _send.apply(this, arguments);
  };

  if (navigator.sendBeacon) {
    const _sb = navigator.sendBeacon.bind(navigator);
    navigator.sendBeacon = function (url, data) {
      try { if (blocked(url, typeof data === "string" ? data : "")) { notify("beacon", url); return false; } } catch (_) {}
      return _sb(url, data);
    };
  }

  if (typeof window.WebSocket === "function") {
    const _WS = window.WebSocket;
    function WrappedWS(url, protocols) {
      let reject = false;
      try { reject = blocked(url, decodeURIComponent(String(url))); } catch (_) {}
      if (reject) { notify("websocket", url); throw new Error("隐私守护：已阻止向第三方 WebSocket 发送敏感数据"); }
      return protocols === undefined ? new _WS(url) : new _WS(url, protocols);
    }
    WrappedWS.prototype = _WS.prototype;
    ["CONNECTING", "OPEN", "CLOSING", "CLOSED"].forEach(function (k) { try { WrappedWS[k] = _WS[k]; } catch (_) {} });
    window.WebSocket = WrappedWS;
  }

  // Image 信标：仅在 URL 含「校验通过的」卡号/身份证时才拦截（普通图片不受影响）。
  try {
    const desc = Object.getOwnPropertyDescriptor(HTMLImageElement.prototype, "src");
    if (desc && desc.set) {
      Object.defineProperty(HTMLImageElement.prototype, "src", {
        configurable: true,
        get: desc.get,
        set: function (v) {
          try { if (enabled && isCross(v) && sensitive(decodeURIComponent(String(v)))) { notify("img", v); return; } } catch (_) {}
          return desc.set.call(this, v);
        }
      });
    }
  } catch (_) {}
})();
