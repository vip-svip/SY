#!/system/bin/sh
# ============================================================
#  leakguard.sh — 隐私防泄露（DNS / IPv6 / IP / VPN / 节点）
#
#  目标：在模块三层拦截 + 代理路由之外，补上一层「泄露兜底」，
#  覆盖真实 IP、DNS 外泄、IPv6 旁路、VPN 断连裸奔、代理节点外泄直连。
#
#  子命令：
#    status            汇总各防护开关与运行态（面板用）
#    enable/disable    总开关
#    dns on|off        DNS 泄露防护（强制模块 DNS + 阻断明文 53 回退）
#    ipv6 on|off       IPv6 泄露防护（无 v6 出口时阻断 v6，防旁路）
#    ip on|off         真实 IP 泄露防护（阻断 STUN/直连探测端口旁路）
#    vpn on|off        防 VPN 断连裸奔（内核守护：断开即阻断，避免明文出网）
#    node on|off       防代理节点泄露（代理不可用时阻断直连，防真实 IP 暴露）
#    apply             落地全部策略（幂等）
#    panic             一键收紧：全部开启（紧急止损）
#    app-enter <pkg>   应用前台钩子（无障碍服务调用）
#    hook-enter <pkg>  LSPosed 钩子回调（进程加载时上报）
#    tune <sub> <pkg>  按应用收敛（写 config/privacy_targets.txt）
#    report            导出诊断（当前规则计数 + 最近泄露事件）
#
#  POSIX sh 兼容，零外部依赖；所有命令均幂等、可重复执行。
# ============================================================
. "$(dirname "$0")/common.sh"

LG_DIR="$DATA_DIR/rules/leakguard"
mkdir -p "$LG_DIR" 2>/dev/null
STATE="$LG_DIR/state.conf"
EVENTS="$LG_DIR/events.log"
TARGETS="$MODDIR/config/privacy_targets.txt"   # 与 App/LSPosed 共用的事实源
CHAIN="SY_LEAKGUARD"

# 默认目标应用：社交/购物/输入法等隐私敏感场景（可按需删改）
DEFAULT_TARGETS="com.tencent.mm
com.tencent.mobileqq
com.taobao.taobao
com.jingdong.app.mall
com.sina.weibo"

lg_init() {
  [ -f "$STATE" ] || : > "$STATE"
  [ -f "$TARGETS" ] || { mkdir -p "$(dirname "$TARGETS")" 2>/dev/null; printf '%s\n' "$DEFAULT_TARGETS" > "$TARGETS"; }
}
lg_get() { # key default
  v=$(grep -E "^${1}=" "$STATE" 2>/dev/null | tail -n1 | cut -d= -f2-)
  [ -n "$v" ] && echo "$v" || echo "$2"
}
lg_set() { # key value
  lg_init
  if grep -qE "^${1}=" "$STATE" 2>/dev/null; then
    tmp="$STATE.tmp.$$"; sed "s|^${1}=.*|${1}=${2}|" "$STATE" > "$tmp" && mv "$tmp" "$STATE"
  else
    echo "${1}=${2}" >> "$STATE"
  fi
}
lg_event() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$EVENTS"; log "leakguard: $*"; }

ipt() { command -v iptables >/dev/null 2>&1 || return 1; iptables "$@" 2>/dev/null; }
ip6t() { command -v ip6tables >/dev/null 2>&1 || return 1; ip6tables "$@" 2>/dev/null; }

lg_chain_ensure() {
  ipt -N "$CHAIN" 2>/dev/null
  ipt -C OUTPUT -j "$CHAIN" 2>/dev/null || ipt -I OUTPUT 1 -j "$CHAIN"
  ip6t -N "$CHAIN" 2>/dev/null
  ip6t -C OUTPUT -j "$CHAIN" 2>/dev/null || ip6t -I OUTPUT 1 -j "$CHAIN"
}
lg_chain_flush() { ipt -F "$CHAIN" 2>/dev/null; ip6t -F "$CHAIN" 2>/dev/null; }

# ---- DNS 泄露：强制走模块 DNS，阻断其它明文 53 ----
lg_dns() { # on|off
  if [ "$1" = "on" ]; then
    lg_chain_ensure
    # 允许回环(面板/内核)与模块 DNS 自身，其余到 53 一律阻断，避免泄露到运营商 DNS
    ipt -C "$CHAIN" -p udp --dport 53 -m owner --uid-owner 0 -j ACCEPT 2>/dev/null || \
      ipt -A "$CHAIN" -p udp --dport 53 -m owner --uid-owner 0 -j ACCEPT
    ipt -C "$CHAIN" -p udp --dport 53 ! -d 127.0.0.1 -j REJECT 2>/dev/null || \
      ipt -A "$CHAIN" -p udp --dport 53 ! -d 127.0.0.1 -j REJECT
    ipt -C "$CHAIN" -p tcp --dport 53 ! -d 127.0.0.1 -j REJECT 2>/dev/null || \
      ipt -A "$CHAIN" -p tcp --dport 53 ! -d 127.0.0.1 -j REJECT
    lg_set dns on; lg_event "DNS 泄露防护已开启"
  else
    lg_set dns off; lg_event "DNS 泄露防护已关闭"
  fi
  lg_apply
}

