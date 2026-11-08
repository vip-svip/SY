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
#   FX_ARB_LINK_FILE    回归夹具：只读文件，内容为 ip -o link show 输出
#   FX_ARB_VPNINFO_FILE 回归夹具：只读文件，内容为 "<iface>|<ownerUid>" 或空
#   测试注入只读数据，不执行环境变量中的命令。
#   FX_ARB_PROC_NET_DIR 替代 /proc/net（含 tcp tcp6 udp udp6）
#   FX_ARB_MODULE_ROOT  静态槽位不变量扫描根目录
#   FX_ARB_DNS_PORT / FX_ARB_FILTER_DNS_PORT / FX_ARB_PROXY_PORT  本地服务端口
# =============================================================================
set -u

FX_ARB_VERSION="1.0.0"
FX_ARB_DNS_PORT=${FX_ARB_DNS_PORT:-5353}
# AdGuard Home is the client-facing DNS filter and binds port 53; Unbound
# remains the independent upstream resolver on 5353. Probe both separately.
FX_ARB_FILTER_DNS_PORT=${FX_ARB_FILTER_DNS_PORT:-53}
FX_ARB_PROXY_PORT=${FX_ARB_PROXY_PORT:-7890}
# All fixture inputs are accepted only by the explicit regression harness.
# In production, probe sources are pinned to live Android system paths so a
# caller cannot feed a clean fixture and obtain a false compatibility verdict.
if [ "${FX_ARB_TESTING:-0}" = "1" ]; then
  FX_ARB_LINK_FILE=${FX_ARB_LINK_FILE:-}
  FX_ARB_VPNINFO_FILE=${FX_ARB_VPNINFO_FILE:-}
  FX_ARB_SELF_UID=${FX_ARB_SELF_UID:-}
  FX_ARB_PROC_NET_DIR=${FX_ARB_PROC_NET_DIR:-/proc/net}
else
  FX_ARB_LINK_FILE=
  FX_ARB_VPNINFO_FILE=
  FX_ARB_SELF_UID=
  FX_ARB_PROC_NET_DIR=/proc/net
fi
FX_ARB_SELF_VPN=false
FX_ARB_SELF_IF=""
# A caller-controlled module root could point the static slot scan at an
# unrelated clean directory and falsely certify that FX does not use VpnService.
# Permit fixture injection only in the regression harness; production always
# derives the module root from this script's own installed location.
if [ "${FX_ARB_TESTING:-0}" = "1" ]; then
  FX_ARB_MODULE_ROOT=${FX_ARB_MODULE_ROOT:-}
else
  FX_ARB_MODULE_ROOT=
fi
if [ -z "$FX_ARB_MODULE_ROOT" ]; then
  case "$0" in
    */scripts/fx-vpn-coexistence-arbiter.sh)
      FX_ARB_MODULE_ROOT=${0%/scripts/fx-vpn-coexistence-arbiter.sh}
      ;;
  esac
fi

# --- 端口占用：直接读 /proc/net，不依赖 ss/netstat/lsof（Android 常缺） -------
fx_arb_normalize_port() {
  _v=$1
  case "$_v" in ''|*[!0-9]*) return 2 ;; esac
  # Strip leading zeroes before numeric tests: shell test/printf may interpret
  # a leading zero as octal. Bound decimal width before arithmetic to avoid
  # integer overflow from malformed environment values.
  while [ "${#_v}" -gt 1 ] && [ "${_v#0}" != "$_v" ]; do
    _v=${_v#0}
  done
  [ "${#_v}" -le 5 ] || return 2
  [ "$_v" -ge 1 ] && [ "$_v" -le 65535 ] || return 2
  printf '%s' "$_v"
}

fx_arb_port_hex() {
  _v=$(fx_arb_normalize_port "$1") || return 2
  printf '%04X' "$_v"
}

# Emit a JSON number only after strict decimal/range validation. Invalid
# configuration is represented as null, never interpolated into JSON.
fx_arb_json_port() {
  _v=$(fx_arb_normalize_port "$1") || { printf 'null'; return 0; }
  printf '%s' "$_v"
}

