#!/system/bin/sh
# ============================================================
# PrivacyGuard substatus.sh — 规则源/订阅的抓取状态明细（v1.10.7 新增）
#
# 为什么需要：用户在「规则」页看不到订阅下载失败的原因（只看到条目还在那里，
# 或者条目消失了），apply.log 里虽有 FAIL 行但需要点开日志翻。这里把每次抓取的
# 结果**按源落盘成结构化状态**，WebUI 直接读取并在对应条目下方显示「成功/失败 +
# 原因 + 量（行数/大小）+ 时间」。
#
# 状态文件：$PG/cache/substatus.db（TSV，一行一个源）
#   TYPE<TAB>KEY<TAB>STATUS<TAB>DETAIL<TAB>BYTES/LINES<TAB>EPOCH
#   TYPE   = rule | hostssub | vpnsub
#   KEY    = 源的 URL 或标识（WebUI 用它匹配条目 data-url）
#   STATUS = ok | fail | partial | cached
#   DETAIL = 人类可读原因（失败时是 curl rc / TLS / 404 等）
#
# 用法:
#   substatus.sh record <type> <key> <status> <detail> [amount]
#   substatus.sh get [type]        输出 JSON 数组（WebUI 用）
#   substatus.sh summary [type]    输出最新状态汇总及超过 24 小时未更新的源数量
#   substatus.sh list              人读表格
#   substatus.sh clear             清空
# 并发安全：只用 >> 追加 + 读取时取每个 KEY 的最后一行（后写覆盖前写）。
# ============================================================
# >>> pg-moddir (auto)
_pg_d=$(dirname "$0" 2>/dev/null)
MODDIR=$(cd "$_pg_d" 2>/dev/null && pwd)
case "$MODDIR" in */scripts) MODDIR=${MODDIR%/scripts} ;; esac
if [ ! -f "$MODDIR/module.prop" ]; then
  _pg_d2=$MODDIR
  _pg_n=0
  while [ -n "$_pg_d2" ] && [ "$_pg_d2" != "/" ] && [ $_pg_n -lt 4 ]; do
    if [ -f "$_pg_d2/module.prop" ]; then MODDIR=$_pg_d2; break; fi
    _pg_d2=$(dirname "$_pg_d2")
    _pg_n=$((_pg_n + 1))
  done
fi
# <<< pg-moddir
PG=${PG:-/data/adb/privacyguard}
DB="$PG/cache/substatus.db"

js() {
  printf '%s' "$1" | sed -e 's/|/%7C/g' -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/ /g' | tr -d '\r\n'
}

mkdir -p "$PG/cache" 2>/dev/null

case "$1" in
  record)
    _r_type="$2"; _r_key="$3"; _r_st="$4"; _r_detail="$5"; _r_amt="$6"
    [ -n "$_r_type" ] && [ -n "$_r_key" ] || exit 0
    [ -n "$_r_st" ] || _r_st="ok"
    _r_now=$(date +%s 2>/dev/null)
    case "$_r_now" in ''|*[!0-9]*) _r_now=0 ;; esac
    # 用 | 作内部分隔（URL 不含 |，详情里也不含），最后转 TSV 存
    printf '%s|%s|%s|%s|%s|%s\n' \
      "$(js "$_r_type")" "$(js "$_r_key")" "$(js "$_r_st")" \
      "$(js "$_r_detail")" "$(js "$_r_amt")" "$_r_now" >> "$DB" 2>/dev/null
    # 文件过大时压缩：只保留每个 KEY 的最后一条
    _r_lines=$(wc -l < "$DB" 2>/dev/null | tr -d ' ')
    case "$_r_lines" in ''|*[!0-9]*) _r_lines=0 ;; esac
    if [ "$_r_lines" -gt 400 ]; then
      awk -F'|' '{ a[$1"|"$2] = $0 } END { for (k in a) print a[k] }' "$DB" > "$DB.tmp" 2>/dev/null \
        && mv -f "$DB.tmp" "$DB" 2>/dev/null
    fi
    ;;
  get)
    _g_type="$2"
    [ -f "$DB" ] || { printf '{"ok":1,"items":[]}\n'; exit 0; }
    awk -F'|' -v want="$_g_type" -v now="$(date +%s 2>/dev/null)" '
      {
        if (want != "" && $1 != want) next
        key = $1 "|" $2
        last[key] = $0
      }
      END {
        first = 1
        printf "{\"ok\":1,\"items\":["
        for (k in last) {
          split(last[k], f, "|")
          if (!first) printf ","
          first = 0
          age = (now != "" && f[6] != "" && now - f[6] > 0) ? (now - f[6]) : 0
          printf "{\"type\":\"%s\",\"key\":\"%s\",\"status\":\"%s\",\"detail\":\"%s\",\"amount\":\"%s\",\"age\":%d}", f[1], f[2], f[3], f[4], f[5], age
        }
        printf "]}\n"
      }
    ' "$DB" 2>/dev/null
    ;;
  summary)
    _sum_type="$2"
    [ -f "$DB" ] || { printf '{"ok":1,"total":0,"ok_count":0,"fail_count":0,"partial_count":0,"cached_count":0,"stale_count":0}\n'; exit 0; }
    awk -F'|' -v want="$_sum_type" -v now="$(date +%s 2>/dev/null)" '
      {
        if (want != "" && $1 != want) next
        key = $1 "|" $2
        last[key] = $0
      }
      END {
        total=ok=fail=partial=cached=stale=0
        for (k in last) {
          split(last[k], f, "|")
          total++
          if (f[3] == "ok") ok++
          else if (f[3] == "fail") fail++
          else if (f[3] == "partial") partial++
          else if (f[3] == "cached") cached++
          if (now ~ /^[0-9]+$/ && f[6] ~ /^[0-9]+$/ && now-f[6] > 86400) stale++
        }
        printf "{\"ok\":1,\"total\":%d,\"ok_count\":%d,\"fail_count\":%d,\"partial_count\":%d,\"cached_count\":%d,\"stale_count\":%d}\n", total,ok,fail,partial,cached,stale
      }
    ' "$DB" 2>/dev/null
    ;;
  list)
    [ -f "$DB" ] || { echo "（无记录）"; exit 0; }
    awk -F'|' '
      { last[$1"|"$2] = $0 }
      END {
        for (k in last) {
          split(last[k], f, "|")
          printf "%-8s %-9s %-60s %s\n", f[1], f[3], substr(f[2],1,58), f[4]
        }
      }
    ' "$DB" 2>/dev/null | sort
    ;;
  clear)
    rm -f "$DB" 2>/dev/null
    echo "cleared"
    ;;
  *)
    echo "usage: substatus.sh record|get [type]|summary [type]|list|clear" >&2
    exit 1
    ;;
esac
exit 0
