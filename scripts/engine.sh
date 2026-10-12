#!/system/bin/sh
# ============================================================
#  engine.sh — SY-Fusion 融合过滤引擎（AdGuard Home + uBlock Origin）
#  ------------------------------------------------------------
#  严格 POSIX sh + POSIX awk 实现，零外部依赖，可在 Android
#  (toybox/busybox awk) 与桌面 (gawk/mawk) 双端一致运行。
#
#  支持的规则语法（可任意混排于同一文件）：
#   · AdBlock Plus / uBlock Origin 网络规则
#       ||domain^   |http://...|   domain   /regex/   @@例外   *  ^  分隔符
#   · 修饰符
#       $important $badfilter $dnsrewrite= $client= $ctag= $denyallow=
#       $domain= $third-party/$3p $first-party/$1p $match-case
#       $csp= $removeparam= $redirect= $cookie= $header= $method= $permissions=
#       资源类型: $document $script $image $stylesheet $xmlhttprequest
#                 $subdocument $websocket $webrtc $ping $object $media $font
#                 $other $popup $all $empty $mp4 $inline-script $inline-font
#                 $generichide $specifichide $elemhide $genericblock
#   · Cosmetic / 注入（uBO 与 AdGuard 双语法）
#       ##selector      #@#selector     domain##selector
#       ##+js(name,args)                 (uBO 脚本注入)
#       #%#//scriptlet('name','args')    (AdGuard 脚本注入)
#       #$#selector {css}                (AdGuard CSS 注入)
#       #?#selector                      (扩展 CSS)
#       $$html-filter / ##^html-filter    (HTML 过滤)
#   · hosts 格式        0.0.0.0 d / 127.0.0.1 d / ::1 d / IP d(重写)
#   · dnsmasq 格式      address=/d/  address=/d/IP  local=/d/  server=/d/
#   · 纯域名清单        example.com
#   · 注释              !  #  ;  [Adblock Plus 2.0]
#
#  优先级（与 uBlock/AdGuard Home 一致）：
#       重要放行 > 重要拦截 > 普通放行 > 普通拦截
#       $badfilter 关闭同形规则；$denyallow 限定例外范围
#
#  用法: engine.sh {build|compile|stats|syntax|test <domain>|verify|clear|paths}
# ============================================================
. "$(dirname "$0")/common.sh"

AWKDIR="$(cd "$(dirname "$0")" && pwd)"
ENG_RAW="$CACHE/engine"
ENG_OUT="$RULES_DIR/engine"
REC="$ENG_RAW/records.tsv"
mkdir -p "$ENG_RAW" "$ENG_OUT"

# ---- 引擎配置（单次 awk 读取，避免多次 fork）----
_eng_cfg() {
  awk -F'=' '
    /^[ \t]*#/ { next }
    {
      k = $1; gsub(/^[ \t]+|[ \t]+$/, "", k)
      if (k !~ /^(ENGINE_HEURISTIC|ENGINE_STRICT_SCOPE|ENGINE_CLIENT|ENGINE_CTAG|HOSTS_EXTRA)$/) next
      v = $0; sub(/^[^=]*=/, "", v); gsub(/^[ \t]+|[ \t]+$/, "", v)
      gsub(/[^A-Za-z0-9_.,:\/-]/, "", v)
      printf "%s=%s\n", k, v
    }
  ' "$CONFIG" 2>/dev/null
}
eval "$(_eng_cfg)"
ENGINE_HEURISTIC=${ENGINE_HEURISTIC:-1}
ENGINE_STRICT_SCOPE=${ENGINE_STRICT_SCOPE:-0}
ENGINE_CLIENT=${ENGINE_CLIENT:-}
ENGINE_CTAG=${ENGINE_CTAG:-}
HOSTS_EXTRA=${HOSTS_EXTRA:-www}

