#!/system/bin/sh
# ============================================================
#  SY-Fusion 多轮自检套件
#  用法: sh tests/run_tests.sh [all|1|2|3|4|5|6|7]
#   1 功能正确性   2 幂等性      3 作用域严格模式   4 启发式开关
#   5 大规模性能   6 多语法覆盖  7 畸形输入健壮性
#  兼容 Android (toybox/busybox) 与桌面 (busybox/gawk) 双端
# ============================================================
set -u

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
MOD="$(cd "$TESTS_DIR/.." && pwd)"
if [ -d /data/local/tmp ] && [ -w /data/local/tmp ] 2>/dev/null; then
  TMP="${SYADGH_TEST_DIR:-/data/local/tmp/syadgh-test}"
else
  TMP="${SYADGH_TEST_DIR:-/tmp/syadgh-test}"
fi
DATA="$TMP/data"
OUT="$DATA/rules/engine"
TAB="$(printf '\t')"

PASS=0; FAIL=0; FAILED=""

ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); FAILED="$FAILED
  x $1"; printf '  [FAIL] %s\n' "$1"; }
hr()  { printf '%s\n' "------------------------------------------------------------"; }

engine() { AB_DATA_DIR="$DATA" sh "$MOD/scripts/engine.sh" "$@"; }

field() { printf '%s' "$1" | sed -n "s/.*\"$2\":\"\([^\"]*\)\".*/\1/p"; }
numf()  { printf '%s' "$1" | sed -n "s/.*\"$2\":\([0-9][0-9]*\).*/\1/p"; }

assert_has() { # <相对OUT的文件> <子串>
  if grep -qF -- "$2" "$OUT/$1" 2>/dev/null; then ok; else bad "文件 $1 缺少内容: $2"; fi
}
assert_not_has() {
  if grep -qF -- "$2" "$OUT/$1" 2>/dev/null; then bad "文件 $1 不应包含: $2"; else ok; fi
}

setup() {
  rm -rf "$TMP"
  mkdir -p "$DATA/config" "$DATA/cache/dns" "$DATA/rules/remote" \
           "$DATA/rules/netblock" "$DATA/logs" "$DATA/run"
  cp "$TESTS_DIR/corpus/01_mixed.txt" "$DATA/cache/dns/list_mixed.txt"
  printf 'mixed|http://example.invalid/list.txt|1|test\n' > "$DATA/config/lists.conf"
  : > "$DATA/config/user_rules.txt"
  : > "$DATA/config/blacklist.conf"
  : > "$DATA/config/whitelist.conf"
  conf_default
}

conf_default() {
  printf 'ENGINE_HEURISTIC=1\nENGINE_STRICT_SCOPE=0\nENGINE_CLIENT=\nENGINE_CTAG=\nHOSTS_EXTRA=www\n' \
    > "$DATA/config/sy.conf"
}

# ============================================================
round1() {
  hr; echo "轮次 1/7  功能正确性（多语法 / 优先级 / 边界）"; hr
  engine build >/dev/null 2>&1
  if [ ! -s "$OUT/hosts" ]; then bad "编译未产生 hosts"; return; fi

  # 批量诊断（单次装载）后与期望值比对，避免逐域名派生
  engine testfile "$TESTS_DIR/expect.tsv" > "$TMP/match.tsv" 2>/dev/null
  awk -F'\t' -v m="$TMP/match.tsv" '
    BEGIN {
      while ((getline l < m) > 0) {
        n = split(l, a, "\t")
        if (n < 3) continue
        R[a[1]] = a[2]; P[a[1]] = a[3]
      }
      close(m)
    }
    /^#/ { next }
    NF >= 3 {
      d = $1; e = $2; ep = $3
      if (R[d] == e && P[d] == ep) print "PASS"
      else printf "FAIL\t%s 期望 %s/%s 实际 %s/%s\n", d, e, ep, R[d], P[d]
    }
  ' "$TESTS_DIR/expect.tsv" > "$TMP/cmp.txt" 2>/dev/null
  while IFS= read -r line; do
    case "$line" in
      PASS) ok ;;
      FAIL*) bad "$(printf '%s' "$line" | cut -f2-)" ;;
    esac
  done < "$TMP/cmp.txt"

  # ---- 分类输出断言 ----
  assert_has "block.txt" "block-a.test"
  assert_has "block_imp.txt" "block-b.test"
  assert_has "allow.txt" "allow-a.test"
  assert_has "allow_imp.txt" "allow-b.test"
  assert_has "heuristic_block.txt" "path-a.test"
  assert_has "heuristic_block.txt" "exact.test"
  assert_has "regex_block.txt" "regex-a\.test"
  assert_has "pattern_block.txt" "wild-a.*"
  assert_has "rewrite.txt" "hosts-rw.test|NOERROR;A;1.2.3.4"
  assert_has "rewrite.txt" "rw-b.test|NXDOMAIN"
  assert_has "dnsrules.conf" "address=/block-a.test/"
  assert_has "hosts" "0.0.0.0 block-a.test"
  assert_has "hosts" "0.0.0.0 www.block-a.test"
  assert_not_has "hosts" "0.0.0.0 allow-a.test"
  assert_not_has "hosts" "0.0.0.0 allow-b.test"
  assert_not_has "hosts" "0.0.0.0 badf-a.test"
  assert_not_has "hosts" "0.0.0.0 both-a.test"
  assert_not_has "hosts" "0.0.0.0 dnsmasq-d.test"

  # ---- cosmetic / 注入 ----
  assert_has "cosmetic_hide.txt" "cosmetic.test##.ad"
  assert_has "cosmetic_hide.txt" "cosmetic.test,other.test##.sponsor"
  assert_has "cosmetic_hide.txt" "##.generic-banner"
  assert_has "cosmetic_unhide.txt" "cosmetic.test##.allowed"
  assert_has "scriptlets.txt" "set-constant"
  assert_has "scriptlets.txt" "abort-on-property-read"
  assert_has "css_inject.txt" ".z { display:none }"
  assert_has "ext_css.txt" "div:has(> .ad)"
  assert_has "html_filter.txt" 'script[data-src="b"]'

  # ---- verify ----
  v=$(engine verify)
  redb=$(numf "$v" redundant_block)
  reda=$(numf "$v" redundant_allow)
  cf=$(numf "$v" conflicts)
  [ "${redb:-1}" = "0" ] && ok || bad "verify 报告冗余拦截规则: $redb"
  [ "${reda:-1}" = "0" ] && ok || bad "verify 报告冗余放行规则: $reda"
  echo "     verify: 拦截/放行同域覆盖 $cf 处（adblock 语义下属正常，放行优先）"
}

