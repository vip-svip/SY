#!/system/bin/sh
# ============================================================================
# PrivacyGuard modconvert.sh — 第三方客户端模块文件 → PrivacyGuard 规则
#
# 支持格式（自动识别，按内容嗅探，扩展名仅作提示）:
#   Shadowrocket / Surge / Stash    .sgmodule
#   Loon                            .plugin
#   Stash / Shadowrocket            .stoverride
# 识别的段: [Rule] [Host] [URL Rewrite] [Map Local] [Script] [MITM]
#           [Header Rewrite] [Body Rewrite] [General]
#
# 输出模式:
#   --list         人类可读摘要（各段条目数、可转/不可转、SKIP 原因）
#   --emit         可直接追加到 settings.conf 的行，逐条带 "# source:" 注释
#   --emit --plain 只输出条目行（便于管道二次处理）
#   --json         机器可读摘要（WebUI 用）
#
# ⚠ 能力边界（必须诚实告知用户）:
#   * 具备显式 type/pattern/HTTPS script-path 的 [Script] 声明会进入 [list:script]，
#     由同步器下载/校验、MITM 引擎按 URL 触发；未声明触发条件的脚本不会伪装成已启用。
#   * [URL Rewrite] 原始规则以 base64 存入独立 [list:urlrewrite] 段，由运行时校验后发布；
#     不会降级为域名拦截。Map Local/Header Rewrite/Body Rewrite 仍需专用 L7 实现。
#   * [MITM] hostname 会进入独立 [list:mitmhost] 白名单；未列出的 TLS 主机透传。仍须用户主动启用并信任 MITM CA。
#
# 用法:
#   modconvert.sh --list  file.sgmodule [file2.plugin ...]
#   modconvert.sh --emit  file.sgmodule > modconvert.out
#   modconvert.sh --json  file.plugin
#   modconvert.sh --list  -            # 从 stdin 读（WebUI 粘贴文本时用）
#
# POSIX sh / toybox 兼容：无 bash 数组、无 [[ ]]、无 $RANDOM；awk 只用基础特性。
# ============================================================================

PROG=modconvert.sh

BLOCK_SECTION="block"    # 域名/IP 拦截  → settings.conf 的 [list:block]
FX_SECTION="fx"          # FX 专用反诈/96110 规则库；第三方导入不得写入此段
RULE_SECTION="rule"      # 通用第三方路由规则与远程文本规则集 → [list:rule]
DOMAIN_SECTION="domain" # 白名单/放行    → [list:domain]
SCRIPT_SECTION="script" # HTTPS JS 脚本订阅 → [list:script]
URLREWRITE_SECTION="urlrewrite" # URL 级重写，base64 保存原始规则
MITM_SECTION="mitmhost" # TLS 中间人只对显式声明的主机执行解密

TMPD=${TMPDIR:-/data/local/tmp}
MAX_BYTES=2097152

MODE=""
PLAIN=0
FILES=""

usage() {
  cat <<'EOF'
用法: modconvert.sh <--list|--emit|--json> [--plain] <文件...|->
  --list   人类可读摘要（段统计、可转条数、SKIP 原因）
  --emit   输出可追加到 settings.conf 的 [list:*] 片段（带 # source: 注释）
  --json   机器可读摘要（WebUI 用）
  --plain  配合 --emit：只输出条目，不带段头/注释
文件参数 - 表示从 stdin 读取。
支持 .sgmodule / .plugin / .stoverride，以及 Clash/Mihomo YAML 的 `rules:` 静态规则子集（Shadowrocket/Loon/Surge/Stash/Clash/Mihomo）。
EOF
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --list) MODE=list ;;
    --emit) MODE=emit ;;
    --json) MODE=json ;;
    --plain) PLAIN=1 ;;
    -h|--help|help) usage ;;
    --) shift; break ;;
    -) FILES="$FILES -" ;;          # 注意: 必须在 -*) 之前，否则 "-" 会被当未知选项
    -*) echo "$PROG: 未知选项 $1" >&2; usage ;;
    *) FILES="$FILES $1" ;;
  esac
  shift
done
[ -n "$FILES" ] || usage
[ -n "$MODE" ] || usage

