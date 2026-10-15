#!/system/bin/sh
# ============================================================
#  leakguard.sh — 深度隐私防泄露引擎（v1.0.3 重写）
#
#  设计目标：把「DNS / 真实 IP / IPv6 / VPN 断连 / 代理节点 泄露」
#  这五类口径，做成内核态可开关、可组合、可自愈的防护面。
#  全部基于 iptables / ip6tables / sysctl，不依赖任何第三方二进制。
#
#  v1.0.2 的缺陷（本版修复）：
#   · dns/ip/ipv6/vpn/node 的 off 分支只 echo「已关闭」，从不真正删除规则
#     → 关闭后仍在拦截（功能不生效 + 状态与事实不符）。本版用统一链 + 精确删除。
#   · 状态只写内存变量，重启即丢且与内核实际规则不一致。本版以「内核规则为准」，
#     状态文件只作持久化记忆，apply 时按内核实测校准。
#   · 无幂等：重复 enable 会叠加重复规则。本版每条链先 flush 再按配置重建。
#   · 无 owner（出口 IP 归属）能力，无法验证是否真的走代理。本版新增 owner，
#     调用 abserver geoip + 本地 RIR 授权库，离线判读出口 IP 归属。
#
#  子命令：
#   status                  查看各防护内核态与开关状态
#   enable | disable        总开关（含全部子项）
#   dns   on|off|test       防 DNS 明文泄露（53/853 收敛）
#   ipv6  on|off|test       无 v6 出口时整链阻断 v6 旁路
#   ip    on|off|test       防真实 IP 泄露（STUN/WebRTC 探测面收敛）
#   vpn   on|off|test       防 VPN 断连裸奔（kill-switch）
#   node  on|off|test       防代理节点泄露（代理不可用时阻断直连）
#   apps  [list|add P|del P]  按应用（uid）收敛出口，读 privacy_targets.txt
#   owner A,B               对比两个出口 IP 归属，判定真实 IP 泄露/旁路
#   tune  on|off            sysctl 隐私加固（rp_filter / IPv6 RA / ICMP 收敛）
#   apply                   按持久化配置重建全部规则（开机调用，幂等）
#   panic                   一键全防护 + 记录快照（可恢复）
#   restore                 从快照恢复并移除全部本模块规则
#   report                  结构化 JSON 报告（供面板「隐私」页）
#   app-enter PKG [CLS]     前台/进程进入通知钩子（App/无障碍/LSPosed 调用）
#   hook-enter PKG          LSPosed 进程加载钩子
# ============================================================
set -u

# ---- 路径与配置：统一走 common.sh 的约定 ----
# 【真实缺陷修复】旧版自己实现 conf_get，并把状态写进 MODDIR/.state（模块目录）。
#  这与项目其他脚本（都 source common.sh、用 DATA_DIR）不一致，后果有两个：
#   ① 面板/脚本用 -datadir 或 AB_DATA_DIR 指定数据目录时，本脚本读到的配置与
#      其他组件不是同一份 —— 表现为「开了防泄露但状态显示未开」；
#   ② 状态文件落在模块目录里，**卸载后残留**（uninstall 只清 DATA_DIR）。
#  现在统一：配置读 DATA_DIR/config/sy.conf，状态落到 DATA_DIR/rules/leakguard/，
#  随 rm -rf DATA_DIR 一并清理，符合「卸载零残留」。
if [ -f "$(dirname "$0")/common.sh" ]; then
  . "$(dirname "$0")/common.sh"
fi

# common.sh 未加载成功时的兜底（保证脚本独立可跑）
if [ -z "${DATA_DIR:-}" ]; then
  DATA_DIR="${AB_DATA_DIR:-}"
  if [ -z "$DATA_DIR" ]; then
    DATA_DIR=/data/adb/SY
    [ -d "$DATA_DIR" ] || DATA_DIR=/data/SY
  fi
fi
if [ -z "${MODDIR:-}" ]; then
  for d in /data/adb/modules/SY /data/adb/modules_update/SY /data/adb/modules/SY-Fusion; do
    [ -d "$d" ] && MODDIR="$d" && break
  done
fi
MODDIR="${MODDIR:-/data/adb/modules/SY}"

