#!/system/bin/sh
# =============================================================================
# FX 1.0.0 —— 内核级代理 / 第三方 VPN 共存裁决器
#
# 产品要求（docs/FX_1.0.0_PRODUCT_RESTRUCTURE_AND_AI_HANDOFF.md）：
#   - FX 代理主实现必须是 Root/系统网络栈级数据面，**不占 Android VPN 槽**；
#   - 第三方 VPN 占用 VPN 槽时，FX 内核级代理不得因此自动关闭；
#   - 必须实测网络路径并分级为「完全并行 / 受支持链式 / 部分兼容 / 不兼容」；
#   - 本地 DNS 是独立服务，必须避免端口冲突。
#
# 本脚本只做"观察与裁决"，不修改任何 iptables/nftables/ip rule/路由。
# 它是可被 WebUI / apply.sh 调用的真实检测器：结果全部来自本机实时状态。
#
# 用法：
#   fx-vpn-coexistence-arbiter.sh            # JSON（默认）
#   fx-vpn-coexistence-arbiter.sh --text     # 人类可读
#
# 退出码：0=正常（可共存等级，或无外部 VPN）
#         2=探测不可用/状态歧义（fail-safe，不得谎报并行）
#         3=不兼容（真违规：FX 自身占槽，或本地服务端口被他人占用且无回退）
#
# 测试注入点（仅回归使用；生产留空即读真实系统）：
#   FX_ARB_LINK_CMD     替代 `ip -o link show`
#   FX_ARB_VPNINFO_CMD  产出 "<iface>|<ownerUid>" 或空
#   FX_ARB_PROC_NET_DIR 替代 /proc/net（含 tcp tcp6 udp udp6）
#   FX_ARB_MODULE_ROOT  静态槽位不变量扫描根目录
#   FX_ARB_DNS_PORT / FX_ARB_PROXY_PORT  本地服务端口
# =============================================================================
set -u

FX_ARB_VERSION="1.0.0"
FX_ARB_DNS_PORT=${FX_ARB_DNS_PORT:-5353}
# AdGuard Home is the client-facing DNS filter and binds port 53; Unbound
# remains the independent upstream resolver on 5353. Probe both separately.
FX_ARB_FILTER_DNS_PORT=${FX_ARB_FILTER_DNS_PORT:-53}
FX_ARB_PROXY_PORT=${FX_ARB_PROXY_PORT:-7890}
FX_ARB_LINK_CMD=${FX_ARB_LINK_CMD:-"ip -o link show"}
FX_ARB_VPNINFO_CMD=${FX_ARB_VPNINFO_CMD:-"vpncore_android_active_vpn_info"}
FX_ARB_PROC_NET_DIR=${FX_ARB_PROC_NET_DIR:-/proc/net}
FX_ARB_MODULE_ROOT=${FX_ARB_MODULE_ROOT:-}
# In production the arbiter is executed from the active FX module's scripts/
# directory. Derive that exact module root unless a regression injects one.
if [ -z "$FX_ARB_MODULE_ROOT" ]; then
  case "$0" in
    */scripts/fx-vpn-coexistence-arbiter.sh)
      FX_ARB_MODULE_ROOT=${0%/scripts/fx-vpn-coexistence-arbiter.sh}
      ;;
  esac
fi

# --- 端口占用：直接读 /proc/net，不依赖 ss/netstat/lsof（Android 常缺） -------
fx_arb_port_hex() {
  _v=$1
  case "$_v" in ''|*[!0-9]*) return 2 ;; esac
  [ "$_v" -ge 1 ] && [ "$_v" -le 65535 ] || return 2
  printf '%04X' "$_v"
}

# fx_arb_listening <hexport> <file...> -> 0 表示存在监听套接字
fx_arb_listening() {
  _want=$1
  shift
  for _f in "$@"; do
    [ -r "$_f" ] || continue
    if awk -v want="$_want" '
      NR > 1 {
        n = split($2, a, ":")
        if (n < 2 || toupper(a[n]) != want) next
        # TCP sockets are conflicts only while listening. A bound UDP socket
        # appears in udp/udp6 (normally state 07); UDP has no LISTEN state.
        is_udp = (FILENAME ~ /\/udp6?$/)
        if (is_udp || toupper($4) == "0A") found = 1
      }
      END { exit(found ? 0 : 1) }
    ' "$_f"; then
      return 0
    fi
  done
  return 1
}