fx_arb_display_port() {
  _v=$(fx_arb_normalize_port "$1") || { printf 'invalid'; return 0; }
  printf '%s' "$_v"
}

# fx_arb_listening <hexport> <file...> -> 0 表示存在监听套接字
fx_arb_listening() {
  _want=$1
  shift
  for _f in "$@"; do
    [ -r "$_f" ] || continue
    case "$_f" in */udp|*/udp6) _is_udp=1 ;; *) _is_udp=0 ;; esac
    if awk -v want="$_want" -v is_udp="$_is_udp" '
      NR > 1 {
        n = split($2, a, ":")
        if (n < 2 || toupper(a[n]) != want) next
        # TCP sockets are conflicts only while listening. UDP tables are
        # already bound-socket inventories (normally state 07), regardless
        # of awk FILENAME behavior.
        if (is_udp == 1 || toupper($4) == "0A") found = 1
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

# Detect collisions between FX-owned listeners before checking the host socket table.
# A free port is not sufficient when two FX daemons are configured to bind it.
fx_arb_config_conflicts() {
  _dns=$(fx_arb_normalize_port "$FX_ARB_DNS_PORT" 2>/dev/null) || _dns=
  _filter=$(fx_arb_normalize_port "$FX_ARB_FILTER_DNS_PORT" 2>/dev/null) || _filter=
  _proxy=$(fx_arb_normalize_port "$FX_ARB_PROXY_PORT" 2>/dev/null) || _proxy=
  _out=""
  if [ -n "$_dns" ] && [ -n "$_filter" ] && [ "$_dns" = "$_filter" ]; then _out="dns=dns_filter"; fi
  if [ -n "$_dns" ] && [ -n "$_proxy" ] && [ "$_dns" = "$_proxy" ]; then _out="${_out}${_out:+,}dns=proxy"; fi
  if [ -n "$_filter" ] && [ -n "$_proxy" ] && [ "$_filter" = "$_proxy" ]; then _out="${_out}${_out:+,}dns_filter=proxy"; fi
  printf '%s' "$_out"
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
  # Keep the core dataplane entry points mandatory: an incomplete module must
  # never be certified as slot-independent.
  for _f in "$_root/scripts/apply.sh" "$_root/scripts/vpncore.sh" \
            "$_root/scripts/yulong-root-proxy.sh" "$_root/scripts/yulong-vpn-control.sh"; do
    if [ -L "$_f" ] || [ ! -f "$_f" ] || [ ! -r "$_f" ]; then
      _missing=1
    fi
  done

  # Scan every module-owned shell source, including newly added helpers.
  # Exclude this observer: it necessarily contains the VpnService detection
  # expression in its own source and must never self-report as a VPN client.
  # Full-line comments are not executable API usage and are ignored.
  _scan_count=0
  _find_failed=0
  # The binary override is honored only by isolated regression fixtures; on
  # an installed module the scanner always uses the platform find command.
  _find_bin=find
  if [ "${FX_ARB_TESTING:-0}" = "1" ] && [ -n "${FX_ARB_FIND_BIN:-}" ]; then
    _find_bin=$FX_ARB_FIND_BIN
  fi
  _scan_files=$("$_find_bin" "$_root" \( -type f -o -type l \) -name '*.sh' -print 2>/dev/null) || _find_failed=1
  # find does not follow directory symlinks. Reject links below scripts/ so
  # a linked directory cannot conceal a nested shell helper from this scan.
  _script_links=$("$_find_bin" "$_root/scripts" -type l -print 2>/dev/null) || _find_failed=1
  [ -z "$_script_links" ] || _missing=1
  while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    [ "$_f" = "$_root/scripts/fx-vpn-coexistence-arbiter.sh" ] && continue
    [ "$_f" = "$0" ] && continue
    _scan_count=$((_scan_count + 1))
    if [ -L "$_f" ] || [ ! -f "$_f" ] || [ ! -r "$_f" ]; then
      _missing=1
      continue
    fi
    if grep -v '^[[:space:]]*#' "$_f" 2>/dev/null | grep -Eq 'VpnService[[:space:]]*[.][[:space:]]*(prepare|Builder)|VpnService[$]Builder'; then
      _hit=1
    else
      _grep_rc=$?
      [ "$_grep_rc" -eq 1 ] || _missing=1
    fi
  done <<EOF
$_scan_files
EOF
  [ "$_find_failed" = "0" ] || _missing=1
  [ "$_scan_count" -gt 0 ] || _missing=1

  # A positive API match is decisive even if another scanned file is absent.
  # A negative result is valid only when every required and discovered shell
  # source is a readable regular file and the scan is non-empty.
  if [ "$_hit" = "1" ]; then
    printf 'true'
  elif [ "$_missing" = "1" ]; then
    printf 'unknown'
  else
    printf 'false'
  fi
}

# Read Android's authoritative active-VPN owner/interface record. A successful
# empty result is permitted only when dumpsys confirms its mVpns section.
# Missing/denied/partial dumpsys or multiple/malformed VpnInfo rows are unknown.
fx_arb_android_vpn_info() {
  command -v dumpsys >/dev/null 2>&1 || return 1
  _dump=$(dumpsys connectivity 2>/dev/null) || return 1
  [ -n "$_dump" ] || return 1
  printf '%s\n' "$_dump" | awk '
    /mVpns:/ { have_vpn_section=1 }
    index($0, "VpnInfo{") {
      rows++
      uid=""
      iface=""
      if (match($0, /ownerUid=[0-9]+/)) uid=substr($0, RSTART+9, RLENGTH-9)
      if (match($0, /vpnIface=[A-Za-z0-9_.-]+/)) iface=substr($0, RSTART+9, RLENGTH-9)
      if (uid=="" || iface=="") malformed=1
      else record=iface "|" uid
    }
    END {
      if (rows==1 && malformed==0) { print record; exit 0 }
      if (rows==0 && have_vpn_section==1) exit 0
      exit 1
    }
  '
}

# Resolve FX's package UID for the active Android user. VpnInfo exposes only
# ownerUid, not package name, so an active tunnel cannot be called third-party
# until this package UID comparison succeeds. FX_ARB_SELF_UID is test data only.
fx_arb_normalize_uid() {
  _v=$1
  case "$_v" in ''|*[!0-9]*|0) return 2 ;; esac
  while [ "${#_v}" -gt 1 ] && [ "${_v#0}" != "$_v" ]; do _v=${_v#0}; done
  [ "${#_v}" -le 10 ] || return 2
  printf '%s' "$_v"
}

fx_arb_self_uid() {
  if [ -n "$FX_ARB_SELF_UID" ]; then fx_arb_normalize_uid "$FX_ARB_SELF_UID"; return $?; fi
  command -v am >/dev/null 2>&1 || return 1
  _user=$(am get-current-user 2>/dev/null) || return 1
  case "$_user" in ''|*[!0-9]*) return 1 ;; esac
  [ "${#_user}" -le 5 ] || return 1
  _packages=
  if command -v cmd >/dev/null 2>&1; then _packages=$(cmd package list packages -U --user "$_user" de.privacyguard.adhook 2>/dev/null) || _packages=; fi
  if [ -z "$_packages" ] && command -v pm >/dev/null 2>&1; then _packages=$(pm list packages -U --user "$_user" de.privacyguard.adhook 2>/dev/null) || _packages=; fi
  [ -n "$_packages" ] || return 1
  _uid=$(printf '%s\n' "$_packages" | awk '
    $1 == "package:de.privacyguard.adhook" { for (i=2; i<=NF; i++) if ($i ~ /^uid:[0-9]+$/) { split($i,a,":"); uid=a[2]; rows++ } }
    END { if (rows == 1 && uid != "") print uid; else exit 1 }
  ') || return 1
  fx_arb_normalize_uid "$_uid"
}

# --- 活动 VPN 所有者探测：先排除 FX 自身 UID --------------------------------
fx_arb_probe_external() {
  FX_ARB_EXT_IF=""
  FX_ARB_EXT_UID=""
  FX_ARB_SELF_VPN=false
  FX_ARB_SELF_IF=""
  FX_ARB_PROBE="ok"

  if [ -n "$FX_ARB_LINK_FILE" ]; then
    [ -f "$FX_ARB_LINK_FILE" ] && [ ! -L "$FX_ARB_LINK_FILE" ] && [ -r "$FX_ARB_LINK_FILE" ] || { FX_ARB_PROBE="unavailable"; return 0; }
    _links=$(cat "$FX_ARB_LINK_FILE" 2>/dev/null) || _links=
  else
    _links=$(ip -o link show 2>/dev/null) || _links=
  fi
  if [ -z "$_links" ]; then
    FX_ARB_PROBE="unavailable"
    return 0
  fi
  _ifaces=$(printf '%s\n' "$_links" | sed -n 's/^[0-9][0-9]*: \([^:@]*\).*/\1/p' \
    | grep -E '^(tun[0-9]*|vpn[0-9]*|wg[0-9]*|ppp[0-9]*|ipsec[0-9]*|tap[0-9]*|utun[0-9]*|tailscale[0-9]*|zt[[:alnum:]_-]*)$' || true)

  if [ -n "$FX_ARB_VPNINFO_FILE" ]; then
    [ -f "$FX_ARB_VPNINFO_FILE" ] && [ ! -L "$FX_ARB_VPNINFO_FILE" ] && [ -r "$FX_ARB_VPNINFO_FILE" ] || { FX_ARB_PROBE="unavailable"; return 0; }
    _info=$(cat "$FX_ARB_VPNINFO_FILE" 2>/dev/null) || _info=
  else
    _info=$(fx_arb_android_vpn_info) || { FX_ARB_PROBE="unavailable"; return 0; }
  fi
  if [ -n "$_info" ]; then
    # The injected inventory follows the same single-record contract as the
    # production dumpsys parser. Multiple lines or delimiters are ambiguous;
    # silently accepting the first row could bind the wrong VPN owner.
    case "$_info" in
      *'
'*|*'|'*'|'*) FX_ARB_PROBE="ambiguous"; return 0 ;;
    esac
    _if=${_info%%|*}
    _uid=${_info#*|}
    case "$_uid" in
      ''|*[!0-9]*|0 ) FX_ARB_PROBE="ambiguous"; return 0 ;;
    esac
    case " $_ifaces " in
      *" $_if "*) FX_ARB_EXT_IF="$_if" ;;
      *) FX_ARB_PROBE="ambiguous" ;;
    esac
    if [ -n "$FX_ARB_EXT_IF" ]; then
      _uid=$(fx_arb_normalize_uid "$_uid") || { FX_ARB_PROBE="ambiguous"; FX_ARB_EXT_IF=""; return 0; }
      _self_uid=$(fx_arb_self_uid) || { FX_ARB_PROBE="unavailable"; FX_ARB_EXT_IF=""; return 0; }
      if [ "$_uid" = "$_self_uid" ]; then FX_ARB_SELF_VPN=true; FX_ARB_SELF_IF="$FX_ARB_EXT_IF"; FX_ARB_EXT_IF="";
      else FX_ARB_EXT_UID="$_uid"; fi
    fi
  elif [ -n "$_ifaces" ]; then
    # 有隧道样接口但拿不到唯一 VpnInfo/ownerUid：绝不猜哪条是外部 VPN。
    FX_ARB_PROBE="ambiguous"
  fi
  return 0
}