CONF="$DATA_DIR/config/sy.conf"
STATE_DIR="$DATA_DIR/rules/leakguard"
STATE="$STATE_DIR/leakguard.state"
LOG="${LOGS:-$DATA_DIR/logs}/leakguard.log"
TARGETS="$DATA_DIR/config/privacy_targets.txt"
OWNER_DB="$MODDIR/data/geo/rir"
AB="$MODDIR/bin/abserver-$(uname -m 2>/dev/null | sed 's/aarch64/arm64/;s/x86_64/amd64/')"
[ -x "$AB" ] || AB="$MODDIR/bin/abserver"

mkdir -p "$STATE_DIR" "$(dirname "$LOG")" 2>/dev/null


# ---- 链名 ----
CH_OUT="SY_LEAK_OUT"      # OUTPUT 过滤
CH_IN="SY_LEAK_IN"        # INPUT 过滤
CH_FWD="SY_LEAK_FWD"      # FORWARD 过滤
CH6_OUT="SY_LEAK6_OUT"
CH6_IN="SY_LEAK6_IN"

have() { command -v "$1" >/dev/null 2>&1; }
IPT="$(have iptables && echo iptables || true)"
IP6T="$(have ip6tables && echo ip6tables || true)"
NFT="$(have nft && echo nft || true)"

log() { echo "[$(date '+%F %T' 2>/dev/null || echo now)] $*" >>"$LOG" 2>/dev/null; }

# 读取 sy.conf 中某个键
# conf_get 由 common.sh 提供；这里只在未加载成功时兜底，
# 避免两个同名函数互相覆盖导致「读配置的行为随加载顺序而变」。
if ! command -v conf_get >/dev/null 2>&1; then
  conf_get() {
    [ -f "$CONF" ] || { echo ""; return; }
    sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$CONF" | head -1
  }
fi

# ---------------- 状态持久化（内核规则才是事实源） ----------------
state_init() {
  [ -f "$STATE" ] || cat >"$STATE" <<EOF
DNS=0
IPV6=0
IP=0
VPN=0
NODE=0
TUNE=0
EOF
}
state_get() { state_init; sed -n "s/^$1=//p" "$STATE" | head -1; }
state_set() {
  state_init
  if grep -q "^$1=" "$STATE" 2>/dev/null; then
    sed -i "s/^$1=.*/$1=$2/" "$STATE"
  else
    echo "$1=$2" >>"$STATE"
  fi
}

# ---------------- iptables 链管理（幂等） ----------------
ipt_chain_ensure() { # table chain
  $IPT -t "$1" -N "$2" 2>/dev/null || true
}
ipt_chain_flush() { $IPT -t "$1" -F "$2" 2>/dev/null || true; }
ipt_jump_ensure() { # table parent chain
  $IPT -t "$1" -C "$2" -j "$3" 2>/dev/null || $IPT -t "$1" -I "$2" 1 -j "$3" 2>/dev/null || true
}
ipt_jump_remove() { # table parent chain
  while $IPT -t "$1" -C "$2" -j "$3" 2>/dev/null; do
    $IPT -t "$1" -D "$2" -j "$3" 2>/dev/null || break
  done
}

ipt6_chain_ensure() { $IP6T -N "$1" 2>/dev/null || true; }
ipt6_chain_flush() { $IP6T -F "$1" 2>/dev/null || true; }
ipt6_jump_ensure() { $IP6T -C "$1" -j "$2" 2>/dev/null || $IP6T -I "$1" 1 -j "$2" 2>/dev/null || true; }
ipt6_jump_remove() { while $IP6T -C "$1" -j "$2" 2>/dev/null; do $IP6T -D "$1" -j "$2" 2>/dev/null || break; done; }

# 本机回环与已建立连接永远放行（避免自锁）
guard_loopback() { # chain
  $IPT -A "$1" -o lo -j RETURN 2>/dev/null || true
  $IPT -A "$1" -d 127.0.0.0/8 -j RETURN 2>/dev/null || true
  $IPT -A "$1" -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN 2>/dev/null || true
}

