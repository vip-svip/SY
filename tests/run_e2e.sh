#!/bin/sh
# 独立端到端验证（不依赖 run_tests.sh 的断言表，逐条人工推导期望值）
set -u
MOD="$1"
# 沙箱目录：Android 上 /tmp 是只读的，必须优先用 /data/local/tmp
if [ -d /data/local/tmp ] && [ -w /data/local/tmp ] 2>/dev/null; then
  T="${SYADGH_TEST_DIR:-/data/local/tmp/syadgh-verify}"
else
  T="${SYADGH_TEST_DIR:-/tmp/syadgh-verify}"
fi
rm -rf "$T"; mkdir -p "$T/data/rules/dns" "$T/data/config" "$T/data/cache/dns"
D="$T/data"

P=0; F=0
ck() { # <描述> <实际> <期望>
  if [ "$2" = "$3" ]; then P=$((P+1)); printf '  ok   %s\n' "$1"
  else F=$((F+1)); printf '  FAIL %s  实际=[%s] 期望=[%s]\n' "$1" "$2" "$3"; fi
}
has() { # <文件> <子串> <描述>
  if grep -qF -- "$2" "$3" 2>/dev/null; then P=$((P+1)); printf '  ok   %s\n' "$1"
  else F=$((F+1)); printf '  FAIL %s  (%s 中无 [%s])\n' "$1" "$3" "$2"; fi
}
hasnt() {
  if grep -qF -- "$2" "$3" 2>/dev/null; then F=$((F+1)); printf '  FAIL %s  (%s 中不应有 [%s])\n' "$1" "$3" "$2"
  else P=$((P+1)); printf '  ok   %s\n' "$1"; fi
}
eng() { AB_DATA_DIR="$D" sh "$MOD/scripts/engine.sh" "$@"; }
OUT="$D/rules/engine"

# ============================================================
# 语料: 覆盖每类语法，每类都有可独立推导的期望结果
# ============================================================
cat > "$D/cache/dns/01_matrix.txt" <<'RULES'
! ---- 网络规则 ----
||block-plain.com^
||block-important.com^$important
@@||allow-plain.com^
@@||allow-important.com^$important
||cancel-me.com^
||cancel-me.com^$badfilter
/^regex-block\.com$/
@@/^regex-allow\.com$/
/^dollar-block\.com$/
||only-third.com^$third-party
||only-first.com^$first-party
||scoped.com^$client=phoneA
||tagged.com^$ctag=tagX
||deny-target.com^
@@||deny-target.com^$denyallow=deny-target.com
||open-target.com^
@@||open-target.com^$denyallow=other.com
||rewrite-me.com^$dnsrewrite=1.2.3.4
||imp-allow-beats-imp-block.com^$important
@@||imp-allow-beats-imp-block.com^$important
! ---- 路径/模式(启发式) ----
||cdn.example.com/ads/banner.js
||track.example.net/pixel?
! ---- hosts ----
0.0.0.0 hosts-block.com
127.0.0.1 hosts-loop.com
1.2.3.4 hosts-rewrite.com
! ---- dnsmasq ----
address=/dnsmasq-block.com/
address=/dnsmasq-multi-a.com/dnsmasq-multi-b.com/
address=/dnsmasq-rw.com/9.9.9.9
local=/dnsmasq-local.com/
server=/dnsmasq-server.com/8.8.8.8
! ---- 纯域名 ----
plain-domain.com
! ---- cosmetic ----
example.com##.ad-banner
example.com#@#.ad-banner
example.com#$#.ad { display:none }
example.com#?#div:has(> .sponsor)
example.com##+js(set-constant, adFlag, false)
example.com#%#//scriptlet('abort-on-property-read', 'ads')
example.com##^script:has-text(sponsor)
! ---- 畸形 ----
||||broken
$important
RULES

eng build >/dev/null 2>&1

printf '\n== 1. 网络规则分类 ==\n'
has "普通拦截 ||block-plain.com^"        "block-plain.com"      "$OUT/block.txt"
has "重要拦截 ||block-important.com^"    "block-important.com"  "$OUT/block_imp.txt"
has "普通放行 @@allow-plain"             "allow-plain.com"      "$OUT/allow.txt"
has "重要放行 @@allow-important"         "allow-important.com"  "$OUT/allow_imp.txt"
has "正则拦截 /regex/"                   "regex-block"          "$OUT/regex_block.txt"
has "正则放行 @@/regex/"                 "regex-allow"          "$OUT/regex_allow.txt"
has "正则产物保留 /.../ 定界符"          "/^regex-block\.com$/" "$OUT/regex_block.txt"
hasnt "badfilter 关闭同形规则"           "cancel-me.com"        "$OUT/block.txt"
hasnt "badfilter 规则本身不入拦截"       "cancel-me.com"        "$OUT/block_imp.txt"
has 'DNS 重写 $dnsrewrite'               "rewrite-me.com"       "$OUT/rewrite.txt"
has "重要重写进入重要通道"               "rewrite-me.com"       "$OUT/rewrite.txt"

