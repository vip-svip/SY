#!/bin/sh
# ============================================================
#  tests/run_panel_api.sh — 面板 API 端到端（本地真实 HTTP）
#
#  起一个真的 abserver serve，用 curl 打全部新老端点，
#  校验 JSON 形状与鉴权，确保「界面能拿到它需要的数据」。
#
#  用法: sh tests/run_panel_api.sh <abserver 可执行文件>
#        省略参数时自动在 bin/ 下找 host 版二进制
# ============================================================
set -u

MOD="$(cd "$(dirname "$0")/.." && pwd)"
BINSRC="${1:-}"
if [ -z "$BINSRC" ]; then
  for c in "$MOD/bin/abserver.host" "$MOD/bin/abserver.exe" "$MOD/bin/abserver"; do
    [ -x "$c" ] && { BINSRC="$c"; break; }
  done
fi
[ -n "$BINSRC" ] && [ -e "$BINSRC" ] || { echo "ERR: 找不到 abserver 可执行文件"; exit 2; }

T="${SYADGH_API_DIR:-/tmp/syadgh-api}"
rm -rf "$T"; mkdir -p "$T/mod/bin" "$T/mod/scripts" "$T/data/config" \
  "$T/data/rules/proxy" "$T/data/logs" "$T/data/cache" "$T/data/run"

