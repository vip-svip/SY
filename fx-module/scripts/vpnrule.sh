#!/system/bin/sh
# ============================================================
# PrivacyGuard vpnrule.sh — Clash/FX 规则 → sing-box route.rules 编译器
#
# 为什么需要：模块 WebUI 能识别 33 种 Clash 规则语法，但 shell 层原来只消费
# HOSTS/DOMAIN*/ADBLOCK/IP-CIDR（写进 hosts 或 iptables），其余当垃圾行丢弃。
# v1.10.5 起代理核心改为 sing-box `redirect` 入站 + `route action sniff`，
# 能从 REDIRECT 过来的纯 IP 连接里还原域名/协议，因此下面这批语法现在可以
# 编译成内核路由规则真正生效（真机 1.14.3 逐条 check 验证）：
#   DOMAIN / DOMAIN-SUFFIX / DOMAIN-KEYWORD / DOMAIN-REGEX / HOST* / ADBLOCK
#   IP-CIDR / IP-CIDR6 / MIXED-IP-CIDR
#   PROCESS-NAME / PACKAGE-NAME
#   DST-PORT / SRC-PORT（含端口区间）
#   PROTOCOL / NETWORK / RULE-SET / AND / OR / NOT / REJECT / MATCH / FINAL
#
# 明确不支持（真机 check 实测 unknown field / 运行期 FATAL）：
#   URL-REGEX, USER-AGENT  → 需要 L7 解密拿完整 URL / HTTP 头
#   IP-ASN                 → sing-box 已移除 ASN 数据库
#   GEOIP, GEOSITE         → 1.12 起数据库废弃，运行期 FATAL
#   MITM                   → 需要 CA 中间人解密
# 这些一律输出 SKIP:<TYPE> 计数，绝不写进 JSON（写入 unknown field 会让
# sing-box run 直接 FATAL，整个 VPN 挂掉）。
#
# 用法:
#   vpnrule.sh --list          人读明细：OK 条数 / SKIP 条数与原因
#   vpnrule.sh --emit          输出 route.rules 的 JSON 数组片段（不含外层 []）
#   vpnrule.sh --json          机器可读统计（WebUI 用）
#   vpnrule.sh --check <bin>   用指定 sing-box 二进制兜底校验（可选）
#   规则来源: $PG/settings.conf 的 [list:rule] + [list:fx]（只取勾选=1）
#   可覆盖: VPNRULE_SRC=<file> 指定规则文件（测试用）
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
CONF=${CONF:-$PG/settings.conf}
SRC=${VPNRULE_SRC:-$CONF}
WORK=${VPNRULE_WORK:-$PG/cache/vpnrule.$$}
mkdir -p "$WORK" 2>/dev/null
MODE="$1"
BIN="$2"
# [list:fx] is additionally gated by the single FX master switch. Per-row state
# controls individual sources only; it must never bypass fx=0 in the proxy route compiler.
FX_MASTER=$(grep -m1 '^fx=' "$CONF" 2>/dev/null | cut -d= -f2-)
[ "$FX_MASTER" = "1" ] || FX_MASTER=0

# ---------- 输出模式 ----------
n_ok=0; n_skip=0; n_total=0
skip_detail=""

# JSON 字符串转义（只需处理 " \ 与控制字符；规则里常见的是反斜杠）
js() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/ /g' | tr -d '\r'
}

# 端口合法性：1..65535
port_ok() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }

# 端口区间 a:b（sing-box 要求 "a:b" 形式且两端合法、a<=b）
prange_ok() {
  _pa=${1%%:*}; _pb=${1#*:}
  port_ok "$_pa" && port_ok "$_pb" || return 1
  [ "$_pa" -le "$_pb" ]
}

# CIDR 校验：必须有 /；IPv4 掩码限定 0..32，IPv6 限定 0..128，并验证地址组数。
cidr_ok() {
  _c="$1"
  case "$_c" in */*) ;; *) return 1 ;; esac
  _addr=${_c%/*}; _mask=${_c#*/}
  case "$_mask" in ''|*[!0-9]*) return 1 ;; esac
  case "$_addr" in
    *:*)
      [ "$_mask" -le 128 ] || return 1
      # Deliberately conservative IPv6 syntax validation; rejecting a malformed rule
      # is safer than letting one bad CIDR make the entire sing-box config fail.
      printf '%s\n' "$_addr" | awk '
        BEGIN { ok=1 }
        {
          if ($0 !~ /^[0-9a-fA-F:]+$/ || index($0,":")==0 || $0 ~ /:::/) ok=0
          tmp=$0; compressed=gsub(/::/,"x",tmp)
          if (compressed>1) ok=0
          n=split($0,a,":"); used=0
          for (i=1; i<=n; i++) if (a[i]!="") {
            if (length(a[i])>4) ok=0
            used++
          }
          if (compressed==1) { if (used>=8) ok=0 }
          else if (used!=8) ok=0
        }
        END { exit(ok ? 0 : 1) }
      ' || return 1
      ;;
    *.*)
      [ "$_mask" -le 32 ] || return 1
      printf '%s\n' "$_addr" | awk -F. '
        BEGIN { ok=1 }
        {
          if (NF!=4) ok=0
          for (i=1; i<=NF; i++) if ($i !~ /^[0-9]+$/ || length($i)>3 || ($i+0)>255) ok=0
        }
        END { exit(ok ? 0 : 1) }
      ' || return 1
      ;;
    *) return 1 ;;
  esac
  return 0
}
# 目标 → outbound 或 action 片段
target_json() {
  # $1 = DIRECT/REJECT/PROXY/组名
  _t=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
  case "$_t" in
    ''|direct|直连|pass|accept|allow|bypass|放行|绕过) printf '%s' '"outbound":"direct"' ;;
    reject|拒绝|block|拦截|drop|deny|reject-drop) printf '%s' '"action":"reject","method":"drop"' ;;
    *) printf '%s' '"outbound":"proxy"' ;;
  esac
}

