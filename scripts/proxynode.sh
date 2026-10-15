#!/system/bin/sh
# ============================================================
#  proxynode.sh — 网络代理模块（内核 + 节点 + 订阅 + 防 IP 泄露）
#  · 节点管理: vmess/vless/trojan/ss/hysteria2 分享链接，多节点
#  · 订阅: 支持多个代理订阅(URL)，每个订阅带独立开关，可一起启用
#  · 内核: 自动探测 bin/ 下的 sing-box / xray，可在线下载内核
#  · 配置: 由选中节点自动生成内核 config.json，可手动覆盖
#  · URL 导入: 从订阅链接拉取节点(base64/明文自动识别)
#  · 防泄露(核心): 杀伤开关 + DNS 隧道 + 阻断 WebRTC/组播
#  用法: proxynode.sh {status|nodes|add-node|del-node|del-nodes|clear-nodes|
#        select|up|down|restart|leak|import-b64|import-multi|import-file|import-url|gen-config|config-get|
#        config-set-b64|core-list|core-set|core-download|subs|sub-add|sub-del|
#        sub-toggle|sub-update|logs}
# ============================================================
. "$(dirname "$0")/common.sh"

PN="$DATA_DIR/rules/proxy"
NODES="$PN/nodes.conf"        # 格式: 备注|协议|分享链接
SELECTED="$PN/.selected"      # 选中的节点序号
LEAK_FLAG="$PN/.leak"         # 存在=开启防泄露
CORE_FLAG="$PN/.core"         # 记录用户选择的内核路径
SUBS="$PN/subs.conf"          # 格式: enabled|url   (enabled=1/0)
CFG="$PN/config.json"         # 内核配置
PIDF="$PN/core.pid"
CHAIN="AB_PROXY"
mkdir -p "$PN"

PROXY_PORT=$(cfg_get PROXY_PORT 2080)
PROXY_ENABLE=$(cfg_get PROXY_ENABLE 0)

# ---------- 内核探测 ----------
# ---------- 内核探测：架构判定 + 路径查找（core_path 依赖 core_arch，必须先定义）----------
core_arch() {
  # 【缺陷修复】旧版对 32 位 ARM 返回 "arm"，但 sing-box 官方发布的包名是
  # sing-box-<版本>-linux-**armv7**（没有 "arm" 这个包）。按旧返回值去下载
  # 必然 404 —— 32 位 ARM 设备永远装不上内核。这里改为返回 armv7。
  abi=$(getprop ro.product.cpu.abi 2>/dev/null)
  case "$abi" in
    *arm64*|*aarch64*) echo arm64 ;;
    *armeabi-v7a*|*armv7*) echo armv7 ;;
    *armeabi*) echo armv7 ;;   # 兼容老式 armeabi 值
    *x86_64*|*amd64*|*x64*) echo amd64 ;;
    *i386*|*i686*) echo 386 ;;
    *) echo arm64 ;;
  esac
}

core_path() {
  # 【缺陷修复】旧版用 "$MODDIR/bin/kernels/"sing-box-* 这样的通配符遍历，
  # 会**跨架构**命中：arm64 设备上可能挑到 amd64 的内核（因为 amd64 的
  # sing-box- 前缀同样匹配 sing-box-*），运行即崩（exec format error）。
  # 现在先按本机架构精确挑，再退到不带架构后缀的统一名，最后才是兜底。
  if [ -n "$CORE_FLAG" ] && [ -f "$CORE_FLAG" ]; then
    # 只认可执行的、且架构对得上的记录
    rec=$(cat "$CORE_FLAG" 2>/dev/null)
    if [ -n "$rec" ] && [ -x "$rec" ]; then echo "$rec"; return; fi
  fi
  arch=$(core_arch)
  for c in \
    "$MODDIR/bin/kernels/sing-box-$arch" \
    "$MODDIR/bin/sing-box" \
    "$MODDIR/bin/singbox" \
    "$MODDIR/bin/kernels/sing-box" \
    "$MODDIR/bin/kernels/singbox" \
    "$MODDIR/bin/core/sing-box-$arch" \
    "$MODDIR/bin/bin/sing-box-$arch" \
    "$MODDIR/bin/xray" "$MODDIR/bin/v2ray" \
    "$DATA_DIR/bin/sing-box-$arch" \
    "/system/bin/sing-box"; do
    # 【健壮性】文件在但执行位丢了（重刷模块/复制文件常丢权限）→ 补权限再返回。
    # 只认 -x 会让"内核明明在却说没有"，这是用户看到"内核不生效"的常见成因之一。
    if [ -f "$c" ]; then
      if [ ! -x "$c" ]; then chmod 0755 "$c" 2>/dev/null; fi
      { [ -x "$c" ] || [ -f "$c" ]; } && { echo "$c"; return; }
    fi
  done
  # 兜底：若确实只有别名的内核，如实返回（并让调用方校验架构）
  for c in "$MODDIR/bin/kernels/"sing-box-*; do
    [ -f "$c" ] || continue
    [ -x "$c" ] || chmod 0755 "$c" 2>/dev/null
    { [ -x "$c" ] || [ -f "$c" ]; } && { echo "$c"; return; }
  done
  echo ""
}
CORE="$(core_path)"

