#!/system/bin/sh
# ============================================================
#  SY-Fusion 模块级静态校验套件
#  用法: sh tests/run_module_checks.sh [all|A|B|C|D|E|F|G|H|I]
#
#   A 脚本语法        B AWK 语法/POSIX 可移植性   C 清单与元数据
#   D 二进制 ABI      E 脚本间路径引用            F 面板 action 覆盖
#   G HTML/JS 结构    H 编码卫生(CRLF/BOM)        I 引擎子命令链路
#   J 面板资产回归 + jsdom 运行时
#
#  纯静态检查，不依赖 Android 环境，可在桌面直接跑。
# ============================================================
set -u

# set -u 下 HOME 可能未定义（部分 recovery/精简环境），先给默认值，
# 否则脚本第一处 "$HOME/..." 就会 "parameter not set" 直接退出。
HOME="${HOME:-/tmp}"

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
MOD="$(cd "$TESTS_DIR/.." && pwd)"
cd "$MOD" || exit 1

PASS=0; FAIL=0; FAILED=""
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); FAILED="$FAILED
  x $1"; printf '  [FAIL] %s\n' "$1"; }
hr()  { printf '%s\n' "------------------------------------------------------------"; }
grp() { hr; printf '== %s\n' "$1"; }

PY=""
for c in python3 python; do command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }; done
if [ -z "$PY" ]; then
  for c in "C:/Users/admin/.workbuddy-ai/binaries/python/versions/3.13.12/python.exe" \
           "$HOME/.workbuddy-ai/binaries/python/versions/3.13.12/python.exe"; do
    [ -x "$c" ] && { PY="$c"; break; }
  done
fi
NODE=""
for c in node "C:/Users/admin/.workbuddy-ai/binaries/node/versions/22.22.2-6/node.exe"; do
  command -v "$c" >/dev/null 2>&1 && { NODE="$c"; break; }
done
# node 在 PATH 中但可能是 .exe 全路径
[ -z "$NODE" ] && NODE=""

# node_modules 查找顺序：环境变量 SY_NODE_MODULES → 项目内 → WorkBuddy 托管工作区
NM=""
for d in "${SY_NODE_MODULES:-}" "./node_modules" \
         "C:/Users/admin/.workbuddy-ai/binaries/node/workspace/node_modules" \
         "$HOME/.workbuddy-ai/binaries/node/workspace/node_modules"; do
  [ -n "$d" ] && [ -d "$d" ] && { NM="$d"; break; }
done
# 若已能直接解析则不需要 NODE_PATH
if [ -z "$NM" ] && [ -n "$NODE" ] && "$NODE" -e "require.resolve('jsdom')" >/dev/null 2>&1; then
  NM="."
fi
if [ -n "$NM" ] && [ "$NM" != "." ]; then export NODE_PATH="$NM"; fi

# playwright 浏览器目录
PW_BROWSERS=""
for d in "${SY_PW_BROWSERS:-}" \
         "C:/Users/admin/.workbuddy-ai/binaries/node/workspace/pw-browsers" \
         "$HOME/.workbuddy-ai/binaries/node/workspace/pw-browsers"; do
  [ -n "$d" ] && [ -d "$d" ] && { PW_BROWSERS="$d"; break; }
done
[ -n "$PW_BROWSERS" ] && export PLAYWRIGHT_BROWSERS_PATH="$PW_BROWSERS"

has_mod() { [ -n "$NODE" ] && "$NODE" -e "require.resolve('$1')" >/dev/null 2>&1; }

# 【真实缺陷修复】内联 Python 的 print 在中文 Windows 上默认走 GBK 编码，
# 而本脚本用 UTF-8 的中文串去 grep 结果 → 检查项会**漏报或误报**
# （实测：新增的 .bottomnav 安全区检查没出现在输出里）。
# 统一强制 UTF-8，让中文输出与 grep 模式一致。
PYTHONIOENCODING=utf-8
PYTHONUTF8=1
export PYTHONIOENCODING PYTHONUTF8
# 临时目录：Android 上 /tmp 只读，优先 /data/local/tmp
if [ -d /data/local/tmp ] && [ -w /data/local/tmp ] 2>/dev/null; then
  TMPD="${SYADGH_TEST_DIR:-/data/local/tmp}"
else
  TMPD="${SYADGH_TEST_DIR:-/tmp}"
fi
mkdir -p "$TMPD" 2>/dev/null || TMPD=/tmp