trim() { sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

secnorm() {
  # 注意: 必须先把整行规范化再折叠空白。原实现用 awk '$1=$1; print' 会把
  # 多词段名压成第一个词（"[URL Rewrite]" → "url"），导致段匹配全错。
  printf '%s' "$1" | sed -e 's/^[[:space:]]*\[//' -e 's/\][[:space:]]*$//' \
    | tr 'A-Z' 'a-z' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
          -e 's/[[:space:]][[:space:]]*/ /g'
}

valid_domain() {
  case "$1" in .*|*..*|*.) return 1 ;; esac
  printf '%s' "$1" | grep -qE '^[A-Za-z0-9*][A-Za-z0-9._*-]*$'
}
valid_ip() {
  # Validate exactly four IPv4 octets and an optional /0..32 prefix. A regex-only
  # check accepted 999.999.999.999/99 and could feed malformed rules to sing-box.
  printf '%s\n' "$1" | awk -F'[./]' '
    BEGIN { ok=1 }
    {
      if (NF!=4 && NF!=5) ok=0
      for (i=1; i<=4 && i<=NF; i++) {
        if ($i !~ /^[0-9]+$/ || length($i)>3 || ($i+0)>255) ok=0
      }
      if (NF==5 && ($5 !~ /^[0-9]+$/ || length($5)>2 || ($5+0)>32)) ok=0
    }
    END { exit(ok ? 0 : 1) }
  '
}
# Conservative IPv6 CIDR validator: hexadecimal groups only, one optional ::,
# exactly eight groups without compression, fewer than eight with compression.
valid_ip6() {
  printf '%s\n' "$1" | awk -F/ '
    BEGIN { ok=1 }
    {
      if (NF!=2) ok=0
      addr=$1; mask=$2
      if (mask !~ /^[0-9]+$/ || length(mask)>3 || (mask+0)>128) ok=0
      if (addr !~ /^[0-9a-fA-F:]+$/ || index(addr,":")==0 || addr ~ /:::/) ok=0
      tmp=addr; compressed=gsub(/::/,"x",tmp)
      if (compressed>1) ok=0
      count=split(addr,groups,":"); used=0
      for (i=1; i<=count; i++) if (groups[i]!="") {
        if (length(groups[i])>4) ok=0
        used++
      }
      if (compressed==1) { if (used>=8) ok=0 }
      else if (used!=8) ok=0
    }
    END { exit(ok ? 0 : 1) }
  '
}

S_DIR=$TMPD/pgmc.$$
mkdir -p "$S_DIR" 2>/dev/null || { echo "$PROG: 无法创建临时目录 $S_DIR" >&2; exit 1; }
cleanup() { rm -rf "$S_DIR"; }
trap 'cleanup' EXIT INT TERM HUP

# 记录格式（全部 TSV，避免解析歧义）:
#   entries.tsv : section <TAB> content <TAB> note <TAB> source
#   skips.tsv   : class   <TAB> source  <TAB> detail
#   stats.tsv   : section
#   files.tsv   : file <TAB> converted <TAB> skipped
: > "$S_DIR/entries.tsv"
: > "$S_DIR/skips.tsv"
: > "$S_DIR/stats.tsv"
: > "$S_DIR/files.tsv"
: > "$S_DIR/seen.txt"