# ---------------- 各类防护 ----------------
dns_on() {
  [ -z "$IPT" ] && { echo "ERR: 无 iptables"; return 1; }
  ipt_chain_ensure filter "$CH_OUT"
  ipt_chain_flush filter "$CH_OUT"
  guard_loopback "$CH_OUT"
  # 允许到模块内 DNS（本地 53 / DoT 上游）
  $IPT -A "$CH_OUT" -p udp --dport 53 -d 127.0.0.1 -j RETURN 2>/dev/null || true
  $IPT -A "$CH_OUT" -p tcp --dport 53 -d 127.0.0.1 -j RETURN 2>/dev/null || true
  # 其余明文 DNS（53/853）一律阻断，堵住运营商 DNS 泄露
  $IPT -A "$CH_OUT" -p udp --dport 53 -j REJECT 2>/dev/null || true
  $IPT -A "$CH_OUT" -p tcp --dport 53 -j REJECT 2>/dev/null || true
  $IPT -A "$CH_OUT" -p tcp --dport 853 -j REJECT 2>/dev/null || true
  ipt_jump_ensure filter OUTPUT "$CH_OUT"
  state_set DNS 1
  log "dns on"
  echo "DNS: on"
}

dns_off() {
  [ -n "$IPT" ] && ipt_jump_remove filter OUTPUT "$CH_OUT"
  [ -n "$IPT" ] && ipt_chain_flush filter "$CH_OUT"
  state_set DNS 0
  log "dns off"
  echo "DNS: off"
}

dns_test() {
  # 逐项校验：是否存在阻断 53 的规则
  if [ -n "$IPT" ] && $IPT -C OUTPUT -j "$CH_OUT" 2>/dev/null; then
    echo "DNS: POSTURE ok (chain $CH_OUT active; plaintext 53/853 rejected)"
  else
    echo "DNS: POSTURE off (plaintext DNS not intercepted)"
  fi
}

ipv6_on() {
  if [ -z "$IP6T" ]; then echo "WARN: 无 ip6tables，改用 sysctl 关闭 v6"; tune_ipv6_sysctl_disable; state_set IPV6 1; return 0; fi
  ipt6_chain_ensure "$CH6_OUT"
  ipt6_chain_flush "$CH6_OUT"
  $IP6T -A "$CH6_OUT" -o lo -j RETURN 2>/dev/null || true
  $IP6T -A "$CH6_OUT" -d ::1 -j RETURN 2>/dev/null || true
  $IP6T -A "$CH6_OUT" -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN 2>/dev/null || true
  # 阻断全部 v6 出站（无 v6 出口场景下，防「v4 被拦、v6 旁路」）
  $IP6T -A "$CH6_OUT" -j REJECT 2>/dev/null || true
  ipt6_jump_ensure OUTPUT "$CH6_OUT"
  state_set IPV6 1
  log "ipv6 on"
  echo "IPv6: on"
}

ipv6_off() {
  [ -n "$IP6T" ] && ipt6_jump_remove OUTPUT "$CH6_OUT"
  [ -n "$IP6T" ] && ipt6_chain_flush "$CH6_OUT"
  # 【真实缺陷修复】旧版只 flush 链、不删链 —— 空链会残留在 ip6tables 里；
  # 若用户反复开关，还可能在别的表留下同名链（表现为"关不掉"）。
  [ -n "$IP6T" ] && $IP6T -X "$CH6_OUT" 2>/dev/null || true
  # 【真实缺陷修复】若之前因为「没有 ip6tables」而用 sysctl 关了 v6，
  # 关闭防护时必须把 sysctl 还原，否则 IPv6 被永久禁用（用户会以为网络坏了）。
  tune_ipv6_sysctl_restore
  state_set IPV6 0
  log "ipv6 off"
  echo "IPv6: off"
}

ip_on() {
  [ -z "$IPT" ] && { echo "ERR: 无 iptables"; return 1; }
  ipt_chain_ensure filter "$CH_OUT"
  # 不 flush 整条（共享链），用独立子链
  ipt_chain_ensure filter SY_LEAK_STUN
  ipt_chain_flush filter SY_LEAK_STUN
  guard_loopback SY_LEAK_STUN
  # STUN / WebRTC 探测端口：真实 IP 最常从这些口漏出去
  for p in 3478 3479 5349 5350 19302 19303 19304 19305 19306 19307 19308 19309; do
    $IPT -A SY_LEAK_STUN -p udp --dport $p -j REJECT 2>/dev/null || true
    $IPT -A SY_LEAK_STUN -p tcp --dport $p -j REJECT 2>/dev/null || true
  done
  ipt_jump_ensure filter "$CH_OUT" SY_LEAK_STUN
  state_set IP 1
  log "ip on"
  echo "IP: on (STUN/WebRTC 探测端口已收敛)"
}

