#!/system/bin/sh
# ============================================================
#  SY-Fusion 打包脚本
#  用法: sh package.sh [输出目录]
#  流程: 预检 → 打包 → 校验（含 ZIP 内 module.prop 回读）
# ============================================================
set -u

MOD="$(cd "$(dirname "$0")" && pwd)"
cd "$MOD" || exit 1

OUT_DIR="${1:-$MOD/dist}"
mkdir -p "$OUT_DIR" 2>/dev/null

PY=""
for c in python3 python "C:/Users/admin/.workbuddy-ai/binaries/python/versions/3.13.12/python.exe"; do
  command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }
done
[ -n "$PY" ] || { echo "ERR: 需要 python 来打包"; exit 1; }

VER="$(sed -n 's/^version=//p' module.prop | tr -d '\r' | head -n1)"
[ -n "$VER" ] || { echo "ERR: 无法从 module.prop 读取 version"; exit 1; }
ZIP="$OUT_DIR/SY_${VER}.zip"

printf '%s\n' "== 预检 =="
"$PY" - <<'PYEOF'
import os, sys, json
TEXT = {".sh",".awk",".md",".conf",".txt",".prop",".json",".go",".mod",".html",".css",".js",".tsv",".py"}
BIN  = {".zip",".png",".jpg",".jpeg",".webp",".so",".apk",".db",".mmdb",".srs",".dat"}
errs = []
for root, dirs, files in os.walk("."):
    if ".git" in root.split(os.sep): continue
    for f in files:
        p = os.path.join(root, f)
        ext = os.path.splitext(f)[1].lower()
        if ext in BIN or "bin" in root.split(os.sep): continue
        if ext not in TEXT and f not in ("update-binary", "updater-script"): continue
        b = open(p, "rb").read()
        if b.count(b"\r"): errs.append("CR 换行: " + p)
        if b[:3] == b"\xef\xbb\xbf": errs.append("UTF-8 BOM: " + p)
mp = dict(l.split("=", 1) for l in open("module.prop", encoding="utf-8").read().strip().split("\n") if "=" in l)
uj = json.load(open("update.json", encoding="utf-8"))
if mp.get("version") != uj.get("version"):
    errs.append("版本不一致: module.prop=%s update.json=%s" % (mp.get("version"), uj.get("version")))
if str(mp.get("versionCode")) != str(uj.get("versionCode")):
    errs.append("versionCode 不一致")
for need in ("module.prop","customize.sh","service.sh","post-fs-data.sh","uninstall.sh",
             "action.sh","webroot/index.html",
             "META-INF/com/google/android/update-binary",
             "META-INF/com/google/android/updater-script",
             "scripts/route.sh","scripts/installapp.sh",
             "bin/abserver-arm64","bin/abserver-arm","bin/abserver-amd64"):
    if not os.path.exists(need): errs.append("缺少文件: " + need)
if errs:
    print("预检失败:"); [print("  x " + e) for e in errs]; sys.exit(1)
print("  预检通过 (LF/BOM/版本/必备文件)")
PYEOF
[ $? -eq 0 ] || { echo "ERR: 预检未通过，终止打包"; exit 1; }

printf '%s\n' "== 打包 =="
rm -f "$ZIP"
"$PY" - "$ZIP" <<'PYEOF'
import os, sys, zipfile, stat

zip_path = sys.argv[1]
# 打入 ZIP 的目录/文件（tests 一并包含，便于设备上复跑引擎自检）
INCLUDE_DIRS = ["bin", "config", "scripts", "src", "system", "webroot",
                "META-INF", "tests", "app", "rulesets", "data"]
INCLUDE_FILES = ["module.prop", "customize.sh", "post-fs-data.sh", "service.sh",
                 "action.sh", "uninstall.sh", "README.md", "changelog.md",
                 "update.json", ".gitattributes", "ui-preview.html"]
EXEC_EXT = {".sh"}
EXEC_NAMES = {"update-binary"}
# app/build 是构建中间产物（含签名密钥与临时 dex），绝不能进模块包
EXCLUDE_PARTS = {"build"}

