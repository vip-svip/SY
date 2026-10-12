# -*- coding: utf-8 -*-
"""真机 WebView 渲染性能对比（Android 端回归工具）

回答的问题：面板"卡不卡"是可以在真机上被量化复现的吗？

方法学要点（相对朴素做法的四处修正）：
  1. 图层选择：排除 `ActivityRecordInputSink` 等无缓冲队列的层，
     并实测筛选出真正有非零时间戳的应用窗口层。
  2. 冷启动污染：先等页面完全加载并静止，再 reset gfxinfo，
     把首次渲染/首屏布局排除在样本外。
  3. 交互等价：固定手势次数与每次手势时长，两版本承受完全相同的输入负载；
     并额外给出**按帧数归一化**的比率（丢 Vsync 率 / UI 超时率 / 绘制超时率），
     因为 gfxinfo 的绝对次数会随帧数变化，只有归一化后才有可比性。
  4. 采样噪声：每项重复 ROUNDS 轮取中位数；渲染进程偶发异常态会导致整轮空转，
     由 probe_alive() 检测并自动重试。

已知限制：Android 13 起应用窗口层走 BLAST 缓冲，`SurfaceFlinger --latency`
对本机窗口层返回全零（脚本会打印"呈现间隔: 无样本"）。因此结论以 gfxinfo 的
帧耗时分位、卡顿帧占比与归一化超时率为准——这三者已足以判定"卡不卡"。

配套：
  tests/make_heavy_variant.py  生成"重玻璃"受控变体（DOM 完全不变，只改 CSS），
                               用于隔离验证 backdrop-filter / feTurbulence 的代价
  tests/perf_serve.sh          在设备上起多个静态面板服务，供多版本同机对比

用法: python tests/perf_compare.py <serial> <标签=URL> [<标签=URL> ...]
例:   python tests/perf_compare.py 6c8dc14781cf \
          "新面板=http://127.0.0.1:8848/index.html" \
          "旧面板=http://127.0.0.1:8849/index.html" \
          "重玻璃=http://127.0.0.1:8850/index.html"
"""
import re, statistics, subprocess, sys, time

# Windows 上 Python 默认把 stdout 的 \n 翻译成 \r\n，重定向到文件会写入 CRLF，
# 而本仓库的编码卫生检查要求全部文本文件为 LF。这里强制统一为 LF。
try:
    sys.stdout.reconfigure(newline="\n")
except Exception:
    pass

SERIAL = sys.argv[1]
TARGETS = []
for a in sys.argv[2:]:
    label, _, url = a.partition("=")
    TARGETS.append((label, url))

PKG = "com.android.browser"
ROUNDS = 3
SETTLE = 8.0          # 页面加载 + 数据渲染完成后再开始采样
BURST_ITER = 22       # 固定手势次数（每轮 = 下滚 + 上滚）
SWIPE_MS = 250
X, Y_TOP, Y_BOT = 540, 1750, 780


def adb(*a, timeout=600):
    return subprocess.run(["adb", "-s", SERIAL] + list(a), capture_output=True,
                          text=True, encoding="utf-8", errors="replace",
                          timeout=timeout).stdout


def sh(cmd, timeout=600):
    return adb("shell", cmd, timeout=timeout)


# ---------------- gfxinfo ----------------

def reset_gfx():
    sh("dumpsys gfxinfo %s reset" % PKG)


def read_gfx():
    out = sh("dumpsys gfxinfo %s" % PKG)
    d = {}
    m = re.search(r"Total frames rendered:\s*(\d+)", out)
    d["total"] = int(m.group(1)) if m else 0
    m = re.search(r"Janky frames:\s*(\d+)\s*\(([\d.]+)%\)", out)
    d["janky"] = int(m.group(1)) if m else 0
    d["janky_pct"] = float(m.group(2)) if m else 0.0
    for k in ("50th", "90th", "95th", "99th"):
        m = re.search(r"%s percentile:\s*(\d+)ms" % k, out)
        d[k] = int(m.group(1)) if m else -1
    for key, pat in (("missed_vsync", r"Number Missed Vsync:\s*(\d+)"),
                     ("slow_ui", r"Number Slow UI thread:\s*(\d+)"),
                     ("slow_draw", r"Number Slow issue draw commands:\s*(\d+)"),
                     ("high_input", r"Number High input latency:\s*(\d+)"),
                     ("hms", r"Janky frames \(legacy\)|HISTOGRAM")):
        m = re.search(pat, out)
        d[key] = int(m.group(1)) if (m and pat.endswith(r"(\d+)")) else -1
    return d