# fx_arb_port_owner <port> -> free | other | unknown
#   free    : 无监听者（FX 可以安全绑定）
#   other   : 已有监听者（视为他人占用；FX 不得争抢，需换端口或降级）
#   unknown : /proc/net 不可读（不得据此声称无冲突）
fx_arb_port_owner() {
  _port=$1
  _hx=$(fx_arb_port_hex "$_port") || { printf 'unknown'; return 0; }
  _files="$FX_ARB_PROC_NET_DIR/tcp $FX_ARB_PROC_NET_DIR/tcp6 $FX_ARB_PROC_NET_DIR/udp $FX_ARB_PROC_NET_DIR/udp6"
  # A partial inventory is not evidence that the missing protocol/family is
  # free. Require every proc-net table before making a negative assertion.
  for _f in $_files; do
    [ -r "$_f" ] || { printf 'unknown'; return 0; }
  done

  if fx_arb_listening "$_hx" $_files; then
    printf 'other'
  else
    printf 'free'
  fi
  return 0
}

# --- 静态不变量：Root 内核数据面绝不能创建 VpnService（否则会抢槽） -----------
fx_arb_slot_used() {
  _root=${FX_ARB_MODULE_ROOT:-}
  [ -n "$_root" ] || { printf 'unknown'; return 0; }
  [ -d "$_root" ] && [ ! -L "$_root" ] || { printf 'unknown'; return 0; }

  # Reject symlinked Android module ancestors when running from the real
  # KernelSU/Magisk module location. Test fixtures may use isolated /tmp roots.
  case "$_root" in
    /data/adb/modules/*)
      for _path in /data /data/adb /data/adb/modules; do
        [ -d "$_path" ] && [ ! -L "$_path" ] || { printf 'unknown'; return 0; }
      done
      ;;
    /data/adb/modules_update/*)
      for _path in /data /data/adb /data/adb/modules_update; do
        [ -d "$_path" ] && [ ! -L "$_path" ] || { printf 'unknown'; return 0; }
      done
      ;;
  esac

  _prop="$_root/module.prop"
  [ -f "$_prop" ] && [ ! -L "$_prop" ] && [ -r "$_prop" ] \
    && grep -qx 'id=privacyguard' "$_prop" \
    && grep -qx 'version=1.0.0' "$_prop" || { printf 'unknown'; return 0; }

  _hit=0
  _missing=0
  for _f in "$_root/scripts/apply.sh" "$_root/scripts/vpncore.sh" \
            "$_root/scripts/yulong-root-proxy.sh" "$_root/scripts/yulong-vpn-control.sh"; do
    if [ -L "$_f" ] || [ ! -f "$_f" ] || [ ! -r "$_f" ]; then
      _missing=1
      continue
    fi
    if grep -Eq 'VpnService[[:space:]]*\.[[:space:]]*(prepare|Builder)|VpnService\$Builder' "$_f" 2>/dev/null; then
      _hit=1
    fi
  done

  # A positive API match is decisive even if another scanned file is absent.
  # A negative result is valid only when every required dataplane file exists.
  if [ "$_hit" = "1" ]; then
    printf 'true'
  elif [ "$_missing" = "1" ]; then
    printf 'unknown'
  else
    printf 'false'
  fi
}

# --- 外部 VPN 探测：接口与 ownerUid 必须来自同一条有效 VpnInfo ----------------
fx_arb_probe_external() {
  FX_ARB_EXT_IF=""
  FX_ARB_EXT_UID=""
  FX_ARB_PROBE="ok"

  _links=$(eval "$FX_ARB_LINK_CMD" 2>/dev/null)
  if [ -z "$_links" ]; then
    FX_ARB_PROBE="unavailable"
    return 0
  fi
  _ifaces=$(printf '%s\n' "$_links" | sed -n 's/^[0-9][0-9]*: \([^:@]*\).*/\1/p' \
    | grep -E '^(tun[0-9]*|vpn[0-9]*|wg[0-9]*|ppp[0-9]*|ipsec[0-9]*|tap[0-9]*|utun[0-9]*|tailscale[0-9]*|zt[[:alnum:]_-]*)$' || true)

  _info=$(eval "$FX_ARB_VPNINFO_CMD" 2>/dev/null || true)
  if [ -n "$_info" ]; then
    _if=${_info%%|*}
    _uid=${_info#*|}
    case " $_ifaces " in
      *" $_if "*) FX_ARB_EXT_IF="$_if" ;;
      *) FX_ARB_PROBE="ambiguous" ;;
    esac
    case "$_uid" in
      ''|*[!0-9]*|0) _uid="" ;;
    esac
    [ -n "$FX_ARB_EXT_IF" ] && FX_ARB_EXT_UID="$_uid"
  elif [ -n "$_ifaces" ]; then
    # 有隧道样接口但拿不到唯一 VpnInfo/ownerUid：绝不猜哪条是外部 VPN。
    FX_ARB_PROBE="ambiguous"
  fi
  return 0
}

