#!/system/bin/sh
# ============================================================
# PrivacyGuard subread.sh — 分块读取本地订阅正文（v1.10.2）
#
# 为什么需要：正文已落盘到 $PG/subs/<key>.txt，前端不再一次性拿全文，
# 而是按字节偏移分块取，每块单独 base64，避免大字符串经桥层全量拷贝。
#
# 性能（v1.10.3 WebUI 修复）：旧实现即使取 8KB 分块，每次也执行
#   `wc -c < FILE` + `awk 'END{print NR}' FILE`
# 两遍全文件扫描；前端读 1MB 正文要 128 次调用 × 2 次全文件扫描 ⇒ O(n²)。
# 现在：文件大小只用一次 wc-c（普通文件 O(1)）；行数只在 --stat 时统计。
#
# v1.10.5（编辑器不卡死·只读分页查看器）新增：
#   --page <startLine> <count> [maxBytes]
#       只回「从第 startLine 行开始、最多 count 行 / maxBytes 字节」的一页正文。
#       前端只把这一页塞进只读 <pre>，永远不把整份大文本放进可编辑控件
#       （AdGuard Home 的做法：大文本永远不进编辑控件）。
#       行数/总大小来自 subfetch.sh 的元数据，前端据此算页数。
#   --put-reset / --put-append <b64> / --put-commit
#       小文件（≤64KB）显式点「编辑」后的安全回写：分片 base64 追加到临时
#       文件再原子 mv，避免一条超长命令撑爆桥层。
#
# 用法:
#   subread.sh <key> <offset> <len> [head]        按字节分块（原有契约）
#   subread.sh <key> --stat                       元数据（size/lines 准确）
#   subread.sh <key> --page <start> <count> [max] 按行分页（新增）
#   subread.sh <key> --put-reset | --put-append <b64> | --put-commit
#
# 输出:
#   {"ok":1,"key":"..","size":N,"lines":N,"off":X,"len":L,"eof":0|1,"b64":"..."}
#   分块模式下 lines 为 0（前端显示行数来自 subfetch.sh 元数据）
#   --page: {"ok":1,...,"total":N,"start":S,"lines":L,"trunc":0|1,"b64":"..."}
#   {"ok":0,"err":"..."}
# ============================================================
_pg_d=$(dirname "$0" 2>/dev/null)
MODDIR=$(cd "$_pg_d" 2>/dev/null && pwd)
case "$MODDIR" in */scripts) MODDIR=${MODDIR%/scripts} ;; esac
if [ ! -f "$MODDIR/module.prop" ]; then
  _pg_d2=$MODDIR
  _pg_n=0
  while [ -n "$_pg_d2" ] && [ "$_pg_d2" != "/" ] && [ $_pg_n -lt 4 ]; do
    if [ -f "$_pg_d2/module.prop" ]; then MODDIR=$_pg_d2; break; fi
    _pg_d2=$(dirname "$_pg_d2")
    _pg_n=$((_pg_n+1))
  done
fi
. "$MODDIR/scripts/util.sh"

key="$1"
off="$2"
len="$3"
opt="$4"

if [ -z "$key" ]; then echo '{"ok":0,"err":"no key"}'; exit 0; fi
# key 只允许安全字符，防路径穿越
case "$key" in *[!A-Za-z0-9_.-]*) echo '{"ok":0,"err":"bad key"}'; exit 0 ;; esac

FILE="$PG/subs/$key.txt"
META="$PG/subs/$key.meta"