# Root Proxy's observe command is deliberately read-only. It proves only the
# DNS fallback chain: Unbound egress bound to the current external VPN tunnel,
# source-specific route consistency to authoritative resolver addresses, both
# FX-owned DNS redirects, exact chain contracts and live dual-stack DNS health.
# It does not prove non-DNS proxy traffic or full device-wide traffic chaining.
FX_ARB_ROOT_PROXY_STATE="unavailable"
FX_ARB_ROUTE_PROBE="unverified"
FX_ARB_RP_IF=""
FX_ARB_RP_UID=""
FX_ARB_RP_EGRESS=""
FX_ARB_RP_ROUTE="unknown"
FX_ARB_RP_REDIRECTS="unknown"
FX_ARB_RP_DNS_PROBE="unknown"
FX_ARB_ROOT_PROXY_DNS_CHAIN="unverified"
FX_ARB_RP_PRIVATE_DNS_MODE="unknown"
FX_ARB_RP_DNS_FILTER_COVERAGE="unknown"
FX_ARB_RP_ADGUARD_UPSTREAM_ROUTE="unknown"
FX_ARB_ROOT_PROXY_OUTPUT=""

fx_arb_root_proxy_field() {
  _key=$1
  printf '%s\n' "$FX_ARB_ROOT_PROXY_OUTPUT" | awk -F= -v key="$_key" '
    $1==key {
      if (NF!=2 || seen) bad=1
      seen++
      value=$2
    }
    END {
      if (bad || seen!=1) exit 1
      print value
    }
  '
}