# --- 裁决 -------------------------------------------------------------------
# 分级：kernel_only(内核级独立) / full_parallel(完全并行) / chained(受支持链式)
#       / partial(部分兼容) / incompatible(不兼容) / unknown(探测不可用)
fx_arb_decide() {
  FX_ARB_VERDICT=""
  FX_ARB_GRADE_CN=""
  FX_ARB_REASONS=""
  FX_ARB_RC=0

  FX_ARB_SLOT_USED=$(fx_arb_slot_used)
  FX_ARB_DNS_OWNER=$(fx_arb_port_owner "$FX_ARB_DNS_PORT")
  FX_ARB_FILTER_DNS_OWNER=$(fx_arb_port_owner "$FX_ARB_FILTER_DNS_PORT")
  FX_ARB_PROXY_OWNER=$(fx_arb_port_owner "$FX_ARB_PROXY_PORT")

  # 1) 硬性不变量：Root 数据面占槽 = 不兼容（违反"不占 VpnService 槽"）
  if [ "$FX_ARB_SLOT_USED" = "true" ]; then
    FX_ARB_VERDICT="incompatible"
    FX_ARB_GRADE_CN="不兼容"
    FX_ARB_REASONS="root dataplane calls VpnService API and would occupy the VPN slot"
    FX_ARB_RC=3
    return 0
  fi

  # 2) 槽位不变量无法完整核实时，不能把数据面标成独立运行。
  if [ "$FX_ARB_SLOT_USED" = "unknown" ]; then
    FX_ARB_VERDICT="unknown"
    FX_ARB_GRADE_CN="探测不可用"
    FX_ARB_REASONS="unable to verify the FX module dataplane VpnService invariant"
    FX_ARB_RC=2
    return 0
  fi

  # 3) 探测不可用/歧义：fail-safe，不谎报并行
  if [ "$FX_ARB_PROBE" = "unavailable" ] || [ "$FX_ARB_PROBE" = "ambiguous" ]; then
    FX_ARB_VERDICT="unknown"
    FX_ARB_GRADE_CN="探测不可用"
    FX_ARB_REASONS="external VPN presence ${FX_ARB_PROBE}; refusing to claim coexistence"
    FX_ARB_RC=2
    return 0
  fi

  # 3) 无外部 VPN：内核数据面独立运行（不涉及槽位争用）
  if [ -z "$FX_ARB_EXT_IF" ]; then
    if [ "$FX_ARB_DNS_OWNER" = "other" ] || [ "$FX_ARB_FILTER_DNS_OWNER" = "other" ] || [ "$FX_ARB_PROXY_OWNER" = "other" ]; then
      FX_ARB_VERDICT="partial"
      FX_ARB_GRADE_CN="部分兼容"
      FX_ARB_REASONS="no external VPN, but a local service port is owned by another process"
      return 0
    fi
    if [ "$FX_ARB_DNS_OWNER" = "unknown" ] || [ "$FX_ARB_FILTER_DNS_OWNER" = "unknown" ] || [ "$FX_ARB_PROXY_OWNER" = "unknown" ]; then
      FX_ARB_VERDICT="partial"
      FX_ARB_GRADE_CN="部分兼容"
      FX_ARB_REASONS="no external VPN, but local port state is unreadable"
      return 0
    fi
    FX_ARB_VERDICT="kernel_only"
    FX_ARB_GRADE_CN="内核级独立"
    FX_ARB_REASONS="no external VPN detected; kernel dataplane runs without the VPN slot"
    return 0
  fi

  # 4) 外部 VPN 存在：只有端口都空闲才算真正并行
  if [ "$FX_ARB_DNS_OWNER" = "other" ] || [ "$FX_ARB_FILTER_DNS_OWNER" = "other" ] || [ "$FX_ARB_PROXY_OWNER" = "other" ]; then
    FX_ARB_VERDICT="partial"
    FX_ARB_GRADE_CN="部分兼容"
    FX_ARB_REASONS="external VPN on ${FX_ARB_EXT_IF} plus a local port already occupied; one pipeline degraded"
    return 0
  fi
  if [ "$FX_ARB_DNS_OWNER" = "unknown" ] || [ "$FX_ARB_FILTER_DNS_OWNER" = "unknown" ] || [ "$FX_ARB_PROXY_OWNER" = "unknown" ]; then
    FX_ARB_VERDICT="partial"
    FX_ARB_GRADE_CN="部分兼容"
    FX_ARB_REASONS="external VPN on ${FX_ARB_EXT_IF} but local port state unreadable"
    return 0
  fi

  # Interface/UID discovery proves VPN presence and ownership only. It does
  # not prove packet routing, return path, DNS reachability, or tunnel binding.
  # Until an end-to-end data-plane probe exists, never certify parallel/chained.
  FX_ARB_VERDICT="partial"
  FX_ARB_GRADE_CN="部分兼容"
  if [ -n "$FX_ARB_EXT_UID" ]; then
    FX_ARB_REASONS="external VPN ${FX_ARB_EXT_IF} (uid ${FX_ARB_EXT_UID}) detected; route and return-path behavior are unverified"
  else
    FX_ARB_REASONS="external VPN ${FX_ARB_EXT_IF} detected without owner uid; route and outer-tunnel binding are unverified"
  fi
  return 0
}