# ---- 小文件回写（--put-*）不需要已存在的正文文件 ----
case "$off" in
  --put-reset)
    _pt="$PG/subs/.put.$key"
    : > "$_pt" 2>/dev/null || { echo '{"ok":0,"err":"cannot open temp"}'; exit 0; }
    echo '{"ok":1,"key":"'"$key"'","stage":"reset"}'
    exit 0
    ;;
  --put-append)
    _pt="$PG/subs/.put.$key"
    [ -f "$_pt" ] || { echo '{"ok":0,"err":"no reset"}'; exit 0; }
    if [ -z "$len" ]; then echo '{"ok":0,"err":"no data"}'; exit 0; fi
    printf '%s' "$len" | base64 -d >> "$_pt" 2>/dev/null || { echo '{"ok":0,"err":"append failed"}'; exit 0; }
    echo '{"ok":1,"key":"'"$key"'","stage":"append"}'
    exit 0
    ;;
  --put-commit)
    _pt="$PG/subs/.put.$key"
    [ -f "$_pt" ] || { echo '{"ok":0,"err":"nothing to commit"}'; exit 0; }
    mv -f "$_pt" "$FILE" 2>/dev/null || { rm -f "$_pt"; echo '{"ok":0,"err":"commit failed"}'; exit 0; }
    chmod 600 "$FILE" 2>/dev/null
    _sz=$(wc -c < "$FILE" 2>/dev/null | tr -d ' ')
    case "$_sz" in ''|*[!0-9]*) _sz=0 ;; esac
    _nl=$(awk 'END{print NR}' "$FILE" 2>/dev/null)
    case "$_nl" in ''|*[!0-9]*) _nl=0 ;; esac
    _url=""
    [ -f "$META" ] && _url=$(sed -n 's/^url=//p' "$META" 2>/dev/null | head -1)
    _now=$(date +%s 2>/dev/null)
    case "$_now" in ''|*[!0-9]*) _now=0 ;; esac
    {
      echo "url=$_url"
      echo "size=$_sz"
      echo "lines=$_nl"
      echo "time=$_now"
      echo "edited=1"
    } > "$META" 2>/dev/null
    printf '{"ok":1,"key":"%s","size":%s,"lines":%s,"stage":"commit"}\n' "$key" "$_sz" "$_nl"
    exit 0
    ;;
esac

if [ ! -f "$FILE" ]; then
  echo '{"ok":0,"err":"no local copy","key":"'"$key"'"}'
  exit 0
fi

# 文件大小：普通文件上 wc -c 是 O(1) 量级的短读/stat，可以每次分块都取
_sz=$(wc -c < "$FILE" 2>/dev/null | tr -d ' ')
case "$_sz" in ''|*[!0-9]*) _sz=0 ;; esac

if [ "$off" = "--stat" ]; then
  # 行数统计是全文扫描，只在元数据模式做一次
  _nl=$(awk 'END{print NR}' "$FILE" 2>/dev/null)
  case "$_nl" in ''|*[!0-9]*) _nl=0 ;; esac
  printf '{"ok":1,"key":"%s","size":%s,"lines":%s}\n' "$key" "$_sz" "$_nl"
  exit 0
fi

