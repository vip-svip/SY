#!/system/bin/sh
# ============================================================
#  stats.sh — 拦截统计 (参照 AdGuard Home 统计面板)
#  数据源: $LOGS/dns_block.log (由 dnssrv/日志模块写入，每行含被拦截域名)
#  用法: stats.sh {summary|top [n]|clear}
#  作者: vip-svip
# ============================================================
. "$(dirname "$0")/common.sh"

LOG="$LOGS/dns_block.log"

extract_domains() { # 从日志行提取域名
  if [ ! -f "$LOG" ]; then return 0; fi
  awk '
    {
      line=$0
      # 优先抓取 qname=/domain:/host: 等键值
      d=""
      if (match(line, /qname=([^ ]+)/)) d=substr(line, RSTART+6, RLENGTH-6)
      else if (match(line, /domain[:=]([^ ]+)/)) d=substr(line, RSTART+7, RLENGTH-7)
      else if (match(line, /host[:=]([^ ]+)/)) d=substr(line, RSTART+5, RLENGTH-5)
      else {
        # 退化为取该行第一个形如域名的 token
        n=split(line, a, /[ \t,|]+/)
        for (i=1;i<=n;i++) if (a[i] ~ /\./ && a[i] !~ /^[0-9.]+$/) { d=a[i]; break }
      }
      gsub(/["\x27]/, "", d)
      if (d != "") print tolower(d)
    }
  ' "$LOG"
}

summary() {
  total=0
  if [ -f "$LOG" ]; then total=$(wc -l < "$LOG" 2>/dev/null | tr -d ' '); fi
  uniq=$(extract_domains | sort -u | grep -c . 2>/dev/null)
  today=$(date +%Y-%m-%d)
  tcount=0
  if [ -f "$LOG" ]; then tcount=$(grep -c "$today" "$LOG" 2>/dev/null); fi
  E="$RULES_DIR/engine"
  blk=$(count_lines "$E/block.txt")
  bli=$(count_lines "$E/block_imp.txt")
  alw=$(count_lines "$E/allow.txt")
  ali=$(count_lines "$E/allow_imp.txt")
  [ -s "$E/block.txt" ] || { blk=$(count_lines "$RAW_DIR/filter_block.txt"); bli=$(count_lines "$RAW_DIR/filter_block_imp.txt"); alw=$(count_lines "$RAW_DIR/filter_allow.txt"); ali=$(count_lines "$RAW_DIR/filter_allow_imp.txt"); }
  nl=0; [ -f "$DATA_DIR/config/lists.conf" ] && nl=$(grep -vcE '^[[:space:]]*(#|$)' "$DATA_DIR/config/lists.conf" 2>/dev/null)
  printf '{"blocked_total":%s,"blocked_today":%s,"unique_domains":%s,"rule_block":%s,"rule_block_imp":%s,"rule_allow":%s,"rule_allow_imp":%s,"lists":%s}\n' \
    "${total:-0}" "${tcount:-0}" "${uniq:-0}" "${blk:-0}" "${bli:-0}" "${alw:-0}" "${ali:-0}" "${nl:-0}"
}

top() {
  n="$1"; [ -z "$n" ] && n=20
  printf '['
  first=1
  extract_domains | sort | uniq -c | sort -rn | head -n "$n" | while read -r cnt dom; do
    [ -z "$dom" ] && continue
    if [ "$first" = 1 ]; then first=0; else printf ','; fi
    printf '{"domain":"%s","count":%s}' "$(json_escape "$dom")" "$cnt"
  done
  printf ']\n'
}

case "$1" in
  summary) summary ;;
  top)     top "$2" ;;
  clear)   : > "$LOG"; echo "OK: 拦截日志已清空" ;;
  *) echo "usage: stats.sh {summary|top [n]|clear}" ;;
esac