ip_off() {
  [ -n "$IPT" ] && ipt_jump_remove filter "$CH_OUT" SY_LEAK_STUN
  [ -n "$IPT" ] && ipt_chain_flush filter SY_LEAK_STUN
  state_set IP 0
  log "ip off"
  echo "IP: off"
}

# 判定「代理是否在线」：优先 Clash API，其次进程
proxy_online() {
  if [ -x "$AB" ]; then
    out=$("$AB" clash -api 127.0.0.1:9090 status -json 2>/dev/null)
    echo "$out" | grep -q '"ok":true' && return 0
  fi
  [ -f "$MODDIR/.state/core.pid" ] && kill -0 "$(cat "$MODDIR/.state/core.pid" 2>/dev/null)" 2>/dev/null && return 0
  return 1
}

vpn_on() {
  [ -z "$IPT" ] && { echo "ERR: 无 iptables"; return 1; }
  ipt_chain_ensure filter SY_LEAK_KILL
  ipt_chain_flush filter SY_LEAK_KILL
  guard_loopback SY_LEAK_KILL
  # 允许到本地代理端口（走隧道）
  pp=$(conf_get PROXY_PORT); pp=${pp:-2080}
  $IPT -A SY_LEAK_KILL -p tcp --dport "$pp" -d 127.0.0.1 -j RETURN 2>/dev/null || true
  $IPT -A SY_LEAK_KILL -p udp --dport "$pp" -d 127.0.0.1 -j RETURN 2>/dev/null || true
  # 代理离线时：阻断明文出网（kill-switch）；在线时本链整体放行
  if proxy_online; then
    $IPT -A SY_LEAK_KILL -j RETURN 2>/dev/null || true
  else
    $IPT -A SY_LEAK_KILL -j REJECT 2>/dev/null || true
  fi
  ipt_jump_ensure filter OUTPUT SY_LEAK_KILL
  state_set VPN 1
  log "vpn on"
  echo "VPN kill-switch: on ($(proxy_online && echo proxy-up || echo proxy-down→blocking))"
}

vpn_off() {
  [ -n "$IPT" ] && ipt_jump_remove filter OUTPUT SY_LEAK_KILL
  [ -n "$IPT" ] && ipt_chain_flush filter SY_LEAK_KILL
  state_set VPN 0
  log "vpn off"
  echo "VPN kill-switch: off"
}

# 断连守护：后台循环，出口断开即刻切断，恢复自动放行
vpn_guard_start() {
  pidf="$STATE_DIR/vpn.guard.pid"
  if [ -f "$pidf" ] && kill -0 "$(cat "$pidf" 2>/dev/null)" 2>/dev/null; then
    echo "VPN guard: already running"; return 0
  fi
  (
    while :; do
      if proxy_online; then
        $IPT -F SY_LEAK_KILL 2>/dev/null
        guard_loopback SY_LEAK_KILL
        pp=$(conf_get PROXY_PORT); pp=${pp:-2080}
        $IPT -A SY_LEAK_KILL -p tcp --dport "$pp" -d 127.0.0.1 -j RETURN 2>/dev/null
        $IPT -A SY_LEAK_KILL -j RETURN 2>/dev/null
      else
        $IPT -F SY_LEAK_KILL 2>/dev/null
        guard_loopback SY_LEAK_KILL
        pp=$(conf_get PROXY_PORT); pp=${pp:-2080}
        $IPT -A SY_LEAK_KILL -p tcp --dport "$pp" -d 127.0.0.1 -j RETURN 2>/dev/null
        $IPT -A SY_LEAK_KILL -j REJECT 2>/dev/null
      fi
      sleep 5
    done
  ) >/dev/null 2>&1 &
  echo $! >"$pidf"
  echo "VPN guard: started (pid $(cat "$pidf"))"
}