# 追加一条规则到临时文件（每行一条完整 JSON 对象）
emit_rule() { printf '%s\n' "$1" >> "$WORK/rules.ndjson"; n_ok=$((n_ok + 1)); }
skip_rule() {
  n_skip=$((n_skip + 1))
  skip_detail="$skip_detail
  SKIP:$1  $2"
}

# ---------- 逻辑规则嵌套解析（AND,((A),(B)) / OR / NOT） ----------
# 用 awk 做括号配对（mksh 的 ${var#*(} 会触发 extglob 解析错误；cut -c 对 UTF-8
# 也不可靠）。awk 按字节处理，且括号只可能是 ASCII '(' ')'。
# 输入: "((DOMAIN,a.com),(NETWORK,tcp))" 或 "(DOMAIN,a.com)"
# 输出: 每个括号组内的内容，一行一个，供调用方逐个 parse_single
split_parens() {
  printf '%s' "$1" | awk '{
    s = $0
    n = length(s)
    depth = 0; start = 0
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (c == "(") { depth++; if (depth == 1) start = i + 1 }
      else if (c == ")") { depth--; if (depth == 0 && start > 0) { print substr(s, start, i - start); start = 0 } }
    }
  }'
}

parse_cond_list() {
  _pcl_in="$1"
  # 输入形如 "((DOMAIN-SUFFIX,a.com),(NETWORK,tcp))" —— 最外层一对是「条件列表
  # 的包裹括号」，里面的每个 (...) 才是一个子条件。所以先剥最外层，再对内部
  # 做括号配对（别再额外包一层，否则整段会被当成一个组）。
  _pcl_body=$(printf '%s' "$_pcl_in" | awk '{
      s = $0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      if (substr(s,1,1) == "(" && substr(s,length(s),1) == ")") s = substr(s, 2, length(s) - 2)
      print s
    }')
  _pcl_out=""; _pcl_first=1
  _groups=$(split_parens "$_pcl_body")
  if [ -z "$_groups" ]; then
    # 没有括号组 → 整段就是一个条件（如 AND,(DOMAIN,a.com),(NETWORK,tcp) 之外的形态）
    _groups="$_pcl_body"
  fi
  while IFS= read -r _g; do
    [ -n "$_g" ] || continue
    _j=$(parse_single "$_g") || return 1
    [ -n "$_j" ] || return 1
    if [ "$_pcl_first" = 1 ]; then _pcl_out="$_j"; _pcl_first=0; else _pcl_out="$_pcl_out,$_j"; fi
  done <<__PCL__
$_groups
__PCL__
  [ -n "$_pcl_out" ] || return 1
  printf '%s' "$_pcl_out"
  return 0
}

# 解析单条条件（不含外层括号、不含策略段），如 DOMAIN,a.com / NETWORK,tcp
parse_single() {
  _ps="$1"
  # 允许传 "TYPE,arg" 形式；若只传 arg 则由调用方先拼 TYPE
  case "$_ps" in
    *,*) _type=${_ps%%,*}; _arg=${_ps#*,} ;;
    *)   return 1 ;;
  esac
  _type_up=$(printf '%s' "$_type" | tr 'a-z' 'A-Z')
  case "$_type_up" in
    DOMAIN|HOST) printf '%s' "{\"domain\":[\"$(js "$_arg")\"]}" ;;
    DOMAIN-SUFFIX|HOST-SUFFIX) printf '%s' "{\"domain_suffix\":[\"$(js "$_arg")\"]}" ;;
    DOMAIN-KEYWORD|HOST-KEYWORD) printf '%s' "{\"domain_keyword\":[\"$(js "$_arg")\"]}" ;;
    DOMAIN-REGEX) printf '%s' "{\"domain_regex\":[\"$(js "$_arg")\"]}" ;;
    IP-CIDR|IP-CIDR6|MIXED-IP-CIDR)
      cidr_ok "$_arg" || return 1
      printf '%s' "{\"ip_cidr\":[\"$(js "${_arg%%,*}")\"]}"
      ;;
    # PROCESS-NAME 的语义（真机 + find_process 实证，勿"自动分流"到 package_name）：
    #   process_name 匹配**可执行文件基名**：客户端是 /system/bin/curl 时，
    #   process_name:["curl"] 命中，process_name:["/system/bin/curl"] **不**命中。
    #   package_name 匹配**Android 包名**：客户端 uid 2000 时 package_name:["com.android.shell"]
    #   命中，而把包名写进 process_name **不**命中。两者不可互换，因此这里保持原样输出：
    #   用户写 PROCESS-NAME,curl → process_name；写 PACKAGE-NAME,com.foo.bar → package_name。
    #   （原本打算做"含点就转 package_name"的自动分流，实测证明会把 curl 这类可执行名误判，
    #    故放弃。）
    PROCESS-NAME) printf '%s' "{\"process_name\":[\"$(js "$_arg")\"]}" ;;
    PACKAGE-NAME) printf '%s' "{\"package_name\":[\"$(js "$_arg")\"]}" ;;
    DST-PORT)
      case "$_arg" in
        *-*) _a=${_arg%%-*}; _b=${_arg#*-}; prange_ok "$_a:$_b" || return 1
             printf '%s' "{\"port_range\":[\"$_a:$_b\"]}" ;;
        *)   port_ok "$_arg" || return 1
             printf '%s' "{\"port\":[$_arg]}" ;;
      esac
      ;;
    SRC-PORT)
      case "$_arg" in
        *-*) _a=${_arg%%-*}; _b=${_arg#*-}; prange_ok "$_a:$_b" || return 1
             printf '%s' "{\"source_port_range\":[\"$_a:$_b\"]}" ;;
        *)   port_ok "$_arg" || return 1
             printf '%s' "{\"source_port\":[$_arg]}" ;;
      esac
      ;;
    PORT-RANGE)
      prange_ok "$_arg" || return 1
      printf '%s' "{\"port_range\":[\"$(js "$_arg")\"]}"
      ;;
    PROTOCOL) printf '%s' "{\"protocol\":[\"$(js "$_arg")\"]}" ;;
    NETWORK)
      _nw=$(printf '%s' "$_arg" | tr 'A-Z' 'a-z')
      case "$_nw" in tcp|udp) printf '%s' "{\"network\":[\"$_nw\"]}" ;; *) return 1 ;; esac
      ;;
    NOT)
      # 注意: 绝不能用 ${_arg#*(} / ${_arg%)} —— mksh(toybox/MIUI) 把 `*(` 当成
      # extglob 模式起点，会报 "no closing quote" 并把后续整段（含 esac）吃掉，
      # 表现为 "syntax error: unmatched 'case'"。真机实测踩过。用 sed 剥括号。
      _inner=$(printf '%s' "$_arg" | sed 's/^[[:space:]]*(//; s/)[[:space:]]*$//')
      _j=$(parse_single "$_inner") || return 1
      printf '%s' "{\"invert\":true,$(printf '%s' "$_j" | sed 's/^{//')"
      ;;
    *) return 1 ;;
  esac
  return 0
}

