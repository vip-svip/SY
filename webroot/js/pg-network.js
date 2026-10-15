/* ============================================================
 *  SY 内置：WebRTC IP 阻断 / 地理阻断 / DNS prefetch 剥离
 *  来源: privacy-guard-extension v1.12.0 归档（并入 SY 模块，非原样照搬）
 *  用法: 由 MITM 注入到 HTML（需版面注入开启），或由 App 的 WebView 加载。
 *  注意: 这些脚本设计为**运行在页面上下文**，不要在模块 shell 里 source。
 * ============================================================ */
/* 隐私守护 · 网络层防护（MAIN 世界）  v14
 * v14：资源提示过滤不再移除 preload/modulepreload（此前会破坏跨域 CDN 资源加载）。
 * 目标：堵住 DNS 泄露、IP 泄露、VPN 泄露与代理节点（节点）泄露的页面侧通道。
 *
 * 覆盖：
 *  1) WebRTC：包装 RTCPeerConnection（含 webkit 别名与静态方法）；
 *     过滤 host / 内网 / 本地 IP；strict 全阻断；清洗 getStats()；屏蔽 icecandidateerror；
 *     处理 IPv6 与 mDNS(.local)。
 *  2) DNS：移除指向第三方的 dns-prefetch/preconnect/prefetch/prerender/preload/modulepreload；
 *     x-dns-prefetch-control 置 off。
 *  3) 位置：拦截 navigator.geolocation 精确定位（可实时开关）。
 *
 * v10 修复：
 *  - 【不生效】DNS 预取开关现在真正生效，并与内容脚本下发的配置联动。
 *  - 【不生效】geolocation 开关支持实时切换（关闭时恢复原生方法）。
 *  - 清理 isLocalAddr 冗余逻辑；strict 运行期切换可可靠回落。
 *
 * 诚实边界：页面侧无法改写系统/运营商 DNS、系统 VPN/代理路由与公网出口节点。
 * 隐私边界：不读取 Cookie/localStorage/令牌/密码；不把数据发往任何地方。
 */