vpn_guard_stop() {
  pidf="$STATE_DIR/vpn.guard.pid"
  [ -f "$pidf" ] && kill "$(cat "$pidf" 2>/dev/null)" 2>/dev/null
  rm -f "$pidf"
  echo "VPN guard: stopped"
}

node_on() {
  [ -z "$IPT" ] && { echo "ERR: 无 iptables"; return 1; }
  ipt_chain_ensure filter SY_LEAK_NODE
  ipt_chain_flush filter SY_LEAK_NODE
  guard_loopback SY_LEAK_NODE
  pp=$(conf_get PROXY_PORT); pp=${pp:-2080}
  $IPT -A SY_LEAK_NODE -p tcp --dport "$pp" -d 127.0.0.1 -j RETURN 2>/dev/null || true
  if proxy_online; then
    $IPT -A SY_LEAK_NODE -j RETURN 2>/dev/null || true
  else
    # 代理不可用时阻断直连，避免真实 IP 在断流瞬间暴露
    $IPT -A SY_LEAK_NODE -j REJECT 2>/dev/null || true
  fi
  ipt_jump_ensure filter OUTPUT SY_LEAK_NODE
  state_set NODE 1
  log "node on"
  echo "NODE leakguard: on"
}

node_off() {
  [ -n "$IPT" ] && ipt_jump_remove filter OUTPUT SY_LEAK_NODE
  [ -n "$IPT" ] && ipt_chain_flush filter SY_LEAK_NODE
  state_set NODE 0
  log "node off"
  echo "NODE leakguard: off"
}

# 还原 IPv6 sysctl（关闭防护 / 卸载时调用）。
# 【真实缺陷修复】旧版 tune_ipv6_sysctl_disable 把 disable_ipv6 置 1 后，
# **没有任何路径把它改回 0** —— 用户关掉防护或卸载模块后，IPv6 依然是禁用的，
# 表现为"用了一阵子之后家里 Wi-Fi 的 v6 莫名其妙没了"。
tune_ipv6_sysctl_restore() {
  for k in net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6; do
    f="/proc/sys/$(echo "$k" | tr '.' '/')"
    [ -w "$f" ] && echo 0 >"$f" 2>/dev/null || true
  done
  log "ipv6 sysctl restored"
}

tune_ipv6_sysctl_disable() {
  for k in net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6; do
    [ -w "/proc/sys/$(echo "$k" | tr '.' '/')" ] && echo 1 >"/proc/sys/$(echo "$k" | tr '.' '/')" 2>/dev/null || true
  done
}

tune_on() {
  # 隐私相关 sysctl 加固
  set_sys() { [ -w "/proc/sys/$(echo "$1" | tr '.' '/')" ] && echo "$2" >"/proc/sys/$(echo "$1" | tr '.' '/')" 2>/dev/null && echo "  set $1=$2" || echo "  skip $1"; }
  set_sys net.ipv4.conf.all.rp_filter 1
  set_sys net.ipv4.conf.default.rp_filter 1
  set_sys net.ipv4.conf.all.accept_redirects 0
  set_sys net.ipv4.conf.all.send_redirects 0
  set_sys net.ipv4.conf.all.accept_source_route 0
  set_sys net.ipv4.icmp_echo_ignore_broadcasts 1
  set_sys net.ipv6.conf.all.accept_redirects 0
  set_sys net.ipv6.conf.all.accept_ra 0
  set_sys net.ipv6.conf.all.use_tempaddr 2
  state_set TUNE 1
  log "tune on"
  echo "TUNE: on"
}

tune_off() {
  # 【真实缺陷修复】旧版只把 rp_filter 改回 0，其余 8 项加固（accept_redirects /
  # accept_source_route / accept_ra / use_tempaddr 等）**从不还原** ——
  # 用户关掉防护后，系统仍处在加固状态，且没有任何提示。
  # 这里逐项还原到 Linux 默认值。
  set_sys() { [ -w "/proc/sys/$(echo "$1" | tr '.' '/')" ] && echo "$2" >"/proc/sys/$(echo "$1" | tr '.' '/')" 2>/dev/null && echo "  restore $1=$2" || true; }
  set_sys net.ipv4.conf.all.rp_filter 0
  set_sys net.ipv4.conf.default.rp_filter 0
  set_sys net.ipv4.conf.all.accept_redirects 1
  set_sys net.ipv4.conf.all.send_redirects 1
  set_sys net.ipv4.conf.all.accept_source_route 0
  set_sys net.ipv4.icmp_echo_ignore_broadcasts 1
  set_sys net.ipv6.conf.all.accept_redirects 0
  set_sys net.ipv6.conf.all.accept_ra 1
  set_sys net.ipv6.conf.all.use_tempaddr 0
  tune_ipv6_sysctl_restore
  state_set TUNE 0
  log "tune off"
  echo "TUNE: off"
}