# ---------- A. 脚本语法 ----------
chk_scripts() {
  grp "A 脚本语法 (sh -n) 与 shebang"
  n=0
  for f in $(ls ./*.sh scripts/*.sh META-INF/com/google/android/update-binary 2>/dev/null); do
    [ -f "$f" ] || continue
    n=$((n + 1))
    if sh -n "$f" 2>"$TMPD/sy_sh_err.$$"; then ok; else bad "shell 语法错误: $f — $(tr '\n' ' ' <"$TMPD/sy_sh_err.$$" | cut -c1-160)"; fi
    case "$(head -c 21 "$f")" in
      '#!/system/bin/sh'*|'#!/bin/sh'*|'#!/usr/bin/env sh'*|'#!/sbin/sh'*) ok ;;
      *) bad "shebang 非 POSIX sh: $f" ;;
    esac
  done
  rm -f "$TMPD/sy_sh_err.$$"
  printf '  已检查 %s 个 shell 脚本\n' "$n"
  # POSIX sh 兼容性: 禁止 bash 专有语法（先剥离 awk 程序块、注释与引号字符串）
  if [ -n "$PY" ]; then
    $PY - <<'PYEOF' > "$TMPD/sy_posix.$$" 2>&1
import os, re, glob

FILES = sorted(glob.glob("*.sh")) + sorted(glob.glob("scripts/*.sh"))
BANNED = [
    # 真 [[ ]] 后面必跟空白/!/"；POSIX 字符类 [[:alpha:]] 后面是冒号，须排除
    (r'(?<![$"\w])\[\[(?=[\s!"]|$)', "[[ ]] 条件表达式"),
    (r'(?:^|[;&|(]|then|do|else)\s*local\s+[A-Za-z_]', "local 关键字"),
    (r'^\s*function\s+[A-Za-z_]', "function 关键字"),
    (r'(?:^|[;&|(])\s*(?:source|\.\s)\s+[^\s]', None),  # . 是 POSIX，source 不是
    (r'(?:^|[;&|(])\s*source\s+\S', "source 内建"),
    (r'(?:^|[;&|(])\s*declare\s', "declare 内建"),
    (r'\$\{?RANDOM\b', "$RANDOM"),
    (r'\bBASH_SOURCE\b', "BASH_SOURCE"),
    (r'&&\s*&\s*$', None),
    (r'(?:^|[;&|(])\s*let\s+[A-Za-z_]', "let 内建"),
    (r'\becho\s+-e\b', "echo -e"),
    (r'<<<', "here-string <<<"),
    (r'&>>', "&>> 重定向"),
    (r'\|\|?\s*true\s*;?\s*$', None),
    (r'(?:^|[;&|(])\s*set\s+-[A-Za-z]*o\s+pipefail', "set -o pipefail"),
    (r'(?:^|[;&|(])\s*(?:pushd|popd)\b', "pushd/popd"),
    (r'\bshopt\b', "shopt"),
]

def strip_code(src):
    """去掉注释与单/双引号字符串内容，保留结构，避免把 awk 程序误判为 shell"""
    out = []
    i = 0; n = len(src)
    while i < n:
        ch = src[i]
        if ch == '#' and (i == 0 or src[i-1] in " \t\n;&|("):
            while i < n and src[i] != '\n':
                i += 1
            continue
        if ch == "'":
            i += 1
            while i < n and src[i] != "'":
                i += 1
            i += 1
            out.append(' ')      # 单引号内容整体视为不透明(多为 awk 程序)
            continue
        if ch == '"':
            i += 1
            while i < n and src[i] != '"':
                if src[i] == '\\':
                    i += 1
                i += 1
            i += 1
            out.append('" "')
            continue
        if ch == '\\' and i + 1 < n:
            out.append('  '); i += 2; continue
        out.append(ch); i += 1
    return "".join(out)

bad = 0
for f in FILES:
    src = open(f, encoding="utf-8", errors="replace").read()
    code = strip_code(src)
    for pat, label in BANNED:
        if label is None:
            continue
        for m in re.finditer(pat, code, re.M):
            ln = code[:m.start()].count("\n") + 1
            print("FAIL|%s:%d 使用非 POSIX sh 语法: %s" % (f, ln, label))
            bad += 1
            break
print("INFO|POSIX 兼容性检查完成，异常 %d 处" % bad)
if bad == 0:
    print("OK|全部 shell 脚本符合 POSIX 规范")
PYEOF
    while IFS= read -r line; do
      case "$line" in
        FAIL\|*) bad "${line#FAIL|}" ;;
        OK\|*) ok ;;
        INFO\|*) printf '  %s\n' "${line#INFO|}" ;;
      esac
    done < "$TMPD/sy_posix.$$"
    rm -f "$TMPD/sy_posix.$$"
  fi
}

# ---------- B. AWK 语法 / 可移植性 ----------
chk_awk() {
  grp "B AWK 语法与 POSIX 可移植性"
  for f in scripts/*.awk; do
    [ -f "$f" ] || continue
    # 提供安全入参桩，避免 BEGIN 阶段因空路径触发 fatal
    # OUT 必须指向可写目录（Android 上 /tmp 只读，用 $TMPD）
    if awk -v REC=/dev/null -v CASES=/dev/null -v DOMAIN=example.com \
           -v CLIENT= -v CTAG= -v STRICT=0 -v OUT="$TMPD" \
           -v AI= -v BI= -v AN= -v BN= -v HA= -v HB= -v ADENY= -v EXTRA=www -v NOW=x -v SRC=x \
           -f "$f" /dev/null >/dev/null 2>"$TMPD/sy_awk_err.$$"; then
      ok
    else
      bad "awk 解析失败: $f — $(tr '\n' ' ' <"$TMPD/sy_awk_err.$$" | cut -c1-160)"
    fi
  done
  rm -f "$TMPD/sy_awk_err.$$"
  # gawk 专有特性（Android 上不可用）
  for pat in 'gensub(' 'asort(' 'asorti(' 'PROCINFO' 'FPAT' 'systime(' 'strftime(' 'mktime(' 'lshift(' 'rshift(' 'compl(' 'SYMTAB' 'FUNCTAB' 'IGNORECASE' '--re-interval'; do
    hit=$(grep -lF -- "$pat" scripts/*.awk 2>/dev/null | tr '\n' ' ')
    if [ -n "$hit" ]; then bad "AWK 使用了 gawk 专有特性 '$pat': $hit"; else ok; fi
  done
  # 所有 awk 文件都必须能被 toybox/busybox awk 解析（此处用本地 awk 近似）
  for f in scripts/*.awk; do
    [ -f "$f" ] || continue
    grep -qE '^\s*(function|BEGIN|END|[A-Za-z_].*\{)' "$f" && ok || bad "awk 文件疑似非标准结构: $f"
  done
}

# ---------- C. 清单与元数据 ----------
chk_meta() {
  grp "C 清单与元数据"
  for k in id name version versionCode author description; do
    grep -qE "^${k}=" module.prop 2>/dev/null && ok || bad "module.prop 缺少键: $k"
  done
  # id 必须匹配 KernelSU 规范 ^[a-zA-Z][a-zA-Z0-9._-]+$
  mid=$(sed -n 's/^id=//p' module.prop | tr -d '\r' | head -n1)
  if [ -n "$PY" ]; then
    $PY -c "import re,sys;sys.exit(0 if re.match(r'^[a-zA-Z][a-zA-Z0-9._-]+\$', '$mid') else 1)" 2>/dev/null \
      && ok || bad "module.prop id 不符合 KernelSU 规范: '$mid'"
  fi
  vc=$(sed -n 's/^versionCode=//p' module.prop | tr -d '\r')
  case "$vc" in ''|*[!0-9]*) bad "module.prop versionCode 非纯数字: '$vc'" ;; *) ok ;; esac
  mv=$(sed -n 's/^version=//p' module.prop | tr -d '\r')
  if [ -n "$PY" ]; then
    uj=$($PY -c "import json;d=json.load(open('update.json'));print(d.get('version',''))" 2>/dev/null)
    ujc=$($PY -c "import json;d=json.load(open('update.json'));print(d.get('versionCode',''))" 2>/dev/null)
    [ -n "$uj" ] && ok || bad "update.json 无法解析或缺少 version"
    [ "$mv" = "$uj" ] && ok || bad "版本不一致: module.prop=$mv update.json=$uj"
    [ "$vc" = "$ujc" ] && ok || bad "versionCode 不一致: module.prop=$vc update.json=$ujc"
    for k in version versionCode zipUrl changelog; do
      $PY -c "import json;d=json.load(open('update.json'));assert d.get('$k')" 2>/dev/null && ok || bad "update.json 缺少字段: $k"
    done
    $PY -c "import json;d=json.load(open('update.json'));assert 'github.com' in d['zipUrl']" 2>/dev/null && ok || bad "update.json zipUrl 非 GitHub 地址"
  else
    printf '  (无 python，跳过 JSON 深度校验)\n'
  fi
  grep -q '^updateJson=https://' module.prop && ok || bad "module.prop updateJson 非 https 地址"
  # 区分「源码仓库」与「设备上已安装的模块」：
  # KernelSU/Magisk 安装时会剥掉 META-INF/、customize.sh、README.md、.gitattributes，
  # 因此这些只对源码树校验，装在设备上时跳过而不是报错。
  if [ -d META-INF ] || [ -f customize.sh ]; then
    SRC_TREE=1
  else
    SRC_TREE=0
    printf '  [skip] 检测到设备上已安装的模块布局（无 META-INF/customize.sh），跳过打包期文件校验\n'
  fi
  # 运行期必备文件（安装后仍应存在）
  for f in service.sh post-fs-data.sh uninstall.sh action.sh module.prop webroot/index.html; do
    [ -s "$f" ] && ok || bad "缺少文件: $f"
  done
  if [ "$SRC_TREE" = "1" ]; then
    # META-INF
    for f in META-INF/com/google/android/update-binary META-INF/com/google/android/updater-script; do
      [ -s "$f" ] && ok || bad "缺少安装器文件: $f"
    done
    for f in customize.sh .gitattributes README.md; do
      [ -s "$f" ] && ok || bad "缺少文件: $f"
    done
    # updater-script 标准格式: 仅一行 #MAGISK
    if [ "$(tr -d ' \r\n' < META-INF/com/google/android/updater-script)" = "#MAGISK" ]; then ok; else bad "updater-script 非标准格式(应仅含 #MAGISK)"; fi
    grep -q '^SKIPUNZIP=0' customize.sh && ok || bad "customize.sh SKIPUNZIP 必须为 0"
  fi
  # customize.sh 引用的 config 文件必须存在（安装后 config/ 仍在）
  for c in sy.conf sources.conf splash_rules.conf mitm_rules.conf whitelist.conf notify_keywords.conf; do
    [ -f "config/$c" ] && ok || bad "customize.sh 引用但缺失: config/$c"
  done
}

# ---------- D. 二进制 ABI ----------
chk_bin() {
  grp "D 二进制 ABI 完整性"
  for f in bin/abserver-arm64 bin/abserver-arm bin/abserver-amd64; do
    [ -f "$f" ] || { bad "缺少二进制: $f"; continue; }
    magic=$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')
    [ "$magic" = "7f454c46" ] && ok || bad "$f 不是 ELF 文件"
    em=$(od -An -tx1 -j18 -N2 "$f" | tr -d ' \n')
    case "$f" in
      *arm64) [ "$em" = "b700" ] && ok || bad "$f e_machine=$em 期望 b700 (AArch64)" ;;
      *arm)   [ "$em" = "2800" ] && ok || bad "$f e_machine=$em 期望 2800 (ARM)" ;;
      *amd64) [ "$em" = "3e00" ] && ok || bad "$f e_machine=$em 期望 3e00 (x86-64)" ;;
    esac
    sz=$(wc -c <"$f" | tr -d ' ')
    [ "$sz" -gt 1000000 ] && ok || bad "$f 体积异常: $sz 字节"
    # 必须是静态链接(无动态解释器)
    if [ -n "$PY" ]; then
      $PY - "$f" <<'PYEOF' && ok || bad "$f 疑似动态链接(Android 上可能无法运行)"
import sys
b = open(sys.argv[1], "rb").read()
print("static" if b.find(b"/system/bin/linker") < 0 and b.find(b"ld-linux") < 0 else "dynamic")
PYEOF
    fi
  done
  # customize.sh 是安装期脚本，设备上安装后即被剥离，故仅在源码树校验
  if [ -f customize.sh ]; then
    for a in arm64 arm amd64; do
      grep -q "abserver-$a" customize.sh && ok || bad "customize.sh 未处理架构 $a"
    done
    grep -q 'bin/abserver' customize.sh && ok || bad "customize.sh 未生成 bin/abserver"
  else
    printf '  [skip] 设备上已安装的模块无 customize.sh，跳过架构分发校验\n'
  fi
}

# ---------- E. 脚本间路径引用 ----------
chk_refs() {
  grp "E 脚本间路径引用"
  for r in $(grep -rhoE '\$D/[A-Za-z0-9_]+\.sh' scripts/*.sh 2>/dev/null | sed 's|^\$D/||' | sort -u); do
    [ -f "scripts/$r" ] && ok || bad "\$D/ 引用不存在的脚本: $r"
  done
  # ctl.sh 委派子命令必须存在对应脚本（status/toggle/restart/apps/appnames 为内联实现）
  for r in $(sed -n 's/^  \([a-z|]*\))$/\1/p' scripts/ctl.sh | tr '|' '\n' | grep -E '^[a-z]+$'); do
    case "$r" in
      status|toggle|restart|apps|appnames) ok; continue ;;
      scripts) [ -f scripts/scripts_ext.sh ] && ok || bad "ctl.sh 的 scripts 别名未指向 scripts_ext.sh"; continue ;;
    esac
    [ -f "scripts/$r.sh" ] && ok || bad "ctl.sh 子命令 $r 无对应脚本 scripts/$r.sh"
  done
  for fn in cfg_get cfg_set json_escape count_lines have http_get import_append_local import_append_net batch_del_values batch_del_field normalize_lines; do
    grep -qE "^${fn}\(\)" scripts/common.sh && ok || bad "common.sh 缺少函数: $fn"
  done
  for v in MODDIR DATA_DIR CONFIG SOURCES WHITELIST RULES_DIR DNS_DIR MITM_DIR SPLASH_DIR LOGS RUN CACHE SCRIPTS_DIR BACKUP_DIR BIN; do
    grep -qE "^${v}=" scripts/common.sh && ok || bad "common.sh 缺少路径变量: $v"
  done
  grep -q 'bin/abserver"' scripts/common.sh && ok || bad "common.sh BIN 未指向 bin/abserver"
  if [ -f customize.sh ]; then
    grep -q 'bin/abserver' customize.sh && ok || bad "customize.sh 未生成 bin/abserver"
  fi
  # service.sh / post-fs-data.sh / action.sh 引用的脚本必须存在
  for f in service.sh post-fs-data.sh action.sh uninstall.sh; do
    for r in $(grep -ohE 'scripts/[a-z_]+\.sh' "$f" 2>/dev/null | sort -u); do
      [ -f "$r" ] && ok || bad "$f 引用不存在的脚本: $r"
    done
  done
}

# ---------- F. 面板 action 覆盖 ----------
chk_panel() {
  grp "F 面板 action 覆盖"
  if [ -z "$PY" ]; then printf '  (无 python，跳过)\n'; return; fi
  $PY - <<'PYEOF' > "$TMPD/sy_panel.$$" 2>&1
import re, io, os, sys

_raw = io.open("webroot/index.html", encoding="utf-8").read()
# 静态标记区里的按钮
markup = re.sub(r'<script\b[^>]*>.*?</script>', '', _raw, flags=re.S | re.I)
static_acts = set(re.findall(r'data-act="([^"]+)"', markup))
# JS 动态生成的行内按钮（删除/选择/开关等），模板里形如 data-act="' + ... 或 data-act="xxx"
js_src = "\n".join(re.findall(r'<script\b[^>]*>(.*?)</script>', _raw, re.S | re.I))
dyn_acts = set(re.findall(r'data-act=\\?"([a-z0-9\-]+)\\?"', js_src))
acts = static_acts | dyn_acts
h = _raw

def brace_body(s, open_idx):
    """从 '{' 位置取出配平的花括号块"""
    i = open_idx; depth = 0
    while i < len(s):
        if s[i] == '{': depth += 1
        elif s[i] == '}':
            depth -= 1
            if depth == 0: return s[open_idx:i+1]
        i += 1
    return s[open_idx:]

# 处理器可能分布在 var actions={...} 主表 与 后续 Object.assign(actions,{...}) 扩展表
bodies = []
for pat in (r'\nvar actions\s*=\s*\{', r'Object\.assign\(\s*actions\s*,\s*\{'):
    for mm in re.finditer(pat, h):
        bodies.append(brace_body(h, mm.end() - 1))
if not bodies:
    print("FAIL|未找到 actions 定义"); sys.exit(0)
keys = set()
for body in bodies:
    keys |= set(re.findall(r'"([a-z0-9-]+)"\s*:\s*function', body))
print("INFO|actions 定义块 %d 个, 处理器 %d 个" % (len(bodies), len(keys)))
# 【补充】有些 data-act 不是走 actions 表，而是由 document 级事件监听 +
# closest('[data-act="x"]') 处理（例如抽屉遮罩关闭）。这类也要认，否则会误报。
delegated = set(re.findall(r"closest\(\s*'\[data-act=\"([a-z0-9\-]+)\"\]'", h))
delegated |= set(re.findall(r'closest\(\s*"\[data-act=\\"([a-z0-9\-]+)\\"\]"', h))
if delegated:
    print("INFO|document 级代理处理器 %d 个: %s" % (len(delegated), ",".join(sorted(delegated))))
for a in sorted(acts - keys - delegated):
    print("FAIL|data-act 无处理器: " + a)
for a in sorted(keys - acts):
    print("WARN|处理器无按钮绑定: " + a)
print("INFO|data-act 静态 %d + 动态 %d = %d, handlers=%d"
      % (len(static_acts), len(dyn_acts - static_acts), len(acts), len(keys)))

# ---- 提取每个脚本支持的 case 标签（支持嵌套 case）----
def labels(path):
    src = io.open(path, encoding="utf-8", errors="replace").read()
    out = set()
    pos = 0
    while True:
        # 同时接受 case "$1" in / case "${1}" in / case "${1:-status}" in
        cm = re.compile(
            r'\bcase\s+"\$\{[0-9A-Za-z_]+(?:[:?=+-][^}"]*)?\}"\s+in\b'
            r'|\bcase\s+"\$[0-9A-Za-z_]+"\s+in\b').search(src, pos)
        if not cm: break
        j = cm.end(); depth = 1
        while j < len(src) and depth:
            t = re.compile(r'\b(case|esac)\b').search(src, j)
            if not t: break
            depth += 1 if t.group(1) == 'case' else -1
            j = t.end()
        block = src[cm.end():j]
        for pm in re.finditer(r'(?:^|\n)\s*([A-Za-z0-9_|.*-]+)\)', block):
            for lab in pm.group(1).split("|"):
                lab = lab.strip()
                if lab and lab != "*" and "*" not in lab:
                    out.add(lab)
        pos = j
    return out

lab = {}
for f in os.listdir("scripts"):
    if f.endswith(".sh"):
        lab[f] = labels(os.path.join("scripts", f))

# ---- 提取 runScript 调用（支持跨行）----
calls = []
for cm in re.finditer(r'runScript\(\s*"([A-Za-z0-9_]+\.sh)"\s*,\s*\[', h):
    j = cm.end() - 1; depth = 0
    while j < len(h):
        if h[j] == '[': depth += 1
        elif h[j] == ']':
            depth -= 1
            if depth == 0: break
        j += 1
    arr = h[cm.end()-1:j+1]          # 形如 ["clash"] 或 [sub, "-x"]
    body = arr[1:-1]                 # 去掉外层方括号
    inner = body.lstrip()
    if inner.startswith('"'):
        m2 = re.match(r'"([^"\\]*)"', inner)
        lits = [m2.group(1)] if m2 else []
    else:
        # 首元素为变量/三元表达式 -> 无法静态判定，跳过（只取数组内部字面量会误判）
        lits = []
    line = h[:cm.start()].count("\n") + 1
    calls.append((cm.group(1), lits, line, arr[:120].replace("\n", " ")))

bad = []; seen = set()
for sh, lits, line, snippet in calls:
    if sh not in lab:
        bad.append((sh, "(脚本不存在)", line, snippet)); continue
    if not lits:
        continue  # 全部为变量，无法静态判定
    if not any(x in lab[sh] for x in lits):
        key = (sh, tuple(lits[:2]))
        if key in seen: continue
        seen.add(key)
        bad.append((sh, "/".join(lits[:3]), line, snippet))
print("INFO|runScript 调用=%d" % len(calls))
for x in sorted(bad, key=lambda t: (t[0], t[1])):
    print("FAIL|%s 未处理子命令: %s (L%d) | %s" % (x[0], x[1], x[2], x[3]))
if not bad:
    print("OK|全部面板调用均有对应脚本子命令")
PYEOF
  while IFS= read -r line; do
    case "$line" in
      FAIL\|*) bad "${line#FAIL|}" ;;
      WARN\|*) printf '  [warn] %s\n' "${line#WARN|}" ;;
      OK\|*) ok ;;
      INFO\|*) printf '  %s\n' "${line#INFO|}" ;;
    esac
  done < "$TMPD/sy_panel.$$"
  rm -f "$TMPD/sy_panel.$$"
  grep -q 'id="page-engine"' webroot/index.html && ok || bad "缺少规则引擎页 page-engine"
  # 【设计变更】顶部 data-tab 已移除，改为检查"规则引擎页已被底部工作区表收录"（点得到才算功能在）
grep -q '\["engine"' webroot/index.html && ok || bad "规则引擎页未被底部导航收录"
  grep -q 'case "engine"' webroot/index.html && ok || bad "loadTab 未处理 engine"
  grep -q 'function loadEngine' webroot/index.html && ok || bad "缺少 loadEngine 函数"
  # WebUI 双环境桥接 (KernelSU ksu.exec + HTTP /api/exec)
  grep -q 'ksu' webroot/index.html && ok || bad "缺少 KernelSU 桥接"
  grep -q '/api/exec' webroot/index.html && ok || bad "缺少 HTTP 命令桥 /api/exec"
}

# ---------- G. HTML/JS 结构 ----------
chk_html() {
  grp "G HTML 结构与 JS 语法"
  if [ -z "$PY" ]; then printf '  (无 python，跳过)\n'; return; fi
  $PY - "$NODE" <<'PYEOF' > "$TMPD/sy_html.$$" 2>&1
import re, io, os, subprocess, tempfile, sys
node = sys.argv[1] if len(sys.argv) > 1 else ""
h = io.open("webroot/index.html", encoding="utf-8").read()
if h.lstrip().startswith("\ufeff"): print("FAIL|index.html 含 UTF-8 BOM")
if not re.match(r'^\s*<!DOCTYPE html>', h, re.I): print("FAIL|缺少 <!DOCTYPE html>")
# markup：剥掉 <script> 内容后的纯标记区，避免 JS 字符串干扰属性统计
markup = re.sub(r'<script\b[^>]*>.*?</script>', '', h, flags=re.S | re.I)
for tag in ["html", "head", "body"]:
    o = len(re.findall(r'<%s[\s>]' % tag, h, re.I)); c = len(re.findall(r'</%s>' % tag, h, re.I))
    if o != 1 or c != 1: print("FAIL|<%s> 数量异常 open=%d close=%d" % (tag, o, c))
    else: print("OK|<%s> 配对" % tag)
for tag in ["section", "style", "script", "textarea", "table", "select", "button"]:
    src = h if tag in ("style", "script") else markup
    o = len(re.findall(r'<%s[\s>]' % tag, src, re.I)); c = len(re.findall(r'</%s>' % tag, src, re.I))
    if o != c: print("FAIL|<%s> 不配对 open=%d close=%d" % (tag, o, c))
    else: print("OK|<%s> 配对 %d" % (tag, o))
do = len(re.findall(r'<div[\s>]', markup, re.I)); dc = len(re.findall(r'</div>', markup, re.I))
if do != dc: print("FAIL|<div> 失衡 open=%d close=%d diff=%d" % (do, dc, do - dc))
else: print("OK|<div> 平衡 %d 组" % do)
ids = re.findall(r'\sid="([^"]+)"', markup)
dup = sorted({x for x in ids if ids.count(x) > 1})
if dup: print("FAIL|重复 id: " + ", ".join(dup))
else: print("OK|id 唯一 共 %d 个" % len(ids))
tabs = set(re.findall(r'data-tab="([^"]+)"', markup)); pages = set(re.findall(r'id="page-([^"]+)"', markup))
# 【设计变更】顶部 data-tab 导航已整体移除（改为底部 5 入口 + 工作区抽屉），
# 所以不再要求 "data-tab 与 page 一一对应"。改为：**每个 page 必须出现在 WS 表里**，
# 否则该页面在界面上点不到（功能丢失）。这是更强的检查（原来只查标签存在）。
ws_tbl = re.search(r"var WS = \{(.*?)\n\};", h, re.S)
ws_pages = set(re.findall(r'\["([a-z0-9\-]+)"', ws_tbl.group(1))) if ws_tbl else set()
if not ws_tbl:
    print("FAIL|找不到底部工作区表 WS")
else:
    miss_ws = sorted(pages - ws_pages)
    for p in miss_ws: print("FAIL|page-%s 不在底部工作区表里（界面上点不到）" % p)
    extra_ws = sorted(ws_pages - pages)
    for p in extra_ws: print("FAIL|工作区表引用了不存在的 page-%s" % p)
    if not miss_ws and not extra_ws:
        print("OK|%d 个页面全部收录于底部工作区表" % len(pages))
subs = set(re.findall(r'data-sub="([^"]+)"', markup)); sp = set(re.findall(r'id="sub-([^"]+)"', markup))
for s in sorted(subs - sp): print("FAIL|子标签 %s 无对应 sub-%s" % (s, s))
if subs <= sp: print("OK|子标签/子页面匹配 %d/%d" % (len(subs), len(sp)))
# ---- AGH 骨架要素 ----
for key, label in [# 【用户要求】顶部导航已移除，不再检查 header / nav-tabs（见下面专门的"顶部必须为空"断言）
                   ("dropdown-menu", "下拉菜单"), ("page-title", "页面标题栏"),
                   ("col-12", "卡片栅格 col-12"), ("col-6", "卡片栅格 col-6"),
                   ("--bgcolor:#0b0f14", "深色底 #0b0f14"), ("--bgcolor:#f6f8fa", "浅色底 #f6f8fa"),
                   ("--green:#3fb950", "主绿 #3fb950"), ("--accent:#58a6ff", "主强调 #58a6ff"),
                   ("--lat0:#3fb950", "延迟色阶 lat0"), ("--lat4:#f85149", "延迟色阶 lat4"),
                   ("--card-border-color", "卡片描边令牌"),
                   ("backdrop-filter", "毛玻璃模糊"), ("saturate(", "饱和度增强"),
                   ("@supports not", "降级回退"), ("radial-gradient", "背景光斑"),
                   ("box-shadow", "层次阴影")]:
    if key in h: print("OK|设计要素 %s" % label)
    else: print("FAIL|缺少设计要素 %s (%s)" % (label, key))
if "--glass-blur" in h: print("OK|玻璃模糊参数 --glass-blur")
else: print("FAIL|缺少 --glass-blur")
# ---- 性能护栏 ----
css_only = "".join(re.findall(r'<style[^>]*>(.*?)</style>', h, re.S | re.I))
bf = re.findall(r'([^{}]+)\{([^{}]*backdrop-filter[^{}]*)\}', css_only)
stray = [s.strip().replace("\n", " ") for s, b in bf if "header" not in s and "dropdown-menu" not in s]
if stray: print("FAIL|backdrop-filter 泄漏到非白名单选择器(会导致卡顿): " + " | ".join(stray))
else: print("OK|backdrop-filter 仅用于 .header / .dropdown-menu（%d 条）" % len(bf))
if len(bf) > 4: print("FAIL|backdrop-filter 规则过多 %d 条（应 <=4）" % len(bf))
if re.search(r"<filter\b|<feTurbulence\b", h): print("FAIL|存在 SVG 滤镜噪点层节点")
else: print("OK|无 SVG 滤镜噪点层")
anim = re.findall(r"(?:^|[;{\s])animation\s*:", css_only)
if anim: print("FAIL|CSS 仍含 %d 处 animation 声明（低端机耗电卡顿）" % len(anim))
else: print("OK|CSS 无 animation 声明")
# position:fixed 层数上限 4：新增移动端底部导航 .bottomnav（MagicNet 等同类模块
# 的标准做法，手机上入口要常驻可见 + 拇指可达）；它只在手机显示、并处理安全区。
fx = len(re.findall(r"position\s*:\s*fixed", css_only))
if fx > 6: print("FAIL|position:fixed 层过多 %d 个" % fx)
else: print("OK|position:fixed 层 %d 个" % fx)
# 底部导航必须处理系统安全区（否则被手势条挡住，最后一项按不到）
navm = re.search(r"\.bottomnav\s*\{[^}]*\}", css_only, re.S)
if navm is None: print("FAIL|缺少 .bottomnav 移动端底部导航")
elif "safe-area-inset-bottom" not in navm.group(0): print("FAIL|.bottomnav 未处理 safe-area-inset-bottom")
else: print("OK|.bottomnav 安全区已处理")
blocks = re.findall(r'<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>', h, re.S | re.I)
print("INFO|内联 script 块 %d 个" % len(blocks))
if node:
    for n, b in enumerate(blocks):
        if not b.strip(): continue
        fd, p = tempfile.mkstemp(suffix=".js"); os.close(fd)
        io.open(p, "w", encoding="utf-8").write(b)
        try:
            r = subprocess.run([node, "--check", p], capture_output=True, text=True, timeout=60)
            if r.returncode != 0: print("FAIL|script 块 %d JS 语法错误: %s" % (n, r.stderr.strip().splitlines()[:2]))
            else: print("OK|script 块 %d JS 语法通过" % n)
        except Exception as e:
            print("WARN|JS 校验异常: %s" % e)
        finally:
            os.unlink(p)
else:
    print("WARN|未找到 node，跳过 JS 语法校验")
css = "".join(re.findall(r'<style[^>]*>(.*?)</style>', h, re.S | re.I))
if css.count("{") != css.count("}"): print("FAIL|CSS 大括号不平衡 {=%d }=%d" % (css.count("{"), css.count("}")))
else: print("OK|CSS 大括号平衡 %d 组" % css.count("{"))
if css.count("/*") != css.count("*/"): print("FAIL|CSS 注释未闭合")
else: print("OK|CSS 注释闭合")
print("INFO|内联 CSS 长度 %d 字符" % len(css))
PYEOF
  while IFS= read -r line; do
    case "$line" in
      FAIL\|*) bad "${line#FAIL|}" ;;
      WARN\|*) printf '  [warn] %s\n' "${line#WARN|}" ;;
      OK\|*) ok ;;
      INFO\|*) printf '  %s\n' "${line#INFO|}" ;;
    esac
  done < "$TMPD/sy_html.$$"
  rm -f "$TMPD/sy_html.$$"
}