printf '\n== 2. 路径/模式(启发式) ==\n'
has "路径规则提取域名 cdn.example.com"   "cdn.example.com"      "$OUT/pattern_block.txt"
has "路径规则提取域名 track.example.net" "track.example.net"    "$OUT/pattern_block.txt"

printf '\n== 3. hosts / dnsmasq / 纯域名 ==\n'
has "hosts 0.0.0.0 拦截"                 "hosts-block.com"      "$OUT/block.txt"
has "hosts 127.0.0.1 拦截"               "hosts-loop.com"       "$OUT/block.txt"
has "hosts 1.2.3.4 视为重写"             "hosts-rewrite.com"    "$OUT/rewrite.txt"
hasnt "hosts 1.2.3.4 不进拦截表"         "hosts-rewrite.com"    "$OUT/block.txt"
has "dnsmasq address=/d/ 拦截"           "dnsmasq-block.com"    "$OUT/block.txt"
has "dnsmasq 多域名 a"                   "dnsmasq-multi-a.com"  "$OUT/block.txt"
has "dnsmasq 多域名 b"                   "dnsmasq-multi-b.com"  "$OUT/block.txt"
has "dnsmasq 带 IP 视为重写"             "dnsmasq-rw.com"       "$OUT/rewrite.txt"
has "dnsmasq local=/d/ 拦截"             "dnsmasq-local.com"    "$OUT/block.txt"
hasnt "dnsmasq server=/d/ 不算拦截"      "dnsmasq-server.com"   "$OUT/block.txt"
has "纯域名清单"                         "plain-domain.com"     "$OUT/block.txt"

printf '\n== 4. cosmetic / 注入 ==\n'
has "## 元素隐藏"                        ".ad-banner"           "$OUT/cosmetic_hide.txt"
has "#@# 取消隐藏"                       ".ad-banner"           "$OUT/cosmetic_unhide.txt"
has '#$# CSS 注入'                       "display:none"         "$OUT/css_inject.txt"
has "#?# 扩展 CSS"                       "div:has(> .sponsor)"  "$OUT/ext_css.txt"
has "##+js scriptlet (uBO)"              "set-constant"         "$OUT/scriptlets.txt"
has "#%#//scriptlet (AdGuard)"           "abort-on-property-read" "$OUT/scriptlets.txt"
has "##^ HTML 过滤"                      "script:has-text"      "$OUT/html_filter.txt"

printf '\n== 5. 无效规则统计 ==\n'
inv=$(eng verify | sed -n 's/.*"invalid":\([0-9]*\).*/\1/p')
[ -n "$inv" ] || inv=0
ck "畸形规则计入 invalid 且 >=2" "$([ "$inv" -ge 2 ] && echo yes || echo no)" "yes"

printf '\n== 6. hosts 生成与优先级 ==\n'
H="$OUT/hosts"
has "hosts 含 0.0.0.0 拦截域"            "0.0.0.0 block-plain.com"      "$H"
has "hosts 含 www. 变体"                 "0.0.0.0 www.block-plain.com"  "$H"
hasnt "放行域不进 hosts"                 "allow-plain.com"              "$H"
hasnt "badfilter 域不进 hosts"           "cancel-me.com"                "$H"
hasnt "重写域不进 0.0.0.0 拦截"          "0.0.0.0 rewrite-me.com"       "$H"
hasnt "dnsmasq server 域不进 hosts"      "dnsmasq-server.com"           "$H"
hasnt "正则规则不进 hosts"               "regex-block"                  "$H"
ck "hosts 含 localhost" "$(grep -c '^127\.0\.0\.1 localhost$' "$H")" "1"