# ---------------- SurfaceFlinger 呈现间隔 ----------------

BAD_LAYER = ("ActivityRecordInputSink", "ActivityRecord{", "Background for",
             "Splash Screen", "Bounds for", "TouchEventReceiver",
             "InputMethod", "StatusBar", "NavigationBar")


def pick_layer():
    """挑出真正带缓冲队列的应用窗口层"""
    layers = [l.strip() for l in sh("dumpsys SurfaceFlinger --list").splitlines()]
    cands = []
    for l in layers:
        if PKG not in l:
            continue
        if any(b in l for b in BAD_LAYER):
            continue
        cands.append(l)
    return cands


def latency_of(layer):
    sh("dumpsys SurfaceFlinger --latency-clear '%s'" % layer)
    out = sh("dumpsys SurfaceFlinger --latency '%s'" % layer)
    lines = out.strip().splitlines()
    ts = []
    for ln in lines[1:]:
        p = ln.split()
        if len(p) >= 3 and p[1].isdigit():
            v = int(p[1])
            if v > 0:
                ts.append(v)
    ts.sort()
    gaps = [(ts[i + 1] - ts[i]) / 1e6 for i in range(len(ts) - 1)]
    return [g for g in gaps if 0 < g < 500]


# ---------------- 交互 ----------------

def burst():
    """设备端一次性跑完手势，避免 adb 往返开销干扰手势密度"""
    loop = ("i=0; while [ $i -lt %d ]; do "
            "input swipe %d %d %d %d %d; "
            "input swipe %d %d %d %d %d; "
            "i=$((i+1)); done") % (
        BURST_ITER, X, Y_TOP, X, Y_BOT, SWIPE_MS, X, Y_BOT, X, Y_TOP, SWIPE_MS)
    t0 = time.monotonic()
    sh(loop, timeout=900)
    return time.monotonic() - t0


def probe_alive():
    """确认页面真的在绘制：轻扫一次看帧数是否增长"""
    reset_gfx()
    sh("input swipe %d %d %d %d %d" % (X, Y_TOP, X, Y_BOT, SWIPE_MS))
    time.sleep(0.6)
    return read_gfx()["total"]


def one_round(url, attempt=1):
    sh("am force-stop %s" % PKG)
    time.sleep(2.5)
    sh("am start -a android.intent.action.VIEW -d '%s' -p %s" % (url, PKG))
    time.sleep(SETTLE)          # 先让页面彻底加载并静止
    # 样本有效性校验：渲染进程偶发异常态会整轮空转，必须重试
    if probe_alive() <= 0:
        if attempt <= 3:
            print("    ! 样本无效（页面未绘制），重试 %d/3" % attempt)
            time.sleep(3)
            return one_round(url, attempt + 1)
        print("    ! 连续 3 次无效，本轮作废")
        return None
    reset_gfx()                 # 再开始计数 → 排除冷启动首帧
    dur = burst()
    time.sleep(1.5)
    g = read_gfx()
    if g["total"] <= 0 and attempt <= 3:
        print("    ! 采样窗口内 0 帧，重试 %d/3" % attempt)
        time.sleep(3)
        return one_round(url, attempt + 1)
    g["dur"] = dur
    g["fps"] = (g["total"] / dur) if dur > 0 else 0.0
    return g


def median_of(rows, key):
    vals = [r[key] for r in rows if r.get(key) is not None]
    return statistics.median(vals) if vals else None


# ---------------- 主流程 ----------------

print("\n设备: %s   浏览器: %s" % (SERIAL, PKG))
print("每项 %d 轮取中位数 | 加载等待 %.0fs | 手势 %d×2 次 × %dms"
      % (ROUNDS, SETTLE, BURST_ITER, SWIPE_MS))

# 先启动一次以确定真实图层
sh("am force-stop %s" % PKG)
time.sleep(1)
sh("am start -a android.intent.action.VIEW -d '%s' -p %s" % (TARGETS[0][1], PKG))
time.sleep(SETTLE)
cands = pick_layer()
print("\n候选窗口层: %s" % (cands if cands else "（无）"))
LAYER, gaps_probe = None, []
for c in cands:
    gp = latency_of(c)
    print("  %-70s 样本=%d" % (c[:70], len(gp)))
    if gp and len(gp) > len(gaps_probe):
        LAYER, gaps_probe = c, gp