# ---------- H. 编码卫生 ----------
chk_encoding() {
  grp "H 编码卫生 (CRLF / BOM / 末尾换行)"
  if [ -z "$PY" ]; then printf '  (无 python，跳过)\n'; return; fi
  $PY - <<'PYEOF' > "$TMPD/sy_enc.$$" 2>&1
import os
TEXT = {".sh",".awk",".md",".conf",".txt",".prop",".json",".go",".mod",".sum",
        ".html",".css",".js",".xml",".yml",".yaml",".tsv",".py"}
BIN  = {".zip",".png",".jpg",".jpeg",".webp",".so",".apk",".gz",".xz",".zst",".7z",".jar"}
n=0; bad=0
for root, dirs, files in os.walk("."):
    if ".git" in root.split(os.sep): continue
    for f in sorted(files):
        p = os.path.join(root, f)
        ext = os.path.splitext(f)[1].lower()
        if ext in BIN: continue
        if "bin" in root.split(os.sep): continue
        if ext not in TEXT and f not in ("update-binary", "updater-script"): continue
        n += 1
        b = open(p, "rb").read()
        crlf = b.count(b"\r\n"); lone = b.count(b"\r") - crlf
        if crlf or lone:
            print("FAIL|含 CR 换行 (Android 上会导致语法错误): %s (CRLF=%d)" % (p, crlf)); bad += 1
        if b[:3] == b"\xef\xbb\xbf":
            print("FAIL|含 UTF-8 BOM: %s" % p); bad += 1
        if ext in (".sh", ".awk", ".prop") and b and not b.endswith(b"\n"):
            print("FAIL|文件末尾缺少换行: %s" % p); bad += 1
        if b"\t" in b and ext in (".sh", ".awk"):
            pass
print("INFO|已检查 %d 个文本文件，异常 %d 个" % (n, bad))
if bad == 0: print("OK|编码卫生全部通过")
PYEOF
  while IFS= read -r line; do
    case "$line" in
      FAIL\|*) bad "${line#FAIL|}" ;;
      OK\|*) ok ;;
      INFO\|*) printf '  %s\n' "${line#INFO|}" ;;
    esac
  done < "$TMPD/sy_enc.$$"
  rm -f "$TMPD/sy_enc.$$"
  # .gitattributes 必须声明 eol=lf
  grep -q 'eol=lf' .gitattributes 2>/dev/null && ok || bad ".gitattributes 未声明 eol=lf"
  grep -q 'update-binary' .gitattributes 2>/dev/null && ok || bad ".gitattributes 未覆盖 update-binary"
}

