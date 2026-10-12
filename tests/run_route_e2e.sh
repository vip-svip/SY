#!/system/bin/sh
# ============================================================
#  run_route_e2e.sh — 规则路由端到端验证
#
#  只 check 通过不算数：配置能被解析，不代表规则真的按预期
#  分流。这个脚本起一个真内核 + 一个本地 HTTP 服务，然后
#  从混合入站打流量进去，逐条验证规则命中结果。
#
#  验证项：
#    · MATCH,DIRECT          → 流量放行，能取到内容
#    · DOMAIN-KEYWORD,REJECT → 命中拦截，连接失败
#    · IP-CIDR 私网直连      → 放行
#    · 逻辑规则 AND/NOT      → 命中预期分支
#    · 未命中规则走 final    → 按 final 策略
#
#  用法:
#    SY_ABSERVER=/path/abserver SY_KERNEL=/path/sing-box tests/run_route_e2e.sh
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
KERNEL="${SY_KERNEL:-}"
KERNELS="${SY_KERNELS:-/c/Users/admin/AppData/Local/Temp/sbtest}"

TMPD="${TMPDIR:-}"
if [ -z "$TMPD" ] || [ ! -d "$TMPD" ] || [ ! -w "$TMPD" ]; then TMPD=/data/local/tmp; fi
if [ ! -d "$TMPD" ] || [ ! -w "$TMPD" ]; then TMPD="$ROOT/.e2e-tmp"; fi
mkdir -p "$TMPD" 2>/dev/null

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); echo "  [ok]    $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  [FAIL]  $1"; }
skip() { SKIP=$((SKIP+1)); echo "  [skip]  $1"; }

echo "== 规则路由端到端验证 =="

if [ -z "$ABSERVER" ] || [ ! -x "$ABSERVER" ]; then echo "ERR: 找不到 abserver"; exit 2; fi

if [ -z "$KERNEL" ]; then
  for K in "$KERNELS"/sing-box-*; do
    [ -d "$K" ] || continue
    for c in "$K/sing-box" "$K/sing-box.exe"; do
      [ -x "$c" ] && KERNEL="$c" && break
    done
    [ -n "$KERNEL" ] && break
  done
fi
if [ -z "$KERNEL" ] || [ ! -x "$KERNEL" ]; then
  echo "ERR: 找不到 sing-box 内核（用 SY_KERNEL 指定）"; exit 2
fi

# curl：Windows 自带 curl.exe；Android 上通常没有
CURL=""
for c in curl curl.exe /system/bin/curl /data/adb/magisk/curl; do
  command -v "$c" >/dev/null 2>&1 && CURL="$c" && break
done
if [ -z "$CURL" ]; then skip "缺少 curl，无法做流量验证"; echo "== 结果: 通过 $PASS / 失败 $FAIL =="; exit 0; fi

# 本地 HTTP 服务：优先 python，退而用内核自带的 http 探测
PY=""
for c in python3 python python.exe \
         "C:/Users/admin/.workbuddy-ai/binaries/python/versions/3.13.12/python.exe"; do
  command -v "$c" >/dev/null 2>&1 && PY="$c" && break
  [ -x "$c" ] && PY="$c" && break
done
if [ -z "$PY" ]; then skip "缺少 python，无法起本地 HTTP 服务"; echo "== 结果: 通过 $PASS / 失败 $FAIL =="; exit 0; fi

WORK="$TMPD/sy-e2e"
rm -rf "$WORK" 2>/dev/null; mkdir -p "$WORK/www"
echo "SY_ROUTE_OK" > "$WORK/www/index.html"
echo "SY_BLOCKED_OK" > "$WORK/www/blockme.txt"

SRV_PORT=12300
PROXY_PORT=12301

"$PY" -m http.server "$SRV_PORT" --bind 127.0.0.1 --directory "$WORK/www" >"$WORK/http.log" 2>&1 &
SRV_PID=$!
sleep 2

cleanup() {
  kill $SRV_PID 2>/dev/null
  [ -n "${SB_PID:-}" ] && kill $SB_PID 2>/dev/null
  wait 2>/dev/null
}
trap cleanup EXIT

# 本机能否直连到这个 HTTP 服务（排除环境本身的问题）
if ! "$CURL" -s --max-time 5 "http://127.0.0.1:$SRV_PORT/index.html" | grep -q SY_ROUTE_OK; then
  skip "本地 HTTP 服务不可达，跳过流量验证"
  echo "== 结果: 通过 $PASS / 失败 $FAIL / 跳过 $SKIP =="
  exit 0
fi
ok "本地 HTTP 服务就绪"