# ============================================================
round2() {
  hr; echo "轮次 2/7  幂等性（重复编译输出一致）"; hr
  conf_default
  engine build >/dev/null 2>&1
  h1=$(cat "$OUT/block.txt" "$OUT/allow.txt" "$OUT/rewrite.txt" "$OUT/hosts" 2>/dev/null \
       | grep -v '生成时间' | md5sum 2>/dev/null | cut -d' ' -f1)
  engine build >/dev/null 2>&1
  h2=$(cat "$OUT/block.txt" "$OUT/allow.txt" "$OUT/rewrite.txt" "$OUT/hosts" 2>/dev/null \
       | grep -v '生成时间' | md5sum 2>/dev/null | cut -d' ' -f1)
  if [ -n "$h1" ] && [ "$h1" = "$h2" ]; then ok; else bad "重复编译输出不一致 ($h1 vs $h2)"; fi
  # 记录数稳定
  r1=$(numf "$(engine stats)" records)
  engine build >/dev/null 2>&1
  r2=$(numf "$(engine stats)" records)
  [ "$r1" = "$r2" ] && ok || bad "重复编译记录数漂移 $r1 -> $r2"
  # hosts 排序确定性
  s1=$(grep -v '^#' "$OUT/hosts" 2>/dev/null | md5sum 2>/dev/null | cut -d' ' -f1)
  engine build >/dev/null 2>&1
  s2=$(grep -v '^#' "$OUT/hosts" 2>/dev/null | md5sum 2>/dev/null | cut -d' ' -f1)
  [ -n "$s1" ] && [ "$s1" = "$s2" ] && ok || bad "hosts 数据行不确定 ($s1 vs $s2)"
}

# ============================================================
round3() {
  hr; echo "轮次 3/7  作用域严格模式（\$client）"; hr
  printf 'ENGINE_HEURISTIC=1\nENGINE_STRICT_SCOPE=1\nENGINE_CLIENT=10.0.0.5\nHOSTS_EXTRA=www\n' > "$DATA/config/sy.conf"
  engine build >/dev/null 2>&1
  res=$(field "$(engine test scope-a.test)" result)
  [ "$res" = "block" ] && ok || bad "client 匹配时应拦截, 实际 $res"

  printf 'ENGINE_HEURISTIC=1\nENGINE_STRICT_SCOPE=1\nENGINE_CLIENT=192.168.1.9\nHOSTS_EXTRA=www\n' > "$DATA/config/sy.conf"
  engine build >/dev/null 2>&1
  res=$(field "$(engine test scope-a.test)" result)
  [ "$res" = "none" ] && ok || bad "client 不匹配时应放行, 实际 $res"
  assert_not_has "hosts" "0.0.0.0 scope-a.test"
  conf_default
}