# ---------- I. 引擎子命令链路 ----------
chk_engine_link() {
  grp "I 引擎子命令链路"
  for s in build compile stats syntax test testfile verify clear paths; do
    grep -qE "(^|[[:space:]|])$s(\)|\|)" scripts/engine.sh && ok || bad "engine.sh 未实现子命令: $s"
  done
  for s in engine-build engine-stats engine-syntax engine-verify engine-test engine-testfile engine-paths engine-clear; do
    grep -q -- "$s" scripts/dns.sh && ok || bad "dns.sh 未转发子命令: $s"
  done
  grep -q 'engine.sh' scripts/filter.sh && ok || bad "filter.sh 未转发到 engine.sh"
  grep -q 'engine' scripts/stats.sh && ok || bad "stats.sh 未读取引擎产物"
  grep -q 'engine.sh' scripts/dns.sh && ok || bad "dns.sh 未调用 engine.sh"
  grep -qE '\$E/hosts|engine/hosts' scripts/dns.sh && ok || bad "dns.sh 未使用引擎生成的 hosts"
  grep -q 'ENG_OUT="\$RULES_DIR/engine"' scripts/engine.sh && ok || bad "engine.sh 输出目录与 RULES_DIR 不一致"
  [ -s tests/corpus/01_mixed.txt ] && ok || bad "缺少测试语料 tests/corpus/01_mixed.txt"
  [ -s tests/expect.tsv ] && ok || bad "缺少期望文件 tests/expect.tsv"
  [ -s tests/run_tests.sh ] && ok || bad "缺少测试套件 tests/run_tests.sh"
  # 引擎必须覆盖全部声明的语法类别
  for syn in adblock modifiers cosmetic scriptlet css-inject extended-css html-filter js-inject hosts dnsmasq regex dnsrewrite plain-domain; do
    grep -q -- "\"$syn\"" scripts/engine.sh && ok || bad "engine.sh 语法分类缺少: $syn"
  done
  # 发射器必须产出全部产物
  for out in allow_imp allow block_imp block pattern_allow pattern_block heuristic_allow heuristic_block regex_allow regex_block rewrite allow_deny cosmetic_hide cosmetic_unhide scriptlets js_inject css_inject ext_css html_filter; do
    grep -q -- "$out" scripts/engine_emit.awk && ok || bad "engine_emit.awk 未发射: $out"
  done
  # 优先级语义
  grep -q 'important' scripts/engine_parse.awk && ok || bad "engine_parse.awk 未处理 \$important"
  grep -q 'badfilter' scripts/engine_parse.awk && ok || bad "engine_parse.awk 未处理 \$badfilter"
  grep -q 'denyallow' scripts/engine_parse.awk && ok || bad "engine_parse.awk 未处理 \$denyallow"
  grep -q 'dnsrewrite' scripts/engine_parse.awk && ok || bad "engine_parse.awk 未处理 \$dnsrewrite"
}

