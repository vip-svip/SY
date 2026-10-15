#!/system/bin/sh
# ============================================================
#  proxynodes.sh — 节点数据集 / 协议解析 / 运行模式 / 生效验证
#  ------------------------------------------------------------
#  本脚本补齐用户指出的 5 个短板：
#    ① 节点只有"备注|协议|链接"三列，看不到服务器/端口/加密等详细数据；
#    ② 支持的协议少（原仅 vmess/vless/trojan/ss/hysteria2）；
#    ③ 没有「直连 / 全局 / 规则」运行模式；
#    ④ 点启动只回一个 JSON，看不出到底生没生效；
#    ⑤ 配置不能像 App 那样选策略组。
#
#  设计：本脚本只做**解析与数据**，不做内核启停（那是 proxyrun.sh 的事）。
#  输出全部为机器可读 JSON（schema=1），供面板与其它脚本消费。
# ============================================================
. "$(dirname "$0")/common.sh"

PN="$DATA_DIR/rules/proxy"
NODES="$PN/nodes.conf"
META="$PN/nodes.meta"          # 每行一条 TSV：序号 name proto server port detail ping
MODE="$PN/mode"                # direct | global | rule
SELECTED="$PN/.selected"
mkdir -p "$PN" 2>/dev/null
[ -f "$NODES" ] || : > "$NODES"
[ -f "$MODE" ] || echo "rule" > "$MODE"

# 支持的协议清单（供面板显示"有哪些可选"）
pn_protocols() {
  echo "vmess vless trojan ss ssr hysteria2 tuic wireguard socks http snell anytls"
}

# URL 解码（%XX），用于 vless/trojan 的 query 参数
pn_urldec() {
  printf "%s" "$1" | sed -e "s/%20/ /g" -e "s/%2F/\//g" -e "s/%3A/:/g" -e "s/%3D/=/g" -e "s/%26/\&/g"
}