# ---------- 读取规则行 ----------
# [list:rule] 与 [list:fx] 都是 `内容|备注|1`；只取启用行，跳过注释与空行
extract_rules() {
  _er_src="$1"
  [ -f "$_er_src" ] || return 0
  # 必须先剥 UTF-8 BOM（EF BB BF）：Windows/多数编辑器导出的 conf 会带 BOM，
  # 首行变成 "\357\273\277[list:rule]"，`/^\[list:rule\]/` 就匹配不上 →
  # 整段规则被当成"非列表区"全部丢弃（这与订阅导入为空的 BOM bug 同源）。
  # sed 的 s/^\xef\xbb\xbf// 在 toybox/busybox 上行为不一致，改用 head 判首字节。
  _er_clean="$WORK/lines.clean"
  if [ "$(head -c 3 "$_er_src" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "efbbbf" ]; then
    tail -c +4 "$_er_src" > "$_er_clean" 2>/dev/null || cp "$_er_src" "$_er_clean"
  else
    cp "$_er_src" "$_er_clean" 2>/dev/null
  fi
  awk -v fx_enabled="$FX_MASTER" '
    /^\[list:rule\]/ { section = "rule"; next }
    /^\[list:fx\]/   { section = "fx"; next }
    /^\[/              { section = ""; next }
    (section == "rule" || (section == "fx" && fx_enabled == "1")) && $0 !~ /^[[:space:]]*#/ && $0 != "" {
      n = split($0, a, "|")
      if (n >= 3 && a[3] == "1" && a[1] != "") print a[1]
      else if (n == 1 && $0 !~ /^[[:space:]]*$/) print a[1]
    }
  ' "$_er_clean"
}

: > "$WORK/rules.ndjson"

extract_rules "$SRC" > "$WORK/lines.txt"

# v1.10.8: 展开「内置 FX 文件」与「多行条目」。
# 背景：
#   - 内置 FX 规则随模块打包在 $MODDIR/fxrules/<id>.txt，[list:fx] 里只存 fxfile://<id>；
#   - 旧的多行条目用字面 \n 连接（modconvert 生成），单行解析器会读成一条怪规则。
# 两者都在这里展开成单行规则，再交给下面的 TYPE/POLICY 解析器；不支持的
# 类型（URL-REGEX 等）仍会走 skip_rule 明确记录。
_exp="$WORK/lines.expanded"
_wl_exp="$WORK/subscription-whitelist.rules"
: > "$_exp"
: > "$_wl_exp"
# Whitelist is emitted first so its DIRECT route wins over later subscription rejects.
# Only validated domain tokens are accepted; the hosts generator applies the same list
# to local hosts entries, while this route layer applies it to subscription traffic.
awk '
  function valid_domain(d, n, labels, i) {
    if (length(d) < 1 || length(d) > 253 || d !~ /^[a-z0-9.-]+$/ || d ~ /[.][.]|^[.]|[.]$/) return 0
    n=split(d, labels, ".")
    for (i=1; i<=n; i++) {
      if (length(labels[i]) < 1 || length(labels[i]) > 63) return 0
      if (labels[i] !~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/) return 0
    }
    return 1
  }
  /^\[list:domain\]/ { inlist=1; next }
  /^\[/ { inlist=0 }
  inlist && $0 !~ /^[[:space:]]*#/ && $0 != "" {
    n=split($0,a,"|"); d=a[1]; enabled=(n>=3 ? a[3] : "1")
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", d)
    sub(/^\*\./,"",d); d=tolower(d)
    # Ignore malformed and single-label entries in VPN routing; keep them available to hosts.
    if (enabled=="1" && index(d,".") > 0 && valid_domain(d) && !seen[d]++) print "DOMAIN-SUFFIX," d ",DIRECT"
  }
' "$SRC" >> "$_wl_exp" 2>/dev/null || :
while IFS= read -r _l; do
  [ -n "$_l" ] || continue
  case "$_l" in
    http://*|https://*)
      case "$_l" in
        *runningcheese/RunningCheese-Firefox/master/Restore/Adblock_Watermark.txt|*runningcheese/RunningCheese-Firefox/master/Restore/Adblock_Popup.txt|*NoAppDownload.txt|*cxfl-ublock.txt|*easylist_adult/*|*yokoffing/filterlists/main/adult_annoyance_list.txt|*DandelionSprout/adfilt/master/stayingonbrowser/*)
          # These are element/request filters whose semantics may depend on page,
          # resource type or popup context. The MITM filter engine consumes their
          # verified cache; do not widen them to route-wide domain rejection.
          continue ;;
      esac
      # Subscription payloads are downloaded by apply.sh into a checksum-paired cache.
      # Compile only a cache whose SHA-256 sidecar matches; never trust partial downloads.
      _url_key=$(printf '%s' "$_l" | cksum 2>/dev/null | awk '{print $1}')
      _url_cache="$PG/cache/rules/$_url_key"
      _url_sum="$_url_cache.sha256"
      _url_actual=""
      if [ -n "$_url_key" ] && [ -s "$_url_cache" ] && [ -s "$_url_sum" ]; then
        if command -v sha256sum >/dev/null 2>&1; then _url_actual=$(sha256sum "$_url_cache" 2>/dev/null | awk 'NR==1{print tolower($1)}');
        elif command -v toybox >/dev/null 2>&1; then _url_actual=$(toybox sha256sum "$_url_cache" 2>/dev/null | awk 'NR==1{print tolower($1)}'); fi
      fi
      _url_expected=$(cat "$_url_sum" 2>/dev/null | tr -d '[:space:]')
      if [ "${#_url_expected}" -eq 64 ] && [ "$_url_actual" = "$_url_expected" ]; then
        awk -v wl="$_wl_exp" '
          function trim(s){gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s}
          function emit_typed(line, n, a, i, last, normalized) {
            n=split(line,a,",")
            for(i=1;i<=n;i++) a[i]=trim(a[i])
            a[1]=toupper(a[1])
            if (n<2 || a[2]=="") return
            last=toupper(a[n])
            # An option without a policy is not a policy. Insert the FX/list deny default
            # before the modifier rather than misreading no-resolve as an outbound tag.
            if (n==3 && (last=="NO-RESOLVE" || last=="SRC" || last=="EXTENDED" || last=="NO-DROP")) {
              a[4]=a[3]; a[3]="REJECT"; n=4
            } else if (n<3) {
              a[3]="REJECT"; n=3
            } else if (a[3]=="") a[3]="REJECT"
            normalized=a[1]
            for(i=2;i<=n;i++) normalized=normalized "," a[i]
            print normalized
          }
          /^[[:space:]]*#/ || /^[[:space:]]*$/ {next}
          {
            line=trim($0); sub(/\r$/, "", line); sub(/^-+[[:space:]]*/, "", line)
            # Only plain unmodified ABP domain filters can become DNS/routes.
            # $third-party/$popup/domain= and URL-path rules must stay in the
            # request-aware MITM parser; globalizing them breaks first-party sites.
            if (line ~ /^@@\|\|[A-Za-z0-9.-]+\^$/) {d=line; sub(/^@@\|\|/,"",d); sub(/\^$/, "", d); print "DOMAIN-SUFFIX," tolower(d) ",DIRECT" >> wl; next}
            if (line ~ /^@@\|\|/) next
            if (line ~ /^\|\|[A-Za-z0-9.-]+\^$/) {d=line; sub(/^\|\|/,"",d); sub(/\^$/, "", d); print "DOMAIN-SUFFIX," tolower(d) ",REJECT"; next}
            if (line ~ /^\|\|/) next
            if (line ~ /^(0\.0\.0\.0|127\.0\.0\.1)[[:space:]]+/) {d=line; sub(/^[^[:space:]]+[[:space:]]+/,"",d); split(d,a,/[[:space:]]+/); if(a[1] ~ /^[A-Za-z0-9.-]+$/ && a[1] ~ /\./) print "DOMAIN-SUFFIX," tolower(a[1]) ",REJECT"; next}
            if (line ~ /^(DOMAIN|DOMAIN-SUFFIX|DOMAIN-KEYWORD|DOMAIN-REGEX|HOST|HOST-SUFFIX|IP-CIDR|IP-CIDR6|PROCESS-NAME|PACKAGE-NAME|DST-PORT|SRC-PORT|NETWORK|PROTOCOL),/) {emit_typed(line); next}
            if (line ~ /^[A-Za-z0-9.-]+\.[A-Za-z]+$/) print "DOMAIN-SUFFIX," tolower(line) ",REJECT"
          }
        ' "$_url_cache" >> "$_exp" 2>/dev/null
      else
        skip_rule "SUBSCRIPTION" "cache missing or SHA-256 mismatch: $_l"
      fi
      ;;
    builtin://*)
      # Built-in host/domain lists must also affect sing-box route mode; previously
      # they only reached the hosts file, so they appeared enabled but did nothing
      # when Hosts blocking was off. Cosmetic files remain MITM-only and are skipped
      # here deliberately. This parser accepts only explicit host mappings or typed
      # domain rules; it never interprets UI selectors as network policy.
      _bid=${_l#builtin://}
      case "$_bid" in *.txt) _bid_file="$_bid" ;; *) _bid_file="$_bid.txt" ;; esac
      _bf="$PG/rulefiles-user/$_bid_file"
      [ -f "$_bf" ] || _bf="$MODDIR/rulefiles/$_bid_file"
      case "$_bid_file" in
        NoAppDownload.txt|Adblock_Watermark.txt|AdultSite_AdPopup.txt|Adblock_Warning_Removal.txt|AdultSite_Elements_EasyList.txt|RunningCheese_Watermark.txt|RunningCheese_Popup.txt|AdultSite_AdServers.txt|AdultSite_Allowlist.txt|AdultSite_AdServersPopup.txt|AdultSite_SitePopup.txt|AdultSite_ThirdPartyPopup.txt|AdultSite_RequestRules.txt|AdultSite_ThirdParty.txt)
          # Built-in cosmetic selectors are MITM-only; never compile them as host routes.
          : ;;
        *)
          if [ -r "$_bf" ]; then
            awk -F, '
              function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
              /^[[:space:]]*[#!]/ || /^[[:space:]]*$/ {next}
              {
                line=$0; sub(/\r$/, "", line); line=trim(line)
                if (line ~ /^(0\.0\.0\.0|127\.0\.0\.1|::1)[[:space:]]+/) {
                  sub(/^[^[:space:]]+[[:space:]]+/, "", line); split(line,a,/[[:space:]]+/)
                  d=tolower(a[1]); sub(/[.]$/, "", d)
                  if (d ~ /^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$/ && d ~ /[.]/) print "DOMAIN-SUFFIX," d ",REJECT"
                  next
                }
                n=split(line,a,",")
                for(i=1;i<=n;i++) a[i]=trim(a[i])
                type=toupper(a[1])
                if ((type=="DOMAIN" || type=="DOMAIN-SUFFIX") && a[2] ~ /^[A-Za-z0-9.-]+$/) {
                  policy=(n>=3 && a[3]!="" ? toupper(a[3]) : "REJECT")
                  if (policy=="REJECT" || policy=="BLOCK" || policy=="DROP" || policy=="DENY" || policy=="REJECT-DROP") {
                    print type "," tolower(a[2]) ",REJECT"
                  }
                }
              }
            ' "$_bf" >> "$_exp" 2>/dev/null || skip_rule "BUILTIN" "failed to parse bundled host list: $_bid_file"
          else
            skip_rule "BUILTIN" "missing bundled source: rulefiles/$_bid_file"
          fi
          ;;
      esac
      ;;
    fxfile://*)
      _fid=${_l#fxfile://}
      # v1.10.9: WebUI 逐行编辑产生的用户副本优先（fileedit.sh 写 $PG/fxrules-user/）
      _ff="$PG/fxrules-user/$_fid.txt"
      [ -f "$_ff" ] || _ff="$MODDIR/fxrules/$_fid.txt"
      if [ -r "$_ff" ]; then
        # Large generic FX lists keep domain matching in the hosts layer to avoid
        # generating tens of thousands of route objects. The bundled anti-fraud source
        # is intentionally small, so also compile its domains into sing-box: this keeps
        # domain rejection active in rule/proxy mode even if an app uses a remote resolver.
        # fxfile rows use the same deny-list default as the hosts/firewall consumers:
        # a typed row without an explicit action is REJECT, never an empty/unknown policy.
        # This keeps an edited local FX source consistent across hosts and sing-box.
        if [ "$_fid" = "anti_fraud_96110" ] || [ "$_fid" = "96110_candidate" ]; then
          awk -F, '
            function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
            function emit_typed(line, n,a,i,last,normalized) {
              n=split(line,a,",")
              for(i=1;i<=n;i++) a[i]=trim(a[i])
              a[1]=toupper(a[1])
              if (n<2 || a[2]=="") return
              last=toupper(a[n])
              if (n==3 && (last=="NO-RESOLVE" || last=="SRC" || last=="EXTENDED" || last=="NO-DROP")) {
                a[4]=a[3]; a[3]="REJECT"; n=4
              } else if (n<3) { a[3]="REJECT"; n=3 }
              else if (a[3]=="") a[3]="REJECT"
              normalized=a[1]
              for(i=2;i<=n;i++) normalized=normalized "," a[i]
              print normalized
            }
            /^[[:space:]]*#/ || /^[[:space:]]*$/ {next}
            {
              line=trim($0); sub(/\r$/, "", line); sub(/^-+[[:space:]]*/, "", line)
              type=line; sub(/,.*/, "", type); type=toupper(type)
              if (type=="DOMAIN" || type=="DOMAIN-SUFFIX") {
                if (domains < 256) { emit_typed(line); domains++ } else overflow=1
                next
              }
              if (type ~ /^(IP-CIDR|IP-CIDR6|PROCESS-NAME|PACKAGE-NAME|DOMAIN-KEYWORD)$/) emit_typed(line)
            }
            END { if (overflow) print "vpnrule: FX domain rule cap reached (256); remaining domains are hosts-only" > "/dev/stderr" }
          ' "$_ff" >> "$_exp"
        else
          awk -F, '
            function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
            function emit_typed(line, n,a,i,last,normalized) {
              n=split(line,a,",")
              for(i=1;i<=n;i++) a[i]=trim(a[i])
              a[1]=toupper(a[1])
              if (n<2 || a[2]=="") return
              last=toupper(a[n])
              if (n==3 && (last=="NO-RESOLVE" || last=="SRC" || last=="EXTENDED" || last=="NO-DROP")) {
                a[4]=a[3]; a[3]="REJECT"; n=4
              } else if (n<3) { a[3]="REJECT"; n=3 }
              else if (a[3]=="") a[3]="REJECT"
              normalized=a[1]
              for(i=2;i<=n;i++) normalized=normalized "," a[i]
              print normalized
            }
            /^[[:space:]]*#/ || /^[[:space:]]*$/ {next}
            {
              line=trim($0); sub(/\r$/, "", line); sub(/^-+[[:space:]]*/, "", line)
              type=line; sub(/,.*/, "", type); type=toupper(type)
              if (type ~ /^(IP-CIDR|IP-CIDR6|PROCESS-NAME|PACKAGE-NAME|DOMAIN-KEYWORD)$/) emit_typed(line)
            }
          ' "$_ff" >> "$_exp"
        fi
      else
        # Missing bundled FX source is a hard skip, not a literal rule. Emitting
        # fxfile://... into the parser used to create a misleading invalid rule
        # entry and obscured the fact that the archive lacked the referenced file.
        skip_rule "FXFILE" "missing bundled source: fxrules/$_fid.txt"
      fi
      ;;
    *\\n*)
      printf '%s\n' "$_l" | sed 's/\\n/\n/g' >> "$_exp"
      ;;
    *)
      printf '%s\n' "$_l" >> "$_exp"
      ;;
  esac