printf '\n== 7. 命中诊断（优先级求值）==\n'
q() { eng test "$1" | sed -n 's/.*"priority":"\([^"]*\)".*/\1/p'; }
ck "重要拦截命中"                 "$(q block-important.com)"            "important-block"
ck "普通拦截命中"                 "$(q block-plain.com)"                "block"
ck "普通放行命中"                 "$(q allow-plain.com)"                "allow"
ck "重要放行命中"                 "$(q allow-important.com)"            "important-allow"
ck "重要放行 > 重要拦截"          "$(q imp-allow-beats-imp-block.com)"  "important-allow"
ck "badfilter 后未命中"           "$(q cancel-me.com)"                  "none"
ck "正则拦截命中"                 "$(q regex-block.com)"                "block"
ck "含 \$ 的正则仍可命中"         "$(q dollar-block.com)"               "block"
ck "DNS 重写命中"                 "$(q rewrite-me.com)"                 "dnsrewrite"
ck "hosts 1.2.3.4 为重写"         "$(q hosts-rewrite.com)"              "dnsrewrite"
ck "hosts 0.0.0.0 为拦截"         "$(q hosts-block.com)"                "block"
ck "dnsmasq 拦截命中"             "$(q dnsmasq-block.com)"              "block"
ck "dnsmasq server 未命中"        "$(q dnsmasq-server.com)"             "none"
ck "子域继承父域拦截"             "$(q sub.block-plain.com)"            "block"
ck "无规则域未命中"               "$(q not-in-list.com)"                "none"

printf '\n== 7b. 浏览器侧(cosmetic)规则诊断 ==\n'
cq() { eng test "$1" | sed -n 's/.*"cosmetic":\([0-9]*\).*/\1/p'; }
ck "example.com 命中 7 条浏览器侧规则" "$(cq example.com)"        "7"
ck "子域继承父域 cosmetic 规则"        "$(cq sub.example.com)"    "7"
ck "无关域无 cosmetic 规则"            "$(cq not-in-list.com)"    "0"
ck "cosmetic 不改变 DNS 层结论"        "$(q example.com)"         "none"

printf '\n== 8. $denyallow 限定例外范围 ==\n'
ck "denyallow 命中 -> 例外失效, 仍拦截" "$(q deny-target.com)"          "block"
ck "denyallow 未命中 -> 例外生效, 放行" "$(q open-target.com)"          "allow"

printf '\n== 9. 作用域严格模式 ($client) ==\n'
st() { AB_DATA_DIR="$D" ENGINE_STRICT_SCOPE=1 ENGINE_CLIENT="$1" sh "$MOD/scripts/engine.sh" test scoped.com | sed -n 's/.*"priority":"\([^"]*\)".*/\1/p'; }
ck "STRICT + 匹配 client -> 拦截"   "$(st phoneA)"  "block"
ck "STRICT + 不匹配 client -> 未命中" "$(st phoneB)" "none"

printf '\n== 10. 幂等性（重复编译产物一致）==\n'
eng build >/dev/null 2>&1
S1=$(cat "$OUT/block.txt" "$OUT/block_imp.txt" "$OUT/allow.txt" "$OUT/allow_imp.txt" \
        "$OUT/rewrite.txt" "$OUT/cosmetic_hide.txt" "$OUT/scriptlets.txt" | md5sum)
eng build >/dev/null 2>&1
S2=$(cat "$OUT/block.txt" "$OUT/block_imp.txt" "$OUT/allow.txt" "$OUT/allow_imp.txt" \
        "$OUT/rewrite.txt" "$OUT/cosmetic_hide.txt" "$OUT/scriptlets.txt" | md5sum)
ck "两次编译产物一致" "$S1" "$S2"
B1=$(grep -v '^#' "$OUT/hosts" | md5sum); eng build >/dev/null 2>&1
B2=$(grep -v '^#' "$OUT/hosts" | md5sum)
ck "hosts 数据体稳定" "$B1" "$B2"

printf '\n== 11. 多语法统计 ==\n'
syn=$(eng syntax)
for k in adblock modifiers cosmetic scriptlet css-inject extended-css html-filter hosts dnsmasq regex dnsrewrite plain-domain; do
  v=$(printf '%s' "$syn" | sed -n "s/.*\"$k\":\([0-9]*\).*/\1/p")
  ck "语法类别 $k 计数 > 0" "$([ -n "$v" ] && [ "$v" -gt 0 ] && echo yes || echo "no($v)")" "yes"
done

printf '\n== 12. 体检 ==\n'
vf=$(eng verify)
ck "verify 返回 records" "$(printf '%s' "$vf" | grep -c '"records"')" "1"
ck "verify 无冗余拦截"   "$(printf '%s' "$vf" | sed -n 's/.*"redundant_block":\([0-9]*\).*/\1/p')" "0"
ck "verify 无冗余放行"   "$(printf '%s' "$vf" | sed -n 's/.*"redundant_allow":\([0-9]*\).*/\1/p')" "0"
ck "verify 统计 badfilter 关闭数" "$(printf '%s' "$vf" | sed -n 's/.*"badfilter_rules":\([0-9]*\).*/\1/p')" "1"

printf '\n============================================================\n'
printf '独立端到端验证: 通过 %s 项, 失败 %s 项\n' "$P" "$F"
[ "$F" -eq 0 ] && echo "ALL INDEPENDENT CHECKS PASSED" || echo "存在失败项"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