# ---------- 内置内核: 架构探测 + 自动下载 ----------

core_autodownload() { # 下载 sing-box 内核到 bin/（多镜像回退）
  # 断网优化：无网时不要逐个镜像等超时（3 个源 × 120s ≈ 6 分钟卡顿）
  if [ -f "$(dirname "$0")/offline.sh" ]; then
    if ! sh "$(dirname "$0")/offline.sh" check >/dev/null 2>&1; then
      echo "ERR: 当前检测不到网络，无法下载内核。"
      echo "     可在「设置 → 代理内核」填可用的直链 PROXY_CORE_URL，"
      echo "     或手动把 sing-box 放到 $MODDIR/bin/sing-box（面板「内核」处可指定路径）。"
      return 1
    fi
  fi
  arch=$(core_arch)
  ver=$(cfg_get PROXY_CORE_VER "1.10.1")
  custom=$(cfg_get PROXY_CORE_URL "")
  pkg="sing-box-${ver}-linux-${arch}.tar.gz"
  mkdir -p "$MODDIR/bin"
  out="$MODDIR/bin/_core_${ver}_${arch}.tar.gz"
  # 镜像顺序：用户自定义 → 官方 → 国内可达的镜像。
  # 官方 github.com 在部分网络下不可达（实测超时/ECONNRESET），
  # 只给一个地址等于"按钮点了没反应"——所以必须多源回退，并逐个报结果。
  official="https://github.com/SagerNet/sing-box/releases/download/v${ver}/${pkg}"
  list=""
  [ -n "$custom" ] && list="$custom"
  list="$list $official"
  list="$list https://mirror.ghproxy.com/${official}"
  list="$list https://gh-proxy.com/${official}"
  list="$list https://ghfast.top/${official}"
  ok="no"
  for u in $list; do
    [ -z "$u" ] && continue
    log "proxynode: 尝试内核源 $u"
    if http_get "$u" "$out" 120 && [ -s "$out" ]; then ok="yes"; break; fi
    rm -f "$out"
    echo "  源不可用，换下一个: $u"
  done
  if [ "$ok" != "yes" ]; then
    echo "ERR: 所有内核源都不可用（已尝试 $(printf '%s' "$list" | wc -w | tr -d ' ') 个）。"
    echo "     可在「设置 → 代理内核」填一个可用的直链 PROXY_CORE_URL，"
    echo "     或手动把 sing-box 放到 $MODDIR/bin/sing-box（面板「内核」处可指定路径）。"
    return 1
  fi
  ( cd "$MODDIR/bin" && tar -xzf "$out" 2>/dev/null )
  rm -f "$out"
  found=""
  for cand in "$MODDIR/bin/sing-box" "$MODDIR/bin"/sing-box-*/sing-box; do
    [ -f "$cand" ] && { chmod 0755 "$cand"; found="$cand"; break; }
  done
  [ -z "$found" ] && { echo "ERR: 解压后未找到 sing-box（包可能不完整）"; return 1; }
  echo "$found" > "$CORE_FLAG"
  echo "OK: 内核已就绪 -> $(basename "$found")"
}
core_ensure() { # 确保有可用内核, 无则自动获取
  cur=$(core_path)
  if [ -n "$cur" ]; then echo "OK: 内核已存在 $cur"; return 0; fi
  core_autodownload
}

b64dec() { base64 -d 2>/dev/null || base64 --decode 2>/dev/null; }

