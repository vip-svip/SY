#!/system/bin/sh
# ============================================================
#  run_kernel_compat.sh — 用真实 sing-box 内核校验编译产物
#
#  为什么需要这份测试：
#    配置语法随内核版本断代（DNS 服务器写法、default_domain_resolver、
#    入站 sniff、download_detour 各自在不同版本引入/移除）。
#    只有让真内核去 check 并且真的 run 起来，才能证明产出的配置
#    是"能跑的"，而不是"看起来像"的。
#
#  用法:
#    tests/run_kernel_compat.sh
#    SY_ABSERVER=/path/abserver SY_KERNELS=/path/to/kernels tests/run_kernel_compat.sh
#
#  环境变量:
#    SY_ABSERVER   abserver 路径（默认自动在仓库根目录找）
#    SY_KERNELS    内核目录，子目录名形如 sing-box-<ver>-<os>-<arch>
#    SY_RULESET_DIR  预置的 .srs 目录（可选，用于离线用例）
#
#  退出码: 0 全通过；1 有失败
# ============================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)

ABSERVER="${SY_ABSERVER:-}"
if [ -z "$ABSERVER" ]; then
  for c in "$ROOT/abserver" "$ROOT/abserver.exe" "$ROOT/bin/abserver"; do
    [ -x "$c" ] && ABSERVER="$c" && break
  done
fi
KERNELS="${SY_KERNELS:-/c/Users/admin/AppData/Local/Temp/sbtest}"

# 临时目录：Android 上 /tmp 只读，优先 /data/local/tmp
TMPD="${TMPDIR:-}"
if [ -z "$TMPD" ] || [ ! -d "$TMPD" ] || [ ! -w "$TMPD" ]; then
  TMPD=/data/local/tmp
fi
if [ ! -d "$TMPD" ] || [ ! -w "$TMPD" ]; then
  TMPD="$ROOT/.compat-tmp"
fi
mkdir -p "$TMPD" 2>/dev/null

PASS=0
FAIL=0
SKIP=0
WARN=0

ok()   { PASS=$((PASS+1)); echo "  [ok]    $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  [FAIL]  $1"; }
skip() { SKIP=$((SKIP+1)); echo "  [skip]  $1"; }
warn() { WARN=$((WARN+1)); echo "  [warn]  $1"; }

echo "== sing-box 内核兼容性测试 =="
echo "abserver : $ABSERVER"
echo "kernels  : $KERNELS"
echo "tmp      : $TMPD"
if [ -z "$ABSERVER" ] || [ ! -x "$ABSERVER" ]; then
  echo "ERR: 找不到 abserver（用 SY_ABSERVER 指定）"
  exit 2
fi

WORK="$TMPD/sy-compat"
rm -rf "$WORK" 2>/dev/null
mkdir -p "$WORK"

# ---------- 自备规则集 ----------
# 测试要能独立跑：自己抓一份 .srs 到本地，既验证抓取功能，
# 又让离线启动用例有真实素材。抓不到就退化成不含规则集的用例。
RSDIR="${SY_RULESET_DIR:-$WORK/rs}"
HAVE_RS=0
if [ -n "${SY_RULESET_DIR:-}" ] && [ -d "$SY_RULESET_DIR" ]; then
  HAVE_RS=1
else
  echo
  echo "-- 抓取规则集（用于离线用例）"
  if "$ABSERVER" route fetch-rules -dir "$RSDIR" \
        -codes "cn,category-ads-all,geolocation-!cn" -geoip-codes "cn" 2>&1 | sed 's/^/   /'; then
    HAVE_RS=1
  else
    echo "   [warn] 规则集抓取失败，离线用例将退化为最小配置"
  fi
fi

# ---------- 测试用 profile ----------
# 覆盖：多协议节点、多类型策略组、全部可编译规则类型、
#       逻辑规则(AND/NOT)、规则集引用、多形态 DNS
if [ "$HAVE_RS" = "1" ]; then
  # Windows 路径含反斜杠，直接塞进 JSON 会破坏转义，统一转成正斜杠
  RSDIR_JSON=$(printf '%s' "$RSDIR" | sed 's|\\|/|g')
  RULESET_BLOCK='{"name":"my-ads","type":"local","format":"binary","path":"'"$RSDIR_JSON"'/geosite-category-ads-all.srs","enabled":true}'
  RULESET_RULE='{"kind":"RULE-SET","payload":"my-ads","policy":"REJECT","enabled":true},'
