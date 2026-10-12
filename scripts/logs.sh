#!/system/bin/sh
# ============================================================
#  logs.sh — 日志查看 (面板「日志」页数据源)
#  用法: logs.sh {list|cat <name>|clear <name>|clear-all|tail <name> [n]}
#  作者: vip-svip
# ============================================================
. "$(dirname "$0")/common.sh"

_mtime() { stat -c '%y' "$1" 2>/dev/null | cut -d. -f1; }

list_json() {
  printf '['
  first=1
  for f in "$LOGS"/*.log "$LOGS"/*.txt; do
    [ -f "$f" ] || continue
    n=$(basename "$f")
    sz=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
    mt=$(_mtime "$f")
    [ "$first" = 1 ] || printf ','
    first=0
    printf '{"name":"%s","size":%s,"mtime":"%s"}' "$(json_escape "$n")" "${sz:-0}" "$(json_escape "$mt")"
  done
  printf ']'
}

cat_log() { # name [tail_n]
  n="$1"; [ -z "$n" ] && { echo "ERR: 缺少日志名"; return 1; }
  [ "$n" = "$(basename "$n")" ] || { echo "ERR: 非法名称"; return 1; }
  f="$LOGS/$n"
  [ -f "$f" ] || { echo "(日志 $n 不存在)"; return 0; }
  t="${2:-400}"
  echo "===== $n ($(wc -l < "$f" 2>/dev/null | tr -d ' ') 行) ====="
  tail -n "$t" "$f"
}

clear_one() {
  n="$1"; [ -z "$n" ] && { echo "ERR: 缺少日志名"; return 1; }
  [ "$n" = "$(basename "$n")" ] || { echo "ERR: 非法名称"; return 1; }
  : > "$LOGS/$n"
  echo "OK: 已清空日志 $n"
}

clear_all() {
  for f in "$LOGS"/*.log "$LOGS"/*.txt; do
    [ -f "$f" ] && : > "$f"
  done
  echo "OK: 已清空全部日志"
}

case "$1" in
  list)      list_json ;;
  cat|tail)  cat_log "$2" "$3" ;;
  clear)     clear_one "$2" ;;
  clear-all) clear_all ;;
  *) echo "usage: logs.sh {list|cat <name> [n]|clear <name>|clear-all}" ;;
esac