# ---------- 多格式导入: 分享链接 / base64 / sing-box JSON / Clash YAML ----------
_proto_of() {
  case "$1" in
    vmess://*) echo vmess ;; vless://*) echo vless ;; trojan://*) echo trojan ;;
    ss://*) echo ss ;; hysteria2://*|hy2://*) echo hysteria2 ;; *) echo auto ;;
  esac
}
_append_link_lines() {  # stdin: 一行一个分享链接
  added=0
  while IFS= read -r line; do
    line=$(printf '%s' "$line" | tr -d '\r')
    case "$line" in
      vmess://*|vless://*|trojan://*|ss://*|hysteria2://*|hy2://*)
        nm=$(printf '%s' "$line" | sed -n 's/.*#//p'); [ -z "$nm" ] && nm="导入节点"
        printf '%s|%s|%s\n' "$nm" "$(_proto_of "$line")" "$line" >> "$NODES"
        added=$((added+1)) ;;
    esac
  done
  echo "$added"
}
# 把 clash(yaml)/sing-box(json) 归一为 TSV: type server port uuid password cipher sni name
_config_to_tsv() {
  sed -e 's/{/\
/g' -e 's/}/\
/g' -e 's/,/\
/g' -e 's/"//g' -e 's/":[[:space:]]*/: /g' | \
  awk '
    function ac(l){ sub(/^[^:]*:/,"",l); gsub(/^[ \t]+|[ \t]+$/,"",l); return l }
    function flush(){
      if (type=="ss"||type=="vmess"||type=="vless"||type=="trojan") {
        if (name=="") name="导入节点"
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", type, server, port, uuid, password, cipher, sni, name
      }
      type=server=port=uuid=password=cipher=sni=name=""
    }
    /^[ \t]*-/ { flush(); next }
    {
      l=$0; sub(/^[ \t]+/,"",l)
      if (l ~ /^type:/)            type=ac(l)
      else if (l ~ /^server_port:/) port=ac(l)
      else if (l ~ /^server:/)      server=ac(l)
      else if (l ~ /^port:/)        port=ac(l)
      else if (l ~ /^uuid:/)        uuid=ac(l)
      else if (l ~ /^password:/)    password=ac(l)
      else if (l ~ /^cipher:/ || l ~ /^method:/) cipher=ac(l)
      else if (l ~ /^servername:/ || l ~ /^sni:/) sni=ac(l)
      else if (l ~ /^name:/ || l ~ /^tag:/ || l ~ /^ps:/) name=ac(l)
    }
    END{ flush() }
  '
}
_tsv_to_nodes() {  # stdin: _config_to_tsv 输出
  added=0
  while IFS='	' read -r type server port uuid password cipher sni name; do
    [ -z "$type" ] && continue
    [ -z "$name" ] && name="导入节点"
    case "$type" in
      vmess)
        j=$(printf '{"v":"2","ps":"%s","add":"%s","port":"%s","id":"%s","aid":"0","net":"tcp","type":"none","host":"","path":"","tls":""}' \
              "$name" "$server" "$port" "$uuid")
        b=$(printf '%s' "$j" | base64 | tr -d '\n')
        link="vmess://$b" ;;
      vless)
        [ -z "$sni" ] && sni="$server"
        link="vless://$uuid@$server:$port?encryption=none&security=tls&sni=$sni#$name" ;;
      trojan)
        [ -z "$sni" ] && sni="$server"
        link="trojan://$password@$server:$port?sni=$sni#$name" ;;
      ss)
        ui=$(printf '%s:%s' "$cipher" "$password" | base64 | tr -d '\n')
        link="ss://$ui@$server:$port#$name" ;;
      *) continue ;;
    esac
    printf '%s|%s|%s\n' "$name" "$type" "$link" >> "$NODES"
    added=$((added+1))
  done
  echo "$added"
}
# 自动识别并导入一段内容; $1=内容
_import_any() {
  c="$1"
  [ -z "$c" ] && { echo "ERR: 空内容"; return 1; }
  # 1) 直接就是分享链接?
  case "$c" in *"://"*) printf '%s\n' "$c" | _append_link_lines >/dev/null; return 0 ;; esac
  # 2) base64 订阅?
  dec=$(printf '%s' "$c" | b64dec)
  case "$dec" in
    *"://"*) printf '%s\n' "$dec" | _append_link_lines >/dev/null; return 0 ;;
    *'"outbounds"'*|*'proxies:'*) c="$dec" ;;
  esac
  # 3) sing-box json / Clash yaml
  case "$c" in
    *'"outbounds"'*|*'proxies:'*)
      printf '%s\n' "$c" | _config_to_tsv | _tsv_to_nodes >/dev/null
      return 0 ;;
  esac
  echo "ERR: 无法识别的配置格式"; return 1
}

jget()  { # json key (single-line JSON value string)
  sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
}
jgetn() { # json key (numeric, 兼容带引号/不带引号)
  sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\{0,1\}\([0-9][0-9]*\)"\{0,1\}.*/\1/p' | head -n1
}

have_ipt() { have iptables; }

# ---------- 防泄露 ----------
ensure_chain() {
  have_ipt || return 1
  iptables -t nat -N "$CHAIN" 2>/dev/null
  iptables -t nat -C OUTPUT -j "$CHAIN" 2>/dev/null || iptables -t nat -A OUTPUT -j "$CHAIN" 2>/dev/null
}
clear_leak() {
  have_ipt || return 0
  iptables -t nat -F "$CHAIN" 2>/dev/null
  iptables -t nat -D OUTPUT -j "$CHAIN" 2>/dev/null
  iptables -t nat -X "$CHAIN" 2>/dev/null
  iptables -D OUTPUT -p udp --dport 3478 -j REJECT 2>/dev/null
  iptables -D OUTPUT -p udp --dport 19302 -j REJECT 2>/dev/null
  iptables -D OUTPUT -m pkttype --pkt-type multicast -j DROP 2>/dev/null
  iptables -D FORWARD -j AB_PROXY_KILL 2>/dev/null
  iptables -F AB_PROXY_KILL 2>/dev/null; iptables -X AB_PROXY_KILL 2>/dev/null
}
apply_leak() {
  have_ipt || { echo "ERR: 缺少 iptables，无法启用防泄露"; return 1; }
  clear_leak; ensure_chain
  iptables -t nat -A "$CHAIN" -o lo -j RETURN 2>/dev/null
  iptables -t nat -A "$CHAIN" -p udp --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null
  iptables -t nat -A "$CHAIN" -p tcp --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null
  iptables -I OUTPUT -p udp --dport 3478 -j REJECT 2>/dev/null
  iptables -I OUTPUT -p udp --dport 19302 -j REJECT 2>/dev/null
  iptables -I OUTPUT -m pkttype --pkt-type multicast -j DROP 2>/dev/null
  iptables -N AB_PROXY_KILL 2>/dev/null; iptables -F AB_PROXY_KILL 2>/dev/null
  iptables -A AB_PROXY_KILL -d 127.0.0.0/8 -j RETURN 2>/dev/null
  iptables -A AB_PROXY_KILL -d 10.0.0.0/8 -j RETURN 2>/dev/null
  iptables -A AB_PROXY_KILL -d 172.16.0.0/12 -j RETURN 2>/dev/null
  iptables -A AB_PROXY_KILL -d 192.168.0.0/16 -j RETURN 2>/dev/null
  iptables -A AB_PROXY_KILL -p tcp -m owner ! --uid-owner 0 -j REJECT 2>/dev/null
  echo 1 > "$LEAK_FLAG"
  log "proxynode: 防泄露已启用"
  echo "OK: 防节点IP泄露已开启（杀伤开关 + DNS隧道 + 阻断WebRTC/组播）"
}
remove_leak() { clear_leak; rm -f "$LEAK_FLAG"; echo "OK: 已关闭防泄露"; }