done < "$WORK/lines.txt"
# Merge whitelist DIRECT rules first, then stable-deduplicate exact route rows. Do not sort:
# route order is significant, and rules with different policies remain distinct.
if cat "$_wl_exp" "$_exp" > "$WORK/lines.final.raw" 2>/dev/null; then
  if awk '!seen[$0]++' "$WORK/lines.final.raw" > "$WORK/lines.final" 2>/dev/null && mv -f "$WORK/lines.final" "$WORK/lines.txt" 2>/dev/null; then
    rm -f "$WORK/lines.final.raw" 2>/dev/null || true
  else
    mv -f "$WORK/lines.final.raw" "$WORK/lines.txt" 2>/dev/null || true
  fi
fi

while IFS= read -r line; do
  [ -n "$line" ] || continue
  n_total=$((n_total + 1))
  # 规范化：去空白
  line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  TYPE=$(printf '%s' "${line%%,*}" | tr 'a-z' 'A-Z')
  # ---- 拆成「纯条件」与「策略」----
  # 统一交给 awk 切字段（mksh 下 sed 的贪心/转义行为不稳定，这里不用 sed）。
  # 用 `|` 作内部分隔符：原始名单里的 `|` 已在 extract_rules 阶段被当字段分隔切掉，
  # 所以条件/策略里不可能再出现 `|`，可以安全用作 IFS。
  #   $1=TYPE  $2..$(NF-1)=条件参数  $NF=策略
  #   若 $NF 是 no-resolve/src 等修饰，则策略取 $(NF-1)、修饰进 MODS
  _split=$(printf '%s' "$line" | awk -F',' '{
      n = NF
      last = tolower($n)
      if (last == "no-resolve" || last == "src" || last == "extended" || last == "no-drop") {
        mod = $n; pol = $(n-1); condn = n - 2
      } else {
        mod = ""; pol = $n; condn = n - 1
      }
      cond = $2
      for (i = 3; i <= condn; i++) cond = cond "," $i
      printf "%s|%s|%s\n", cond, pol, mod
    }')
  ARG=""; POLICY=""; MODS=""
  _oldIFS=$IFS; IFS='|'
  set -- $_split
  IFS=$_oldIFS
  ARG="$1"; POLICY="$2"; MODS="$3"
  POLUP=$(printf '%s' "$POLICY" | tr 'a-z' 'A-Z')

  case "$TYPE" in
    # ---------------- 不支持：明确 SKIP，绝不进 JSON ----------------
    URL-REGEX|USER-AGENT|IP-ASN|MITM|SCRIPT|GEOIP|GEOSITE|FINAL|MATCH)
      case "$TYPE" in
        FINAL|MATCH)
          # MATCH/FINAL 不是规则，而是 route.final；由调用方读取
          printf '%s\n' "$POLICY" > "$WORK/final.txt"
          n_ok=$((n_ok + 1))
          ;;
        *)
          skip_rule "$TYPE" "需要 L7 解密/已废弃数据库，内核路由无法表达"
          ;;
      esac
      ;;
    # ---------------- 逻辑组合 ----------------
    AND|OR|NOT)
      _mode=$(printf '%s' "$TYPE" | tr 'A-Z' 'a-z')
      # NOT 是单条件取反：用 logical+invert 表达
      if [ "$_mode" = "not" ]; then
        # NOT 的正确形态：{"type":"logical","mode":"and","rules":[<条件组>],"invert":true}
        # invert 必须在 logical 对象上，不能放进子条件 —— 子条件里的 invert 语义是
        # 「该条件取反后再参与 and」，与 Clash 的 NOT（整组都不匹配）不等价。
        # NOT,((DOMAIN,d.com)) 与 NOT,(DOMAIN,d.com) 两种写法都要支持：parse_cond_list
        # 会先剥最外层括号再按括号组切分，正好覆盖这两种输入。
        _conds=$(parse_cond_list "$ARG") || { skip_rule "$TYPE" "条件无法解析: $line"; continue; }
        _tgt=$(target_json "$POLICY")
        emit_rule "{\"type\":\"logical\",\"mode\":\"and\",\"rules\":[$_conds],\"invert\":true,$_tgt}"
        continue
      fi
      _conds=$(parse_cond_list "$ARG") || { skip_rule "$TYPE" "条件无法解析: $line"; continue; }
      _tgt=$(target_json "$POLICY")
      emit_rule "{\"type\":\"logical\",\"mode\":\"$_mode\",\"rules\":[$_conds],$_tgt}"
      ;;
    # ---------------- RULE-SET ----------------
    RULE-SET)
      # 参数: path[,policy]。只支持本地已存在的规则集文件。
      # 关键（v1.10.7）：只在 route.rules 里写 `rule_set:["tag"]` 但**不生成
      # `route.rule_set` 定义块**，run 阶段会 FATAL `rule-set not found`
      # （check 抓不到）。所以这里必须同时产出一份定义，供 vpncore 拼进
      # route.rule_set。定义格式按扩展名推断：
      #   .json → {"type":"local","tag":"...","format":"source","path":"..."}
      #   .srs  → {"type":"local","tag":"...","format":"binary","path":"..."}
      # 文件不存在 / 格式与扩展名不符 → SKIP（不做半对的事）。
      _rs=$(printf '%s' "$ARG" | cut -d, -f1)
      _rs=$(printf '%s' "$_rs" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      case "$_rs" in
        */*)
          if [ ! -f "$_rs" ]; then
            skip_rule RULE-SET "规则集文件不存在: $_rs"
          else
            _tag=$(printf '%s' "$_rs" | sed 's#.*/##;s#\.[^.]*$##')
            _ext=$(printf '%s' "$_rs" | sed 's#.*\.##')
            case "$_ext" in
              json) _fmt=source ;;
              srs)  _fmt=binary ;;
              *)    skip_rule RULE-SET "无法识别的规则集格式（需 .json 或 .srs）: $_rs"; continue ;;
            esac
            # 基本内容校验：.json 必须以 { 或 [ 开头；.srs 是二进制不校验内容
            if [ "$_fmt" = "source" ]; then
              _head1=$(head -c 1 "$_rs" 2>/dev/null)
              case "$_head1" in
                '{'|'[') : ;;
                *) skip_rule RULE-SET "规则集内容不像合法 JSON（format=source）: $_rs"; continue ;;
              esac
            fi
            _tgt=$(target_json "$POLICY")
            emit_rule "{\"rule_set\":[\"$(js "$_tag")\"],$_tgt}"
            # 记录定义（同一 tag 只记一次）
            _rset_def="{\"type\":\"local\",\"tag\":\"$(js "$_tag")\",\"format\":\"$_fmt\",\"path\":\"$(js "$_rs")\"}"
            if ! grep -q "\"tag\":\"$(js "$_tag")\"" "$WORK/rulesets.ndjson" 2>/dev/null; then
              printf '%s\n' "$_rset_def" >> "$WORK/rulesets.ndjson"
            fi
          fi
          ;;
        *)
          skip_rule RULE-SET "仅支持本地规则集文件路径（远程 URL 需先下载到 $PG/rulesets/）: $ARG"
          ;;
      esac
      ;;
    # ---------------- 单条件规则 ----------------
    *)
      _cond=$(parse_single "$TYPE,$ARG") || { skip_rule "$TYPE" "参数/语法不被 sing-box 接受: $line"; continue; }
      [ -n "$_cond" ] || { skip_rule "$TYPE" "条件解析为空: $line"; continue; }
      _tgt=$(target_json "$POLICY")
      # 把目标字段并入条件对象：{"a":[...]} → {"a":[...],"outbound":"direct"}
      _merged=$(printf '%s' "$_cond" | sed "s/}\$/,${_tgt}}/")
      emit_rule "$_merged"
      ;;
  esac