add_entry() { # 去重：脚本订阅同一 URL 可对应多个不同 pattern，必须保留不同元数据
  if [ "$1" = "$SCRIPT_SECTION" ]; then
    _ae_key="$1|$2|$3"
  else
    _ae_key="$1|$2"
  fi
  if grep -qxF "$_ae_key" "$S_DIR/seen.txt" 2>/dev/null; then
    return 1
  fi
  printf '%s\n' "$_ae_key" >> "$S_DIR/seen.txt"
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$S_DIR/entries.tsv"
  return 0
}
add_skip()  { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$S_DIR/skips.tsv"; }

# 从 URL 正则里抠出域名：\\. -> . ，然后取第一个形如域名的片段
dom_from_regex() {
  printf '%s' "$1" | sed -e 's/\\\././g' -e 's/\\\//\//g' \
    | grep -oE '[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}' | head -1
}

# ============================ 单文件解析 ============================
conv_file() {
  src=$1
  fc=0
  sk=0
  cur=""
  rawcur=""
  yaml_rules=0
  lnno=0

  real="$src"
  if [ "$src" = "-" ]; then
    real="$S_DIR/stdin.txt"
    cat > "$real"
  fi
  [ -f "$real" ] || { echo "$PROG: 找不到文件 $src" >&2; return 1; }
  sz=$(wc -c < "$real" 2>/dev/null | tr -d ' ')
  case "$sz" in ''|*[!0-9]*) sz=0 ;; esac
  if [ "$sz" -gt "$MAX_BYTES" ]; then
    echo "$PROG: 跳过 $src（$sz 字节 > 上限 $MAX_BYTES）" >&2
    return 1
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    lnno=$((lnno + 1))
    t=$(printf '%s' "$line" | trim)
    case "$t" in ''|';'*|'#'*|'!'*|'//'*) continue ;; esac

    # Clash/Mihomo YAML rule-list subset. Parse only the explicit `rules:` list;
    # do not mistake proxy groups, DNS settings, or rule-provider metadata for rules.
    if [ "$yaml_rules" = "1" ]; then
      case "$line" in
        [![:space:]]*)
          case "$t" in
            rules:*) : ;;
            *) yaml_rules=0; cur=""; rawcur="" ;;
          esac ;;
      esac
    fi
    case "$t" in
      rules:)
        cur=rule; rawcur="Clash/Mihomo rules:"; yaml_rules=1
        printf '%s\n' 'clash/mihomo rules' >> "$S_DIR/stats.tsv"
        continue ;;
      rules:[[:space:]]*)
        cur=rule; rawcur="Clash/Mihomo rules:"; yaml_rules=1
        printf '%s\n' 'clash/mihomo rules' >> "$S_DIR/stats.tsv"
        continue ;;
    esac

    # 段头
    case "$t" in
      \[*\])
        cur=$(secnorm "$t")
        rawcur="$t"
        printf '%s\n' "$cur" >> "$S_DIR/stats.tsv"
        continue
        ;;
    esac

    loc="$src:$lnno"

    # Normalize common YAML list items and quotes before matching rule syntax.
    # This is intentionally conservative: it does not attempt to parse full YAML.
    case "$t" in
      -* ) t=$(printf '%s' "$t" | sed 's/^[[:space:]]*-[[:space:]]*//') ;;
    esac
    case "$t" in
      \"*\") t=${t#\"}; t=${t%\"} ;;
      '*') t=${t#\'}; t=${t%\'} ;;
    esac

    # AdGuard / Adblock Plus / uBlock Origin static network-filter subset.
    # Cosmetic filters and request-modifying options are never silently treated
    # as domain blocks; only safe domain-wide filters are converted.
    case "$t" in
      '@@||'*|'||'*)
        _flt="$t"; _allow=0
        case "$_flt" in '@@||'*) _allow=1; _flt=${_flt#@@} ;; esac
        case "$_flt" in '||'*) _flt=${_flt#||} ;; esac
        _dom=${_flt%%^*}
        _opts=""
        case "$_flt" in *'^$'*) _opts=unsupported ;; esac
        case "$_dom" in *\$*) _opts=${_dom#*\$}; _dom=${_dom%%\$*} ;; esac
        case "$_dom" in */*|*\**|*\|*|*\^*) _dom="" ;; esac
        # Options change match scope or response behavior. Do not silently widen them.
        if [ -n "$_opts" ]; then _dom=""; fi
        if [ -n "$_dom" ] && valid_domain "$_dom"; then
          if [ "$_allow" = "1" ]; then
            add_entry "$DOMAIN_SECTION" "$_dom" "adblock-allow" "$loc"; fc=$((fc + 1))
          else
            # Adblock's ||domain^ means the domain and every subdomain, not just an
            # exact hosts-file entry. Keep the DNS/hosts block for the apex and emit
            # a suffix route so child subdomains are actually rejected by the route engine.
            add_entry "$BLOCK_SECTION" "$_dom" "adblock-filter" "$loc"; fc=$((fc + 1))
            add_entry "$RULE_SECTION" "DOMAIN-SUFFIX,$_dom,REJECT" "adblock-route" "$loc"; fc=$((fc + 1))
          fi
        else
          add_skip "SKIP:adblock" "$loc" "非纯域名过滤规则（路径/通配符/复杂条件），未自动转换: $t"; sk=$((sk + 1))
        fi
        continue ;;
      '@@'*|*'##'*|*'#@#'*|*'#$#'*|*'#%#'*)
        add_skip "SKIP:adblock" "$loc" "例外/元素/脚本注入类过滤器需扩展引擎，未转换: $t"; sk=$((sk + 1)); continue ;;
    esac

    case "$cur" in
      general)
        add_skip "SKIP:general" "$loc" "General 设置项无对应实现: ${t%%=*}"
        sk=$((sk + 1)); continue ;;
      mitm)
        case "$t" in
          *=*)
            k=$(printf '%s' "$t" | cut -d= -f1 | trim | tr 'A-Z' 'a-z')
            case "$k" in
              hostname|hostnames)
                # %APPEND% is a client-config directive, not a hostname. Preserve
                # only actual exact/wildcard DNS names as an explicit runtime allowlist.
                v=$(printf '%s' "$t" | cut -d= -f2- | sed -e 's/#.*$//' -e 's/%APPEND%//Ig' | trim)
                for h in $(printf '%s' "$v" | tr ',' ' '); do
                  h=$(printf '%s' "$h" | trim | tr 'A-Z' 'a-z')
                  [ -z "$h" ] && continue
                  case "$h" in
                    '*.'*) _mh_base=${h#*.}; _mh_ok=0; valid_domain "$_mh_base" && _mh_ok=1 ;;
                    *'**'*|*'*'*) _mh_ok=0 ;;
                    *) _mh_ok=0; valid_domain "$h" && _mh_ok=1 ;;
                  esac
                  if [ "$_mh_ok" = 1 ]; then
                    add_entry "$MITM_SECTION" "$h" "modconvert-mitmhost" "$loc" && fc=$((fc + 1))
                  else
                    add_skip "MITM:host" "$loc" "非法或不支持的 MITM 主机名: $h"; sk=$((sk + 1))
                  fi
                done ;;
              *)
                add_skip "SKIP:mitm" "$loc" "MITM 参数无对应实现: $k"; sk=$((sk + 1)) ;;
            esac ;;
          *)
            case "$t" in
              *.pem|*.p12|*.cer|*ca-passphrase*|*ca-file*)
                add_skip "SKIP:mitm" "$loc" "MITM 证书参数: $t"; sk=$((sk + 1)) ;;
              *)
                for h in $(printf '%s' "$t" | tr ',' ' '); do
                  h=$(printf '%s' "$h" | trim)
                  [ -z "$h" ] && continue
                  case "$h" in
                    '*.'*) _mh_base=${h#*.}; _mh_ok=0; valid_domain "$_mh_base" && _mh_ok=1 ;;
                    *'**'*|*'*'*) _mh_ok=0 ;;
                    *) _mh_ok=0; valid_domain "$h" && _mh_ok=1 ;;
                  esac
                  if [ "$_mh_ok" = 1 ]; then add_entry "$MITM_SECTION" "$h" "modconvert-mitmhost" "$loc" && fc=$((fc + 1)); fi
                done ;;
            esac ;;
        esac
        continue ;;
      script)
        case "$t" in
          *=*)
            kt=$(printf '%s' "${t%%=*}" | trim)
            v=${t#*=}
            stype=$(printf '%s' "$v" | sed -n 's/.*type=\([^,]*\).*/\1/p' | trim | tr 'A-Z' 'a-z')
            # The pattern itself is a regex and may contain commas. Stop at the
            # script-path field (the stable terminal field), not at the first
            # comma; otherwise patterns such as ^https://host/(foo,bar)$ truncate.
            pat=$(printf '%s' "$v" | sed -n 's/.*pattern=\(.*\),script-path=.*/\1/p' | sed -E 's/,requires-body=[^,]*//g; s/,timeout=[^,]*//g' | trim)
            [ -n "$pat" ] || pat=$(printf '%s' "$v" | sed -n 's/.*pattern=\([^,]*\).*/\1/p' | trim)
            surl=$(printf '%s' "$v" | sed -n 's/.*script-path=\([^,]*\).*/\1/p' | trim)
            [ -n "$surl" ] || surl=$(printf '%s' "$v" | sed -n 's/.*url=\([^,]*\).*/\1/p' | trim)
            case "$stype" in
              http-request|request) stype=request ;;
              http-response|response) stype=response ;;
              request-response|both) stype=both ;;
              *) stype="" ;;
            esac
            case "$surl" in
              https://*) ;;
              *) surl="" ;;
            esac
            if [ -n "$stype" ] && [ -n "$pat" ] && [ -n "$surl" ]; then
              # Store type+pattern as base64 in the note field, so regex delimiters
              # such as | do not corrupt the module's pipe-separated list format.
              meta=$(printf '%s\n%s\n' "$stype" "$pat" | base64 2>/dev/null | tr -d '\r\n')
              case "$meta" in ''|*[!A-Za-z0-9+/=]*) add_skip "SKIP:script" "$loc" "无法安全编码脚本触发元数据"; sk=$((sk + 1)) ;;
                *) add_entry "$SCRIPT_SECTION" "$surl" "FXMETA_B64:$meta" "$loc" && fc=$((fc + 1)) ;;
              esac
            else
              add_skip "SKIP:script" "$loc" "仅自动转换带 type=http-request/http-response、pattern= 与 HTTPS script-path= 的声明；其它脚本仍需人工适配: $kt"
              sk=$((sk + 1))
              if [ -n "$pat" ]; then
                for d in $(printf '%s' "$pat" | grep -oE '[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}' | sort -u); do
                  add_skip "L7:pattern" "$loc" "$d"
                done
              fi
            fi ;;
          *)
            add_skip "SKIP:script" "$loc" "内联 JS 尚未自动接入实时代理触发链"; sk=$((sk + 1)) ;;
        esac
        continue ;;
      "url rewrite"|rewrite)
        # Preserve the entire URL-scoped rule as base64. This avoids pipe and
        # delimiter corruption in settings.conf while keeping it separate from
        # DNS/domain lists. Runtime validates every decoded rule before publish.
        _rw_rule=$(printf '%s' "$t" | sed -E 's/[[:space:]]+#.*$//')
        # Accept both the spaced FX form (`pattern - 302$1`) and common
        # compact third-party suffixes (`pattern-302$1`). Normalize the action
        # separator before storing so the Go manifest parser receives one form.
        _rw_prefix=$(printf '%s' "$_rw_rule" | sed -E 's/^(.*[^[:space:]])[[:space:]]*-[[:space:]]*(reject-200|reject-dict|reject-array|reject-empty|reject-img|reject|redirect-302|redirect-307|redirect|302|307)(.*)$/\1/')
        _rw_action=$(printf '%s' "$_rw_rule" | sed -E 's/^(.*[^[:space:]])[[:space:]]*-[[:space:]]*(reject-200|reject-dict|reject-array|reject-empty|reject-img|reject|redirect-302|redirect-307|redirect|302|307)(.*)$/\2/' | tr 'A-Z' 'a-z')
        _rw_tail=$(printf '%s' "$_rw_rule" | sed -E 's/^(.*[^[:space:]])[[:space:]]*-(reject-200|reject-dict|reject-array|reject-empty|reject-img|reject|redirect-302|redirect-307|redirect|302|307)(.*)$/\3/; s/^[[:space:]]*//')
        case "$_rw_action" in
          reject|reject-200|reject-img|reject-dict|reject-array|reject-empty|302|307|redirect|redirect-302|redirect-307) ;;
          *) add_skip "SKIP:l7" "$loc" "未知或格式不明确的 URL Rewrite 动作，安全跳过: $t"; sk=$((sk + 1)); continue ;;
        esac
        case "$_rw_prefix" in "$_rw_rule") add_skip "SKIP:l7" "$loc" "URL Rewrite 缺少可识别动作分隔符，安全跳过: $t"; sk=$((sk + 1)); continue ;; esac
        _rw_rule="$_rw_prefix - $_rw_action$_rw_tail"
        _rw_b64=$(printf '%s' "$_rw_rule" | base64 2>/dev/null | tr -d '\r\n')
        case "$_rw_b64" in ''|*[!A-Za-z0-9+/=]*) add_skip "SKIP:l7" "$loc" "URL Rewrite 规则编码失败，安全跳过: $t"; sk=$((sk + 1)) ;;
          *) add_entry "$URLREWRITE_SECTION" "$_rw_b64" "FXURLREWRITE_B64" "$loc" && fc=$((fc + 1)) ;;
        esac
        continue ;;
      "map local")
        add_skip "SKIP:l7" "$loc" "Map Local 需要 L7 内容替换，本模块不支持"; sk=$((sk + 1)); continue ;;
      "header rewrite"|"body rewrite")
        add_skip "SKIP:l7" "$loc" "${rawcur} 需要 L7 改写能力，本模块不支持"; sk=$((sk + 1)); continue ;;
      host)
        case "$t" in
          *=*)
            h=$(printf '%s' "${t%%=*}" | trim)
            v=$(printf '%s' "${t#*=}" | sed -e 's/#.*$//' | trim)
            case "$v" in
              0.0.0.0|127.0.0.1|::1|"")
                if valid_domain "$h"; then
                  add_entry "$BLOCK_SECTION" "$h" "modconvert" "$loc"; fc=$((fc + 1))
                else
                  add_skip "SKIP:host" "$loc" "非法域名: $h"; sk=$((sk + 1))
                fi ;;
              *)
                add_skip "SKIP:host" "$loc" "Host 段 IP 重定向($h -> $v)需 DNS 改写，请用 hosts 功能"
                sk=$((sk + 1)) ;;
            esac ;;
          *)
            add_skip "SKIP:host" "$loc" "无法解析的 Host 行: $t"; sk=$((sk + 1)) ;;
        esac
        continue ;;
      rule)
        kind=$(printf '%s' "$t" | cut -d, -f1 | trim | tr 'A-Z' 'a-z')
        val=$(printf '%s' "$t" | cut -d, -f2 | trim)
        pol=$(printf '%s' "$t" | cut -d, -f3 | trim)
        [ -z "$pol" ] && pol="REJECT"
        polu=$(printf '%s' "$pol" | tr 'A-Z' 'a-z')
        case "$polu" in
          reject*|drop*|deny*) act=block ;;
          direct|pass*) act=allow ;;
          proxy*) act=other ;;
          *) act=other ;;
        esac
        case "$kind" in
          domain|domain-suffix|host|host-suffix)
            if [ "$act" = "block" ]; then
              if valid_domain "$val"; then
                add_entry "$BLOCK_SECTION" "$val" "modconvert" "$loc"; fc=$((fc + 1))
                # Do not rely on Android hosts alone: apps using remote DNS/DoH can
                # bypass it. Every explicit domain block also enters [list:rule]; exact
                # host rules stay exact, suffix rules preserve subdomain semantics.
                case "$kind" in
                  domain|host)
                    add_entry "$RULE_SECTION" "DOMAIN,$val,REJECT" "modconvert-route" "$loc" && fc=$((fc + 1)) ;;
                  domain-suffix|host-suffix)
                    add_entry "$RULE_SECTION" "DOMAIN-SUFFIX,$val,REJECT" "modconvert-route" "$loc" && fc=$((fc + 1)) ;;
                esac
              else
                add_skip "SKIP:rule" "$loc" "非法域名: $val"; sk=$((sk + 1))
              fi
            elif [ "$act" = "allow" ]; then
              if valid_domain "$val"; then
                add_entry "$DOMAIN_SECTION" "$val" "modconvert-whitelist" "$loc"; fc=$((fc + 1))
              else
                add_skip "SKIP:allow" "$loc" "非法白名单域名: $val"; sk=$((sk + 1))
              fi
            else
              add_entry "$RULE_SECTION" "$kind,$val,$pol" "modconvert" "$loc"; fc=$((fc + 1))
            fi ;;
          domain-keyword|host-keyword|domain-regex)
            # These predicates cannot be represented by Android hosts. Keep them in
            # the proxy route compiler instead of silently widening them to a suffix.
            case "$kind" in
              host-keyword) _fxkind=DOMAIN-KEYWORD ;;
              domain-keyword) _fxkind=DOMAIN-KEYWORD ;;
              domain-regex) _fxkind=DOMAIN-REGEX ;;
            esac
            if [ "$act" = "block" ] || [ "$act" = "allow" ] || [ "$act" = "other" ]; then
              if [ -n "$val" ]; then
                add_entry "$RULE_SECTION" "$_fxkind,$val,$pol" "modconvert-route" "$loc"; fc=$((fc + 1))
              else
                add_skip "SKIP:rule" "$loc" "$kind 缺少匹配值"; sk=$((sk + 1))
              fi
            fi ;;
          process-name|package-name|dest-port|dst-port|src-port|protocol|network)
            # Preserve semantics for predicates already handled by vpnrule.sh.
            case "$kind" in dest-port) _fxkind=DST-PORT ;; *) _fxkind=$(printf '%s' "$kind" | tr 'a-z' 'A-Z') ;; esac
            if [ -n "$val" ]; then
              add_entry "$RULE_SECTION" "$_fxkind,$val,$pol" "modconvert-route" "$loc"; fc=$((fc + 1))
            else
              add_skip "SKIP:rule" "$loc" "$kind 缺少匹配值"; sk=$((sk + 1))
            fi ;;
          domain-set)
            add_skip "SKIP:rule" "$loc" "DOMAIN-SET 需规则集文件，请把其中的域名逐条加入 [list:block]"
            sk=$((sk + 1)) ;;
          ip-cidr|ip-cidr6|ip6-cidr)
            # IP-CIDR 是通用路由规则，不是 FX 专用反诈/96110 数据。
            # [list:block] 面向 hosts 域名；IP/CIDR 必须进入 [list:rule]，由 vpnrule.sh 编译。
            # 对明确的拦截策略必须保留 REJECT，省略动作会被 target_json 当作 DIRECT。
            if [ "$act" = "block" ]; then
              case "$kind" in
                ip-cidr)   ok=0; valid_ip  "$val" && ok=1; pfx="IP-CIDR" ;;
                *)         ok=0; valid_ip6 "$val" && ok=1; pfx="IP-CIDR6" ;;
              esac
              if [ "$ok" = "1" ]; then
                add_entry "$RULE_SECTION" "$pfx,$val,REJECT" "modconvert" "$loc"; fc=$((fc + 1))
              else
                add_skip "SKIP:rule" "$loc" "非法 CIDR: $val"; sk=$((sk + 1))
              fi
            else
              add_entry "$RULE_SECTION" "$kind,$val,$pol" "modconvert" "$loc"; fc=$((fc + 1))
            fi ;;
          geoip|ip-asn)
            add_skip "SKIP:rule" "$loc" "$kind 需要 GeoIP 数据库，本模块无 GeoIP"; sk=$((sk + 1)) ;;
          match|final)
            # Clash/Mihomo catch-all rules are route.final policy, not a domain filter.
            if [ -n "$val" ]; then
              add_entry "$RULE_SECTION" "$(printf '%s' "$kind" | tr 'a-z' 'A-Z'),$val" "modconvert-final" "$loc"; fc=$((fc + 1))
            else
              add_skip "SKIP:rule" "$loc" "$kind 缺少最终策略"; sk=$((sk + 1))
            fi ;;
          rule-set)
            # Remote plain-text domain sets are routed through the existing [list:rule]
            # subscription/cache/compiler pipeline. Do not treat arbitrary URLs as domains,
            # and do not claim binary SRS, complex YAML, or non-REJECT targets are active.
            _rs_url="$val"
            _rs_path=$(printf '%s' "$_rs_url" | sed 's/[?#].*$//')
            case "$_rs_url" in
              http://*|https://*)
                if printf '%s' "$_rs_url" | grep -Eq '[[:space:]|]'; then
                  add_skip "SKIP:ruleset" "$loc" "RULE-SET URL 含不支持字符或空白: $_rs_url"; sk=$((sk + 1))
                else
                  case "$_rs_path" in
                    *.txt|*.list|*.conf)
                      if [ "$act" = "block" ]; then
                        add_entry "$RULE_SECTION" "$_rs_url" "modconvert-ruleset-reject" "$loc" && fc=$((fc + 1))
                      else
                        add_skip "SKIP:ruleset" "$loc" "远程文本 RULE-SET 当前仅保证 REJECT 语义；未转换策略: $pol"; sk=$((sk + 1))
                      fi ;;
                    *)
                      add_skip "SKIP:ruleset" "$loc" "只自动接入 .txt/.list/.conf 文本规则集；SRS/复杂 YAML/未知格式需单独适配: $_rs_url"; sk=$((sk + 1)) ;;
                  esac
                fi ;;
              *)
                add_skip "SKIP:ruleset" "$loc" "RULE-SET 仅支持可下载的 HTTP(S) 文本 URL；本地规则集需先安装到规则目录: $_rs_url"; sk=$((sk + 1)) ;;
            esac ;;
          url-regex|url|user-agent|dest-port|src-port|protocol|final|and|or|not)
            add_skip "SKIP:l4l7" "$loc" "$kind 规则需要规则集解析、L7 或逻辑组合支持，未自动转换"
            sk=$((sk + 1)) ;;
          "")
            add_skip "SKIP:rule" "$loc" "空规则行"; sk=$((sk + 1)) ;;
          *)
            if valid_domain "$t" && [ -z "$val" ]; then
              add_entry "$BLOCK_SECTION" "$t" "modconvert" "$loc"; fc=$((fc + 1))
            else
              add_skip "SKIP:rule" "$loc" "未知规则类型: $kind"; sk=$((sk + 1))
            fi ;;
        esac
        continue ;;
    esac

    # 段外 / 未知段
    if [ -z "$cur" ]; then
      case "$t" in
        *=*)
          add_skip "SKIP:bare" "$loc" "段外键值行: ${t%%=*}"; sk=$((sk + 1)) ;;
        *)
          kind=$(printf '%s' "$t" | cut -d, -f1 | tr 'A-Z' 'a-z')
          val=$(printf '%s' "$t" | cut -d, -f2 | trim)
          pol=$(printf '%s' "$t" | cut -d, -f3 | trim)
          [ -z "$pol" ] && pol="REJECT"
          polu=$(printf '%s' "$pol" | tr 'A-Z' 'a-z')
          case "$polu" in
            reject*|drop*|deny*) act=block ;;
            direct|pass*) act=allow ;;
          proxy*) act=other ;;
            *) act=other ;;
          esac
          case "$kind" in
            domain*|host|host-suffix|host-keyword|process-name|package-name|dest-port|dst-port|src-port|protocol|network)
              # 段外裸规则也必须尊重第3列策略: DIRECT/PROXY 是放行，绝不能当拦截写进
              # [list:block]（否则会把用户本来要放行的域名封掉）。
              if [ "$act" = "block" ]; then
                if valid_domain "$val"; then
                  add_entry "$BLOCK_SECTION" "$val" "modconvert" "$loc"; fc=$((fc + 1))
                else
                  add_skip "SKIP:bare" "$loc" "非法域名: $val"; sk=$((sk + 1))
                fi
              elif [ "$act" = "allow" ]; then
                if valid_domain "$val"; then
                  add_entry "$DOMAIN_SECTION" "$val" "modconvert-whitelist" "$loc"; fc=$((fc + 1))
                else
                  add_skip "SKIP:allow" "$loc" "非法白名单域名: $val"; sk=$((sk + 1))
                fi
              else
                add_entry "$RULE_SECTION" "$kind,$val,$pol" "modconvert" "$loc"; fc=$((fc + 1))
              fi ;;
            ip-cidr*)
              case "$kind" in
                ip-cidr6|ip6-cidr) ok=0; valid_ip6 "$val" && ok=1; pfx="IP-CIDR6" ;;
                *)                 ok=0; valid_ip  "$val" && ok=1; pfx="IP-CIDR" ;;
              esac
              if [ "$ok" != "1" ]; then
                add_skip "SKIP:bare" "$loc" "非法 CIDR: $val"; sk=$((sk + 1))
              elif [ "$act" = "block" ]; then
                add_entry "$RULE_SECTION" "$pfx,$val,REJECT" "modconvert" "$loc"; fc=$((fc + 1))
              else
                add_entry "$RULE_SECTION" "$kind,$val,$pol" "modconvert" "$loc"; fc=$((fc + 1))
              fi ;;
            *)
              add_skip "SKIP:bare" "$loc" "段外无法识别的行: $t"; sk=$((sk + 1)) ;;
          esac ;;
      esac
      continue
    fi

    add_skip "SKIP:section" "$loc" "段 [$rawcur] 无对应实现: $t"
    sk=$((sk + 1))
  done < "$real"

  printf '%s\t%s\t%s\n' "$src" "$fc" "$sk" >> "$S_DIR/files.tsv"
}