else
  RULESET_BLOCK=''
  RULESET_RULE=''
fi

cat > "$WORK/profile.json" <<JSON
{
  "nodes": [
    {"name":"HK-Trojan","type":"trojan","server":"127.0.0.1","port":1,"password":"p","sni":"a.example.com","tls":true},
    {"name":"JP-VMess","type":"vmess","server":"127.0.0.1","port":1,"uuid":"b831381d-6324-4d53-ad4f-8cda48b30811","alter_id":0,"tls":true,"network":"ws","ws_path":"/v","ws_host":"b.example.com"},
    {"name":"SG-SS","type":"shadowsocks","server":"127.0.0.1","port":1,"method":"aes-256-gcm","password":"q"},
    {"name":"US-VLESS","type":"vless","server":"127.0.0.1","port":1,"uuid":"b831381d-6324-4d53-ad4f-8cda48b30811","tls":true,"network":"grpc","grpc_service":"gs"}
  ],
  "groups": [
    {"name":"PROXY","type":"select","proxies":["auto","HK-Trojan","JP-VMess","SG-SS","US-VLESS","DIRECT"]},
    {"name":"auto","type":"url-test","proxies":["HK-Trojan","JP-VMess","SG-SS"],"url":"http://127.0.0.1:1/generate_204","interval":300,"tolerance":50},
    {"name":"Streaming","type":"select","proxies":["HK-Trojan","JP-VMess"]}
  ],
  "rule_sets": [${RULESET_BLOCK}],
  "rules": [
    {"kind":"DOMAIN-SUFFIX","payload":"example.com","policy":"PROXY","enabled":true},
    {"kind":"DOMAIN","payload":"exact.test","policy":"PROXY","enabled":true},
    {"kind":"DOMAIN-KEYWORD","payload":"ads","policy":"REJECT","enabled":true},
    {"kind":"DOMAIN-WILDCARD","payload":"*.test.io","policy":"PROXY","enabled":true},
    {"kind":"IP-CIDR","payload":"10.0.0.0/8","policy":"DIRECT","no_resolve":true,"enabled":true},
    {"kind":"GEOIP","payload":"cn","policy":"DIRECT","enabled":true},
    {"kind":"GEOSITE","payload":"category-ads-all","policy":"REJECT","enabled":true},
    {"kind":"GEOSITE","payload":"cn","policy":"DIRECT","enabled":true},
    ${RULESET_RULE}
    {"kind":"AND","payload":"","policy":"PROXY","mode":"and","enabled":true,
     "rules":[{"kind":"DOMAIN-SUFFIX","payload":"a.com","enabled":true},{"kind":"NETWORK","payload":"tcp","enabled":true}]},
    {"kind":"NOT","payload":"","policy":"DIRECT","mode":"not","enabled":true,
     "rules":[{"kind":"DOMAIN-SUFFIX","payload":"b.com","enabled":true}]},
    {"kind":"DEST-PORT","payload":"8443","policy":"PROXY","enabled":true},
    {"kind":"SRC-PORT","payload":"1000-2000","policy":"PROXY","enabled":true},
    {"kind":"PROCESS-NAME","payload":"com.example.app","policy":"PROXY","enabled":true},
    {"kind":"NETWORK","payload":"udp","policy":"REJECT","enabled":true},
    {"kind":"MATCH","payload":"*","policy":"PROXY","enabled":true}
  ],
  "dns": {
    "enabled": true,
    "servers": [
      {"tag":"ns1","address":"223.5.5.5","detour":"direct"},
      {"tag":"ns2","address":"https://1.1.1.1/dns-query","detour":"proxy"},
      {"tag":"ns3","address":"local"}
    ],
    "final":"ns1",
    "strategy":"prefer_ipv4",
    "fake_ip": true,
    "fake_ip_range":"198.18.0.0/15",
    "fake_ip_filter":["example.com"]
  },
  "general": {"log_level":"warn","mixed_port":0,"tun_enabled":false,"clash_api":false}
}
JSON