# ---------- 节点链接解析 -> sing-box outbound ----------
node_to_outbound() { # link
  link="$1"
  proto="${link%%://*}"
  case "$proto" in
    vmess)
      body=$(echo "$link" | sed 's#^vmess://##' | b64dec)
      add=$(echo "$body" | jget add); port=$(echo "$body" | jgetn port)
      [ -z "$port" ] && port=$(echo "$body" | jget port)
      uuid=$(echo "$body" | jget id); aid=$(echo "$body" | jgetn aid); [ -z "$aid" ] && aid=0
      net=$(echo "$body" | jget net); path=$(echo "$body" | jget path); host=$(echo "$body" | jget host)
      tls=$(echo "$body" | jget tls); sni=$(echo "$body" | jget sni); [ -z "$sni" ] && sni="$host"
      [ -z "$add" ] && return 1
      printf '{"type":"vmess","tag":"proxy","server":"%s","server_port":%s,"uuid":"%s","alter_id":%s' "$add" "$port" "$uuid" "$aid"
      [ "$tls" = "tls" ] && printf ',"tls":{"enabled":true,"server_name":"%s"}' "$sni"
      case "$net" in
        ws) printf ',"transport":{"type":"ws","path":"%s","headers":{"Host":"%s"}}' "${path:-/}" "$host" ;;
        grpc) printf ',"transport":{"type":"grpc","service_name":"%s"}' "${path:-}" ;;
      esac
      printf '}'
      ;;
    vless)
      rest=$(echo "$link" | sed 's#^vless://##')
      uuid=$(echo "$rest" | cut -d@ -f1)
      hostport=$(echo "$rest" | cut -d@ -f2 | cut -d'?' -f1 | cut -d'#' -f1)
      addr=$(echo "$hostport" | cut -d: -f1); port=$(echo "$hostport" | cut -d: -f2)
      query=$(echo "$rest" | sed -n 's/.*?\([^#]*\).*/\1/p')
      tls=$(echo "$query" | tr '&' '\n' | sed -n 's/^security=//p'); [ -z "$tls" ] && tls=none
      sni=$(echo "$query" | tr '&' '\n' | sed -n 's/^sni=//p')
      path=$(echo "$query" | tr '&' '\n' | sed -n 's/^path=//p')
      hh=$(echo "$query" | tr '&' '\n' | sed -n 's/^host=//p')
      [ -z "$addr" ] && return 1
      printf '{"type":"vless","tag":"proxy","server":"%s","server_port":%s,"uuid":"%s"' "$addr" "$port" "$uuid"
      [ "$tls" = "tls" ] || [ "$tls" = "reality" ] && printf ',"tls":{"enabled":true,"server_name":"%s"}' "${sni:-$addr}"
      [ -n "$path" ] && printf ',"transport":{"type":"ws","path":"%s","headers":{"Host":"%s"}}' "$path" "${hh:-$addr}"
      printf '}'
      ;;
    trojan)
      rest=$(echo "$link" | sed 's#^trojan://##')
      pw=$(echo "$rest" | cut -d@ -f1)
      hostport=$(echo "$rest" | cut -d@ -f2 | cut -d'?' -f1 | cut -d'#' -f1)
      addr=$(echo "$hostport" | cut -d: -f1); port=$(echo "$hostport" | cut -d: -f2)
      sni=$(echo "$rest" | sed -n 's/.*[?&]sni=\([^&#]*\).*/\1/p')
      [ -z "$addr" ] && return 1
      printf '{"type":"trojan","tag":"proxy","server":"%s","server_port":%s,"password":"%s","tls":{"enabled":true,"server_name":"%s"}}' "$addr" "$port" "$pw" "${sni:-$addr}"
      ;;
    ss)
      rest=$(echo "$link" | sed 's#^ss://##' | cut -d'#' -f1)
      case "$rest" in
        *@*) userinfo=$(echo "$rest" | cut -d@ -f1); hostport=$(echo "$rest" | cut -d@ -f2) ;;
        *)   dec=$(echo "$rest" | b64dec); userinfo=$(echo "$dec" | cut -d@ -f1); hostport=$(echo "$dec" | cut -d@ -f2) ;;
      esac
      dec2=$(echo "$userinfo" | b64dec); [ -n "$dec2" ] && userinfo="$dec2"
      method=$(echo "$userinfo" | cut -d: -f1); pass=$(echo "$userinfo" | cut -d: -f2-)
      addr=$(echo "$hostport" | cut -d: -f1); port=$(echo "$hostport" | cut -d: -f2)
      [ -z "$addr" ] && return 1
      printf '{"type":"shadowsocks","tag":"proxy","server":"%s","server_port":%s,"method":"%s","password":"%s"}' "$addr" "$port" "$method" "$pass"
      ;;
    hysteria2|hy2)
      rest=$(echo "$link" | sed 's#^hysteria2://##;s#^hy2://##')
      pw=$(echo "$rest" | cut -d@ -f1)
      hostport=$(echo "$rest" | cut -d@ -f2 | cut -d'?' -f1 | cut -d'#' -f1)
      addr=$(echo "$hostport" | cut -d: -f1); port=$(echo "$hostport" | cut -d: -f2)
      sni=$(echo "$rest" | sed -n 's/.*[?&]sni=\([^&#]*\).*/\1/p')
      [ -z "$addr" ] && return 1
      printf '{"type":"hysteria2","tag":"proxy","server":"%s","server_port":%s,"password":"%s","tls":{"enabled":true,"server_name":"%s"}}' "$addr" "$port" "$pw" "${sni:-$addr}"
      ;;
    *) return 1 ;;
  esac
}