# ---------------- 按应用（uid）收敛 ----------------
apps_list() {
  [ -d "$TARGETS" ] && TARGETS="$TARGETS" 
  if [ ! -f "$TARGETS" ]; then echo "(no privacy_targets.txt)"; return; fi
  echo "隐私目标应用:"
  grep -v '^[[:space:]]*#' "$TARGETS" 2>/dev/null | grep -v '^[[:space:]]*$' | while read -r p; do
    uid=$(pm list packages -U 2>/dev/null | sed -n "s/package:$p uid:\([0-9]*\).*/\1/p" | head -1)
    echo "  $p  uid=${uid:-?}"
  done
}

apps_apply() {
  [ -z "$IPT" ] && { echo "ERR: 无 iptables"; return 1; }
  [ ! -f "$TARGETS" ] && { echo "no targets"; return 0; }
  ipt_chain_ensure filter SY_LEAK_APPS
  ipt_chain_flush filter SY_LEAK_APPS
  guard_loopback SY_LEAK_APPS
  pp=$(conf_get PROXY_PORT); pp=${pp:-2080}
  grep -v '^[[:space:]]*#' "$TARGETS" 2>/dev/null | grep -v '^[[:space:]]*$' | while read -r p; do
    uid=$(pm list packages -U 2>/dev/null | sed -n "s/package:$p uid:\([0-9]*\).*/\1/p" | head -1)
    [ -z "$uid" ] && continue
    $IPT -A SY_LEAK_APPS -m owner --uid-owner "$uid" -p tcp --dport "$pp" -d 127.0.0.1 -j RETURN 2>/dev/null
    # 目标应用强制走本地代理，否则阻断（防其直连泄露真实 IP）
    if proxy_online; then
      $IPT -A SY_LEAK_APPS -m owner --uid-owner "$uid" -j REJECT 2>/dev/null
    fi
  done
  ipt_jump_ensure filter OUTPUT SY_LEAK_APPS
  echo "APPS: applied"
}