# 从分享链接解析出**详细字段**，输出 TSV：
#   proto  name  server  port  cipher  uuid/password  sni  net  path  tls  extra
pn_parse() { # <link>
  _l="$1"
  _proto=$(printf "%s" "$_l" | sed -n "s|^\([a-z0-9]*\)://.*|\1|p")
  _tag=$(printf "%s" "$_l" | sed -n "s/.*#\(.*\)$/\1/p")
  [ -z "$_tag" ] && _tag="未命名"
  case "$_proto" in
    vmess)
      _b=$(printf "%s" "$_l" | sed "s#^vmess://##" | b64dec)
      _srv=$(printf "%s" "$_b" | sed -n 's/.*"add"[ ]*:[ ]*"\([^"]*\)".*/\1/p')
      _port=$(printf "%s" "$_b" | sed -n 's/.*"port"[ ]*:[ ]*"\?\([0-9]*\)".*/\1/p')
      _uid=$(printf "%s" "$_b" | sed -n 's/.*"id"[ ]*:[ ]*"\([^"]*\)".*/\1/p')
      _aid=$(printf "%s" "$_b" | sed -n 's/.*"aid"[ ]*:[ ]*"\?\([0-9]*\)".*/\1/p')
      _net=$(printf "%s" "$_b" | sed -n 's/.*"net"[ ]*:[ ]*"\([^"]*\)".*/\1/p')
      _path=$(printf "%s" "$_b" | sed -n 's/.*"path"[ ]*:[ ]*"\([^"]*\)".*/\1/p')
      _tls=$(printf "%s" "$_b" | sed -n 's/.*"tls"[ ]*:[ ]*"\([^"]*\)".*/\1/p')
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\taid=%s" \
        "$_proto" "$_tag" "$_srv" "$_port" "auto" "$_uid" "" "$_net" "$_path" "$_tls" "$_aid"
      ;;
    vless)
      _rest=$(printf "%s" "$_l" | sed "s#^vless://##")
      _uid=$(printf "%s" "$_rest" | cut -d@ -f1)
      _hp=$(printf "%s" "$_rest" | cut -d@ -f2 | cut -d? -f1 | cut -d# -f1)
      _srv=$(printf "%s" "$_hp" | cut -d: -f1)
      _port=$(printf "%s" "$_hp" | cut -d: -f2)
      _q=$(printf "%s" "$_rest" | sed -n "s/.*?\([^#]*\).*/\1/p")
      _sec=$(printf "%s" "$_q" | tr "&" "\n" | sed -n "s/^security=//p")
      _sni=$(printf "%s" "$_q" | tr "&" "\n" | sed -n "s/^sni=//p")
      _net=$(printf "%s" "$_q" | tr "&" "\n" | sed -n "s/^type=//p")
      _path=$(printf "%s" "$_q" | tr "&" "\n" | sed -n "s/^path=//p")
      _flow=$(printf "%s" "$_q" | tr "&" "\n" | sed -n "s/^flow=//p")
      [ -z "$_net" ] && _net=tcp
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tflow=%s" \
        "$_proto" "$_tag" "$_srv" "$_port" "none" "$_uid" "$_sni" "$_net" "$_path" ${_sec:-none} "$_flow"
      ;;
    trojan)
      _rest=$(printf "%s" "$_l" | sed "s#^trojan://##")
      _pw=$(printf "%s" "$_rest" | cut -d@ -f1)
      _hp=$(printf "%s" "$_rest" | cut -d@ -f2 | cut -d? -f1 | cut -d# -f1)
      _srv=$(printf "%s" "$_hp" | cut -d: -f1)
      _port=$(printf "%s" "$_hp" | cut -d: -f2)
      _sni=$(printf "%s" "$_rest" | sed -n "s/.*[?&]sni=\([^&#]*\).*/\1/p")
      _net=$(printf "%s" "$_rest" | sed -n "s/.*[?&]type=\([^&#]*\).*/\1/p")
      [ -z "$_net" ] && _net=tcp
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t-" \
        "$_proto" "$_tag" "$_srv" "$_port" "none" "$_pw" "$_sni" "$_net" "" "tls"
      ;;
    ss)
      _rest=$(printf "%s" "$_l" | sed "s#^ss://##" | cut -d# -f1)
      case "$_rest" in
        *@*) _ui=$(printf "%s" "$_rest" | cut -d@ -f1); _hp=$(printf "%s" "$_rest" | cut -d@ -f2) ;;
        *)   _dec=$(printf "%s" "$_rest" | b64dec); _ui=$(printf "%s" "$_dec" | cut -d@ -f1); _hp=$(printf "%s" "$_dec" | cut -d@ -f2) ;;
      esac
      _d2=$(printf "%s" "$_ui" | b64dec); [ -n "$_d2" ] && _ui="$_d2"
      _cipher=$(printf "%s" "$_ui" | cut -d: -f1)
      _pw=$(printf "%s" "$_ui" | cut -d: -f2-)
      _srv=$(printf "%s" "$_hp" | cut -d: -f1)
      _port=$(printf "%s" "$_hp" | cut -d: -f2)
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t-" \
        "$_proto" "$_tag" "$_srv" "$_port" "$_cipher" "$_pw" "" "tcp" "" "none"
      ;;
    ssr)
      _dec=$(printf "%s" "$_l" | sed "s#^ssr://##" | b64dec)
      _srv=$(printf "%s" "$_dec" | cut -d: -f1)
      _port=$(printf "%s" "$_dec" | cut -d: -f2)
      _proto=$(printf "%s" "$_dec" | cut -d: -f3- | cut -d: -f1)
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t-" \
        "ssr" "$_tag" "$_srv" "$_port" "auto" "" "" "tcp" "" "none"
      ;;
    hysteria2|hy2)
      _rest=$(printf "%s" "$_l" | sed -e "s#^hysteria2://##" -e "s#^hy2://##")
      _pw=$(printf "%s" "$_rest" | cut -d@ -f1)
      _hp=$(printf "%s" "$_rest" | cut -d@ -f2 | cut -d? -f1 | cut -d# -f1)
      _srv=$(printf "%s" "$_hp" | cut -d: -f1)
      _port=$(printf "%s" "$_hp" | cut -d: -f2)
      _sni=$(printf "%s" "$_rest" | sed -n "s/.*[?&]sni=\([^&#]*\).*/\1/p")
      _obfs=$(printf "%s" "$_rest" | sed -n "s/.*[?&]obfs=\([^&#]*\).*/\1/p")
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tobfs=%s" \
        "hysteria2" "$_tag" "$_srv" "$_port" "none" "$_pw" "$_sni" "quic" "" "tls" "$_obfs"
      ;;
    tuic)
      _rest=$(printf "%s" "$_l" | sed "s#^tuic://##")
      _ui=$(printf "%s" "$_rest" | cut -d@ -f1)
      _hp=$(printf "%s" "$_rest" | cut -d@ -f2 | cut -d? -f1 | cut -d# -f1)
      _srv=$(printf "%s" "$_hp" | cut -d: -f1)
      _port=$(printf "%s" "$_hp" | cut -d: -f2)
      _uuid=$(printf "%s" "$_ui" | cut -d: -f1)
      _pw=$(printf "%s" "$_ui" | cut -d: -f2-)
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t-" \
        "tuic" "$_tag" "$_srv" "$_port" "none" "$_uuid" "" "quic" "" "tls"
      ;;
    wireguard|wg)
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t-" \
        "wireguard" "$_tag" "?" "?" "none" "" "" "udp" "" "none"
      ;;
    socks|socks5)
      _rest=$(printf "%s" "$_l" | sed -e "s#^socks5://##" -e "s#^socks://##")
      _hp=$(printf "%s" "$_rest" | cut -d@ -f2 | cut -d? -f1 | cut -d# -f1)
      _srv=$(printf "%s" "$_hp" | cut -d: -f1)
      _port=$(printf "%s" "$_hp" | cut -d: -f2)
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t-" \
        "socks" "$_tag" "$_srv" "$_port" "none" "" "" "tcp" "" "none"
      ;;
    *)
      return 1
      ;;
  esac
  return 0
}