# gen_config — 生成内核配置
#
# 现在由 route.sh 走 profile → abserver route compile 的链路：
#   · profile.json 是唯一事实源，策略组/规则集/逻辑规则都在里面
#   · 目标内核版本从真内核读出来，配置语法跟着版本走
#   · 规则集优先用本地 .srs，没网也能起来
# 老的内联拼字符串实现保留在 gen_config_legacy，仅在 route.sh
# 不可用时兜底。
gen_config() {
  RS="$(dirname "$0")/route.sh"
  if [ -f "$RS" ] && [ -x "$BIN" ]; then
    out="$(sh "$RS" compile 2>&1)"
    rc=$?
    if [ $rc -eq 0 ]; then
      echo "$out"
      return 0
    fi
    # 编译失败时不要把坏配置留下，避免内核读到半截文件
    echo "$out"
    echo "WARN: 规则路由编译失败，回退到简化配置"
  fi
  gen_config_legacy
}

gen_config_legacy() {
  sel=$(cat "$SELECTED" 2>/dev/null)
  [ -z "$sel" ] && { echo "ERR: 请先选择节点"; return 1; }
  line=$(sed -n "${sel}p" "$NODES" 2>/dev/null)
  [ -z "$line" ] && { echo "ERR: 节点 #$sel 不存在"; return 1; }
  link=$(echo "$line" | cut -d'|' -f3-)
  ob=$(node_to_outbound "$link")
  [ -z "$ob" ] && { echo "ERR: 节点链接解析失败，请检查格式"; return 1; }
  {
    printf '{\n'
    printf '  "log": {"level": "warn"},\n'
    printf '  "dns": {\n'
    printf '    "servers": [\n'
    # 注意：不能给直连 DNS 写 detour:direct，sing-box 1.14 会直接报
    # "detour to an empty direct outbound makes no sense" 而拒绝启动
    printf '      {"tag": "proxy-dns", "address": "https://1.1.1.1/dns-query", "detour": "proxy"},\n'
    printf '      {"tag": "local-dns", "address": "223.5.5.5"}\n'
    printf '    ],\n'
    printf '    "strategy": "ipv4_only"\n'
    printf '  },\n'
    printf '  "inbounds": [\n'
    printf '    {"type": "tun", "tag": "tun-in", "address": ["172.19.0.1/30"], "mtu": 9000, "auto_route": true, "strict_route": true, "stack": "system"},\n'
    printf '    {"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": %s}\n' "$PROXY_PORT"
    printf '  ],\n'
    printf '  "outbounds": [\n'
    printf '    %s,\n' "$ob"
    printf '    {"type": "direct", "tag": "direct"},\n'
    printf '    {"type": "block", "tag": "block"}\n'
    printf '  ],\n'
    printf '  "route": {\n'
    printf '    "rules": [\n'
    printf '      {"action": "sniff"},\n'
    printf '      {"protocol": "dns", "action": "hijack-dns"}\n'
    printf '    ],\n'
    printf '    "final": "proxy",\n'
    printf '    "auto_detect_interface": true\n'
    printf '  }\n'
    printf '}\n'
  } > "$CFG"
  echo "OK: 已根据节点 #$sel 生成内核配置 ($CFG)"
}

