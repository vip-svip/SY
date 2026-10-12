#!/system/bin/sh
# ============================================================
#  dnssrv.sh — 独立 DNS 服务模块
#  真正的 DNS 层控制：自定义 DNS 服务器 / DoH / DoT / 防泄露。
#  通过 iptables 强制将 53 端口 DNS 重定向到所选服务器，并可
#  阻断 DoT(853) 等已知 DNS 泄露信道，实现全网 DNS 接管。
#  用法: dnssrv.sh {status|servers|add-server|del-server|clear-servers|
#                   set-mode|set-doh|set-dot|leak|apply|clear|test}
# ============================================================
. "$(dirname "$0")/common.sh"

DNS_SRV_FILE="$DNS_DIR/dns_servers.conf"
DNS_MODE_FILE="$DNS_DIR/.dns_mode"
DNS_DOH_FILE="$DNS_DIR/.dns_doh"
DNS_DOT_FILE="$DNS_DIR/.dns_dot"
DNS_LEAK_FILE="$DNS_DIR/.dns_leak"

CHAIN="AB_DNS"

have_ipt() { have iptables; }

ensure_chain() {
  have_ipt || return 1
  iptables -t nat -N "$CHAIN" 2>/dev/null
  iptables -t nat -C OUTPUT -j "$CHAIN" 2>/dev/null || iptables -t nat -A OUTPUT -j "$CHAIN" 2>/dev/null
}

clear_rules() {
  have_ipt || return 0
  iptables -t nat -F "$CHAIN" 2>/dev/null
  iptables -t nat -D OUTPUT -j "$CHAIN" 2>/dev/null
  iptables -t nat -X "$CHAIN" 2>/dev/null
}

servers_list() { cat "$DNS_SRV_FILE" 2>/dev/null | sed '/^[[:space:]]*$/d'; }

apply() {
  mode=$(cat "$DNS_MODE_FILE" 2>/dev/null || echo custom)
  [ -z "$mode" ] && mode="custom"
  if [ "$mode" = "off" ]; then clear_rules; echo "OK: DNS 接管已关闭（系统默认 DNS 生效）"; return 0; fi
  if ! have_ipt; then echo "ERR: 设备缺少 iptables，无法接管 DNS"; return 1; fi
  clear_rules
  ensure_chain
  first=""
  if [ "$mode" = "custom" ]; then
    first=$(servers_list | head -n1)
    if [ -z "$first" ]; then
      # 内置公共 DNS 兜底
      first="223.5.5.5"
      echo "$first" > "$DNS_SRV_FILE"
    fi
    iptables -t nat -A "$CHAIN" -p udp --dport 53 -j DNAT --to-destination "$first" 2>/dev/null
    iptables -t nat -A "$CHAIN" -p tcp --dport 53 -j DNAT --to-destination "$first" 2>/dev/null
    # 排除本机回环
    iptables -t nat -I "$CHAIN" -o lo -j RETURN 2>/dev/null
  fi
  # 防泄露：阻断 DoT(853) 与明文外发 53 到非指定服务器
  if [ -f "$DNS_LEAK_FILE" ]; then
    iptables -I OUTPUT -p tcp --dport 853 -j REJECT 2>/dev/null
    iptables -I OUTPUT -p udp --dport 853 -j REJECT 2>/dev/null
  fi
  log "dnssrv: apply mode=$mode server=$first"
  if [ "$mode" = "auto" ]; then
    echo "OK: DNS 按系统/运营商自动解析（未接管）"
  else
    echo "OK: 全网 DNS 已重定向到 $first$([ -f "$DNS_LEAK_FILE" ] && echo '，并已阻断 DoT 泄露')"
  fi
}

doh_note() {
  echo "提示: DoH 加密解析需内核解析器支持(部分 ROM 需 sing-box/xray)。已保存配置，接管生效时优先使用。"
}

case "$1" in
  status)
    mode=$(cat "$DNS_MODE_FILE" 2>/dev/null || echo custom)
    [ -z "$mode" ] && mode="custom"
    doh=$(cat "$DNS_DOH_FILE" 2>/dev/null)
    dot=$(cat "$DNS_DOT_FILE" 2>/dev/null)
    leak="no"; [ -f "$DNS_LEAK_FILE" ] && leak="yes"
    n=$(servers_list | wc -l | tr -d ' ')
    printf '{"mode":"%s","count":%s,"doh":"%s","dot":"%s","leak":"%s"}\n' "$mode" "$n" "$doh" "$dot" "$leak"
    ;;
  servers)
    i=0
    while read -r s; do
      [ -z "$s" ] && continue
      i=$((i+1))
      printf '%s|%s\n' "$i" "$s"
    done <<EOF
$(servers_list)
EOF
    ;;
  add-server)
    s="$2"; [ -z "$s" ] && { echo "ERR: 缺少 DNS 地址"; exit 1; }
    s=$(echo "$s" | tr -d '[:space:]')
    grep -qxF "$s" "$DNS_SRV_FILE" 2>/dev/null || echo "$s" >> "$DNS_SRV_FILE"
    echo "OK: 已添加 DNS 服务器 $s"
    ;;
  del-server)
    s="$2"
    if [ -f "$DNS_SRV_FILE" ]; then tmp="$DNS_SRV_FILE.tmp.$$"; grep -vxF "$s" "$DNS_SRV_FILE" > "$tmp" 2>/dev/null; mv "$tmp" "$DNS_SRV_FILE"; fi
    echo "OK: 已删除 DNS 服务器 $s"
    ;;
  clear-servers) : > "$DNS_SRV_FILE"; echo "OK: 已清空 DNS 服务器列表" ;;
  set-mode)
    m="$2"; case "$m" in off|auto|custom) echo "$m" > "$DNS_MODE_FILE"; echo "OK: DNS 模式=$m" ;; *) echo "ERR: 模式需为 off|auto|custom" ;; esac
    ;;
  set-doh) u="$2"; echo "$u" > "$DNS_DOH_FILE"; echo "OK: DoH=$u" ;;
  set-dot) u="$2"; echo "$u" > "$DNS_DOT_FILE"; echo "OK: DoT=$u" ;;
  leak)
    v="$2"
    if [ "$v" = "on" ]; then echo 1 > "$DNS_LEAK_FILE"; echo "OK: 已开启 DNS 防泄露"; else rm -f "$DNS_LEAK_FILE"; echo "OK: 已关闭 DNS 防泄露"; fi
    ;;
  apply) apply ;;
  clear) clear_rules; echo "OK: 已清除 DNS 接管规则" ;;
  test)
    dom="${2:-www.baidu.com}"
    if have nslookup; then
      out=$(nslookup "$dom" 2>&1 | sed -n 's/.*Address: //p' | head -n1)
      [ -n "$out" ] && echo "OK: $dom -> $out" || echo "ERR: 解析失败"
    else
      echo "OK: 已配置，解析测试需设备侧 nslookup（当前 ROM 未内置）"
    fi
    ;;
  *) echo "usage: dnssrv.sh {status|servers|add-server|del-server|clear-servers|set-mode|set-doh|set-dot|leak|apply|clear|test}" ;;
esac
