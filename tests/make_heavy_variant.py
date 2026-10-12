# -*- coding: utf-8 -*-
"""受控对照：把「重玻璃」样式加回当前面板，DOM 完全不变。

用途：隔离验证「backdrop-filter 铺满全页 + feTurbulence 噪点层」这一
单一变量对 Android WebView 渲染性能的影响。生成结果仅用于性能对照，
不进入发布包。

用法: python tests/_make_heavy.py <输入 index.html> <输出 index.html>
"""
import io, re, sys

src_path, dst_path = sys.argv[1], sys.argv[2]
with io.open(src_path, "r", encoding="utf-8") as f:
    html = f.read()

# 复原「改动前」的重玻璃特征：
#   1) backdrop-filter 铺到所有玻璃面（卡片/指标卡/按钮/列表/页标题/子标签…）
#   2) 全屏 SVG feTurbulence 噪点层（每帧重算）
#   3) 常驻 CSS 动画（呼吸光晕）
HEAVY = u"""
/* ===== 受控对照：复原「改动前」的重玻璃特征（仅用于性能测试） ===== */
.card,.metric,.btn,.kv,.list,.tagline,.page-title,.subtab,.stat,
.card-head,.row,.container,.t,.l,.n,.empty{
  -webkit-backdrop-filter:blur(16px) saturate(180%);
  backdrop-filter:blur(16px) saturate(180%);
}
.card{background:rgba(255,255,255,.42)!important}
.metric,.stat{background:rgba(255,255,255,.36)!important}
.btn{background:rgba(255,255,255,.34)!important}
.page-title{background:rgba(255,255,255,.30)!important}
/* 常驻动画：持续触发重绘 */
@keyframes __heavyBreathe{
  0%{box-shadow:0 0 0 0 rgba(94,186,0,.28)}
  50%{box-shadow:0 0 26px 8px rgba(94,186,0,.16)}
  100%{box-shadow:0 0 0 0 rgba(94,186,0,.28)}
}
.card{animation:__heavyBreathe 2.6s ease-in-out infinite}
/* 全屏噪点层：feTurbulence 每帧重算 */
#__heavyNoise{
  position:fixed;inset:0;z-index:9998;pointer-events:none;
  opacity:.05;mix-blend-mode:overlay;
}
"""

NOISE_SVG = (u'<svg id="__heavyNoise" xmlns="http://www.w3.org/2000/svg" '
             u'preserveAspectRatio="none"><filter id="__hn">'
             u'<feTurbulence type="fractalNoise" baseFrequency="0.82" '
             u'numOctaves="4" stitchTiles="stitch"/></filter>'
             u'<rect width="100%" height="100%" filter="url(#__hn)"/></svg>')

# 把重玻璃 CSS 追加到最后一个 </style> 之前
idx = html.rfind(u"</style>")
assert idx > 0, u"未找到 </style>"
html = html[:idx] + HEAVY + html[idx:]

# 噪点层插到 </body> 之前
bidx = html.rfind(u"</body>")
assert bidx > 0, u"未找到 </body>"
html = html[:bidx] + NOISE_SVG + html[bidx:]

with io.open(dst_path, "w", encoding="utf-8") as f:
    f.write(html)

print(u"已生成受控变体: %s" % dst_path)
print(u"  注入 backdrop-filter 选择器: 15 组")
print(u"  注入 feTurbulence 噪点层: 1 个 (全屏)")
print(u"  注入常驻 animation: 1 个")
print(u"  产物大小: %d B" % len(html.encode("utf-8")))