fx_arb_valid_ipv4() {
  printf '%s\n' "$1" | awk -F. '
    NF!=4 {bad=1; exit}
    {
      for(i=1;i<=4;i++)
        if($i=="" || $i!~/^[0-9]+$/ || length($i)>3 || $i+0>255 ||
           ($i!="0" && $i~/^0/)) bad=1
      first=$1+0; second=$2+0
      if(first==0 || first==127 || first>=224 ||
         (first==169 && second==254)) bad=1
    }
    END {exit bad}
  '
}

fx_arb_probe_root_proxy_dns() {
  [ -n "$FX_ARB_EXT_IF" ] && [ -n "$FX_ARB_EXT_UID" ] || return 0
  _out=""
  _rc=1
  if [ "${FX_ARB_TESTING:-0}" = "1" ] && [ -n "${FX_ARB_ROOT_PROXY_OBSERVE_FILE:-}" ]; then
    _fixture=$FX_ARB_ROOT_PROXY_OBSERVE_FILE
    [ -f "$_fixture" ] && [ ! -L "$_fixture" ] && [ -r "$_fixture" ] || {
      FX_ARB_ROOT_PROXY_STATE="unknown"; return 0;
    }
    _out=$(cat "$_fixture" 2>/dev/null) || {
      FX_ARB_ROOT_PROXY_STATE="unknown"; return 0;
    }
    _rc=0
  else
    _script="${FX_ARB_MODULE_ROOT:-}/scripts/yulong-root-proxy.sh"
    if [ -n "$FX_ARB_MODULE_ROOT" ] && [ -f "$_script" ] && [ ! -L "$_script" ] && [ -r "$_script" ]; then
      if _out=$(MP="$FX_ARB_MODULE_ROOT" PG=/data/adb/privacyguard CONF=/data/adb/privacyguard/settings.conf sh "$_script" observe 2>/dev/null); then
        _rc=0
      else
        _rc=$?
      fi
    else
      FX_ARB_ROOT_PROXY_STATE="unavailable"
      return 0
    fi
  fi
  FX_ARB_ROOT_PROXY_OUTPUT=$_out
  if [ "$_rc" -ne 0 ]; then
    _active=$(fx_arb_root_proxy_field active 2>/dev/null || :)
    case "$_active" in 0) FX_ARB_ROOT_PROXY_STATE="inactive" ;; *) FX_ARB_ROOT_PROXY_STATE="unavailable" ;; esac
    return 0
  fi
  _active=$(fx_arb_root_proxy_field active 2>/dev/null || :)
  case "$_active" in 0) FX_ARB_ROOT_PROXY_STATE="inactive"; return 0 ;; 1) : ;; *) FX_ARB_ROOT_PROXY_STATE="unknown"; return 0 ;; esac
  _iface=$(fx_arb_root_proxy_field interface 2>/dev/null || :)
  _uid=$(fx_arb_root_proxy_field vpn_uid 2>/dev/null || :)
  _egress=$(fx_arb_root_proxy_field egress_ipv4 2>/dev/null || :)
  _route=$(fx_arb_root_proxy_field route 2>/dev/null || :)
  _redirects=$(fx_arb_root_proxy_field redirects 2>/dev/null || :)
  _dns_probe=$(fx_arb_root_proxy_field dns_probe 2>/dev/null || :)
  _dns_chain=$(fx_arb_root_proxy_field dns_chain 2>/dev/null || :)
  _private_dns=$(fx_arb_root_proxy_field private_dns_mode 2>/dev/null || :)
  _coverage=$(fx_arb_root_proxy_field dns_filter_coverage 2>/dev/null || :)
  _adguard_upstream_route=$(fx_arb_root_proxy_field adguard_upstream_route 2>/dev/null || :)
  _uid=$(fx_arb_normalize_uid "$_uid" 2>/dev/null) || {
    FX_ARB_ROOT_PROXY_STATE="mismatch"; return 0;
  }
  if [ "$_iface" != "$FX_ARB_EXT_IF" ] || [ "$_uid" != "$FX_ARB_EXT_UID" ] ||
      ! fx_arb_valid_ipv4 "$_egress"; then
    FX_ARB_ROOT_PROXY_STATE="mismatch"
    return 0
  fi
  case "$_route" in verified) ;; *) FX_ARB_ROOT_PROXY_STATE="unverified"; return 0 ;; esac
  case "$_redirects" in attached) ;; *) FX_ARB_ROOT_PROXY_STATE="unverified"; return 0 ;; esac
  case "$_dns_probe" in passed) ;; *) FX_ARB_ROOT_PROXY_STATE="unverified"; return 0 ;; esac
  case "$_dns_chain" in verified|partial) ;; *) FX_ARB_ROOT_PROXY_STATE="unverified"; return 0 ;; esac
  case "$_private_dns" in off|opportunistic|hostname|unknown) ;; *) FX_ARB_ROOT_PROXY_STATE="unverified"; return 0 ;; esac
  case "$_coverage" in port53_redirect_active|opportunistic_private_dns_may_bypass_redirect|strict_private_dns_bypasses_redirect|unknown) ;; *) FX_ARB_ROOT_PROXY_STATE="unverified"; return 0 ;; esac
  case "$_adguard_upstream_route" in unbound_pinned|unverified|unknown) ;; *) _adguard_upstream_route=unknown ;; esac
  if [ "$_dns_chain" = verified ] && [ "$_private_dns" = off ] &&
      [ "$_coverage" = port53_redirect_active ] &&
      [ "$_adguard_upstream_route" = unbound_pinned ]; then
    FX_ARB_ROUTE_PROBE="dns_chain_verified"
    FX_ARB_ROOT_PROXY_DNS_CHAIN="verified"
  else
    if [ "$_adguard_upstream_route" = unbound_pinned ]; then
      FX_ARB_ROUTE_PROBE="dns_route_verified"
    else
      FX_ARB_ROUTE_PROBE="dns_upstream_route_unverified"
    fi
    FX_ARB_ROOT_PROXY_DNS_CHAIN="partial"
  fi
  FX_ARB_ROOT_PROXY_STATE="active"
  FX_ARB_RP_IF=$_iface
  FX_ARB_RP_UID=$_uid
  FX_ARB_RP_EGRESS=$_egress
  FX_ARB_RP_ROUTE=$_route
  FX_ARB_RP_REDIRECTS=$_redirects
  FX_ARB_RP_DNS_PROBE=$_dns_probe
  FX_ARB_RP_PRIVATE_DNS_MODE=$_private_dns
  FX_ARB_RP_DNS_FILTER_COVERAGE=$_coverage
  FX_ARB_RP_ADGUARD_UPSTREAM_ROUTE=$_adguard_upstream_route
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
  FX_ARB_CONFIG_CONFLICTS=$(fx_arb_config_conflicts)

  # 1) An active VPN owned by FX's package UID also violates the no-slot contract.
  if [ "$FX_ARB_SELF_VPN" = "true" ]; then
    FX_ARB_VERDICT="incompatible"; FX_ARB_GRADE_CN="不兼容"
    FX_ARB_REASONS="active VPN owner UID matches FX package UID on ${FX_ARB_SELF_IF}; FX occupies Android's VPN slot"
    FX_ARB_RC=3; return 0
  fi

  # 2) 硬性不变量：Root 数据面占槽 = 不兼容（违反"不占 VpnService 槽"）
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

  # A deterministic internal port collision is a known degradation even if
  # the host's /proc/net inventory is otherwise clean.
  if [ -n "$FX_ARB_CONFIG_CONFLICTS" ]; then
    FX_ARB_VERDICT="partial"
    FX_ARB_GRADE_CN="部分兼容"
    FX_ARB_REASONS="FX services share configured listener ports: $FX_ARB_CONFIG_CONFLICTS"
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
    FX_ARB_REASONS="no external VPN detected; kernel dataplane is configured outside the VPN slot; live traffic path remains unverified"
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
  if [ "$FX_ARB_ROOT_PROXY_STATE" = "active" ]; then
    if [ "$FX_ARB_ROOT_PROXY_DNS_CHAIN" = "verified" ]; then
      FX_ARB_REASONS="external VPN ${FX_ARB_EXT_IF} (uid ${FX_ARB_EXT_UID}) verified for the Root Proxy DNS chain; non-DNS FX proxy traffic path remains unverified"
    elif [ "$FX_ARB_RP_ADGUARD_UPSTREAM_ROUTE" != "unbound_pinned" ]; then
      FX_ARB_REASONS="external VPN ${FX_ARB_EXT_IF} (uid ${FX_ARB_EXT_UID}) route is verified for Unbound, but AdGuard Home custom/global upstream or fallback sockets are not proven to use the VPN-bound Unbound resolver; DNS chain and non-DNS FX proxy traffic remain partial"
    else
      FX_ARB_REASONS="external VPN ${FX_ARB_EXT_IF} (uid ${FX_ARB_EXT_UID}) verified for Unbound DNS egress; Android Private DNS may bypass port-53 filtering and non-DNS FX proxy traffic remains unverified"
    fi
  elif [ "$FX_ARB_ROOT_PROXY_STATE" = "mismatch" ]; then
    FX_ARB_REASONS="Root Proxy active VPN interface/UID does not match the current Android VpnInfo; refusing to claim a verified DNS chain"
  else
    FX_ARB_REASONS="external VPN ${FX_ARB_EXT_IF} (uid ${FX_ARB_EXT_UID}) detected; route and return-path behavior remain unverified"
  fi
  return 0
}