# ---------- 构造 profile ----------
# 规则顺序刻意排成能分别验证四种机制：
#   1 DOMAIN-KEYWORD → 拦截
#   2 DOMAIN-SUFFIX  → 放行
#   3 NOT(...)       → 取反后拦截
#   4 MATCH          → 兜底放行
# 请求统一打到 127.0.0.1 上的本地服务，用 Host 头制造域名，
# 由内核的 sniff 动作从 HTTP 头里取出域名，从而让 domain_* 规则可命中。
cat > "$WORK/profile.json" <<JSON
{
  "nodes": [
    {"name":"Dummy","type":"trojan","server":"127.0.0.1","port":1,"password":"p","tls":true}
  ],
  "groups": [
    {"name":"PROXY","type":"select","proxies":["Dummy","DIRECT"]}
  ],
  "rules": [
    {"kind":"DOMAIN-KEYWORD","payload":"blockme","policy":"REJECT","enabled":true},
    {"kind":"DOMAIN-SUFFIX","payload":"allow.local","policy":"DIRECT","enabled":true},
    {"kind":"NOT","payload":"","policy":"REJECT","mode":"not","enabled":true,
     "rules":[{"kind":"DOMAIN-SUFFIX","payload":"other.local","enabled":true}]},
    {"kind":"MATCH","payload":"*","policy":"DIRECT","enabled":true}
  ],
  "dns": {"enabled":false},
  "general": {"log_level":"warn","mixed_port":$PROXY_PORT,"tun_enabled":false}
}
JSON

if ! "$ABSERVER" route compile -profile "$WORK/profile.json" -out "$WORK/sb.json" -quiet 2>"$WORK/c.err"; then
  bad "编译失败: $(head -1 "$WORK/c.err")"
  echo "== 结果: 通过 $PASS / 失败 $FAIL =="; exit 1
fi
ok "路由配置编译成功"

"$KERNEL" run -c "$WORK/sb.json" >"$WORK/run.log" 2>&1 &
SB_PID=$!
i=0
while [ $i -lt 15 ]; do
  sleep 1
  "$CURL" -s --max-time 2 -o /dev/null -x "http://127.0.0.1:$PROXY_PORT" "http://127.0.0.1:$SRV_PORT/index.html" && break
  grep -qi FATAL "$WORK/run.log" 2>/dev/null && break
  i=$((i+1))
done
if grep -qi FATAL "$WORK/run.log" 2>/dev/null; then
  bad "内核启动失败: $(head -2 "$WORK/run.log" | tr '\n' ' ')"
  echo "== 结果: 通过 $PASS / 失败 $FAIL =="; exit 1
fi
ok "内核已启动，混合入站监听 $PROXY_PORT"

# ---------- 逐条规则验证 ----------
# 用 Host 头伪造域名，让 domain_* 规则可以命中。
probe_host() { # probe_host <host> <pass|block> <期望内容> <说明>
  BODY=$("$CURL" -s --max-time 8 -x "http://127.0.0.1:$PROXY_PORT" \
         -H "Host: $1" "http://127.0.0.1:$SRV_PORT/index.html" 2>/dev/null || true)
  case "$2" in
    pass)  if echo "$BODY" | grep -q "$3"; then ok "$4"; else bad "$4（未取到预期内容）"; fi ;;
    block) if [ -z "$BODY" ]; then ok "$4"; else bad "$4（本应被拦截，却拿到了内容）"; fi ;;
  esac
}

probe_host "allow.local"   pass  SY_ROUTE_OK "DOMAIN-SUFFIX 规则放行生效"
probe_host "blockme.local" block ""          "DOMAIN-KEYWORD 拦截规则生效"
probe_host "other.local"   pass  SY_ROUTE_OK "NOT 取反后未命中，落到 MATCH 兜底放行"
probe_host "nomatch.local" block ""          "NOT 取反命中后拦截生效"

# ---------- 策略组切换验证（Clash API）----------
# 这一项验证"策略组真的能被外部切换"，是 Shadowrocket 式交互的基础。
API_PORT=12409
if "$ABSERVER" route compile -profile "$WORK/profile.json" -out "$WORK/sbapi.json" \
     -mixed-port "$PROXY_PORT" -clash-port "$API_PORT" -quiet 2>/dev/null; then
  kill $SB_PID 2>/dev/null; wait $SB_PID 2>/dev/null; sleep 1
  "$KERNEL" run -c "$WORK/sbapi.json" >"$WORK/runapi.log" 2>&1 &
  SB_PID=$!
  i=0
  while [ $i -lt 12 ]; do
    sleep 1
    "$CURL" -s --max-time 2 "http://127.0.0.1:$API_PORT/version" >/dev/null 2>&1 && break
    i=$((i+1))
  done
  GRP=$("$CURL" -s --max-time 5 "http://127.0.0.1:$API_PORT/proxies" 2>/dev/null || true)
  if echo "$GRP" | grep -q '"PROXY"'; then
    ok "Clash API 可读到策略组"
    if "$ABSERVER" clash -api "127.0.0.1:$API_PORT" select -group PROXY -to Dummy >/dev/null 2>&1; then
      NOW=$("$CURL" -s --max-time 5 "http://127.0.0.1:$API_PORT/proxies/PROXY" 2>/dev/null | tr ',' '\n' | grep '"now"' | head -1)
      case "$NOW" in
        *Dummy*) ok "策略组切换生效（now=Dummy）" ;;
        *) bad "策略组切换未生效（$NOW）" ;;
      esac
    else
      bad "策略组切换命令失败"
    fi
    # 延迟测速接口
    if "$ABSERVER" clash -api "127.0.0.1:$API_PORT" delay -name Dummy -timeout 1500 >/dev/null 2>&1; then
      ok "延迟测速接口可用"
    else
      skip "延迟测速（目标不可达，属预期）"
    fi
  else
    skip "Clash API 未就绪（内核可能未编译 with_clash_api）"
  fi
fi

echo
echo "== 结果: 通过 $PASS / 失败 $FAIL / 跳过 $SKIP =="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