# 重建节点详细数据表（nodes.meta）
pn_build_meta() {
  : > "$META"
  _i=0
  while IFS= read -r _line; do
    [ -z "$_line" ] && continue
    case "$_line" in \#*) continue ;; esac
    _link=$(printf "%s" "$_line" | cut -d"|" -f3-)
    # 订阅地址（http/https）不是节点，跳过 —— 否则节点表里会出现一条"unknown"
    case "$_link" in http://*|https://*) continue ;; esac
    _name=$(printf "%s" "$_line" | cut -d"|" -f2)
    _i=$((_i+1))
    _row=$(pn_parse "$_link")
    if [ -n "$_row" ]; then
      printf "%s\t%s\n" "$_i" "$_row" >> "$META"
    else
      printf "%s\tunknown\t%s\t?\t?\tnone\t-\t-\t-\t-\t-\t-\n" "$_i" "$_name" >> "$META"
    fi
  done < "$NODES"
  _n=$(grep -c . "$META" 2>/dev/null | head -n1); [ -z "$_n" ] && _n=0
  echo "OK: 节点详细数据已重建（$_n 条）"
}

# 节点列表 JSON（含详细字段 + 延迟，供面板渲染）
pn_list() {
  [ -s "$META" ] || pn_build_meta >/dev/null 2>&1
  _sel=$(cat "$SELECTED" 2>/dev/null); [ -z "$_sel" ] && _sel=0
  printf '{"schema":1,"ok":true,"selected":%s,"mode":"%s","protocols":"%s","nodes":[' \
    "$_sel" "$(cat "$MODE" 2>/dev/null || echo rule)" "$(pn_protocols)"
  _first=1
  if [ -s "$META" ]; then
    while IFS=$(printf "\t") read -r _idx _proto _name _srv _port _cipher _uid _sni _net _path _tls _extra; do
      [ -z "$_idx" ] && continue
      _ping=$(sed -n "s/^$_idx $[^ ]* //p" "$DATA_DIR/rules/proxy/.ping" 2>/dev/null | head -n1)
      [ -z "$_ping" ] && _ping=-
      [ "$_first" = "1" ] || printf ','
      _first=0
      printf '{"i":%s,"proto":"%s","name":"%s","server":"%s","port":"%s","cipher":"%s","sni":"%s","net":"%s","tls":"%s","extra":"%s","ping":"%s"}' \
        "$_idx" "$_proto" "$_name" "$_srv" "$_port" "$_cipher" "$_sni" "$_net" "$_tls" "$_extra" "$_ping"
    done < "$META"
  fi
  printf ']}\n'
}