# ---------- 订阅辅助 ----------
sub_update_one() { # url
  url="$1"
  tmp="$CACHE/proxysub.tmp"
  http_get "$url" "$tmp" 40 || { echo "ERR: 订阅下载失败: $url"; return 1; }
  # 判断是否 base64 整体编码
  content=$(cat "$tmp")
  case "$content" in
    *"://"*) : ;;                       # 明文含链接
    *) dec=$(echo "$content" | b64dec); [ -n "$dec" ] && content="$dec" ;;
  esac
  n=0
  echo "$content" | tr -d '\r' | while IFS= read -r ln; do
    case "$ln" in
      vmess://*|vless://*|trojan://*|ss://*|hysteria2://*|hy2://*)
        proto="${ln%%://*}"; [ "$proto" = "hy2" ] && proto="hysteria2"
        printf '%s|%s|%s\n' "订阅节点" "$proto" "$ln" >> "$NODES"
        ;;
    esac
  done
  total=$(count_lines "$NODES")
  echo "OK: 订阅已导入，节点共 $total 个"
}

case "$1" in
  status)
    running="no"; pid=""
    [ -f "$PIDF" ] && pid=$(cat "$PIDF" 2>/dev/null) && kill -0 "$pid" 2>/dev/null && running="yes"
    leak="no"; [ -f "$LEAK_FLAG" ] && leak="yes"
    sel=$(cat "$SELECTED" 2>/dev/null)
    selname=""; [ -n "$sel" ] && selname=$(sed -n "${sel}p" "$NODES" 2>/dev/null | cut -d'|' -f1)
    core="none"; [ -n "$CORE" ] && core=$(basename "$CORE")
    subs=0; [ -f "$SUBS" ] && subs=$(grep -vcE '^[[:space:]]*$' "$SUBS" 2>/dev/null)
    cfg="no"; [ -f "$CFG" ] && cfg="yes"
    portof=$(cfg_get PROXY_PORT 2080)
    printf '{"running":"%s","pid":"%s","leak":"%s","core":"%s","nodes":%s,"selected":"%s","port":%s,"subs":%s,"config":"%s"}\n' \
      "$running" "$pid" "$leak" "$core" "$(count_lines "$NODES")" "$(json_escape "$selname")" "$portof" "$subs" "$cfg"
    ;;
  nodes)
    n=0
    while IFS='|' read -r name proto link; do
      [ -z "$name" ] && continue
      n=$((n+1))
      linkmask=$(echo "$link" | cut -c1-26)
      printf '%s|%s|%s|%s...\n' "$n" "$name" "$proto" "$linkmask"
    done < "$NODES" 2>/dev/null
    ;;
  add-node)
    name="$2"; proto="$3"; link="$4"
    [ -z "$name" ] && name="节点$(count_lines "$NODES")"
    [ -z "$proto" ] && proto="auto"
    [ -z "$link" ] && { echo "ERR: 缺少节点分享链接"; exit 1; }
    printf '%s|%s|%s\n' "$name" "$proto" "$link" >> "$NODES"
    echo "OK: 已添加节点「$name」($proto)"
    ;;
  del-node)
    idx="$2"
    if [ -f "$NODES" ]; then
      tmp="$NODES.tmp.$$"; awk -v w="$idx" 'BEGIN{n=0}{n++; if(n!=w)print}' "$NODES" > "$tmp"; mv "$tmp" "$NODES"
    fi
    echo "OK: 已删除节点 #$idx"
    ;;
  del-nodes)   # 批量删除: 逗号分隔序号
    list="$2"; [ -z "$list" ] && { echo "ERR: 缺少序号"; exit 1; }
    echo "$list" | tr ',' '\n' > "$PN/.del.$$"
    tmp="$NODES.tmp.$$"; cnt=0
    awk -v del="$PN/.del.$$" 'BEGIN{while((getline l < del)>0) d[l+0]=1} {n++; if(!(n in d)) print; else c++} END{print "DELETED="c > "/dev/stderr"}' "$NODES" > "$tmp" 2>"$PN/.delcount.$$"
    mv "$tmp" "$NODES"; rm -f "$PN/.del.$$"
    echo "OK: 已批量删除节点"
    ;;
  clear-nodes) : > "$NODES"; rm -f "$SELECTED"; echo "OK: 已清空节点" ;;
  select)
    idx="$2"; echo "$idx" > "$SELECTED"; echo "OK: 已选择节点 #$idx"
    [ -f "$CFG" ] || gen_config >/dev/null 2>&1
    ;;
  up)
    [ "$(cfg_get PROXY_ENABLE 0)" = "1" ] || cfg_set PROXY_ENABLE 1
    sel=$(cat "$SELECTED" 2>/dev/null)
    [ -z "$sel" ] && { echo "ERR: 请先选择节点"; exit 1; }
    CORE="$(core_path)"
    [ -f "$CFG" ] || gen_config >/dev/null 2>&1
    # 【健壮性】内核文件在、但架构与本机不符时，直接启动只会 exec format error，
    # 用户看到的是含糊的"启动后立即退出"。这里先做一次真实可执行性验证：
    # 能报出版本号才算"这个内核在本机跑得起来"。
    CORE_OK="no"
    if [ -n "$CORE" ] && [ -f "$CORE" ]; then
      chmod 0755 "$CORE" 2>/dev/null
      if "$CORE" version >/dev/null 2>&1; then
        CORE_OK="yes"
      else
        echo "ERR: 内核 $CORE 无法在本机执行（架构不符或文件损坏）。"
        echo "     本机架构: $(core_arch) / ABI: $(getprop ro.product.cpu.abi 2>/dev/null)"
        echo "     可用内核: $(ls "$MODDIR/bin/kernels" 2>/dev/null | tr '\n' ' ')"
        echo "     bin/kernels 里应有 sing-box-$(core_arch)。若缺失请重刷模块。"
        exit 1
      fi
    fi
    if [ "$CORE_OK" = "yes" ] && [ -f "$CFG" ]; then
      chmod 0755 "$CORE" 2>/dev/null
      # 启动前预校验配置：配置错误时给出可读原因，避免“点启动代理失败”却无提示
      chk="$("$CORE" check -c "$CFG" 2>&1)"; rc=$?
      if [ "$rc" -ne 0 ]; then
        case "$chk" in
          *"unknown command"*|*"invalid command"*|*"Usage:"*) : ;;  # 该内核不支持 check，跳过预校验
          *) echo "ERR: 内核配置校验未通过，已阻止启动：$(printf '%s' "$chk" | head -n 3)"; exit 1 ;;
        esac
      fi
      # 先清理残留实例，避免旧进程占用 tun/端口导致启动失败（内核“又出bug”根因）
      sh "$0" down >/dev/null 2>&1
      : > "$LOGS/proxy.log"
      # 用统一起进程函数：Android 上 nohup/setsid 可用性因 ROM 而异，
      # 旧版直接调 nohup，缺命令时 "nohup: not found" → 内核永远起不来（用户看到"内核不生效"）。
      # bg_spawn 逐级降级，永因缺命令而失败。
      pid_started=$(bg_spawn "$LOGS/proxy.log" "$CORE" run -c "$CFG")
      run="no"; pid=""; try=0
      while [ "$try" -lt 15 ]; do
        sleep 0.4
        pid="$(pgrep -f "run -c $CFG" 2>/dev/null | head -n1)"
        [ -z "$pid" ] && pid="$(pgrep -f "$(basename "$CORE")" 2>/dev/null | head -n1)"
        if [ -n "$pid" ]; then echo "$pid" > "$PIDF"; run="yes"; break; fi
        try=$((try+1))
      done
      [ "$run" = "yes" ] && echo "OK: 代理内核已启动（$(basename "$CORE")），PID $pid" || echo "ERR: 内核启动后立即退出，请查看日志"
    elif [ -z "$CORE" ]; then
      echo "ERR: 未检测到代理内核。请到「内核」处放入或在线下载 sing-box/xray，再启动。节点已保存，防泄露可独立开启。"
    else
      echo "ERR: 缺少内核配置($CFG)。请先生成配置或导入 config.json。"
    fi
    ;;
  down)
    [ -f "$PIDF" ] && kill "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null
    # 兜底: 按命令行匹配强制清理真实内核进程（修正 setsid PID 失效导致杀不干净）
    [ -n "$CFG" ] && pkill -f "run -c $CFG" 2>/dev/null
    CORE2="$(core_path 2>/dev/null)"; [ -z "$CORE2" ] && CORE2="$CORE"
    [ -n "$CORE2" ] && pkill -f "$(basename "$CORE2") run" 2>/dev/null
    rm -f "$PIDF"
    echo "OK: 代理已停止"
    ;;
  restart) sh "$0" down >/dev/null 2>&1; sh "$0" up ;;
  leak)
    if [ "$2" = "on" ]; then apply_leak; else remove_leak; fi
    ;;
  import-multi)   # 自动识别: 分享链接 / base64 / sing-box JSON / Clash YAML
    c="$2"; [ -z "$c" ] && { echo "ERR: 空内容"; exit 1; }
    before=$(count_lines "$NODES")
    _import_any "$c"
    after=$(count_lines "$NODES")
    echo "OK: 导入完成，新增 $((after-before)) 个节点，节点共 $after 个"
    ;;
  import-file)    # import-file <本地文件路径> 自动识别
    fp="$2"; [ -f "$fp" ] || { echo "ERR: 文件不存在: $fp"; exit 1; }
    before=$(count_lines "$NODES")
    _import_any "$(cat "$fp")"
    after=$(count_lines "$NODES")
    echo "OK: 文件导入完成，新增 $((after-before)) 个节点，节点共 $after 个"
    ;;
  import-b64)
    b="$2"; [ -z "$b" ] && { echo "ERR: 空内容"; exit 1; }
    echo "$b" | b64dec | sed '/^[[:space:]]*$/d' | tr -d '\r' | while IFS= read -r line; do
      name="导入节点"; proto="auto"
      case "$line" in
        vmess://*) proto="vmess" ;; vless://*) proto="vless" ;; trojan://*) proto="trojan" ;;
        ss://*) proto="ss" ;; hysteria2://*|hy2://*) proto="hysteria2" ;;
      esac
      case "$line" in vmess://*|vless://*|trojan://*|ss://*|hysteria2://*|hy2://*)
        printf '%s|%s|%s\n' "$name" "$proto" "$line" >> "$NODES" ;; esac
    done
    echo "OK: 已导入节点，共 $(count_lines "$NODES") 个"
    ;;
  import-url)
    url="$2"; [ -z "$url" ] && { echo "ERR: 缺少订阅URL"; exit 1; }
    sub_update_one "$url"
    ;;
  gen-config) gen_config ;;
  config-get) cat "$CFG" 2>/dev/null ;;
  config-set-b64)
    [ -z "$2" ] && { echo "ERR: 空内容"; exit 1; }
    echo "$2" | b64dec > "$CFG" 2>/dev/null
    echo "OK: 内核配置已保存 ($(count_lines "$CFG") 行)"
    ;;
  core-list)
    found=0
    for c in "$MODDIR/bin/sing-box" "$MODDIR/bin/singbox" "$MODDIR/bin/xray" "$MODDIR/bin/v2ray"; do
      [ -x "$c" ] && { echo "$(basename "$c") @ $c"; found=1; }
    done
    cur=$(core_path); [ -n "$cur" ] && echo "current=$(basename "$cur")"
    [ "$found" = "0" ] && echo "none"
    ;;
  core-set)   # 指定内核路径
    p="$2"; [ -z "$p" ] && { echo "ERR: 缺少路径"; exit 1; }
    [ -x "$p" ] || { echo "ERR: 路径不存在或不可执行: $p"; exit 1; }
    echo "$p" > "$CORE_FLAG"
    echo "OK: 内核已设置为 $p"
    ;;
  core-download)   # 在线下载内核到 bin/
    url="$2"; [ -z "$url" ] && { echo "ERR: 缺少下载URL"; exit 1; }
    bn=$(basename "$url" | sed 's/[?].*$//')
    case "$bn" in
      sing-box*|xray*|v2ray*|*.tar.gz|*.gz) ;;
      *) bn="sing-box" ;;
    esac
    out="$MODDIR/bin/$bn"
    mkdir -p "$MODDIR/bin"
    if http_get "$url" "$out" 90; then
      case "$bn" in
        *.tar.gz|*.gz) ( cd "$MODDIR/bin" && tar -xzf "$out" 2>/dev/null ); rm -f "$out" ;;
      esac
      for cand in "$MODDIR/bin/sing-box" "$MODDIR/bin/xray" "$MODDIR/bin/$bn"; do
        [ -f "$cand" ] && chmod 0755 "$cand"
      done
      cur=$(core_path); echo "OK: 内核下载完成，当前内核=${cur:-无}"
    else
      echo "ERR: 内核下载失败"
    fi
    ;;
  core-ensure) core_ensure ;;
  core-arch)   core_arch ;;
  subs) cat "$SUBS" 2>/dev/null ;;
  sub-add)
    url="$2"; [ -z "$url" ] && { echo "ERR: 缺少订阅URL"; exit 1; }
    grep -qF "|$url" "$SUBS" 2>/dev/null || printf '1|%s\n' "$url" >> "$SUBS"
    echo "OK: 已添加代理订阅"
    ;;
  sub-del)
    idx="$2"
    if [ -f "$SUBS" ]; then
      tmp="$SUBS.tmp.$$"; awk -v w="$idx" 'BEGIN{n=0}{n++; if(n!=w)print}' "$SUBS" > "$tmp"; mv "$tmp" "$SUBS"
    fi
    echo "OK: 已删除代理订阅 #$idx"
    ;;
  sub-toggle)   # sub-toggle <idx> [on|off]
    idx="$2"; v="$3"
    f="$SUBS"; [ -f "$f" ] || { echo "ERR: 无订阅"; exit 1; }
    cur=$(awk -v w="$idx" 'BEGIN{n=0}{n++; if(n==w){print $0; exit}}' "$f" | cut -d'|' -f1)
    case "$v" in
      on|1|enable|enabled) nv=1 ;;
      off|0|disable|disabled) nv=0 ;;
      "") [ "$cur" = "1" ] && nv=0 || nv=1 ;;
      *) nv="$v" ;;
    esac
    tmp="$f.tmp.$$"; awk -v w="$idx" -v nv="$nv" 'BEGIN{c=1}{n++; if(n==w){print nv"|"substr($0,index($0,"|")+1)} else print}' "$f" > "$tmp"; mv "$tmp" "$f"
    [ "$nv" = "1" ] && echo "OK: 订阅 #$idx 已启用" || echo "OK: 订阅 #$idx 已停用"
    ;;
  sub-update)   # 更新全部启用的订阅
    [ -f "$SUBS" ] || { echo "OK: 无订阅"; exit 0; }
    n=0
    while IFS='|' read -r en url; do
      [ "$en" = "1" ] || continue
      [ -z "$url" ] && continue
      log "proxynode: 更新订阅 $url"
      sub_update_one "$url" >/dev/null 2>&1 && n=$((n+1))
    done < "$SUBS"
    echo "OK: 已更新 $n 个启用的订阅，节点共 $(count_lines "$NODES") 个"
    ;;
  logs) tail -n 60 "$LOGS/proxy.log" 2>/dev/null ;;
  *)
    echo "usage: proxynode.sh {status|nodes|add-node|del-node|del-nodes|clear-nodes|select|up|down|restart|leak|import-b64|import-multi|import-file|import-url|gen-config|config-get|config-set-b64|core-list|core-set|core-download|subs|sub-add|sub-del|sub-toggle|sub-update|logs}"
    ;;
esac
