#!/system/bin/sh
# ============================================================
#  filter.sh — 兼容层（转发至融合引擎 engine.sh）
#  ------------------------------------------------------------
#  本脚本保留历史接口，实际编译/统计/诊断均由
#  engine.sh（AdGuard Home + uBlock Origin 融合引擎）完成。
#  同时在旧路径 cache/dns/filter_*.txt 生成镜像，兼容外部引用。
#
#  用法: filter.sh {build|stats|test <domain>|testfile <file>|syntax|verify|clear}
#  作者: vip-svip（融合引擎重构版）
# ============================================================
. "$(dirname "$0")/common.sh"
D="$(dirname "$0")"
RAW_DIR="$CACHE/dns"
ENG_OUT="$RULES_DIR/engine"

# 引擎产物 → 旧路径镜像
mirror() {
  set -- block:filter_block block_imp:filter_block_imp allow:filter_allow \
         allow_imp:filter_allow_imp regex_block:filter_regex rewrite:filter_rewrite
  for p in "$@"; do
    src="${p%%:*}"; dst="${p##*:}"
    if [ -f "$ENG_OUT/$src.txt" ]; then
      cp -f "$ENG_OUT/$src.txt" "$RAW_DIR/$dst.txt" 2>/dev/null
    else
      : > "$RAW_DIR/$dst.txt"
    fi
  done
  return 0
}

case "$1" in
  build)
    sh "$D/engine.sh" build >/dev/null 2>&1
    mirror
    b=$(count_lines "$RAW_DIR/filter_block.txt")
    bi=$(count_lines "$RAW_DIR/filter_block_imp.txt")
    a=$(count_lines "$RAW_DIR/filter_allow.txt")
    ai=$(count_lines "$RAW_DIR/filter_allow_imp.txt")
    re=$(count_lines "$RAW_DIR/filter_regex.txt")
    rw=$(count_lines "$RAW_DIR/filter_rewrite.txt")
    echo "OK: 融合引擎已编译 (拦截 $b / 重要拦截 $bi / 放行 $a / 重要放行 $ai / 正则 $re / 重写 $rw)"
    ;;
  stats)    sh "$D/engine.sh" stats ;;
  test)     sh "$D/engine.sh" test "$2" ;;
  testfile) sh "$D/engine.sh" testfile "$2" ;;
  syntax)   sh "$D/engine.sh" syntax ;;
  verify)   sh "$D/engine.sh" verify ;;
  clear)
    sh "$D/engine.sh" clear >/dev/null 2>&1
    rm -f "$RAW_DIR"/filter_*.txt
    echo "OK: 引擎输出与过滤镜像已清空"
    ;;
  *) echo "usage: filter.sh {build|stats|test <domain>|testfile <file>|syntax|verify|clear}" ;;
esac