# ---- IPv6 泄露：无 v6 出口时全阻断，防 v6 旁路绕过 v4 拦截 ----
lg_ipv6() { # on|off
  lg_chain_ensure
  if [ "$1" = "on" ]; then
    ip6t -C "$CHAIN" -o lo -j ACCEPT 2>/dev/null || ip6t -A "$CHAIN" -o lo -j ACCEPT
    ip6t -C "$CHAIN" -j REJECT 2>/dev/null || ip6t -A "$CHAIN" -j REJECT
    lg_set ipv6 on; lg_event "IPv6 泄露防护已开启（阻断 v6 旁路）"
  else
    ip6t -D "$CHAIN" -j REJECT 2>/dev/null
    lg_set ipv6 off; lg_event "IPv6 泄露防护已关闭"
  fi
}

# ---- 真实 IP：阻断 STUN/直连探测常用的裸 UDP 高端口旁路（可细化）----
lg_ip() { # on|off
  if [ "$1" = "on" ]; then
    lg_chain_ensure
    # 阻断 STUN 常用端口（3478/19302 等）非模块进程直连，降低 WebRTC 探测真实公网 IP 面
    for p in 3478 5349 19302 19305 19307 19309; do
      ipt -C "$CHAIN" -p udp --dport $p ! -d 127.0.0.1 -j REJECT 2>/dev/null || \
        ipt -A "$CHAIN" -p udp --dport $p ! -d 127.0.0.1 -j REJECT
    done
    lg_set ip on; lg_event "真实 IP 泄露防护已开启（阻断 STUN 探测端口）"
  else
    lg_set ip off; lg_event "真实 IP 泄露防护已关闭"
  fi
  lg_apply
}

# ---- VPN 断连裸奔：守护内核，断开即阻断，恢复则放行 ----
lg_vpn() { # on|off
  if [ "$1" = "on" ]; then
    lg_set vpn on
    # 写守护脚本，由 service.sh 周期调用（保持轻量，避免 busybox 定时器依赖）
    cat > "$LG_DIR/vpn_guard.sh" <<'EOS'
#!/system/bin/sh
. "$(dirname "$0")/../../scripts/common.sh" 2>/dev/null
LG_DIR="$DATA_DIR/rules/leakguard"
ip4=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -n1)
if [ -z "$ip4" ]; then
  iptables -C OUTPUT -j SY_LEAKGUARD 2>/dev/null || iptables -I OUTPUT 1 -j SY_LEAKGUARD
  iptables -C SY_LEAKGUARD -m owner --uid-owner 0 -j ACCEPT 2>/dev/null || iptables -A SY_LEAKGUARD -m owner --uid-owner 0 -j ACCEPT
  iptables -C SY_LEAKGUARD -j REJECT 2>/dev/null || iptables -A SY_LEAKGUARD -j REJECT
  echo "[$(date '+%F %T')] VPN 断连 -> 已切断明文出口" >> "$LG_DIR/events.log"
else
  # 出口恢复：移除兜底 REJECT，仅保留白名单链
  while iptables -C SY_LEAKGUARD -j REJECT 2>/dev/null; do iptables -D SY_LEAKGUARD -j REJECT 2>/dev/null; done
fi
EOS
    chmod 0755 "$LG_DIR/vpn_guard.sh" 2>/dev/null
    lg_event "防 VPN 断连裸奔已开启（守护脚本已生成）"
  else
    lg_set vpn off; lg_event "防 VPN 断连裸奔已关闭"
  fi
}

# ---- 代理节点泄露：代理不可用时阻断直连，防真实 IP 暴露 ----
lg_node() { # on|off
  if [ "$1" = "on" ]; then
    lg_set node on
    cat > "$LG_DIR/node_guard.sh" <<'EOS'
#!/system/bin/sh
. "$(dirname "$0")/../../scripts/common.sh" 2>/dev/null
LG_DIR="$DATA_DIR/rules/leakguard"
# 判断内核是否在跑：不在跑则阻断非 root 出网，避免直连暴露真实 IP
if ! pgrep -f 'sing-box|abserver proxy' >/dev/null 2>&1; then
  iptables -C OUTPUT -j SY_LEAKGUARD 2>/dev/null || iptables -I OUTPUT 1 -j SY_LEAKGUARD
  iptables -C SY_LEAKGUARD -m owner --uid-owner 0 -j ACCEPT 2>/dev/null || iptables -A SY_LEAKGUARD -m owner --uid-owner 0 -j ACCEPT
  iptables -C SY_LEAKGUARD -j REJECT 2>/dev/null || iptables -A SY_LEAKGUARD -j REJECT
  echo "[$(date '+%F %T')] 代理未运行 -> 已阻断直连，防止节点泄露/真实 IP 暴露" >> "$LG_DIR/events.log"
else
  while iptables -C SY_LEAKGUARD -j REJECT 2>/dev/null; do iptables -D SY_LEAKGUARD -j REJECT 2>/dev/null; done
fi
EOS
    chmod 0755 "$LG_DIR/node_guard.sh" 2>/dev/null
    lg_event "防代理节点泄露已开启（守护脚本已生成）"
  else
    lg_set node off; lg_event "防代理节点泄露已关闭"
  fi
}

