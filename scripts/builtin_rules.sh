#!/system/bin/sh
# ============================================================
#  builtin_rules.sh — 内置规则管理（三份规则：可查看/编辑/启用停用）
#  ------------------------------------------------------------
#  设计要点（回应"规则要直接点开查看编辑，而不是单独的文件编辑器"）：
#    · 每份规则一个独立入口：view / save / on / off / stats；
#    · 面板为每份规则做**独立页面**（不是丢进通用编辑器）；
#    · 用户修改写到 DATA_DIR/rules/builtin-user/，**不覆盖模块内原件**
#      （重刷模块不丢用户改动）；
#    · 生效方式**分类统计**，不把"元素隐藏类"算进 DNS 拦截数：
#        - 网络类(||domain^ 等) → 可被 DNS/hosts 拦截，真实统计
#        - 元素隐藏类(##...) → 需 MITM 注入 CSS，单独统计并如实标注
# ============================================================
. "$(dirname "$0")/common.sh"

BR_SRC="$MODDIR/rulesets/builtin"
BR_USER="$DATA_DIR/rules/builtin-user"
BR_STATE="$DATA_DIR/rules/builtin.state"
mkdir -p "$BR_USER" 2>/dev/null
BR_LIST="watermark antiadblock noappdownload"

br_name() { # <key> -> 中文名
  case "$1" in
    watermark)      echo "去水印（网页水印隐藏）" ;;
    antiadblock)    echo "反广告拦截检测" ;;
    noappdownload)  echo "阻止网页诱导下载 App" ;;
    *) echo "$1" ;;
  esac
}

br_file() { # <key> -> 当前生效文件（用户副本优先）
  u="$BR_USER/$1.txt"
  if [ -s "$u" ]; then echo "$u"; else echo "$BR_SRC/$1.txt"; fi
}

# 是否启用（默认关闭：规则集体积大，是否拦截由用户显式选择）
br_on() { # <key> -> 0/1
  [ -f "$BR_STATE" ] || { echo 0; return; }
  v=$(sed -n "s/^$1=//p" "$BR_STATE" 2>/dev/null | head -n1)
  [ -z "$v" ] && v=0
  echo "$v"
}

br_set() { # <key> <0|1>
  [ -f "$BR_STATE" ] || : > "$BR_STATE"
  if grep -q "^$1=" "$BR_STATE" 2>/dev/null; then
    sed "s|^$1=.*|$1=$2|" "$BR_STATE" > "$BR_STATE.tmp" && mv "$BR_STATE.tmp" "$BR_STATE"
  else
    echo "$1=$2" >> "$BR_STATE"
  fi
}

# 分类统计（关键：网络类与元素隐藏类分开算）
br_stats() { # <key>
  f=$(br_file "$1")
  net=0; cos=0; total=0
  if [ -s "$f" ]; then
    # 元素隐藏类：含 ##（uBlock/AdGuard 语法）
    cos=$(grep -c "##" "$f" 2>/dev/null | head -n1); [ -z "$cos" ] && cos=0
    # 有效行（非注释非空）
    total=$(grep -v "^[[:space:]]*#" "$f" 2>/dev/null | grep -c . | head -n1); [ -z "$total" ] && total=0
    net=$((total - cos))
    [ "$net" -lt 0 ] && net=0
  fi
  printf '{"key":"%s","name":"%s","enabled":"%s","total":%s,"network":%s,"cosmetic":%s,"file":"%s"}\n' \
    "$1" "$(br_name "$1")" "$(br_on "$1")" "$total" "$net" "$cos" "$f"
}

br_list_all() {
  printf '['
  first=1
  for k in $BR_LIST; do
    [ "$first" = "1" ] || printf ','
    first=0
    br_stats "$k"
  done
  printf ']\n'
}

br_view() { # <key>
  f=$(br_file "$1")
  [ -s "$f" ] || { echo "ERR: 规则文件不存在"; return 1; }
  cat "$f"
}

br_save() { # <key>  (内容从 stdin 读)
  mkdir -p "$BR_USER" 2>/dev/null
  out="$BR_USER/$1.txt"
  cat > "$out.tmp" 2>/dev/null
  if [ -s "$out.tmp" ]; then
    mv "$out.tmp" "$out" 2>/dev/null
    n=$(grep -v "^[[:space:]]*#" "$out" 2>/dev/null | grep -c . | head -n1); [ -z "$n" ] && n=0
    echo "OK: 已保存 $(br_name "$1")（有效 $n 行）"
  else
    rm -f "$out.tmp" 2>/dev/null
    echo "ERR: 输入为空，未保存"
    return 1
  fi
}

br_reset() { # <key> 恢复内置原件
  rm -f "$BR_USER/$1.txt" 2>/dev/null
  echo "OK: 已恢复 $(br_name "$1") 的内置版本"
}

# 把启用的规则交给引擎（网络类进 DNS 引擎；元素隐藏类另存给 MITM）
br_apply() {
  eng="$DATA_DIR/rules/builtin-active"
  mitm="$DATA_DIR/rules/builtin-cosmetic"
  mkdir -p "$DATA_DIR/rules" 2>/dev/null
  : > "$eng"
  : > "$mitm"
  for k in $BR_LIST; do
    [ "$(br_on "$k")" = "1" ] || continue
    f=$(br_file "$k")
    [ -s "$f" ] || continue
    # 网络类 → 引擎；元素隐藏类 → MITM 专用文件
    grep -v "^[[:space:]]*#" "$f" 2>/dev/null | grep -v "##" >> "$eng"
    grep "##" "$f" 2>/dev/null >> "$mitm"
  done
  ne=$(grep -c . "$eng" 2>/dev/null | head -n1); [ -z "$ne" ] && ne=0
  nm=$(grep -c . "$mitm" 2>/dev/null | head -n1); [ -z "$nm" ] && nm=0
  echo "OK: 已汇总启用规则（网络类 $ne 条 → DNS 引擎；元素隐藏类 $nm 条 → MITM 注入）"
}

case "$1" in
  list)  br_list_all ;;
  view)  br_view "$2" ;;
  save)  br_save "$2" ;;
  reset) br_reset "$2" ;;
  stats) br_stats "$2" ;;
  on)    br_set "$2" 1; br_apply ;;
  off)   br_set "$2" 0; br_apply ;;
  apply) br_apply ;;
  *) echo "usage: builtin_rules.sh {list|view <k>|save <k>|reset <k>|stats <k>|on <k>|off <k>|apply}"; exit 2 ;;
esac