done < "$WORK/lines.txt"

# 清掉可能的空行
grep -v '^[[:space:]]*$' "$WORK/rules.ndjson" > "$WORK/rules.ndjson.2" 2>/dev/null || : > "$WORK/rules.ndjson.2"
mv -f "$WORK/rules.ndjson.2" "$WORK/rules.ndjson" 2>/dev/null

# 重新统计（去掉上面单条件分支的临时加减）
n_ok=$(grep -c '^{' "$WORK/rules.ndjson" 2>/dev/null)
case "$n_ok" in ''|*[!0-9]*) n_ok=0 ;; esac

# ---------- 可选：用真实 sing-box 兜底校验 ----------
verify_with_bin() {
  _vb_bin="$1"
  [ -x "$_vb_bin" ] || return 0
  [ -s "$WORK/rules.ndjson" ] || return 0
  _vb_rules=$(paste -sd, "$WORK/rules.ndjson" 2>/dev/null)
  [ -n "$_vb_rules" ] || return 0
  printf '{"log":{"level":"warn"},"inbounds":[{"type":"redirect","tag":"in","listen":"127.0.0.1","listen_port":17996}],"outbounds":[{"type":"direct","tag":"direct"},{"type":"direct","tag":"proxy"},{"type":"direct","tag":"node-1"}],"dns":{"servers":[{"type":"udp","tag":"local","server":"223.5.5.5"}],"final":"local"},"route":{"default_domain_resolver":{"server":"local"},"rules":[{"action":"sniff","sniffer":["http","tls"]},%s],"final":"proxy"}}' "$_vb_rules" > "$WORK/probe.json"
  if ! "$_vb_bin" check -c "$WORK/probe.json" > "$WORK/probe.err" 2>&1; then
    # 逐条剔除到可用为止（宁可少规则，不能让整份配置起不来）
    : > "$WORK/ok.ndjson"
    while IFS= read -r _r1; do
      [ -n "$_r1" ] || continue
      _acc=$(paste -sd, "$WORK/ok.ndjson" 2>/dev/null)
      if [ -n "$_acc" ]; then _try="$_acc,$_r1"; else _try="$_r1"; fi
      printf '{"log":{"level":"warn"},"inbounds":[{"type":"redirect","tag":"in","listen":"127.0.0.1","listen_port":17996}],"outbounds":[{"type":"direct","tag":"direct"},{"type":"direct","tag":"proxy"},{"type":"direct","tag":"node-1"}],"dns":{"servers":[{"type":"udp","tag":"local","server":"223.5.5.5"}],"final":"local"},"route":{"default_domain_resolver":{"server":"local"},"rules":[{"action":"sniff","sniffer":["http","tls"]},%s],"final":"proxy"}}' "$_try" > "$WORK/probe1.json"
      if "$_vb_bin" check -c "$WORK/probe1.json" >/dev/null 2>&1; then
        printf '%s\n' "$_r1" >> "$WORK/ok.ndjson"
      else
        n_ok=$((n_ok - 1)); n_skip=$((n_skip + 1))
        skip_detail="$skip_detail
  SKIP:VALIDATE  sing-box 拒绝此规则: $(printf '%s' "$_r1" | cut -c1-90)"
      fi
    done < "$WORK/rules.ndjson"
    mv -f "$WORK/ok.ndjson" "$WORK/rules.ndjson"
  fi
}