fx_arb_json() {
  _san=$(printf '%s' "$FX_ARB_REASONS" | sed 's/[^ -~]//g; s/["\\]//g')
  if [ -n "$FX_ARB_EXT_IF" ]; then _ext=true; else _ext=false; fi
  _active_if=$FX_ARB_EXT_IF; _vpn_owner=external
  if [ "$FX_ARB_SELF_VPN" = "true" ]; then _active_if=$FX_ARB_SELF_IF; _vpn_owner=fx_uid
  elif [ "$_ext" = "false" ]; then _vpn_owner=none; fi
  printf '{"ok":1,"version":"%s","verdict":"%s","grade_cn":"%s","exit":%s,' "$FX_ARB_VERSION" "$FX_ARB_VERDICT" "$FX_ARB_GRADE_CN" "$FX_ARB_RC"
  printf '"external_vpn":%s,"external_if":"%s","external_uid":"%s","active_vpn_if":"%s","vpn_owner":"%s","probe":"%s",' "$_ext" "$FX_ARB_EXT_IF" "$FX_ARB_EXT_UID" "$_active_if" "$_vpn_owner" "$FX_ARB_PROBE"
  case "$FX_ARB_SLOT_USED" in true|false) _slot_json=$FX_ARB_SLOT_USED ;; *) _slot_json=null ;; esac
  printf '"vpn_service_slot_used":%s,' "$_slot_json"
  printf '"dns":{"port":%s,"owner":"%s"},"dns_filter":{"port":%s,"owner":"%s"},"proxy":{"port":%s,"owner":"%s"},' "$(fx_arb_json_port "$FX_ARB_DNS_PORT")" "$FX_ARB_DNS_OWNER" "$(fx_arb_json_port "$FX_ARB_FILTER_DNS_PORT")" "$FX_ARB_FILTER_DNS_OWNER" "$(fx_arb_json_port "$FX_ARB_PROXY_PORT")" "$FX_ARB_PROXY_OWNER"
  printf '"config_conflicts":"%s",' "$FX_ARB_CONFIG_CONFLICTS"
  printf '"root_proxy":{"state":"%s","interface":"%s","vpn_uid":"%s","egress_ipv4":"%s","route":"%s","redirects":"%s","dns_probe":"%s","dns_chain":"%s","private_dns_mode":"%s","dns_filter_coverage":"%s","adguard_upstream_route":"%s"},' "$FX_ARB_ROOT_PROXY_STATE" "$FX_ARB_RP_IF" "$FX_ARB_RP_UID" "$FX_ARB_RP_EGRESS" "$FX_ARB_RP_ROUTE" "$FX_ARB_RP_REDIRECTS" "$FX_ARB_RP_DNS_PROBE" "$FX_ARB_ROOT_PROXY_DNS_CHAIN" "$FX_ARB_RP_PRIVATE_DNS_MODE" "$FX_ARB_RP_DNS_FILTER_COVERAGE" "$FX_ARB_RP_ADGUARD_UPSTREAM_ROUTE"
  printf '"dataplane":"kernel","route_probe":"%s","reasons":"%s"}\n' "$FX_ARB_ROUTE_PROBE" "$_san"
}