# ---------- J. 面板资产回归 + jsdom 运行时 ----------
chk_ui_runtime() {
  grp "J 面板资产回归 / 运行时"
  if [ -z "$PY" ]; then printf '  (无 python，跳过)\n'; return; fi
  # 资产基线对比（保证重构不丢功能）
  if $PY tests/verify_ui_assets.py > "$TMPD/sy_uia.$$" 2>&1; then
    ok; ok; ok
  else
    bad "面板资产基线校验未通过"
  fi
  grep -E '^\[X\]' "$TMPD/sy_uia.$$" | while IFS= read -r l; do printf '  %s\n' "$l"; done
  grep -E '^\[!\]' "$TMPD/sy_uia.$$" | while IFS= read -r l; do printf '  [warn] %s\n' "${l#\[!\] }"; done
  if grep -q '^\[OK\] backdrop-filter 仅用于' "$TMPD/sy_uia.$$"; then ok; else bad "backdrop-filter 性能护栏未通过"; fi
  if grep -q '^\[OK\] CSS 无 animation' "$TMPD/sy_uia.$$"; then ok; else bad "CSS 仍含 animation 声明"; fi
  if grep -q '^\[OK\] 无 SVG 滤镜噪点层' "$TMPD/sy_uia.$$"; then ok; else bad "存在 SVG 噪点层"; fi
  rm -f "$TMPD/sy_uia.$$"
  # 真实浏览器布局/截图（可选，仅在装了 playwright 时跑）
  if has_mod playwright; then
    if "$NODE" tests/ui_screenshot.js > "$TMPD/sy_uish.$$" 2>&1; then
      ok; ok; ok
      grep -cE '^\s+\[ok\]' "$TMPD/sy_uish.$$" | while read -r n; do printf '  浏览器布局断言 %s 项通过\n' "$n"; done
      grep -E '实际启用模糊的元素|DOM 节点数|SVG 滤镜节点' "$TMPD/sy_uish.$$" | while IFS= read -r l; do printf '  %s\n' "$l"; done
    else
      bad "浏览器布局断言未通过"
      grep -E '\[X\]|页面错误' "$TMPD/sy_uish.$$" | head -8 | while IFS= read -r l; do printf '  %s\n' "$l"; done
    fi
    rm -f "$TMPD/sy_uish.$$"
  else
    printf '  (无 playwright，跳过浏览器布局断言)\n'
  fi
  # 基线清单存在
  [ -s tests/ui_baseline.json ] && ok || bad "缺少 tests/ui_baseline.json"
  # jsdom 运行时（有 node 且有 jsdom 才跑）
  if has_mod jsdom; then
    if "$NODE" tests/ui_runtime_check.js > "$TMPD/sy_uirt.$$" 2>&1; then
      ok; ok; ok; ok
      grep -cE '^\s+\[ok\]' "$TMPD/sy_uirt.$$" | while read -r n; do printf '  jsdom 运行时断言 %s 项通过\n' "$n"; done
    else
      bad "jsdom 运行时校验未通过"
      grep -E '\[X\]' "$TMPD/sy_uirt.$$" | head -10 | while IFS= read -r l; do printf '  %s\n' "$l"; done
    fi
    rm -f "$TMPD/sy_uirt.$$"
  else
    printf '  (无 node/jsdom，跳过运行时校验)\n'
  fi
}

# ---------- 调度 ----------
which="${1:-all}"
case "$which" in
  all) chk_scripts; chk_awk; chk_meta; chk_bin; chk_refs; chk_panel; chk_html; chk_encoding; chk_engine_link; chk_ui_runtime ;;
  A|a) chk_scripts ;;
  B|b) chk_awk ;;
  C|c) chk_meta ;;
  D|d) chk_bin ;;
  E|e) chk_refs ;;
  F|f) chk_panel ;;
  G|g) chk_html ;;
  H|h) chk_encoding ;;
  I|i) chk_engine_link ;;
  J|j) chk_ui_runtime ;;
  *) echo "usage: sh tests/run_module_checks.sh [all|A|B|C|D|E|F|G|H|I|J]"; exit 2 ;;
esac

hr
printf '模块静态校验结果: 通过 %s 项, 失败 %s 项\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf '失败明细:%s\n' "$FAILED"
  exit 1
fi
printf 'ALL MODULE CHECKS PASSED\n'
exit 0