# ---------- 源文件收集 ----------
collect_files() {
  LISTS_CONF="$DATA_DIR/config/lists.conf"
  RAW_DIR="$CACHE/dns"
  # 多规则表(lists.conf)中已启用的列表 —— 单次 awk 处理，避免逐行 fork
  if [ -f "$LISTS_CONF" ]; then
    awk -F'|' -v raw="$RAW_DIR" '
      /^[ \t]*#/ { next }
      /^[ \t]*$/ { next }
      {
        nm = $1; gsub(/[ \t]/, "", nm)
        en = $3; gsub(/[ \t]/, "", en)
        if (en == "") en = 1
        if (en != "1") next
        if (nm == "") next
        print raw "/list_" nm ".txt"
      }
    ' "$LISTS_CONF" 2>/dev/null
  fi
  # 其余原始规则缓存
  for f in "$RAW_DIR"/*.txt; do
    [ -f "$f" ] || continue
    bn=$(basename "$f")
    case "$bn" in all_domains.txt|filter_*|list_*|.filter_*|records.tsv) continue ;; esac
    [ -s "$f" ] && echo "$f"
  done
  # 模块内置 / 外置规则
  for f in \
    "$DATA_DIR/rules/remote/block.txt" \
    "$DATA_DIR/rules/netblock/domains.txt" \
    "$DATA_DIR/config/user_rules.txt" \
    "$DATA_DIR/config/blacklist.conf" \
    "$DNS_DIR/custom.txt" \
    "$DATA_DIR/config/whitelist.conf" \
    "$DNS_DIR/removed.txt"
  do
    [ -f "$f" ] && [ -s "$f" ] && echo "$f"
  done
  return 0
}

# ---------- 解析 ----------
# 单文件解析: 白名单 → @@例外 ; 黑名单 → $important 强制拦截
parse_one() { # <file>
  f="$1"
  [ -f "$f" ] || return 0
  bn=$(basename "$f")
  case "$bn" in
    whitelist.conf|removed.txt)
      tmp="$ENG_RAW/.wl.$$"
      awk '{ l=$0; sub(/^[ \t]+/,"",l); sub(/[ \t]+$/,"",l);
             if (l=="" || substr(l,1,1)=="#" || substr(l,1,1)=="!" || substr(l,1,1)==";" || substr(l,1,2)=="@@") print l;
             else print "@@" l }' "$f" > "$tmp" 2>/dev/null
      awk -v SRC="$bn" -f "$AWKDIR/engine_parse.awk" "$tmp" >> "$REC" 2>/dev/null
      rm -f "$tmp"
      ;;
    blacklist.conf)
      tmp="$ENG_RAW/.bl.$$"
      awk '{ l=$0; sub(/^[ \t]+/,"",l); sub(/[ \t]+$/,"",l);
             if (l=="" || substr(l,1,1)=="#" || substr(l,1,1)=="!" || substr(l,1,1)==";" || index(l,"$")>0) print l;
             else print l "$important" }' "$f" > "$tmp" 2>/dev/null
      awk -v SRC="blacklist.conf" -f "$AWKDIR/engine_parse.awk" "$tmp" >> "$REC" 2>/dev/null
      rm -f "$tmp"
      ;;
    *)
      awk -v SRC="$bn" -f "$AWKDIR/engine_parse.awk" "$f" >> "$REC" 2>/dev/null
      ;;
  esac
}

parse_all() {
  : > "$REC"
  flist="$ENG_RAW/.files.$$"
  collect_files > "$flist"
  while IFS= read -r f; do
    [ -f "$f" ] && parse_one "$f"
  done < "$flist"
  rm -f "$flist"
  # 允许通过 ENGINE_EXTRA_INPUT 追加额外规则文件(测试/高级用法)
  if [ -n "$ENGINE_EXTRA_INPUT" ] && [ -f "$ENGINE_EXTRA_INPUT" ]; then
    awk -v SRC="$(basename "$ENGINE_EXTRA_INPUT")" -f "$AWKDIR/engine_parse.awk" "$ENGINE_EXTRA_INPUT" >> "$REC" 2>/dev/null
  fi
}

# ---------- $badfilter 关闭 ----------
# 同时记录被关闭的规则数（apply 之后 REC 中已无 badfilter 记录，需先行统计）
apply_badfilter() {
  out="$REC.f"
  awk -F'\t' -v OFS='\t' -v CNT="$ENG_RAW/badfilter.count" '
    NR==FNR { if ($12=="1") { bad[$13]=1; nb++ } next }
    { if ($12=="1") next; if ($13 in bad) next; print }
    END { print nb + 0 > CNT; close(CNT) }
  ' "$REC" "$REC" > "$out" 2>/dev/null
  mv -f "$out" "$REC"
}

# ---------- 分类发射 ----------
# 仅在非空时排序，减少进程开销（Android 上尤为明显）
sortu() { [ -s "$1" ] && sort -u "$1" -o "$1" 2>/dev/null; return 0; }

emit_all() {
  for f in allow_imp allow block_imp block pattern_allow pattern_block \
           heuristic_allow heuristic_block regex_allow regex_block rewrite \
           allow_deny cosmetic_hide cosmetic_unhide scriptlets js_inject \
           css_inject ext_css html_filter; do
    : > "$ENG_OUT/$f.txt"
  done
  awk -v OUT="$ENG_OUT" -v CLIENT="$ENGINE_CLIENT" -v CTAG="$ENGINE_CTAG" \
      -v STRICT="$ENGINE_STRICT_SCOPE" -f "$AWKDIR/engine_emit.awk" "$REC"
  for f in allow_imp allow block_imp block heuristic_allow heuristic_block \
           regex_allow regex_block allow_deny cosmetic_hide cosmetic_unhide \
           scriptlets js_inject css_inject ext_css html_filter rewrite \
           pattern_block pattern_allow; do
    sortu "$ENG_OUT/$f.txt"
  done
}

# ---------- hosts 生成 ----------
gen_hosts() {
  HB=""; HA=""
  if [ "$ENGINE_HEURISTIC" = "1" ]; then
    [ -s "$ENG_OUT/heuristic_block.txt" ] && HB="$ENG_OUT/heuristic_block.txt"
    [ -s "$ENG_OUT/heuristic_allow.txt" ] && HA="$ENG_OUT/heuristic_allow.txt"
  fi
  awk \
    -v AI="$ENG_OUT/allow_imp.txt" \
    -v BI="$ENG_OUT/block_imp.txt" \
    -v AN="$ENG_OUT/allow.txt" \
    -v BN="$ENG_OUT/block.txt" \
    -v HA="$HA" \
    -v HB="$HB" \
    -v ADENY="$ENG_OUT/allow_deny.txt" \
    -v EXTRA="$HOSTS_EXTRA" \
    -v NOW="$(date '+%Y-%m-%d %H:%M:%S')" \
    -f "$AWKDIR/engine_hosts.awk" /dev/null > "$ENG_OUT/.hosts.raw" 2>/dev/null
  # 头部(注释) + 排序去重的数据行，保证输出可复现
  grep '^#' "$ENG_OUT/.hosts.raw" > "$ENG_OUT/.hosts.head" 2>/dev/null
  grep -v '^#' "$ENG_OUT/.hosts.raw" 2>/dev/null | sed '/^[[:space:]]*$/d' | sort -u > "$ENG_OUT/.hosts.body"
  nb=$(wc -l < "$ENG_OUT/.hosts.body" 2>/dev/null | tr -d ' ')
  [ -z "$nb" ] && nb=0
  {
    cat "$ENG_OUT/.hosts.head"
    echo "# 统计: hosts 拦截条目 $nb 行"
    cat "$ENG_OUT/.hosts.body"
  } > "$ENG_OUT/hosts"
  rm -f "$ENG_OUT/.hosts.raw" "$ENG_OUT/.hosts.head" "$ENG_OUT/.hosts.body"
  chmod 0644 "$ENG_OUT/hosts" 2>/dev/null
}

# ---------- AdGuard/dnsmasq 格式 DNS 规则(供本地解析器消费) ----------
gen_dnsrules() {
  {
    echo "# SY-Fusion DNS 规则 (AdGuard Home / dnsmasq 兼容)"
    echo "# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
  } > "$ENG_OUT/dnsrules.conf"
  {
    awk '{print "address=/" $0 "/"}' "$ENG_OUT/block_imp.txt" 2>/dev/null
    awk '{print "address=/" $0 "/"}' "$ENG_OUT/block.txt" 2>/dev/null
    if [ "$ENGINE_HEURISTIC" = "1" ]; then
      awk '{print "address=/" $0 "/"}' "$ENG_OUT/heuristic_block.txt" 2>/dev/null
    fi
  } | sort -u >> "$ENG_OUT/dnsrules.conf" 2>/dev/null
}

# ---------- 编译 ----------
do_build() {
  _t0=$(date +%s)
  parse_all
  _t1=$(date +%s)
  apply_badfilter
  _t2=$(date +%s)
  emit_all
  _t3=$(date +%s)
  gen_hosts
  _t4=$(date +%s)
  gen_dnsrules
  _t5=$(date +%s)
  if [ "${ENGINE_DEBUG_TIME:-0}" = "1" ]; then
    echo "TIMING parse=$((_t1 - _t0))s badfilter=$((_t2 - _t1))s emit=$((_t3 - _t2))s hosts=$((_t4 - _t3))s dnsrules=$((_t5 - _t4))s total=$((_t5 - _t0))s" >&2
  fi
  log "$(awk -v o="$ENG_OUT" '
    function cnt(f,   n, l) { n = 0; while ((getline l < f) > 0) n++; close(f); return n }
    BEGIN {
      printf "engine: 编译完成 拦截=%d 重要拦截=%d 放行=%d 重要放行=%d 正则=%d 重写=%d 隐藏=%d 脚本=%d", \
        cnt(o "/block.txt"), cnt(o "/block_imp.txt"), cnt(o "/allow.txt"), cnt(o "/allow_imp.txt"), \
        cnt(o "/regex_block.txt"), cnt(o "/rewrite.txt"), cnt(o "/cosmetic_hide.txt"), cnt(o "/scriptlets.txt")
    }')"
}

# ---------- 统计 ----------
do_stats() {
  b=$(count_lines "$ENG_OUT/block.txt")
  bi=$(count_lines "$ENG_OUT/block_imp.txt")
  a=$(count_lines "$ENG_OUT/allow.txt")
  ai=$(count_lines "$ENG_OUT/allow_imp.txt")
  re=$(count_lines "$ENG_OUT/regex_block.txt")
  rea=$(count_lines "$ENG_OUT/regex_allow.txt")
  rw=$(count_lines "$ENG_OUT/rewrite.txt")
  pb=$(count_lines "$ENG_OUT/pattern_block.txt")
  pa=$(count_lines "$ENG_OUT/pattern_allow.txt")
  hb=$(count_lines "$ENG_OUT/heuristic_block.txt")
  ch=$(count_lines "$ENG_OUT/cosmetic_hide.txt")
  cu=$(count_lines "$ENG_OUT/cosmetic_unhide.txt")
  sc=$(count_lines "$ENG_OUT/scriptlets.txt")
  ci=$(count_lines "$ENG_OUT/css_inject.txt")
  ec=$(count_lines "$ENG_OUT/ext_css.txt")
  hf=$(count_lines "$ENG_OUT/html_filter.txt")
  hosts=$(count_lines "$ENG_OUT/hosts")
  rec=$(count_lines "$REC")
  nl=0
  [ -f "$DATA_DIR/config/lists.conf" ] && nl=$(grep -vcE '^[[:space:]]*(#|$)' "$DATA_DIR/config/lists.conf" 2>/dev/null)
  [ -z "$nl" ] && nl=0
  tot=$((b+bi+a+ai+re+rea+rw+pb+pa+hb+ch+cu+sc+ci+ec+hf))
  printf '{"block":%s,"block_important":%s,"allow":%s,"allow_important":%s,"regex":%s,"regex_allow":%s,"rewrite":%s,"pattern_block":%s,"pattern_allow":%s,"heuristic":%s,"cosmetic_hide":%s,"cosmetic_unhide":%s,"scriptlets":%s,"css_inject":%s,"ext_css":%s,"html_filter":%s,"hosts_lines":%s,"records":%s,"lists":%s,"total":%s}\n' \
    "$b" "$bi" "$a" "$ai" "$re" "$rea" "$rw" "$pb" "$pa" "$hb" "$ch" "$cu" "$sc" "$ci" "$ec" "$hf" "$hosts" "$rec" "$nl" "$tot"
}

# ---------- 语法分析 ----------
do_syntax() {
  awk -F'\t' '
    function esc(s){ gsub(/\\/,"\\\\",s); gsub(/"/,"\\\"",s); return s }
    $1=="X" { inv++; next }
    {
      raw=$15; type=$1; kind=$2; form=$4
      if (type=="C") {
        if (kind=="S") { sc++; SYN["scriptlet"]++ }
        else if (kind=="K") { ci++; SYN["css-inject"]++ }
        else if (kind=="E2") { ec++; SYN["extended-css"]++ }
        else if (kind=="F") { hf++; SYN["html-filter"]++ }
        else if (kind=="J") { ji++; SYN["js-inject"]++ }
        else { cs++; SYN["cosmetic"]++ }
        tot++; next
      }
      if (type=="W") { rw++; SYN["dnsrewrite"]++; tot++; next }
      if (form=="R") { rx++; SYN["regex"]++; tot++; next }
      if (raw ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[ \t]/ || raw ~ /^[0-9a-fA-F:]+:[0-9a-fA-F:]+[ \t]/) { ho++; SYN["hosts"]++; tot++; next }
      if (raw ~ /^address=\// || raw ~ /^local=\//) { dm++; SYN["dnsmasq"]++; tot++; next }
      # 含 $ 修饰符的规则优先计入「修饰符」——修饰符才是其可辨识语法特征
      if (raw ~ /\$/) { mo++; SYN["modifiers"]++; tot++; next }
      # ABP/AdGuard/uBO 网络语法：域锚定、URL 锚定、例外、通配
      if (raw ~ /^\|\|/ || raw ~ /^\|/ || raw ~ /^@@/ || raw ~ /\*/ || raw ~ /\?/) { ab++; SYN["adblock"]++; tot++; next }
      { rd++; SYN["plain-domain"]++; tot++ }
    }
    END {
      printf "{"
      printf "\"total\":%d,\"invalid\":%d", tot+0, inv+0
      printf ",\"by_syntax\":{"
      first=1
      for (k in SYN) {
        if (!first) printf ","
        first=0
        printf "\"%s\":%d", esc(k), SYN[k]
      }
      printf "}}\n"
    }
  ' "$REC"
}