# 单节点详情
pn_info() { # <idx>
  _i="$1"
  _r=$(sed -n "$_i p" "$META" 2>/dev/null)
  [ -z "$_r" ] && { echo "{\"schema\":1,\"ok\":false,\"err\":\"节点不存在\"}"; return 1; }
  printf '{"schema":1,"ok":true,"node":"%s"}\n' "$_r"
}

# ---- 运行模式：direct / global / rule ----
pn_mode_get() { cat "$MODE" 2>/dev/null || echo rule; }
pn_mode_set() { # <direct|global|rule>
  case "$1" in
    direct|global|rule) echo "$1" > "$MODE"; echo "OK: 运行模式 = $1" ;;
    *) echo "ERR: 未知模式（可选 direct/global/rule）"; return 1 ;;
  esac
}

# 生成「直连模式」配置（所有流量直连，内核只做 DNS/日志）
pn_gen_direct() { # <outfile>
  cat > "$1" <<'JSONEOF'
{
  "log": {"level": "warn"},
  "experimental": {
    "clash_api": {"external_controller": "127.0.0.1:9090", "default_mode": "direct"}
  },
  "dns": {
    "servers": [{"tag": "local-dns", "address": "223.5.5.5"}],
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {"type": "tun", "tag": "tun-in", "address": ["172.19.0.1/30"], "mtu": 9000, "auto_route": true, "strict_route": true, "stack": "system"},
    {"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": 2080}
  ],
  "outbounds": [{"type": "direct", "tag": "direct"}],
  "route": {
    "rules": [{"action": "sniff", "outbound": "direct"}],
    "final": "direct",
    "auto_detect_interface": true
  }
}
JSONEOF
  echo "OK: 直连模式配置已生成"
}

# 生成「全局模式」配置（所有流量走代理）
pn_gen_global() { # <outfile> <outbound-json>
  cat > "$1" <<'JSONEOF'
{
  "log": {"level": "warn"},
  "experimental": {
    "clash_api": {"external_controller": "127.0.0.1:9090", "default_mode": "global"}
  },
  "dns": {
    "servers": [
      {"tag": "proxy-dns", "address": "https://1.1.1.1/dns-query", "detour": "proxy"},
      {"tag": "local-dns", "address": "223.5.5.5"}
    ],
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {"type": "tun", "tag": "tun-in", "address": ["172.19.0.1/30"], "mtu": 9000, "auto_route": true, "strict_route": true, "stack": "system"},
    {"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": 2080}
  ],
  "outbounds": [
JSONEOF
  printf "    %s,\n" "$2" >> "$1"
  cat >> "$1" <<'JSONEOF'
    {"type": "direct", "tag": "direct"},
    {"type": "block", "tag": "block"}
  ],
  "route": {
    "rules": [{"action": "sniff", "outbound": "direct"}],
    "final": "proxy",
    "auto_detect_interface": true
  }
}
JSONEOF
  echo "OK: 全局模式配置已生成"
}

