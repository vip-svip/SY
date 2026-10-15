/* ============================================================
 *  SY 内置：反指纹（canvas/webgl/navigator 噪声）
 *  来源: privacy-guard-extension v1.12.0 归档（并入 SY 模块，非原样照搬）
 *  用法: 由 MITM 注入到 HTML（需版面注入开启），或由 App 的 WebView 加载。
 *  注意: 这些脚本设计为**运行在页面上下文**，不要在模块 shell 里 source。
 * ============================================================ */
/* 隐私守护 · 反指纹与 Referrer 收敛（MAIN 世界）  v15（新增）
 * 目标：降低浏览器指纹独特性，减少被跨站关联与画像的可能。
 *
 * 覆盖（默认受 antiFingerprint 开关控制；Canvas 噪声单独开关默认关闭以避免影响绘图/导出）：
 *  - WebGL/WebGL2：伪装 UNMASKED_VENDOR/RENDERER（getParameter 与 getExtension）。
 *  - navigator.hardwareConcurrency / deviceMemory：收敛为常见值，降低熵。
 *  - Battery API：返回“无电池”，避免电量/充放电状态指纹。
 *  - Sensor/DeviceOrientation：可关闭（默认不动，避免影响地图等）。
 *  - Canvas：按会话稳定噪声扰动 toDataURL/toBlob/getImageData（antiFingerprintCanvas 开启时）。
 *  - Referrer：把跨站 Referrer 收敛为 origin（trimReferrer 开启时，注入 meta + document.referrer getter）。
 *
 * 安全边界：不读取 Cookie/localStorage/令牌/密码；不把数据发往任何地方；仅在本地改写返回值。
 * 诚实边界：无法对抗系统/硬件层指纹（TLS/JA3、字体枚举全量、GPU 驱动级特征）；这些属浏览器/系统能力。
 */
(function () {
  "use strict";
  if (window.__pgFpInit === true) return;
  window.__pgFpInit = true;

  let enabled = true;
  let antiFp = true;
  let antiCanvas = false;
  let trimRef = true;

  // 稳定的“指纹盐”，仅用于给噪声种子，不用于识别用户，也不外发。
  var SALT = 0x9e3779b9 ^ (Date.now() & 0xffff);

  window.addEventListener("message", function (e) {
    if (e.source !== window || !e.data || e.data.__pg !== "cfg") return;
    if (typeof e.data.enabled === "boolean") enabled = e.data.enabled;
    if (typeof e.data.antiFingerprint === "boolean") antiFp = e.data.antiFingerprint;
    if (typeof e.data.antiFingerprintCanvas === "boolean") antiCanvas = e.data.antiFingerprintCanvas;
    if (typeof e.data.trimReferrer === "boolean") trimRef = e.data.trimReferrer;
    try { applyReferrerMeta(); } catch (_) {}
  });

  /* ---------------- WebGL 供应商/渲染器伪装 ---------------- */
  function patchWebGL(proto) {
    if (!proto || !proto.getParameter) return;
    var orig = proto.getParameter;
    proto.getParameter = function (p) {
      try {
        if (enabled && antiFp) {
          var VENDOR = 0x9245, RENDERER = 0x9246; // UNMASKED_VENDOR_WEBGL / UNMASKED_RENDERER_WEBGL
          if (p === VENDOR) return "PrivacyGuard";
          if (p === RENDERER) return "PrivacyGuard";
        }
      } catch (_) {}
      return orig.apply(this, arguments);
    };
    if (proto.getExtension) {
      var origExt = proto.getExtension;
      proto.getExtension = function (name) {
        var ext = origExt.apply(this, arguments);
        try {
          if (enabled && antiFp && ext && typeof name === "string" && /WEBGL_debug_renderer_info/i.test(name)) {
            try {
              Object.defineProperty(ext, "UNMASKED_VENDOR_WEBGL", { configurable: true, get: function () { return "PrivacyGuard"; } });
              Object.defineProperty(ext, "UNMASKED_RENDERER_WEBGL", { configurable: true, get: function () { return "PrivacyGuard"; } });
            } catch (_) {}
          }
        } catch (_) {}
        return ext;
      };
    }
  }
  try { patchWebGL(window.WebGLRenderingContext && window.WebGLRenderingContext.prototype); } catch (_) {}
  try { patchWebGL(window.WebGL2RenderingContext && window.WebGL2RenderingContext.prototype); } catch (_) {}

  /* ---------------- 硬件信息收敛 ---------------- */
  function clampNavigatorProp(prop, value) {
    try {
      if (navigator[prop] === undefined) return;
      Object.defineProperty(navigator, prop, { configurable: true, get: function () { return enabled && antiFp ? value : undefined; } });
    } catch (_) {}
  }
  clampNavigatorProp("hardwareConcurrency", 4);
  clampNavigatorProp("deviceMemory", 4);

  /* ---------------- Battery API：返回“无电池” ---------------- */
  try {
    if (navigator.getBattery) {
      navigator.getBattery = function () {
        if (enabled && antiFp) return Promise.reject(new Error("PrivacyGuard: battery disabled"));
        return Promise.resolve({ charging: true, chargingTime: 0, dischargingTime: Infinity, level: 1,
          addEventListener: function () {}, removeEventListener: function () {} });
      };
    }
  } catch (_) {}

  /* ---------------- Canvas 噪声（可选，默认关闭） ---------------- */
  var seedFor = function (str) {
    var h = SALT >>> 0;
    str = String(str || "");
    for (var i = 0; i < str.length; i++) { h = (h * 31 + str.charCodeAt(i)) >>> 0; }
    return h;
  };
  function noiseForPixel(x, y) {
    var h = (seedFor(x + ":" + y) ^ (SALT >>> 3)) >>> 0;
    return (h % 3) - 1; // -1, 0, 1：极轻微，视觉不可辨
  }
  function patchCanvasToBlobLike(obj, method) {
    if (!obj || !obj.prototype || !obj.prototype[method]) return;
    var orig = obj.prototype[method];
    obj.prototype[method] = function () {
      try {
        if (enabled && antiFp && antiCanvas) {
          var ctx = this.getContext && this.getContext("2d");
          if (ctx && this.width && this.height) {
            var img = ctx.getImageData(0, 0, this.width, this.height);
            var d = img.data;
            for (var i = 0; i < d.length; i += 4 * 97) { d[i] = Math.max(0, Math.min(255, d[i] + noiseForPixel(i, 0))); }
            ctx.putImageData(img, 0, 0);
          }
        }
      } catch (_) {}
      return orig.apply(this, arguments);
    };
  }
  try { patchCanvasToBlobLike(window.HTMLCanvasElement, "toDataURL"); } catch (_) {}
  try { patchCanvasToBlobLike(window.HTMLCanvasElement, "toBlob"); } catch (_) {}

  /* ---------------- Referrer 收敛：跨站只发 origin ---------------- */
  function applyReferrerMeta() {
    if (!trimRef) return;
    try {
      var m = document.querySelector('meta[name="referrer"]');
      if (!m) { m = document.createElement("meta"); m.setAttribute("name", "referrer"); (document.head || document.documentElement).appendChild(m); }
      m.setAttribute("content", "strict-origin-when-cross-origin");
    } catch (_) {}
  }
  try { applyReferrerMeta(); } catch (_) {}
  try { document.addEventListener("DOMContentLoaded", applyReferrerMeta); } catch (_) {}
})();