# ---------- 命中诊断 ----------
do_test() {
  d="$1"
  [ -z "$d" ] && { echo '{"error":"missing domain"}'; return 1; }
  [ -f "$REC" ] || do_build >/dev/null 2>&1
  awk -v REC="$REC" -v DOMAIN="$d" -v CLIENT="$ENGINE_CLIENT" -v CTAG="$ENGINE_CTAG" \
      -v STRICT="$ENGINE_STRICT_SCOPE" -f "$AWKDIR/engine_test.awk" /dev/null
}

# ---------- 批量命中诊断（单次装载，多域求值）----------
do_testfile() {
  f="$1"
  [ -n "$f" ] || { echo "ERR: 缺少用例文件"; return 1; }
  [ -f "$f" ] || { echo "ERR: 用例文件不存在: $f"; return 1; }
  [ -f "$REC" ] || do_build >/dev/null 2>&1
  awk -v REC="$REC" -v CASES="$f" -v CLIENT="$ENGINE_CLIENT" -v CTAG="$ENGINE_CTAG" \
      -v STRICT="$ENGINE_STRICT_SCOPE" -f "$AWKDIR/engine_test.awk" /dev/null
}

# ---------- 规则校验 ----------
do_verify() {
  # $badfilter 记录在编译阶段已被剔除，其数量由 apply_badfilter 记录在计数文件
  bfc=0
  [ -f "$ENG_RAW/badfilter.count" ] && bfc=$(tr -dc '0-9' < "$ENG_RAW/badfilter.count" 2>/dev/null)
  [ -n "$bfc" ] || bfc=0
  awk -F'\t' -v BFC="$bfc" '
    { tot++ }
    $1=="X" { inv++ }
    $1=="N" && $4=="D" {
      if ($2=="B") { if ($3=="1") BI[$5]=1; else BN[$5]=1 }
      else         { if ($3=="1") AI[$5]=1; else AN[$5]=1 }
    }
    END {
      # 冗余: 同一域名同时存在于普通与重要层级(低优先级被遮蔽)
      for (d in BN) { if (d in BI) rb++; if (d in AN || d in AI) cf++ }
      for (d in BI) { if (d in AN || d in AI) cf++ }
      for (d in AN) { if (d in AI) ra++ }
      printf "{\"records\":%d,\"invalid\":%d,\"badfilter_rules\":%d,\"redundant_block\":%d,\"redundant_allow\":%d,\"conflicts\":%d,\"ok\":%s}\n", \
        tot+0, inv+0, BFC+0, rb+0, ra+0, cf+0, ((inv+0)==0 ? "true" : "false")
    }
  ' "$REC" 2>/dev/null
}

case "$1" in
  build|compile) do_build; echo "OK: 引擎已编译 — 拦截 $(count_lines "$ENG_OUT/block.txt") / 重要拦截 $(count_lines "$ENG_OUT/block_imp.txt") / 放行 $(count_lines "$ENG_OUT/allow.txt") / hosts $(count_lines "$ENG_OUT/hosts") 行" ;;
  stats)   do_stats ;;
  syntax)  do_syntax ;;
  test)    do_test "$2" ;;
  testfile) do_testfile "$2" ;;
  verify)  do_verify ;;
  paths)
    printf '{"raw":"%s","out":"%s","records":"%s","hosts":"%s"}\n' "$ENG_RAW" "$ENG_OUT" "$REC" "$ENG_OUT/hosts"
    ;;
  clear)
    rm -f "$ENG_OUT"/*.txt "$ENG_OUT"/hosts "$ENG_OUT"/dnsrules.conf "$ENG_RAW"/records.tsv 2>/dev/null
    echo "OK: 引擎输出已清空"
    ;;
  *) echo "usage: engine.sh {build|compile|stats|syntax|test <domain>|testfile <file>|verify|clear|paths}" ;;
esac