# ============================================================
round4() {
  hr; echo "轮次 4/7  启发式域名开关"; hr
  printf 'ENGINE_HEURISTIC=0\nENGINE_STRICT_SCOPE=0\nHOSTS_EXTRA=www\n' > "$DATA/config/sy.conf"
  engine build >/dev/null 2>&1
  assert_not_has "hosts" "0.0.0.0 path-a.test"
  assert_not_has "hosts" "0.0.0.0 exact.test"
  assert_has "hosts" "0.0.0.0 block-a.test"
  assert_has "hosts" "0.0.0.0 wild-b.test"

  printf 'ENGINE_HEURISTIC=1\nENGINE_STRICT_SCOPE=0\nHOSTS_EXTRA=www,www2,m\n' > "$DATA/config/sy.conf"
  engine build >/dev/null 2>&1
  assert_has "hosts" "0.0.0.0 www2.block-a.test"
  assert_has "hosts" "0.0.0.0 m.block-a.test"
  conf_default
  engine build >/dev/null 2>&1
}

# ============================================================
round5() {
  hr; echo "轮次 5/7  大规模性能（20000 条规则）"; hr
  big="$DATA/cache/dns/list_big.txt"
  : > "$big"
  i=1
  while [ "$i" -le 20000 ]; do
    printf '||d%s.perf.test^\n' "$i" >> "$big"
    i=$((i + 1))
  done
  cp "$DATA/config/lists.conf" "$DATA/config/lists.conf.bak"
  printf 'big|http://example.invalid/big.txt|1|perf\n' >> "$DATA/config/lists.conf"

  t0=$(date +%s)
  engine build >/dev/null 2>&1
  t1=$(date +%s)
  dt=$((t1 - t0))

  n=$(wc -l < "$OUT/block.txt" 2>/dev/null | tr -d ' ')
  [ -z "$n" ] && n=0
  if [ "$n" -ge 20000 ]; then ok; else bad "大规模拦截数量不足: $n"; fi
  echo "     20000 条规则编译耗时 ${dt}s, 拦截域 $n 个"
  if [ "$dt" -le 180 ]; then ok; else bad "编译耗时过长: ${dt}s"; fi

  t0=$(date +%s)
  res=$(field "$(engine test d19999.perf.test)" result)
  t1=$(date +%s)
  [ "$res" = "block" ] && ok || bad "大规模命中失败: d19999.perf.test -> $res"
  echo "     单次域名诊断耗时 $((t1 - t0))s"

  mv -f "$DATA/config/lists.conf.bak" "$DATA/config/lists.conf"
  rm -f "$big"
  engine build >/dev/null 2>&1
}

# ============================================================
round6() {
  hr; echo "轮次 6/7  多语法覆盖统计"; hr
  conf_default
  engine build >/dev/null 2>&1
  syn=$(engine syntax)
  for k in adblock cosmetic scriptlet hosts dnsmasq regex dnsrewrite plain-domain css-inject html-filter extended-css; do
    v=$(numf "$syn" "$k")
    if [ -n "${v:-}" ] && [ "$v" -gt 0 ]; then ok; else bad "语法 $k 计数缺失或为 0 (got '${v:-}')"; fi
  done
  echo "     语法分布: $syn"
  inv=$(numf "$syn" invalid)
  [ -n "${inv:-}" ] && ok || bad "syntax 未返回 invalid 字段"
}

# ============================================================
round7() {
  hr; echo "轮次 7/7  畸形输入健壮性"; hr
  fz="$DATA/cache/dns/list_fuzz.txt"
  cat > "$fz" <<'EOF'
||
@@
$$
$$$%%%
###
|||
::::
$
||a b c^
||||
//
[]
##
#@#
||x^$dnsrewrite=
address=//
0.0.0.0
local=/
server=/
$important
!@#!@#!@#
		
||test^$,,,,
EOF
  cp "$DATA/config/lists.conf" "$DATA/config/lists.conf.bak"
  printf 'fuzz|http://example.invalid/fuzz.txt|1|fuzz\n' >> "$DATA/config/lists.conf"

  engine build >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then ok; else bad "畸形输入导致编译失败 rc=$rc"; fi

  v=$(engine verify)
  inv=$(numf "$v" invalid)
  if [ -n "${inv:-}" ]; then ok; else bad "verify 未返回 invalid 计数"; fi
  echo "     畸形语料中被识别为无效规则: ${inv:-?} 条"
  assert_has "block.txt" "block-a.test"

  mv -f "$DATA/config/lists.conf.bak" "$DATA/config/lists.conf"
  rm -f "$fz"
  engine build >/dev/null 2>&1
}

# ============================================================
RUN="${1:-all}"
echo "============================================================"
echo " SY-Fusion 融合引擎 · 多轮自检"
echo " 模块目录: $MOD"
echo " 测试沙箱: $TMP"
echo "============================================================"
setup
case "$RUN" in
  1) round1 ;;
  2) round2 ;;
  3) round3 ;;
  4) round4 ;;
  5) round5 ;;
  6) round6 ;;
  7) round7 ;;
  all) round1; round2; round3; round4; round5; round6; round7 ;;
  *) echo "未知轮次: $RUN"; exit 2 ;;
esac

hr
printf '总计: %d 项通过, %d 项失败\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf '失败明细:%s\n' "$FAILED"
  exit 1
fi
echo "全部通过"
exit 0