# ---- 搭一个最小可用模块目录（scripts + bin + webroot）----
cp "$MOD"/scripts/*.sh "$T/mod/scripts/" 2>/dev/null
cp "$MOD"/scripts/*.awk "$T/mod/scripts/" 2>/dev/null
cp -r "$MOD/webroot" "$T/mod/webroot"
cp "$BINSRC" "$T/mod/bin/abserver.real"
# Windows 上必须带 .exe 才能真正执行；用一层 sh 包装让名字固定成 abserver
cat > "$T/mod/bin/abserver" <<'WRAP'
#!/bin/sh
exec "$(dirname "$0")/abserver.real" "$@"
WRAP
chmod +x "$T/mod/bin/abserver" "$T/mod/bin/abserver.real" 2>/dev/null
printf 'PROXY_PORT=2080\nCLASH_API_PORT=19090\nPROXY_CORE_VER=1.14.3\nPROXY_LOG_LEVEL=warn\n' \
  > "$T/data/config/sy.conf"

# ---- 造一份 profile（2 节点 / 2 组 / 5 规则 / DNS）----
cat > "$T/data/rules/proxy/profile.json" <<'JSON'
{
  "nodes": [
    {"name":"HK-01","type":"vmess","server":"1.2.3.4","port":443,"uuid":"11111111-2222-3333-4444-555555555555","network":"ws","ws_path":"/x","tls":true},
    {"name":"JP-01","type":"trojan","server":"5.6.7.8","port":8443,"password":"pw","sni":"a.example.com"}
  ],
  "groups": [
    {"name":"PROXY","type":"select","proxies":["auto","HK-01","DIRECT"]},
    {"name":"auto","type":"url-test","proxies":["HK-01","JP-01"],"url":"http://www.gstatic.com/generate_204","interval":300}
  ],
  "rule_sets": [],
  "rules": [
    {"kind":"DOMAIN-SUFFIX","payload":"ads.example.com","policy":"REJECT","enabled":true},
    {"kind":"DOMAIN-KEYWORD","payload":"track","policy":"REJECT","enabled":true},
    {"kind":"GEOSITE","payload":"cn","policy":"DIRECT","enabled":true},
    {"kind":"IP-CIDR","payload":"10.0.0.0/8","policy":"DIRECT","enabled":true},
    {"kind":"DST-PORT","payload":"8080","policy":"DIRECT","enabled":true},
    {"kind":"MATCH","payload":"*","policy":"PROXY","enabled":true}
  ],
  "dns": {
    "enabled": true,
    "servers": [
      {"tag":"local","address":"223.5.5.5"},
      {"tag":"remote","address":"https://1.1.1.1/dns-query","detour":"proxy"}
    ],
    "final": "local",
    "strategy": "prefer_ipv4"
  },
  "general": {
    "log_level": "warn", "mixed_port": 2080, "tun_enabled": true,
    "clash_api": true, "clash_api_port": 19090, "sing_box_version": "1.14.3"
  }
}
JSON

PORT="${SYADGH_API_PORT:-18848}"
TOK="APITOKEN123"
# 必须把数据目录同时喂给 serve 与它 fork 出来的脚本，
# 否则脚本会去读 /data/adb/SY（真机路径），测试就测了个寂寞。
AB_DATA_DIR="$T/data" "$T/mod/bin/abserver" serve -addr "127.0.0.1:$PORT" -webroot "$T/mod/webroot" \
  -moddir "$T/mod" -datadir "$T/data" -token "$TOK" > "$T/serve.log" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null' EXIT INT TERM

P=0; F=0
ck() { if [ "$2" = "$3" ]; then P=$((P+1)); printf '  ok   %s\n' "$1";
       else F=$((F+1)); printf '  FAIL %s  实际=[%s] 期望=[%s]\n' "$1" "$2" "$3"; fi; }
has() { if printf '%s' "$2" | grep -qF -- "$3"; then P=$((P+1)); printf '  ok   %s\n' "$1";
        else F=$((F+1)); printf '  FAIL %s  (输出中无 [%s])\n' "$1" "$3"; fi; }
hasnt() { if printf '%s' "$2" | grep -qF -- "$3"; then F=$((F+1)); printf '  FAIL %s  (输出中不应有 [%s])\n' "$1" "$3";
          else P=$((P+1)); printf '  ok   %s\n' "$1"; fi; }

U="http://127.0.0.1:$PORT"
get() { curl -s --max-time 25 "$U$1" 2>/dev/null; }
post() { curl -s --max-time 60 -X POST -H 'Content-Type: application/json' -d "$2" "$U$1" 2>/dev/null; }
# /api/route 的返回是 {"ok":true,"out":"<脚本原始输出>"}，脚本输出里的引号
# 会被 JSON 转义成 \" —— 断言前必须先还原，否则永远匹配不到。
# /api/clash 是直出 JSON，不经这一步。
unw() { sed -e 's/\\"/"/g'; }
getr() { get "$1" | unw; }

# 等监听
i=0
while [ $i -lt 40 ]; do
  curl -s --max-time 2 "$U/api/ping" >/dev/null 2>&1 && break
  i=$((i+1)); sleep 0.25
done

echo "== 鉴权 =="
ck "无 token 被拒（401）" "$(curl -s -o /dev/null -w '%{http_code}' "$U/api/route?sub=status-json")" "401"
ck "ping 不需要 token" "$(printf '%s' "$(get /api/ping)" | grep -c '"ok":true')" "1"

echo "== 静态面板 =="
HTML="$(get "/index.html?token=$TOK")"
has "index.html 已注入面板 token" "$HTML" "__SY_TOKEN__"
has "index.html 含极客控制台导航" "$HTML" 'data-tab="route-proxy"'
has "index.html 含内核日志页" "$HTML" 'id="rlTerm"'

echo "== /api/route =="
R="$(getr "/api/route?sub=status-json&token=$TOK")"
has "status-json 含 ruleset_count" "$R" '"ruleset_count"'
has "status-json 含 mixed_port" "$R" '"mixed_port":2080'
has "status-json 含 clash_port" "$R" '"clash_port":19090'
has "status-json 含 core_size" "$R" '"core_size"'

R="$(getr "/api/route?sub=summary&token=$TOK")"
has "summary 含 counts" "$R" '"counts"'
has "summary 节点数=2" "$R" '"nodes": 2'
has "summary 规则数=6" "$R" '"rules": 6'
has "summary 含 node_types" "$R" '"node_types"'
has "summary 含 general" "$R" '"mixed_port": 2080'

R="$(getr "/api/route?sub=profile&token=$TOK")"
has "profile 可读" "$R" '"HK-01"'

R="$(getr "/api/route?sub=rulesets&token=$TOK")"
has "rulesets 含 items" "$R" '"items"'
has "rulesets 含 builtin 目录" "$R" '"builtin"'

R="$(getr "/api/route?sub=lint&a=-json&token=$TOK")"
has "lint 返回 issues" "$R" '"issues"'

echo "== /api/route 多参数（POST JSON args）=="
R="$(post "/api/route?sub=test&token=$TOK" '{"args":["-json","-domain","ads.example.com"]}' | unw)"
has "test 命中 REJECT" "$R" '"policy": "REJECT"'
has "test 报 matched=true" "$R" '"matched": true'
R="$(post "/api/route?sub=test&token=$TOK" '{"args":["-json","-domain","www.google.com"]}' | unw)"
has "test 未命中走兜底 PROXY" "$R" '"policy": "PROXY"'
R="$(post "/api/route?sub=test&token=$TOK" '{"args":["-json","-domain","x.test","-port","8080"]}' | unw)"
has "test 端口规则生效" "$R" '"policy": "DIRECT"'

echo "== /api/route set-profile（POST 原样 JSON 体）=="
R="$(curl -s --max-time 60 -X POST -H 'Content-Type: application/json' \
     --data-binary @"$T/data/rules/proxy/profile.json" \
     "$U/api/route?sub=set-profile&token=$TOK" 2>/dev/null | unw)"
has "set-profile 接受 JSON 体" "$R" "OK"

echo "== /api/route compile =="
R="$(getr "/api/route?sub=compile&token=$TOK")"
has "compile 成功" "$R" "OK"
has "编译产物已生成" "$(ls "$T/data/rules/proxy/config.json" 2>/dev/null || echo no)" "$T/data/rules/proxy/config.json"

echo "== /api/clash =="
R="$(get "/api/clash?sub=status&token=$TOK")"
has "内核未运行时 status 明确报错" "$R" '"ok":false'
R="$(get "/api/clash?sub=unknown&token=$TOK")"
has "未知子命令列出可用项" "$R" '"subs"'
has "子命令清单含 delay" "$R" 'delay'

echo "== /api/exec =="
R="$(post "/api/exec?token=$TOK" '{"cmd":"route","args":["status-json"]}')"
has "exec 走白名单脚本" "$R" '"out"'

echo
echo "== 结果: 通过 $P / 失败 $F =="
[ $F -eq 0 ] || exit 1