entries = []
for d in INCLUDE_DIRS:
    if not os.path.isdir(d): continue
    for root, dirs, files in os.walk(d):
        dirs[:] = sorted(x for x in dirs if x not in EXCLUDE_PARTS)
        for f in sorted(files):
            entries.append(os.path.join(root, f))
for f in INCLUDE_FILES:
    if os.path.isfile(f): entries.append(f)
entries.sort()

total = 0
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for p in entries:
        arc = p.replace(os.sep, "/")
        data = open(p, "rb").read()
        zi = zipfile.ZipInfo(arc, date_time=(2026, 1, 1, 0, 0, 0))
        # data/ 下是已高度优化的二进制库(mmdb/db/dat)：DEFLATE 收益低、还拖慢装机，
        # 直接 STORED；其余文本/脚本仍走 DEFLATE。
        if arc.startswith("data/") and os.path.splitext(arc)[1].lower() in (".mmdb", ".db", ".dat"):
            zi.compress_type = zipfile.ZIP_STORED
        else:
            zi.compress_type = zipfile.ZIP_DEFLATED
        base = os.path.basename(p)
        if base in EXEC_NAMES or os.path.splitext(base)[1] in EXEC_EXT:
            zi.external_attr = (stat.S_IFREG | 0o755) << 16
        else:
            zi.external_attr = (stat.S_IFREG | 0o644) << 16
        z.writestr(zi, data)
        total += len(data)

print("  已写入 %d 个文件, 未压缩 %d 字节 (%.1f MB)" % (len(entries), total, total / 1048576.0))
PYEOF
[ $? -eq 0 ] || { echo "ERR: 打包失败"; exit 1; }

printf '%s\n' "== 校验 ZIP =="
"$PY" - "$ZIP" <<'PYEOF'
import sys, zipfile, io, json
z = zipfile.ZipFile(sys.argv[1])
names = z.namelist()
bad = z.testzip()
if bad: print("  x ZIP 损坏: " + bad); sys.exit(1)
print("  条目数: %d" % len(names))
# 回读 module.prop
mp = z.read("module.prop").decode("utf-8")
d = dict(l.split("=", 1) for l in mp.strip().split("\n") if "=" in l)
print("  module.prop: id=%s version=%s versionCode=%s" % (d.get("id"), d.get("version"), d.get("versionCode")))
uj = json.loads(z.read("update.json").decode("utf-8"))
assert uj["version"] == d["version"], "ZIP 内版本不一致"
# 必须无 CR
cr = [n for n in names if n.endswith((".sh",".awk",".prop",".conf",".json",".html",".py")) and b"\r" in z.read(n)]
if cr: print("  x ZIP 内含 CR 的文件: %s" % cr); sys.exit(1)
print("  ZIP 内文本文件无 CR 换行")
# 关键文件
for need in ("module.prop","customize.sh","META-INF/com/google/android/update-binary",
             "META-INF/com/google/android/updater-script","webroot/index.html",
             "bin/abserver-arm64","bin/abserver-arm","bin/abserver-amd64"):
    assert need in names, "ZIP 缺少 " + need
print("  关键文件齐全")
# 可执行位
info = z.getinfo("customize.sh")
perm = (info.external_attr >> 16) & 0o777
print("  customize.sh 权限: %o" % perm)
if perm & 0o111 == 0: print("  ! customize.sh 无可执行位")
print("  ZIP 校验通过")
PYEOF
[ $? -eq 0 ] || { echo "ERR: ZIP 校验失败"; exit 1; }

SIZE=$(wc -c < "$ZIP" | tr -d ' ')
"$PY" - "$ZIP" <<'PYEOF'
import sys, hashlib, os
p = sys.argv[1]
h = hashlib.sha256(open(p, "rb").read()).hexdigest()
open(p + ".sha256", "w", newline="\n").write("%s  %s\n" % (h, os.path.basename(p)))
print("SHA256: %s" % h)
PYEOF
printf '\n打包完成: %s (%s 字节, %.2f MB)\n' "$ZIP" "$SIZE" "$("$PY" -c "print($SIZE/1048576)")"
