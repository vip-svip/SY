#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_icons.py — 生成 Android 启动图标（纯标准库，不依赖 PIL）

为什么要自己画：
  Android 7.x 的启动器对矢量图标支持不完整，必须有位图兜底；
  而环境里没有 Pillow，所以直接用 zlib 手写 PNG。

图形：圆角方形渐变底 + 同心弧线 + 中心圆点（网络/路由语义），
几何图形在任何尺寸下都清晰，小到 48px 也不糊。

用法:
  python tools/make_icons.py <输出根目录>
  会写出 res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png
"""
import math
import os
import struct
import sys
import zlib

# 各密度的启动图标边长
DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

# 自适应图标前景用更大画布，安全区 66/108
ADAPTIVE = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    return tuple(int(round(lerp(c1[i], c2[i], t))) for i in range(3))


def rounded_rect_alpha(x, y, size, radius, inset=0.0):
    """圆角方形内部判定，返回 0..1 的覆盖率（用 2x2 超采样近似抗锯齿）。"""
    hits = 0
    for sx in (0.25, 0.75):
        for sy in (0.25, 0.75):
            px, py = x + sx, y + sy
            lo = inset
            hi = size - inset
            if px < lo or px > hi or py < lo or py > hi:
                continue
            # 四个角
            cx = min(max(px, lo + radius), hi - radius)
            cy = min(max(py, lo + radius), hi - radius)
            if (px - cx) ** 2 + (py - cy) ** 2 <= radius * radius:
                hits += 1
    return hits / 4.0


def ring_alpha(x, y, cx, cy, r, width):
    """圆环覆盖率。"""
    hits = 0
    for sx in (0.25, 0.75):
        for sy in (0.25, 0.75):
            d = math.hypot(x + sx - cx, y + sy - cy)
            if abs(d - r) <= width / 2.0:
                hits += 1
    return hits / 4.0


def disc_alpha(x, y, cx, cy, r):
    hits = 0
    for sx in (0.25, 0.75):
        for sy in (0.25, 0.75):
            if math.hypot(x + sx - cx, y + sy - cy) <= r:
                hits += 1
    return hits / 4.0


def draw_icon(size, bg=True, fg_only=False):
    """画一张 size×size 的 RGBA 图。fg_only=True 时只画前景（自适应图标用）。"""
    top = (91, 91, 214)      # #5B5BD6
    bottom = (139, 92, 246)  # #8B5CF6
    white = (255, 255, 255)

    if fg_only:
        # 自适应图标前景：画布放大，图形落在中间安全区
        scale = size / 108.0 * 66.0 / 48.0
        cx = cy = size / 2.0
    else:
        scale = 1.0
        cx = cy = size / 2.0

    radius = size * 0.22 if not fg_only else 0.0

    # 图形按 48 单位设计再等比缩放。
    # 自适应图标的前景画布更大（108 单位里只占中间 66 单位安全区），
    # 所以单位要按安全区换算，否则图形会被裁掉。
    if fg_only:
        u = (size * (66.0 / 108.0)) / 48.0
    else:
        u = size / 48.0

    dot_r = 3.4 * u
    arc_r = [8.5 * u, 14.0 * u, 19.5 * u]
    arc_w = 2.6 * u

    rows = []
    for y in range(size):
        row = bytearray()
        for x in range(size):
            if fg_only:
                a_bg = 0.0
                col = white
            else:
                a_bg = rounded_rect_alpha(x, y, size, radius)
                t = (y / max(1, size - 1))
                col = mix(top, bottom, t)

            # 前景图形：以中心偏下为圆心的同心弧 + 中心点
            oy = cy - 2.0 * u
            alpha_fg = 0.0
            for r in arc_r:
                alpha_fg = max(alpha_fg, ring_alpha(x, y, cx, oy, r, arc_w))
            alpha_fg = max(alpha_fg, disc_alpha(x, y, cx, oy, dot_r))

            if fg_only:
                r_, g_, b_ = white
                a = int(round(255 * alpha_fg))
            else:
                r_ = int(round(lerp(col[0], white[0], alpha_fg)))
                g_ = int(round(lerp(col[1], white[1], alpha_fg)))
                b_ = int(round(lerp(col[2], white[2], alpha_fg)))
                a = int(round(255 * a_bg))
            row += bytes((r_, g_, b_, a))
        rows.append(bytes(row))
    return rows


def write_png(path, rows, size):
    raw = b"".join(b"\x00" + r for r in rows)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "app/res"
    n = 0
    for d, sz in DENSITIES.items():
        write_png(os.path.join(root, "mipmap-" + d, "ic_launcher.png"),
                  draw_icon(sz), sz)
        n += 1
    for d, sz in ADAPTIVE.items():
        write_png(os.path.join(root, "mipmap-" + d, "ic_launcher_foreground.png"),
                  draw_icon(sz, fg_only=True), sz)
        n += 1
    print("wrote %d png files under %s" % (n, root))


if __name__ == "__main__":
    main()