fx_arb_text() {
  echo "FX coexistence arbiter v$FX_ARB_VERSION"
  echo "  verdict : $FX_ARB_VERDICT ($FX_ARB_GRADE_CN)"
  _active_if=${FX_ARB_SELF_IF:-${FX_ARB_EXT_IF:-none}}
  _vpn_owner=none
  [ "$FX_ARB_SELF_VPN" = "true" ] && _vpn_owner=fx_uid
  [ -n "$FX_ARB_EXT_IF" ] && _vpn_owner=external
  echo "  active VPN: $_active_if owner=$_vpn_owner uid=${FX_ARB_EXT_UID:-none} probe=$FX_ARB_PROBE"
  echo "  slot    : vpn_service_slot_used=$FX_ARB_SLOT_USED (must be false)"
  echo "  FX port collisions: ${FX_ARB_CONFIG_CONFLICTS:-none}"
  echo "  dns upstream : port $(fx_arb_display_port "$FX_ARB_DNS_PORT") owner=$FX_ARB_DNS_OWNER"
  echo "  dns filter   : port $(fx_arb_display_port "$FX_ARB_FILTER_DNS_PORT") owner=$FX_ARB_FILTER_DNS_OWNER"
  echo "  proxy        : port $(fx_arb_display_port "$FX_ARB_PROXY_PORT") owner=$FX_ARB_PROXY_OWNER"
  echo "  Root Proxy DNS chain: state=$FX_ARB_ROOT_PROXY_STATE route=$FX_ARB_RP_ROUTE dns=$FX_ARB_ROOT_PROXY_DNS_CHAIN coverage=$FX_ARB_RP_DNS_FILTER_COVERAGE AdGuard-upstream=$FX_ARB_RP_ADGUARD_UPSTREAM_ROUTE"
  echo "  route probe : $FX_ARB_ROUTE_PROBE"
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
  fx_arb_probe_root_proxy_dns
  fx_arb_decide

  if [ "$_mode" = "text" ]; then fx_arb_text; else fx_arb_json; fi
  exit "$FX_ARB_RC"
}

main "$@"