[ -n "$BIN" ] && [ -x "$BIN" ] && verify_with_bin "$BIN"

# ---------- 输出 ----------
case "$MODE" in
  --emit)
    paste -sd, "$WORK/rules.ndjson" 2>/dev/null
    ;;
  --emit-rulesets)
    # 输出 route.rule_set 定义数组片段（v1.10.7）。vpncore 拼进
    # `"route": {"rule_set":[...]}`，否则 rule_set 引用在 run 阶段 FATAL。
    paste -sd, "$WORK/rulesets.ndjson" 2>/dev/null
    ;;
  --print-final)
    # route.final 归一化：只能是真实出站 tag 的小写形式（direct/proxy）。
    # 真机实测 {"final":"PROXY"} / {"final":"DIRECT"} / {"final":"reject"} 都 check rc=0
    # 但 run FATAL "initialize outbound: default outbound not found: <值>"。
    # 无 MATCH/FINAL → 空串（由 vpncore 取默认 proxy）。
    if [ -f "$WORK/final.txt" ]; then
      _fv=$(cat "$WORK/final.txt" 2>/dev/null | tr -d '\r\n ')
      case "$(printf '%s' "$_fv" | tr 'A-Z' 'a-z')" in
        direct|直连) printf 'direct' ;;
        proxy|代理)  printf 'proxy' ;;
        reject|block|拒绝|拦截) printf 'reject' ;;
        '')     : ;;
        *)      printf 'proxy' ;;   # 未知策略保守回退代理，禁止静默直连
      esac
    fi
    ;;
  --json)
    _it=''
    if [ -s "$WORK/rules.ndjson" ]; then
      _it=$(paste -sd, "$WORK/rules.ndjson" 2>/dev/null)
    fi
    _rs=''
    if [ -s "$WORK/rulesets.ndjson" ]; then
      _rs=$(paste -sd, "$WORK/rulesets.ndjson" 2>/dev/null)
    fi
    # final 归一化（与 --print-final 一致）：route.final 只接受真实出站 tag 的小写值。
    # 真机实测 {"final":"PROXY"} check rc=0 但 run FATAL "default outbound not found: PROXY"。
    _fin=''
    if [ -f "$WORK/final.txt" ]; then
      _fin=$(cat "$WORK/final.txt" 2>/dev/null | tr -d '\r\n ')
      case "$(printf '%s' "$_fin" | tr 'A-Z' 'a-z')" in
        direct|直连) _fin=direct ;;
        proxy|代理)  _fin=proxy ;;
        reject|block|拒绝|拦截) _fin=reject ;;
        '')     _fin='' ;;
        *)      _fin=proxy ;;   # 未知策略保守回退代理，禁止静默直连
      esac
    fi
    # 规则集定义个数：必须只输出**一个**数字。旧写法
    # "$(grep -c ... /dev/null; [ -s ... ] && grep -c ... || echo 0)" 会因为
    # 前缀那条命令也输出一行 0，拼成 "0\n1" → 整份 JSON 非法（实测 python json.loads 失败）。
    _rsn=0
    if [ -s "$WORK/rulesets.ndjson" ]; then
      _rsn=$(grep -c '{' "$WORK/rulesets.ndjson" 2>/dev/null)
    fi
    case "$_rsn" in ''|*[!0-9]*) _rsn=0 ;; esac
    printf '{"ok":1,"total":%s,"compiled":%s,"skipped":%s,"rulesets":%s,"final":"%s","rules":[%s],"rule_set":[%s]}\n' \
      "$n_total" "$n_ok" "$n_skip" "$_rsn" \
      "$(js "$_fin")" "$_it" "$_rs"
    ;;
  --list|*)
    echo "=== vpnrule 编译结果 ==="
    echo "  规则总数: $n_total"
    echo "  已编译:   $n_ok"
    echo "  跳过:     $n_skip"
    [ -s "$WORK/rulesets.ndjson" ] && echo "  规则集定义: $(grep -c '{' "$WORK/rulesets.ndjson" 2>/dev/null) 个"
    [ -f "$WORK/final.txt" ] && echo "  MATCH/FINAL → route.final=$(cat "$WORK/final.txt" 2>/dev/null)"
    if [ -n "$skip_detail" ]; then
      echo "  --- 跳过明细 ---$skip_detail"
    fi
    if [ -s "$WORK/rules.ndjson" ]; then
      echo "  --- 已编译规则（最多 10 条）---"
      head -10 "$WORK/rules.ndjson" | sed 's/^/    /'
    fi
    if [ -s "$WORK/rulesets.ndjson" ]; then
      echo "  --- 规则集定义 ---"
      sed 's/^/    /' "$WORK/rulesets.ndjson"
    fi
    ;;
esac

rm -rf "$WORK" 2>/dev/null
exit 0
