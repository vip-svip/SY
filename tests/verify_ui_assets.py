# -*- coding: utf-8 -*-
"""面板资产回归校验

把 webroot/index.html 与 tests/ui_baseline.json 基线清单对比，
确保重构 UI 骨架时不会丢功能；同时执行性能护栏检查。

基线清单在 UI 大改后可用 --regen 重新生成（需人工确认功能无丢失）。

用法:
    python tests/verify_ui_assets.py            # 校验
    python tests/verify_ui_assets.py --regen    # 重建基线
"""
import io, os, re, sys, json, collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "webroot", "index.html")
BASE = os.path.join(ROOT, "tests", "ui_baseline.json")

raw = io.open(SRC, encoding="utf-8").read()
markup = re.sub(r"<script\b[^>]*>.*?</script>", "", raw, flags=re.S | re.I)
blocks = re.findall(r"<script>\s*\n(.*?)\n</script>", raw, re.S)
js = max(blocks, key=len) if blocks else ""
js_all = "\n".join(re.findall(r"<script\b[^>]*>(.*?)</script>", raw, re.S | re.I))
# JS 动态生成的行内按钮（删除/选择/开关等）
dyn_acts = set(re.findall(r'data-act=\\?"([a-z0-9\-]+)\\?"', js_all))

cur = {
    "ids": sorted(set(re.findall(r'\sid="([^"]+)"', markup))),
    "acts": sorted(set(re.findall(r'data-act="([^"]+)"', markup)) | dyn_acts),
    "tabs": sorted(set(re.findall(r'data-tab="([^"]+)"', markup))),
    "subs": sorted(set(re.findall(r'data-sub="([^"]+)"', markup))),
    "nbs": sorted(set(re.findall(r'data-nb="([^"]+)"', markup))),
    "pages": sorted(set(re.findall(r'id="page-([^"]+)"', markup))),
    "ks": sorted(set(re.findall(r'data-k="([^"]+)"', markup))),
    "actions": sorted(set(re.findall(r'^\s*"([a-z0-9\-]+)"\s*:\s*function', js, re.M))),
    "fns": sorted(set(re.findall(r"function\s+([A-Za-z_$][\w$]*)\s*\(", js))),
}

if "--regen" in sys.argv:
    json.dump(cur, io.open(BASE, "w", encoding="utf-8", newline="\n"),
              ensure_ascii=False, indent=1)
    print("已重建基线 %s" % BASE)
    for k, v in cur.items():
        print("  %-8s %d" % (k, len(v)))
    sys.exit(0)

base = json.load(io.open(BASE, encoding="utf-8"))
ok = True
LABEL = {"ids": "元素 id", "acts": "data-act", "tabs": "data-tab", "subs": "data-sub",
         "nbs": "data-nb", "pages": "page 页面", "ks": "data-k",
         "actions": "actions 处理器", "fns": "JS 函数"}

for k, label in LABEL.items():
    a, b = set(base[k]), set(cur[k])
    miss, extra = sorted(a - b), sorted(b - a)
    if miss or extra:
        ok = False
        print("[X] %-14s 缺失=%s 新增=%s" % (label, miss or "-", extra or "-"))
    else:
        print("[OK] %-14s %d 项完全一致" % (label, len(a)))

# 每个 data-act 都要有处理器；每个处理器都应有按钮
orphan = sorted(set(cur["acts"]) - set(cur["actions"]))
if orphan:
    ok = False
    print("[X] data-act 无处理器: %s" % orphan)
else:
    print("[OK] %d 个 data-act 全部有处理器" % len(cur["acts"]))
unused = sorted(set(cur["actions"]) - set(cur["acts"]))
if unused:
    print("[!] 处理器无按钮绑定: %s" % unused)

# JS 引用的 id 必须存在
dom_ids = set(cur["ids"])
ref = set(re.findall(r'setText\(\s*"([^"]+)"', js))
ref |= set(re.findall(r'getElementById\(\s*"([^"]+)"', js))
ref |= set(re.findall(r'\$\(\s*"#([A-Za-z0-9_\-]+)"\s*\)', js))
missing = sorted(ref - dom_ids - {"toast"})
if missing:
    print("[!] JS 引用但 DOM 未找到的 id: %s" % missing)
else:
    print("[OK] JS 引用的 id 全部存在")

# id 唯一性
dup = [k for k, v in collections.Counter(re.findall(r'\sid="([^"]+)"', markup)).items() if v > 1]
if dup:
    ok = False
    print("[X] 重复 id: %s" % dup)
else:
    print("[OK] id 唯一")

# ---------------- 性能护栏 ----------------
css = "".join(re.findall(r"<style[^>]*>(.*?)</style>", raw, re.S | re.I))
bf = re.findall(r"([^{}]+)\{([^{}]*backdrop-filter[^{}]*)\}", css)
stray = [s.strip().replace("\n", " ") for s, _ in bf
         if "header" not in s and "dropdown-menu" not in s]
if stray:
    ok = False
    print("[X] backdrop-filter 泄漏到 %s（会在低端机造成严重卡顿）" % stray)
else:
    print("[OK] backdrop-filter 仅用于 .header / .dropdown-menu（%d 条）" % len(bf))
if len(bf) > 4:
    ok = False
    print("[X] backdrop-filter 规则过多 %d 条" % len(bf))

if re.search(r"<filter\b|<feTurbulence\b", raw):
    ok = False
    print("[X] 存在 SVG 滤镜噪点层节点")
else:
    print("[OK] 无 SVG 滤镜噪点层")

anim = re.findall(r"(?:^|[;{\s])animation\s*:", css)
if anim:
    ok = False
    print("[X] CSS 含 %d 处 animation 声明" % len(anim))
else:
    print("[OK] CSS 无 animation 声明")

fx = len(re.findall(r"position\s*:\s*fixed", css))
if fx > 3:
    ok = False
    print("[X] position:fixed 层过多 %d 个" % fx)
else:
    print("[OK] position:fixed 层 %d 个" % fx)

# 设计令牌必须齐备（深色为默认主题，浅色为主题覆盖）
for tok in ("--bgcolor:#0b0f14", "--mcolor:#e6edf3", "--green:#3fb950",
            "--accent:#58a6ff", "--lat0:#3fb950",
            "--bgcolor:#f6f8fa", "--mcolor:#1f2328", "--green:#1a7f37",
            "--card-border-color", "--stats-card--ads", "--glass-blur"):
    if tok in raw:
        print("[OK] 设计令牌 %s" % tok)
    else:
        ok = False
        print("[X] 缺少设计令牌 %s" % tok)

print()
print("===> %s" % ("全部通过" if ok else "存在问题"))
sys.exit(0 if ok else 1)