print("选用图层: %s" % (LAYER if LAYER else "（不可用，跳过呈现间隔采集）"))

results = {}
for label, url in TARGETS:
    print("\n" + "=" * 68)
    print("  %s" % label)
    print("=" * 68)
    rows = []
    for r in range(ROUNDS):
        g = one_round(url)
        if g is None:
            continue
        rows.append(g)
        print("  第%d轮: 帧=%-5d 窗口=%.2fs 卡顿=%.2f%%  P50=%dms P90=%dms P95=%dms P99=%dms  "
              "丢Vsync=%d UI超时=%d 绘制超时=%d"
              % (r + 1, g["total"], g["dur"], g["janky_pct"],
                 g["50th"], g["90th"], g["95th"], g["99th"],
                 g["missed_vsync"], g["slow_ui"], g["slow_draw"]))
    if not rows:
        print("  ! 无有效样本，跳过")
        continue
    med = {k: median_of(rows, k) for k in
           ("total", "dur", "janky", "janky_pct", "50th", "90th",
            "95th", "99th", "missed_vsync", "slow_ui", "slow_draw")}
    # 归一化比率：绝对次数受帧数影响，按帧数归一才可跨版本比较
    tot = med["total"] or 1
    med["missed_rate"] = 100.0 * med["missed_vsync"] / tot
    med["ui_rate"] = 100.0 * med["slow_ui"] / tot
    med["draw_rate"] = 100.0 * med["slow_draw"] / tot
    # 呈现间隔（用最优图层，仅第一项有效；其余版本图层名可能相同）
    gl = latency_of(LAYER) if LAYER else []
    if gl:
        gls = sorted(gl)
        n = len(gls)
        med["sf_avg"] = sum(gls) / n
        med["sf_p90"] = gls[int(n * 0.90)]
        med["sf_p99"] = gls[min(n - 1, int(n * 0.99))]
        med["sf_over"] = 100.0 * sum(1 for x in gls if x > 22.2) / n
        med["sf_n"] = n
    results[label] = med
    print("  ── 中位数（%d 轮）──" % len(rows))
    print("  渲染帧数=%.0f  窗口=%.2fs  卡顿帧=%.2f%%" % (med["total"], med["dur"], med["janky_pct"]))
    print("  帧耗时分位: P50=%.0fms P90=%.0fms P95=%.0fms P99=%.0fms"
          % (med["50th"], med["90th"], med["95th"], med["99th"]))
    print("  丢 Vsync=%.0f (%.2f%%)  UI 线程超时=%.0f (%.2f%%)  绘制命令超时=%.0f (%.2f%%)"
          % (med["missed_vsync"], med["missed_rate"], med["slow_ui"], med["ui_rate"],
             med["slow_draw"], med["draw_rate"]))
    if gl:
        print("  呈现间隔: 样本=%.0f 均值=%.2fms P90=%.2fms P99=%.2fms >22.2ms=%.2f%%"
              % (med["sf_n"], med["sf_avg"], med["sf_p90"], med["sf_p99"], med["sf_over"]))
    else:
        print("  呈现间隔: 无样本")

# ---------------- 对比 ----------------
print("\n" + "=" * 68)
print("  对比结论（基准 = %s）" % TARGETS[0][0])
print("=" * 68)


def cmp_line(name, key, unit="", better_low=True):
    base = results[TARGETS[0][0]].get(key)
    if base is None:
        return
    for label, _ in TARGETS[1:]:
        v = results[label].get(key)
        if v is None:
            continue
        d = v - base
        good = (d < 0) if better_low else (d > 0)
        print("  %-14s %s=%-9.2f%s  %s=%-9.2f%s  Δ=%+.2f%s  %s"
              % (name, TARGETS[0][0], base, unit, label, v, unit, d, unit,
                 "改善" if good else ("持平" if d == 0 else "变差")))


print("  —— 越大越好 ——")
cmp_line("渲染帧数", "total", " 帧", better_low=False)
print("  —— 越小越好 ——")
cmp_line("卡顿帧占比", "janky_pct", "%")
cmp_line("P50 帧耗时", "50th", "ms")
cmp_line("P90 帧耗时", "90th", "ms")
cmp_line("P95 帧耗时", "95th", "ms")
cmp_line("P99 帧耗时", "99th", "ms")
cmp_line("丢Vsync率", "missed_rate", "%")
cmp_line("UI线程超时率", "ui_rate", "%")
cmp_line("绘制超时率", "draw_rate", "%")
print()