(function () {
  "use strict";
  if (window.__pgNetworkInit === true) return;
  window.__pgNetworkInit = true;

  let enabled = true;
  let strictRTC = false;
  let preserveSrflx = true;
  let blockGeolocation = true;
  let blockDnsPrefetch = true;

  const LOCAL_RE = /^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|127\.|169\.254\.|0\.|::1$|fe80:|f[cd][0-9a-f]{2}:)/i;
  const IPV4_RE = /^(?:\d{1,3}\.){3}\d{1,3}$/;

  const nativeGeo = (typeof navigator !== "undefined" && navigator.geolocation) || null;
  const nativeGetCurrent = nativeGeo ? nativeGeo.getCurrentPosition : null;
  const nativeWatchPosition = nativeGeo ? nativeGeo.watchPosition : null;

  function notify(kind, detail) {
    try { window.postMessage({ __pg: "egress", kind: kind, target: detail || "", ts: Date.now() }, "*"); } catch (_) {}
  }
  function reportCandidate(info) {
    try { window.postMessage({ __pg: "rtc", type: "candidate", candidate: info }, "*"); } catch (_) {}
  }

  window.addEventListener("message", function (e) {
    if (e.source !== window || !e.data || e.data.__pg !== "cfg") return;
    const wasStrict = strictRTC, wasDns = blockDnsPrefetch, wasGeo = blockGeolocation, wasEnabled = enabled;
    if (typeof e.data.enabled === "boolean") enabled = e.data.enabled;
    if (typeof e.data.strictRTC === "boolean") strictRTC = e.data.strictRTC;
    if (typeof e.data.preserveSrflx === "boolean") preserveSrflx = e.data.preserveSrflx;
    if (typeof e.data.blockGeolocation === "boolean") blockGeolocation = e.data.blockGeolocation;
    if (typeof e.data.blockDnsPrefetch === "boolean") blockDnsPrefetch = e.data.blockDnsPrefetch;
    if (strictRTC !== wasStrict) installRTC();
    if (blockDnsPrefetch && (!wasDns || (!wasEnabled && enabled))) { try { stripResourceHints(document); fixMeta(); } catch (_) {} }
    if (blockGeolocation !== wasGeo || enabled !== wasEnabled) applyGeo();
  });

  /* ================= IP / VPN / 节点泄露：WebRTC ================= */
  const NativeCtor = window.RTCPeerConnection || window.webkitRTCPeerConnection;
  const NATIVE_GETSTATS = NativeCtor && NativeCtor.prototype && NativeCtor.prototype.getStats;

  function addrOfCandidate(evt) {
    const c = evt && evt.candidate;
    if (!c) return "";
    let addr = c.address || "";
    if (!addr && c.candidate) { const p = String(c.candidate).split(" "); addr = p[4] || ""; }
    return addr;
  }
  function typeOfCandidate(evt) { const c = evt && evt.candidate; return c ? String(c.type || "").toLowerCase() : ""; }
  function isMdns(addr) { return /\.local$/i.test(addr || ""); }

  function shouldBlockCandidate(evt) {
    if (!enabled) return false;
    const addr = addrOfCandidate(evt), type = typeOfCandidate(evt);
    if (strictRTC) return true;
    if (isMdns(addr)) return false; // 匿名牌，不泄露真实 IP
    if (type === "host" || type === "") {
      if (LOCAL_RE.test(addr)) return true;
      // 公网 host 候选（少见）也视为泄露真实 IP
      if (IPV4_RE.test(addr)) return true;
      return false;
    }
    if (type === "srflx" || type === "prflx") return !preserveSrflx; // 视配置决定是否保留公网候选
    return false;
  }

  const wrappedMap = new WeakMap();
  function wrapListener(fn) {
    if (typeof fn !== "function") return fn;
    if (wrappedMap.has(fn)) return wrappedMap.get(fn);
    const w = function (evt) {
      if (evt && evt.type === "icecandidate") {
        const addr = addrOfCandidate(evt);
        const blocked = shouldBlockCandidate(evt);
        reportCandidate({ type: typeOfCandidate(evt) || "unknown", address: addr, blocked: blocked, mdns: isMdns(addr) });
        if (blocked) { notify("webrtc_ip", "blocked-candidate"); return; }
      }
      if (evt && evt.type === "icecandidateerror") { notify("webrtc_ip", "ice-error-suppressed"); return; }
      return fn.call(this, evt);
    };
    wrappedMap.set(fn, w);
    return w;
  }

  function scrubStatsReport(report) {
    // Report 可能是 RTCStatsReport（Map-like）或数组；尽量就地清洗 IP 字段。
    try {
      const scrub = function (obj) {
        if (!obj || typeof obj !== "object") return;
        ["address", "ip", "relatedAddress", "localAddress", "remoteAddress", "candidateAddress"].forEach(function (k) {
          if (typeof obj[k] === "string" && obj[k] && (LOCAL_RE.test(obj[k]) || IPV4_RE.test(obj[k]))) obj[k] = "***";
        });
        if (typeof obj.candidate === "string" && obj.candidate) {
          const p = obj.candidate.split(" ");
          if (p[4] && (LOCAL_RE.test(p[4]) || IPV4_RE.test(p[4]))) { p[4] = "***"; obj.candidate = p.join(" "); }
        }
      };
      if (typeof report.forEach === "function") report.forEach(function (v) { scrub(v); });
      else if (Array.isArray(report)) report.forEach(scrub);
    } catch (_) {}
    return report;
  }

  function guardPc(pc) {
    // addEventListener（含 icecandidate / icecandidateerror 过滤）
    try {
      const origAdd = pc.addEventListener;
      pc.addEventListener = function (type, listener, opts) {
        if (type === "icecandidate" || type === "icecandidateerror") return origAdd.call(this, type, wrapListener(listener), opts);
        return origAdd.call(this, type, listener, opts);
      };
    } catch (_) {}

    // onicecandidate 属性（关键：回写原生 setter）
    try {
      const proto = NativeCtor && NativeCtor.prototype;
      const desc = proto ? Object.getOwnPropertyDescriptor(proto, "onicecandidate") : null;
      Object.defineProperty(pc, "onicecandidate", {
        configurable: true,
        get: function () { return this.__pgOnIce || null; },
        set: function (fn) {
          this.__pgOnIce = fn;
          const wrapped = wrapListener(fn);
          try { if (desc && desc.set) desc.set.call(this, wrapped); else this.__pgOnIceNative = wrapped; } catch (_) {}
        }
      });
    } catch (_) {}

    // onicecandidateerror 屏蔽
    try {
      const proto = NativeCtor && NativeCtor.prototype;
      const descErr = proto ? Object.getOwnPropertyDescriptor(proto, "onicecandidateerror") : null;
      Object.defineProperty(pc, "onicecandidateerror", {
        configurable: true,
        get: function () { return this.__pgOnIceErr || null; },
        set: function (fn) {
          this.__pgOnIceErr = fn;
          const wrapped = wrapListener(fn);
          try { if (descErr && descErr.set) descErr.set.call(this, wrapped); } catch (_) {}
        }
      });
    } catch (_) {}

    // getStats 清洗本地 IP
    try {
      if (NATIVE_GETSTATS) {
        pc.getStats = function () {
          const p = NATIVE_GETSTATS.apply(this, arguments);
          if (p && typeof p.then === "function") return p.then(function (r) { return scrubStatsReport(r); });
          return scrubStatsReport(p);
        };
      }
    } catch (_) {}
  }

  function WrappedRTC(config) {
    const pc = new NativeCtor(config);
    try { guardPc(pc); } catch (_) {}
    return pc;
  }

  function installRTC() {
    if (typeof NativeCtor !== "function") return;
    try {
      if (strictRTC) {
        const blocked = function () { notify("webrtc_ip", "rtc-disabled"); throw new Error("隐私守护：WebRTC 已被停用以防 IP 泄露"); };
        window.RTCPeerConnection = blocked;
        if (window.webkitRTCPeerConnection) window.webkitRTCPeerConnection = blocked;
      } else {
        window.RTCPeerConnection = WrappedRTC;
        if (window.webkitRTCPeerConnection === NativeCtor) window.webkitRTCPeerConnection = WrappedRTC;
      }
    } catch (_) {}
  }

  if (typeof NativeCtor === "function") {
    WrappedRTC.prototype = NativeCtor.prototype;
    try {
      Object.getOwnPropertyNames(NativeCtor).forEach(function (k) {
        if (k === "prototype" || k === "length" || k === "name") return;
        if (!(k in WrappedRTC)) { try { WrappedRTC[k] = NativeCtor[k]; } catch (_) {} }
      });
    } catch (_) {}
    installRTC();
  }

  /* ================= DNS 泄露：资源提示 ================= */
  // 只中和"纯预取/预连接"提示；不处理 preload/modulepreload（它们是页面渲染必需资源，移除会破坏跨域 CDN 加载）。
  const HINT_SEL = 'link[rel~="dns-prefetch" i],link[rel~="preconnect" i],link[rel~="prefetch" i],link[rel~="prerender" i]';
  const HINT_FALLBACK = 'link[rel="dns-prefetch"],link[rel="preconnect"],link[rel="prefetch"],link[rel="prerender"]';

  function stripResourceHints(root) {
    if (!root || !root.querySelectorAll || !enabled || !blockDnsPrefetch) return 0;
    let n = 0, links;
    try { links = root.querySelectorAll(HINT_SEL); } catch (_) { links = root.querySelectorAll(HINT_FALLBACK); }
    links.forEach(function (el) {
      const href = (el.getAttribute && (el.getAttribute("href") || el.getAttribute("data-href"))) || "";
      let cross = false;
      try { cross = href ? new URL(href, location.href).hostname !== location.hostname : false; } catch (_) {}
      if (cross) { try { el.remove(); } catch (_) {} n++; notify("dns_prefetch", href); }
    });
    return n;
  }

  function fixMeta() {
    try {
      document.querySelectorAll('meta[http-equiv="x-dns-prefetch-control" i]').forEach(function (m) {
        if (String(m.getAttribute("content") || "").toLowerCase() === "on") { m.setAttribute("content", "off"); notify("dns_prefetch", "meta-off"); }
      });
    } catch (_) {}
  }

  try { stripResourceHints(document); } catch (_) {}
  try { fixMeta(); } catch (_) {}
  document.addEventListener("DOMContentLoaded", function () { try { fixMeta(); } catch (_) {} });

  try {
    const target = document.documentElement || document;
    const mo = new MutationObserver(function (muts) {
      if (!enabled || !blockDnsPrefetch) return;
      for (const m of muts) {
        if (!m.addedNodes) continue;
        m.addedNodes.forEach(function (node) {
          if (node && node.nodeType === 1) {
            try { stripResourceHints(node.tagName === "LINK" ? (node.parentNode || document) : node); } catch (_) {}
          }
        });
      }
    });
    mo.observe(target, { childList: true, subtree: true });
  } catch (_) {}

  /* ================= 位置泄露：geolocation（可实时开关） ================= */
  function applyGeo() {
    try {
      if (!nativeGeo) return;
      if (enabled && blockGeolocation) {
        navigator.geolocation.getCurrentPosition = function (success, error) {
          if (typeof error === "function") { try { error({ code: 1, message: "隐私守护：已阻止精确位置获取" }); } catch (_) {} }
          notify("geolocation", "blocked");
        };
        navigator.geolocation.watchPosition = function () { notify("geolocation", "blocked-watch"); return 0; };
        navigator.geolocation.clearWatch = function () {};
      } else {
        restoreGeo();
      }
    } catch (_) {}
  }
  function restoreGeo() {
    try {
      if (!nativeGeo) return;
      if (nativeGetCurrent) navigator.geolocation.getCurrentPosition = nativeGetCurrent.bind(nativeGeo);
      if (nativeWatchPosition) navigator.geolocation.watchPosition = nativeWatchPosition.bind(nativeGeo);
    } catch (_) {}
  }
  applyGeo();
})();