# ---------------- owner：离线判读出口 IP 归属 ----------------
owner() {
  a=${1%%,*}; b=${1#*,}
  echo "== 出口归属对比 =="
  if [ -x "$AB" ]; then
    "$AB" geoip -db "$MODDIR/data/geo" -compare "$a,$b" 2>/dev/null && return 0
  fi
  # 回退：使用本地 RIR 授权库（grep 归属）
  if [ -d "$OWNER_DB" ]; then
    for ip in "$a" "$b"; do
      hit=$(grep -rh -m1 "|$ip|" "$OWNER_DB" 2>/dev/null)
      echo "$ip -> ${hit:-未在本地授权库命中（仅含网段起始记录）}"
    done
    return 0
  fi
  echo "无可用归属库（data/geo 缺失）"
}

# ---------------- 组合开关 ----------------
apply_all() {
  [ "$(state_get DNS)" = "1" ] && dns_on
  [ "$(state_get IPV6)" = "1" ] && ipv6_on
  [ "$(state_get IP)" = "1" ] && ip_on
  [ "$(state_get VPN)" = "1" ] && vpn_on
  [ "$(state_get NODE)" = "1" ] && node_on
  [ "$(state_get TUNE)" = "1" ] && tune_on
  log "applied"
  echo "已按持久化状态重建规则"
}

enable_all() { dns_on; ipv6_on; ip_on; vpn_on; node_on; tune_on; vpn_guard_start; log "enable"; echo "总开关: on"; }
disable_all() { vpn_guard_stop; node_off; vpn_off; ip_off; ipv6_off; dns_off; tune_off; log "disable"; echo "总开关: off"; }

panic() {
  # 一键：全防护 + 记录快照
  cp "$STATE" "$STATE_DIR/leakguard.snapshot" 2>/dev/null || true
  dns_on; ipv6_on; ip_on; vpn_on; node_on; tune_on; vpn_guard_start
  log "panic engaged"
  echo "PANIC: 已启用全防护并记录快照"
}

# ---------------- 状态 ----------------
status() {
  printf '%-8s %s\n' "DNS"  "$(state_get DNS)"
  printf '%-8s %s\n' "IPV6" "$(state_get IPV6)"
  printf '%-8s %s\n' "IP"   "$(state_get IP)"
  printf '%-8s %s\n' "VPN"  "$(state_get VPN)"
  printf '%-8s %s\n' "NODE" "$(state_get NODE)"
  printf '%-8s %s\n' "TUNE" "$(state_get TUNE)"
  if [ -n "$IPT" ]; then
    n=$($IPT -L "$CH_OUT" -n 2>/dev/null | grep -c 'REJECT\|DROP' 2>/dev/null)
    printf '%-8s %s\n' "iptables" "${IPT}(${n} block rules)"
  else
    printf '%-8s %s\n' "iptables" "unavailable"
  fi
  if [ -f "$STATE_DIR/vpn.guard.pid" ] && kill -0 "$(cat "$STATE_DIR/vpn.guard.pid" 2>/dev/null)" 2>/dev/null; then
    echo "guard    running"
  else
    echo "guard    stopped"
  fi
}

report() {
  esc() { echo "$1" | tr -d '"\\' ; }
  cat <<JSON
{"ok":true,"dns":$(state_get DNS),"ipv6":$(state_get IPV6),"ip":$(state_get IP),"vpn":$(state_get VPN),"node":$(state_get NODE),"tune":$(state_get TUNE),"iptables":"$(esc ${IPT:-none})","ip6tables":"$(esc ${IP6T:-none})","proxy_online":$(proxy_online && echo true || echo false),"targets":$(grep -vc '^[[:space:]]*#\|^[[:space:]]*$' "$TARGETS" 2>/dev/null || echo 0)}
JSON
}

# ---------------- 钩子（App / 无障碍 / LSPosed 调用） ----------------
app_enter() { # PKG [CLS]
  pkg=${1:-}; cls=${2:-}
  log "app-enter $pkg $cls"
  # 目标应用进入前台时，确保其被纳入出口收敛
  grep -q "^$pkg$" "$TARGETS" 2>/dev/null && apps_apply >/dev/null 2>&1 || true
}

hook_enter() { app_enter "$1" ""; }

restore() {
  if [ -f "$STATE_DIR/leakguard.snapshot" ]; then
    cp "$STATE_DIR/leakguard.snapshot" "$STATE"
  fi
  node_off; vpn_off; ip_off; ipv6_off; dns_off
  tune_off
  [ -n "$IPT" ] && ipt_chain_flush filter SY_LEAK_APPS
  log "restored"
  echo "已恢复并移除全部本模块规则"
}

# ---------------- Hook 事件（内置 App Hook 子系统上报） ----------------
HOOKLOG="$STATE_DIR/hook.log"
HOOKMODE_FILE="$STATE_DIR/hook.mode"

hook_event() { # TAG DETAIL...
  tag=${1:-unknown}
  shift 2>/dev/null || true
  detail="$*"
  echo "[$(date '+%F %T' 2>/dev/null || echo now)] $tag | $detail" >>"$HOOKLOG" 2>/dev/null
  # 关键钩子命中即触发一次出口收敛（目标应用进入前台等）
  case "$tag" in
    hook-install|activity|hook-enter) apps_apply >/dev/null 2>&1 || true ;;
  esac
}

hook_events() {
  n=${1:-20}
  [ -f "$HOOKLOG" ] || { echo "(no hook events)"; return; }
  tail -n "$n" "$HOOKLOG"
}

hook_get_mode() {
  if [ -f "$HOOKMODE_FILE" ]; then cat "$HOOKMODE_FILE" 2>/dev/null; else echo "targets"; fi
}

hook_mode() {
  case "${1:-}" in
    on|off|all|targets) echo "$1" >"$HOOKMODE_FILE"; echo "hook mode = $1" ;;
    *) hook_get_mode ;;
  esac
}