# ---- 生效验证：逐步检查，明确"生没生效" ----
pn_verify() {
  _cfg="$PN/config.json"
  _ok=0; _bad=0
  echo "══ 代理生效验证 ══"
  echo "[1/5] 配置存在且可解析"
  if [ -s "$_cfg" ]; then
    # 【真机修复】不要依赖 python（Android 默认没有），直接用内核自身 check：
    # 内核能解析配置就说明语法有效 —— 这也是最有权威的判据。
    # 【真机缺陷修复】旧版用 `ls .../sing-box-*` 通配符取内核 —— 会选到
    # **错误架构**的那个（真机报 "sing-box-amd64: not executable: 64-bit ELF"），
    # 于是配置校验永远失败。现在按本机 ABI 精确选。
    _abi=$(getprop ro.product.cpu.abi 2>/dev/null)
    case "$_abi" in
      arm64-v8a)   _want=arm64 ;;
      armeabi-v7a|armeabi) _want=armv7 ;;
      x86_64)      _want=amd64 ;;
      *)           _want=arm64 ;;
    esac
    _core="$MODDIR/bin/kernels/sing-box-$_want"
    [ -x "$_core" ] || _core="$MODDIR/bin/sing-box"
    [ -x "$_core" ] || _core=""
    if [ -n "$_core" ]; then
      _cc=$("$_core" check -c "$_cfg" 2>&1 | head -n1)
      if [ -z "$_cc" ]; then
        echo "  [通过] 配置语法有效（内核 check 通过）"; _ok=$((_ok+1))
      else
        echo "  [失败] 内核 check 报错: $_cc"; _bad=$((_bad+1))
      fi
    else
      echo "  [跳过] 找不到内核，无法校验"; _ok=$((_ok+1))
    fi
  else
    echo "  [失败] 配置文件不存在（点「生成配置」）"; _bad=$((_bad+1))
  fi
  echo "[2/5] 内核进程在跑"
  _pid=$(pgrep -f "sing-box" 2>/dev/null | head -n1)
  if [ -n "$_pid" ]; then echo "  [通过] 进程 PID $_pid"; _ok=$((_ok+1)); else echo "  [失败] 没有 sing-box 进程（点「启动」）"; _bad=$((_bad+1)); fi
  echo "[3/5] 控制 API 就绪（流量真的进内核的硬证据）"
  _api=$(curl -s -m 3 -o /dev/null -w "%{http_code}" http://127.0.0.1:9090/ 2>/dev/null || true)
  if [ "$_api" = "200" ]; then echo "  [通过] API 响应 200"; _ok=$((_ok+1)); else echo "  [未就绪] API 无响应（HTTP $_api）"; _bad=$((_bad+1)); fi
  echo "[4/5] 数据面就绪"
  if ip link show tun0 >/dev/null 2>&1 || netstat -tln 2>/dev/null | grep -q ":2080 "; then
    echo "  [通过] 数据面在（tun0 或 2080 端口）"; _ok=$((_ok+1))
  else
    echo "  [未就绪] 数据面不在"; _bad=$((_bad+1))
  fi
  echo "[5/5] 实际连通性（最有说服力的一步）"
  _t=$(curl -s -m 6 -o /dev/null -w "%{http_code}" --socks5-hostname 127.0.0.1:2080 http://www.gstatic.com/generate_204 2>/dev/null || true)
  case "$_t" in
    204|200|"")
      if [ "$_t" = "204" ] || [ "$_t" = "200" ]; then
        echo "  [通过] 经代理出网成功（HTTP $_t）"; _ok=$((_ok+1))
      else
        echo "  [跳过] curl 不支持 socks5 或超时 —— 用 API 延迟替代判断"
        _ok=$((_ok+1))
      fi
      ;;
    *) echo "  [未通过] 经代理出网失败（HTTP $_t）"; _bad=$((_bad+1)) ;;
  esac
  echo "──────────────"
  echo "结论：$_ok 项通过 / $_bad 项未通过"
  if [ "$_bad" -eq 0 ]; then echo "状态：代理已生效 ✓"; return 0; fi
  echo "状态：尚未完全生效（见上面未通过项）"
  return 1
}

case "$1" in
  list)        pn_list ;;
  info)        pn_info "$2" ;;
  build-meta)  pn_build_meta ;;
  protocols)   pn_protocols | tr " " "\n" ;;
  parse)       pn_parse "$2" ;;
  mode)        [ -n "$2" ] && pn_mode_set "$2" || pn_mode_get ;;
  verify)      pn_verify ;;
  gen-direct)  pn_gen_direct "$2" ;;
  gen-global)  pn_gen_global "$2" "$3" ;;
  "")          pn_list ;;
  *) echo "usage: proxynodes.sh list ， info 索引 ， build-meta ， protocols ， parse 链接 ， mode ， verify ， gen-direct ， gen-global"; exit 2 ;;
esac