PORT=12100
for K in "$KERNELS"/sing-box-*; do
  [ -d "$K" ] || continue
  BIN=""
  for c in "$K/sing-box" "$K/sing-box.exe"; do
    [ -x "$c" ] && BIN="$c" && break
  done
  [ -n "$BIN" ] || continue

  VER=$("$BIN" version 2>/dev/null | head -1 | sed -n 's/^sing-box version *//p' | tr -d '\r' | tr -d ' ')
  [ -n "$VER" ] || VER=$(basename "$K" | sed -n 's/sing-box-\([0-9.]*\)-.*/\1/p')
  PORT=$((PORT+1))
  echo
  echo "-- 内核 $VER  (port $PORT)"

  CFG="$WORK/sb-$VER.json"
  ERR="$WORK/compile-$VER.err"

  # ---- 1) 编译（远程规则集）----
  if ! "$ABSERVER" route compile -profile "$WORK/profile.json" -out "$CFG" \
        -sb-version "$VER" -mixed-port "$PORT" -quiet 2>"$ERR"; then
    bad "$VER 编译失败: $(head -2 "$ERR" | tr '\n' ' ')"
    continue
  fi
  ok "$VER 编译产出配置"

  # ---- 2) 静态校验 ----
  if "$BIN" check -c "$CFG" >"$WORK/check-$VER.log" 2>&1; then
    ok "$VER check 通过"
  else
    bad "$VER check 失败: $(head -2 "$WORK/check-$VER.log" | tr '\n' ' ')"
    continue
  fi

  # ---- 3) 非法残留字段 ----
  BADFIELD=""
  for pat in '_no_resolve' '"interval": *[0-9]' 'geosite:' 'geoip:' '"detour": *"direct"'; do
    grep -qE "$pat" "$CFG" 2>/dev/null && BADFIELD="$BADFIELD $pat"
  done
  if [ -n "$BADFIELD" ]; then
    bad "$VER 配置含非法字段:$BADFIELD"
  else
    ok "$VER 无非法字段残留"
  fi

  # ---- 4) 本地规则集 + 离线启动（硬性要求）----
  #  模块的核心场景就是"手机上没网"，这条必须过。
  CFGL="$WORK/sb-$VER-local.json"
  if [ "$HAVE_RS" = "1" ]; then
    if "$ABSERVER" route compile -profile "$WORK/profile.json" -out "$CFGL" \
          -sb-version "$VER" -mixed-port "$PORT" -ruleset-dir "$RSDIR" -quiet 2>"$ERR"; then
      N_LOCAL=$(grep -c '"type": "local"' "$CFGL" 2>/dev/null)
      if [ "${N_LOCAL:-0}" -ge 2 ]; then
        ok "$VER 本地规则集已内联（$N_LOCAL 个）"
      else
        warn "$VER 本地规则集命中偏少（$N_LOCAL 个）"
      fi
    else
      bad "$VER 本地规则集编译失败: $(head -1 "$ERR")"
    fi
  else
    skip "$VER 离线用例（规则集不可得）"
  fi

  RUNCFG="$CFG"
  [ -f "$CFGL" ] && RUNCFG="$CFGL"

  "$BIN" run -c "$RUNCFG" >"$WORK/run-$VER.log" 2>&1 &
  RPID=$!
  i=0
  STARTED=0
  while [ $i -lt 15 ]; do
    sleep 1
    grep -qi "FATAL" "$WORK/run-$VER.log" 2>/dev/null && break
    if grep -qiE "started|inbound/mixed.*started|listening at" "$WORK/run-$VER.log" 2>/dev/null; then
      STARTED=1; break
    fi
    kill -0 $RPID 2>/dev/null || break
    i=$((i+1))
  done

  if grep -qi "FATAL" "$WORK/run-$VER.log" 2>/dev/null; then
    MSG=$(head -2 "$WORK/run-$VER.log" | tr '\n' ' ')
    # 网络类失败不算配置问题：本机环境可能根本连不上 CDN
    case "$MSG" in
      *"rule-set"*"Get "*|*"download"*|*"dial tcp"*|*"no such host"*)
        warn "$VER 启动受阻于网络（非配置问题）: $(echo "$MSG" | cut -c1-100)" ;;
      *) bad "$VER 启动 FATAL: $(echo "$MSG" | cut -c1-140)" ;;
    esac
  elif [ "$STARTED" = "1" ]; then
    ok "$VER 可正常启动并监听"
  elif kill -0 $RPID 2>/dev/null; then
    ok "$VER 进程存活（未打印启动日志）"
  else
    bad "$VER 启动异常退出"
  fi
  kill $RPID 2>/dev/null
  wait $RPID 2>/dev/null
  sleep 1
done

echo
echo "== 结果: 通过 $PASS / 失败 $FAIL / 警告 $WARN / 跳过 $SKIP =="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