fx_arb_json() {
  _san=$(printf '%s' "$FX_ARB_REASONS" | sed 's/[^ -~]//g; s/["\\]//g')
  if [ -n "$FX_ARB_EXT_IF" ]; then _ext=true; else _ext=false; fi
  printf '{"ok":1,"version":"%s","verdict":"%s","grade_cn":"%s","exit":%s,' \
    "$FX_ARB_VERSION" "$FX_ARB_VERDICT" "$FX_ARB_GRADE_CN" "$FX_ARB_RC"
  printf '"external_vpn":%s,"external_if":"%s","external_uid":"%s","probe":"%s",' \
    "$_ext" "$FX_ARB_EXT_IF" "$FX_ARB_EXT_UID" "$FX_ARB_PROBE"
  case "$FX_ARB_SLOT_USED" in
    true|false) _slot_json=$FX_ARB_SLOT_USED ;;
    *) _slot_json=null ;;
  esac
  printf '"vpn_service_slot_used":%s,' "$_slot_json"
  printf '"dns":{"port":%s,"owner":"%s"},"dns_filter":{"port":%s,"owner":"%s"},"proxy":{"port":%s,"owner":"%s"},' \
    "$FX_ARB_DNS_PORT" "$FX_ARB_DNS_OWNER" "$FX_ARB_FILTER_DNS_PORT" "$FX_ARB_FILTER_DNS_OWNER" "$FX_ARB_PROXY_PORT" "$FX_ARB_PROXY_OWNER"
  printf '"dataplane":"kernel","route_probe":"unverified","reasons":"%s"}\n' "$_san"
}

fx_arb_text() {
  echo "FX coexistence arbiter v$FX_ARB_VERSION"
  echo "  verdict : $FX_ARB_VERDICT ($FX_ARB_GRADE_CN)"
  echo "  external: ${FX_ARB_EXT_IF:-none} uid=${FX_ARB_EXT_UID:-none} probe=$FX_ARB_PROBE"
  echo "  slot    : vpn_service_slot_used=$FX_ARB_SLOT_USED (must be false)"
  echo "  dns upstream : port $FX_ARB_DNS_PORT owner=$FX_ARB_DNS_OWNER"
  echo "  dns filter   : port $FX_ARB_FILTER_DNS_PORT owner=$FX_ARB_FILTER_DNS_OWNER"
  echo "  proxy        : port $FX_ARB_PROXY_PORT owner=$FX_ARB_PROXY_OWNER"
  echo "  reasons : $FX_ARB_REASONS"
}

main() {
  _mode=json
  case "${1:-}" in
    --text) _mode=text ;;
    --json|"") ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac

  fx_arb_probe_external
  fx_arb_decide

  if [ "$_mode" = "text" ]; then fx_arb_text; else fx_arb_json; fi
  exit "$FX_ARB_RC"
}

main "$@"