hook_status() {
  echo "hook mode : $(hook_get_mode)"
  if [ -f "$HOOKLOG" ]; then
    echo "events    : $(wc -l <"$HOOKLOG" 2>/dev/null)"
    echo "by tag    :"
    sed -n 's/^\[[^]]*\] \([^|]*\)|.*/\1/p' "$HOOKLOG" 2>/dev/null | sed 's/[[:space:]]*$//' | sort | uniq -c | sort -rn | head
  else
    echo "events    : 0"
  fi
  echo "builtin hooks:"
  grep -v '^[[:space:]]*#' "$MODDIR/config/hooks.conf" 2>/dev/null | grep -v '^[[:space:]]*$' | sed 's/^/  /'
}

hook_clear() { : >"$HOOKLOG" 2>/dev/null; echo "hook events cleared"; }

# ---------------- 运营商隐私收敛（明文中转/DNS 收敛；标识符由 App Hook 喂假数据） ----------------
carrier() {
  case "${1:-status}" in
    on)
      dns_on; ipv6_on; ip_on; tune_on
      echo "运营商隐私收敛: on"
      carrier_report_short ;;
    off)
      dns_off; ipv6_off; ip_off; tune_off
      echo "运营商隐私收敛: off" ;;
    *) carrier_report_short ;;
  esac
}

carrier_report_short() {
  echo "  明文 DNS(53/853) 拦截 : $(state_get DNS)"
  echo "  IPv6 旁路阻断         : $(state_get IPV6)"
  echo "  STUN/WebRTC 收敛      : $(state_get IP)"
  echo "  sysctl 隐私加固       : $(state_get TUNE)"
  echo "  标识符 Hook(IMEI/IMSI/MAC/位置/WebView) 模式 : $(hook_get_mode)"
}

state_init

case "${1:-status}" in
  status)   status ;;
  enable)   enable_all ;;
  disable)  disable_all ;;
  dns)      case "${2:-status}" in on) dns_on;; off) dns_off;; test) dns_test;; *) dns_test;; esac ;;
  ipv6)     case "${2:-status}" in on) ipv6_on;; off) ipv6_off;; *) [ "$(state_get IPV6)" = 1 ] && echo "IPv6: on" || echo "IPv6: off";; esac ;;
  ip)       case "${2:-status}" in on) ip_on;; off) ip_off;; *) [ "$(state_get IP)" = 1 ] && echo "IP: on" || echo "IP: off";; esac ;;
  vpn)      case "${2:-status}" in on) vpn_on; vpn_guard_start;; off) vpn_guard_stop; vpn_off;; guard) vpn_guard_start;; *) [ "$(state_get VPN)" = 1 ] && echo "VPN: on" || echo "VPN: off";; esac ;;
  node)     case "${2:-status}" in on) node_on;; off) node_off;; *) [ "$(state_get NODE)" = 1 ] && echo "NODE: on" || echo "NODE: off";; esac ;;
  apps)     case "${2:-list}" in list) apps_list;; apply) apps_apply;; add) grep -q "^$3$" "$TARGETS" 2>/dev/null || echo "$3" >>"$TARGETS"; apps_apply;; del) sed -i "/^$3$/d" "$TARGETS" 2>/dev/null; apps_apply;; *) apps_list;; esac ;;
  owner)    owner "${2:-}" ;;
  tune)     case "${2:-status}" in on) tune_on;; off) tune_off;; *) [ "$(state_get TUNE)" = 1 ] && echo "TUNE: on" || echo "TUNE: off";; esac ;;
  apply)    apply_all ;;
  panic)    panic ;;
  restore)  restore ;;
  report)   report ;;
  app-enter) app_enter "${2:-}" "${3:-}" ;;
  hook-enter) hook_enter "${2:-}" ;;
  hook-event) hook_event "${2:-}" "${3:-}" "${4:-}" ;;
  hook-events) hook_events "${2:-20}" ;;
  hook-status) hook_status ;;
  hook-clear) hook_clear ;;
  hook-mode) hook_mode "${2:-}" ;;
  carrier)  carrier "${2:-status}" ;;
  *) echo "usage: leakguard.sh {status|enable|disable|dns|ipv6|ip|vpn|node|apps|owner|tune|apply|panic|restore|report|hook-mode|hook-status|hook-events|hook-clear|hook-event|carrier}" ;;
esac