# ---- 按行分页（只读查看器：一次只回一页，绝不回全文） ----
if [ "$off" = "--page" ]; then
  _start="$len"          # 第 1 个参数：起始行号（1 起）
  _count="$opt"          # 第 2 个参数：最多行数
  _maxb="$5"             # 第 3 个参数：最多字节
  case "$_start" in ''|*[!0-9]*) _start=1 ;; esac
  case "$_count" in ''|*[!0-9]*|0) _count=200 ;; esac
  case "$_maxb" in ''|*[!0-9]*) _maxb=65536 ;; esac
  [ "$_count" -gt 2000 ] && _count=2000
  [ "$_maxb" -gt 262144 ] && _maxb=262144
  # 总行数：优先用 subfetch.sh 元数据，缺失才全文扫一遍
  _total=0
  if [ -f "$META" ]; then
    _total=$(sed -n 's/^lines=//p' "$META" 2>/dev/null | head -1)
    case "$_total" in ''|*[!0-9]*) _total=0 ;; esac
  fi
  if [ "$_total" -le 0 ]; then
    _total=$(awk 'END{print NR}' "$FILE" 2>/dev/null)
    case "$_total" in ''|*[!0-9]*) _total=0 ;; esac
  fi
  [ "$_start" -lt 1 ] && _start=1
  # 起始行字节偏移：awk 只扫到起始行为止（O(行号)，不扫全文到 END）
  _poff=$(awk -v s="$_start" 'BEGIN{o=0}
    NR<s { o+=length($0)+1; next }
    { print o; found=1; exit }
    END { if(!found) print o }' "$FILE" 2>/dev/null)
  case "$_poff" in ''|*[!0-9]*) _poff=0 ;; esac
  _raw="$PG/subs/.page.$$.raw"
  _ptmp="$PG/subs/.page.$$"
  # 只取「本页可能需要的字节」：最多 maxBytes，避免大行/大文件把整页读进内存
  tail -c +$((_poff + 1)) "$FILE" 2>/dev/null | head -c "$_maxb" > "$_raw" 2>/dev/null
  _got=$(wc -c < "$_raw" 2>/dev/null | tr -d ' ')
  case "$_got" in ''|*[!0-9]*) _got=0 ;; esac
  # 页内再按行数截断（只保留前 _count 行），保证前端永远只拿到「一页」
  if [ "$_got" -gt 0 ]; then
    awk -v n="$_count" 'NR<=n' "$_raw" > "$_ptmp" 2>/dev/null
  else
    : > "$_ptmp" 2>/dev/null
  fi
  _plines=$(awk 'END{print NR}' "$_ptmp" 2>/dev/null)
  case "$_plines" in ''|*[!0-9]*) _plines=0 ;; esac
  # 是否还有更多内容（本页被行数或字节上限截断）
  _trunc=0
  if [ "$_got" -ge "$_maxb" ]; then
    _rest=$(tail -c +$((_poff + _maxb + 1)) "$FILE" 2>/dev/null | head -c 1)
    [ -n "$_rest" ] && _trunc=1
  fi
  if [ "$_plines" -ge "$_count" ]; then
    # 本页取满 count 行：若原文在 noff 之后还有行，就是被截断了
    _noff=$(awk -v s="$_start" 'BEGIN{o=0} NR<s{o+=length($0)+1;next} {print o; f=1; exit} END{if(!f)print o}' "$FILE" 2>/dev/null)
    case "$_noff" in ''|*[!0-9]*) _noff=0 ;; esac
    _pbytes=$(wc -c < "$_ptmp" 2>/dev/null | tr -d ' ')
    case "$_pbytes" in ''|*[!0-9]*) _pbytes=0 ;; esac
    _more=$(tail -c +$((_noff + _pbytes + 1)) "$FILE" 2>/dev/null | head -c 1)
    [ -n "$_more" ] && _trunc=1
  fi
  _b64=$(base64 < "$_ptmp" 2>/dev/null | tr -d '\n')
  rm -f "$_ptmp" "$_raw" 2>/dev/null
  printf '{"ok":1,"key":"%s","size":%s,"total":%s,"start":%s,"count":%s,"lines":%s,"trunc":%s,"eof":%s,"b64":"%s"}\n' \
    "$key" "$_sz" "$_total" "$_start" "$_count" "$_plines" "$_trunc" \
    "$([ $((_start + _plines)) -gt $_total ] && echo 1 || echo 0)" "$_b64"
  exit 0
fi

case "$off" in ''|*[!0-9]*) off=0 ;; esac
case "$len" in ''|*[!0-9]*|0) len=131072 ;; esac
if [ "$len" -gt 131072 ]; then len=131072; fi
if [ "$off" -gt "$_sz" ]; then off=$_sz; fi

if [ "$opt" = "head" ]; then
  _b64=$(head -c "$len" "$FILE" 2>/dev/null | base64 | tr -d '\n')
else
  _b64=$(tail -c +$((off + 1)) "$FILE" 2>/dev/null | head -c "$len" | base64 | tr -d '\n')
fi

# 本块实际字节数（base64 长度反推；末尾可能有 1~2 个填充）
_elen=${#_b64}
_got=$(( _elen / 4 * 3 ))
case "$_b64" in
  *==) _got=$(( _got - 2 )) ;;
  *=)  _got=$(( _got - 1 )) ;;
esac

_next=$(( off + _got ))
[ "$opt" = "head" ] && _next=$_got
_eof=0
if [ "$_next" -ge "$_sz" ]; then _eof=1; fi
[ -z "$_b64" ] && _eof=1

# 分块模式不再跑 awk 统计行数（大文件上这是 O(n²) 的主要来源）；
# 前端展示所需行数来自 subfetch.sh 的元数据 JSON。
printf '{"ok":1,"key":"%s","size":%s,"lines":0,"off":%s,"len":%s,"eof":%s,"b64":"%s"}\n' \
  "$key" "$_sz" "$off" "$_got" "$_eof" "$_b64"
exit 0