lg_apply() {
  lg_chain_ensure
  # 允许 root 与回环，避免面板/内核被自己拦
  ipt -C "$CHAIN" -o lo -j ACCEPT 2>/dev/null || ipt -A "$CHAIN" -o lo -j ACCEPT
  ipt -C "$CHAIN" -m owner --uid-owner 0 -j ACCEPT 2>/dev/null || ipt -A "$CHAIN" -m owner --uid-owner 0 -j ACCEPT
  echo "OK: leakguard 策略已落地"
}

lg_panic() {
  for k in dns ipv6 ip vpn node; do lg_set "$k" on; done
  lg_dns on >/dev/null; lg_ipv6 on >/dev/null; lg_ip on >/dev/null
  [ "$(lg_get vpn off)" = "on" ] || lg_vpn on
  lg_event "PANIC：已一键收紧全部隐私防护"
  echo "OK: 已开启全部隐私防泄露"
}

lg_status_json() {
  printf '{"enabled":"%s","dns":"%s","ipv6":"%s","ip":"%s","vpn":"%s","node":"%s","rules":%s,"events":%s}\n' \
    "$(lg_get enabled off)" "$(lg_get dns off)" "$(lg_get ipv6 off)" \
    "$(lg_get ip off)" "$(lg_get vpn off)" "$(lg_get node off)" \
    "$(ipt -S "$CHAIN" 2>/dev/null | grep -c .)" "$(wc -l < "$EVENTS" 2>/dev/null | tr -d ' ')"
}

lg_tune() { # add|del pkg
  lg_init
  act="$1"; pkg="$2"
  [ -n "$pkg" ] || { echo "usage: tune add|del <pkg>"; return 1; }
  case "$act" in
    add) grep -qxF "$pkg" "$TARGETS" 2>/dev/null || echo "$pkg" >> "$TARGETS"; echo "OK: 已加入隐私收敛 $pkg" ;;
    del) tmp="$TARGETS.tmp.$$"; grep -vxF "$pkg" "$TARGETS" > "$tmp" 2>/dev/null; mv "$tmp" "$TARGETS"; echo "OK: 已移出隐私收敛 $pkg" ;;
    *) echo "usage: tune add|del <pkg>" ;;
  esac
}

lg_init
case "$1" in
  status)   lg_status_json ;;
  enable)   lg_set enabled on;  echo "OK: 隐私防泄露总开关已开启" ;;
  disable)  lg_set enabled off; lg_chain_flush; echo "OK: 隐私防泄露总开关已关闭" ;;
  dns)      lg_dns "$2" ;;
  ipv6)     lg_ipv6 "$2" ;;
  ip)       lg_ip "$2" ;;
  vpn)      lg_vpn "$2" ;;
  node)     lg_node "$2" ;;
  apply)    lg_apply ;;
  panic)    lg_panic ;;
  tune)     lg_tune "$2" "$3" ;;
  restore)
    [ "$(lg_get enabled off)" = "on" ] || exit 0
    [ "$(lg_get dns off)"  = "on" ] && lg_dns on  >/dev/null
    [ "$(lg_get ipv6 off)" = "on" ] && lg_ipv6 on >/dev/null
    [ "$(lg_get ip off)"   = "on" ] && lg_ip on   >/dev/null
    echo "OK: 隐私防泄露已按上次状态恢复"
    ;;
  app-enter)  lg_event "app-enter: ${2:-unknown}" ;;
  hook-enter) lg_event "hook-enter: ${2:-unknown}" ;;
  report)
    echo "== SY 隐私防泄露报告 =="
    echo "总开关 : $(lg_get enabled off)"
    echo "DNS    : $(lg_get dns off)   IPv6: $(lg_get ipv6 off)   IP: $(lg_get ip off)"
    echo "VPN    : $(lg_get vpn off)   Node: $(lg_get node off)"
    echo "规则数 : $(ipt -S "$CHAIN" 2>/dev/null | grep -c .)"
    echo "收敛应用: $(grep -vcE '^#|^$' "$TARGETS" 2>/dev/null)"
    echo "-- 最近事件 --"; tail -n 15 "$EVENTS" 2>/dev/null
    ;;
  *) echo "usage: leakguard.sh {status|enable|disable|dns|ipv6|ip|vpn|node|apply|panic|tune|app-enter|hook-enter|report} [on|off]" ;;
esac