# ============================ 主流程 ============================
NERR=0
for f in $FILES; do
  conv_file "$f" || NERR=$((NERR + 1))
done

TOT_CONV=$(awk -F'\t' '{s+=$2} END{print s+0}' "$S_DIR/files.tsv" 2>/dev/null)
TOT_SKIP=$(awk -F'\t' '{s+=$3} END{print s+0}' "$S_DIR/files.tsv" 2>/dev/null)

emit_entries_for() { # $1=section  → 打印该段所有条目
  awk -F'\t' -v s="$1" '
    $1 == s {
      if (plain == 1) print $2 "|" $3 "|1"
      else printf "# source: %s\n%s|%s|1\n", $4, $2, $3
    }' plain="$PLAIN" "$S_DIR/entries.tsv"
}

case "$MODE" in
  list)
    echo "=============================================================="
    echo " PrivacyGuard modconvert — 模块文件转换摘要"
    echo "=============================================================="
    while IFS='	' read -r sf fc sk; do
      echo ""
      echo "文件: $sf"
      echo "  可转换条目: $fc"
      echo "  跳过条目  : $sk"
    done < "$S_DIR/files.tsv"
    echo ""
    echo "--- 识别到的段 ---"
    # 注意: 段名可能含空格（"url rewrite"），awk 必须按 TAB 分隔，否则会被拆成首词
    sort "$S_DIR/stats.tsv" 2>/dev/null \
      | awk -F'\t' '{ c[$1]++ } END { for (s in c) printf "  [%s] %d 行\n", s, c[s] }' | sort
    echo ""
    echo "--- SKIP 明细（按类别）---"
    if [ -s "$S_DIR/skips.tsv" ]; then
      cut -f1 "$S_DIR/skips.tsv" | sort \
        | awk '{ c[$1]++ } END { for (s in c) printf "  %-18s %d 条\n", s, c[s] }' | sort
      echo ""
      echo "  前 10 条明细:"
      head -10 "$S_DIR/skips.tsv" | awk -F'\t' '{ printf "    %-16s %-26s %s\n", $1, $2, $3 }'
    else
      echo "  (无)"
    fi
    echo ""
    echo "--- 输出预览（前 8 条，--emit 格式）---"
    emit_entries_for "$BLOCK_SECTION"   | head -8
    emit_entries_for "$FX_SECTION"      | head -4
    echo ""
    echo "统计: 可转换 $TOT_CONV 条 / 跳过 $TOT_SKIP 条"
    echo ""
    echo "⚠ 重要限制:"
    echo "  * AdGuard/Adblock/uBO 仅转换安全的纯域名网络过滤子集；元素隐藏、复杂例外和脚本注入会标记 SKIP。"
    echo "  * Surge/Loon 风格的显式 http-request/http-response + pattern + HTTPS script-path 可转换为 [list:script]；其它声明仍会 SKIP。"
    echo "  * [URL Rewrite] 保留在独立 [list:urlrewrite] 段；需由 MITM 启动同步器验证后执行。"
    echo "  * [MITM] hostname 会进入独立 [list:mitmhost] 白名单；未列出的 TLS 主机透传，不做中间人解密。"
    echo "  * [Map Local]/[Header Rewrite]/[Body Rewrite] 仍需专用 L7 实现，未伪装成已支持。"
    echo "  * Clash/Mihomo 仅解析显式 `rules:` 列表；代理组、provider、DNS、复杂 YAML 锚点不转换。"
    echo "  * MITM 仍需用户明确启用并信任模块 CA；证书固定应用不保证可用。"
    ;;
  emit)
    if [ "$PLAIN" != "1" ]; then
      echo "# ===== PrivacyGuard modconvert 输出（$(date '+%Y-%m-%d %H:%M:%S')） ====="
      echo "# 用法: 把下面对应 [list:*] 段的内容粘贴到 /data/adb/privacyguard/settings.conf，"
      echo "#       然后 WebUI 点『应用』（或执行 sh apply.sh）生效。"
      echo "# 限制: 仅输出可转换子集；未识别的 JS 声明、复杂 L7/元素过滤不执行，详见 SKIP 明细。"
      echo ""
      echo "[list:$DOMAIN_SECTION]"
      echo "# ---- 白名单/放行（来自 modconvert；优先于拦截）----"
      emit_entries_for "$DOMAIN_SECTION"
      echo ""
      echo "[list:$BLOCK_SECTION]"
      echo "# ---- 域名/IP 拦截（来自 modconvert）----"
      emit_entries_for "$BLOCK_SECTION"
      echo ""
      echo "[list:$FX_SECTION]"
      echo "# ---- 带策略规则（来自 modconvert）----"
      emit_entries_for "$FX_SECTION"
      echo ""
      echo "[list:$RULE_SECTION]"
      echo "# ---- 远程文本规则集（仅支持经过校验的 REJECT 文本集；使用模块下载缓存和规则编译链）----"
      emit_entries_for "$RULE_SECTION"
      echo ""
      echo "[list:$SCRIPT_SECTION]"
      echo "# ---- HTTPS 脚本订阅（仅转换受支持的显式请求/响应声明）----"
      emit_entries_for "$SCRIPT_SECTION"
      echo ""
      echo "[list:$URLREWRITE_SECTION]"
      echo "# ---- URL 路径级重写（base64 原文；MITM 启动时校验并原子发布）----"
      emit_entries_for "$URLREWRITE_SECTION"
      echo ""
      echo "[list:$MITM_SECTION]"
      echo "# ---- HTTPS 解密主机白名单；仅这些主机执行 MITM/脚本钩子，其它主机原始 TLS 透传 ----"
      emit_entries_for "$MITM_SECTION"
    else
      emit_entries_for "$DOMAIN_SECTION"
      emit_entries_for "$BLOCK_SECTION"
      emit_entries_for "$FX_SECTION"
      emit_entries_for "$RULE_SECTION"
      emit_entries_for "$SCRIPT_SECTION"
      emit_entries_for "$URLREWRITE_SECTION"
      emit_entries_for "$MITM_SECTION"
    fi
    if [ -s "$S_DIR/skips.tsv" ]; then
      {
        echo ""
        echo "# ---- 未转换条目（SKIP）汇总 ----"
        cut -f1 "$S_DIR/skips.tsv" | sort \
          | awk '{ c[$1]++ } END { for (s in c) printf "#   %-18s %d 条\n", s, c[s] }' | sort
        echo "# 明细（前 20 条）:"
        head -20 "$S_DIR/skips.tsv" | awk -F'\t' '{ printf "#   %-16s %-26s %s\n", $1, $2, $3 }'
      } >&2
    fi
    ;;
  json)
    printf '{"ok":true,"converted":%s,"skipped":%s,"files":[' "$TOT_CONV" "$TOT_SKIP"
    first=1
    while IFS='	' read -r sf fc sk; do
      if [ "$first" = "1" ]; then first=0; else printf ','; fi
      sfj=$(printf '%s' "$sf" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
      printf '{"file":"%s","converted":%s,"skipped":%s}' "$sfj" "$fc" "$sk"
    done < "$S_DIR/files.tsv"
    printf '],"skips":{'
    # 用 awk 按 TAB 聚合，避免键名里的空格被 shell 拆词
    awk -F'\t' '
      { c[$1]++ ; if (!($1 in seen)) { seen[$1]=1; order[++n]=$1 } }
      END {
        f = 1
        for (i = 1; i <= n; i++) {
          s = order[i]
          if (!f) printf ","
          f = 0
          printf "\"%s\":%d", s, c[s]
        }
      }' "$S_DIR/skips.tsv" 2>/dev/null
    printf '},"sections":['
    # 注意: 段名可能含空格（"url rewrite"），不能用 for-in-$(...)（会按空格拆词），
    # 因此整段用 awk 按 TAB 聚合后直接输出 JSON。
    awk -F'\t' '
      { c[$1]++ ; if (!($1 in seen)) { seen[$1]=1; order[++n]=$1 } }
      END {
        first = 1
        for (i = 1; i <= n; i++) {
          s = order[i]
          if (!first) printf ","
          first = 0
          printf "{\"name\":\"%s\",\"lines\":%d}", s, c[s]
        }
      }' "$S_DIR/stats.tsv" 2>/dev/null
    printf ']}\n'
    ;;
esac
# 任一文件读失败则返回非 0，便于 WebUI 区分"成功转换"与"部分文件不存在"
if [ "$NERR" -gt 0 ]; then exit 1; fi
exit 0
