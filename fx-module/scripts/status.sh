#!/system/bin/sh
# PrivacyGuard status.sh — 输出模块状态（JSON 或纯文本）
# >>> pg-moddir (auto)
# 兼容相对路径/软链/su 调用：先尝试按 $0 推导，失败再逐级向上找 module.prop
_pg_d=$(dirname "$0" 2>/dev/null)
MODDIR=$(cd "$_pg_d" 2>/dev/null && pwd)
case "$MODDIR" in */scripts) MODDIR=${MODDIR%/scripts} ;; esac
if [ ! -f "$MODDIR/module.prop" ]; then
  _pg_d2=$MODDIR
  _pg_n=0
  while [ -n "$_pg_d2" ] && [ "$_pg_d2" != "/" ] && [ $_pg_n -lt 4 ]; do
    if [ -f "$_pg_d2/module.prop" ]; then MODDIR=$_pg_d2; break; fi
    _pg_d2=$(dirname "$_pg_d2")
    _pg_n=$((_pg_n+1))
  done
fi
PG_MODDIR=$MODDIR
# <<< pg-moddir
. "$MODDIR/scripts/util.sh"

# Explicit active DNS probe is opt-in; normal status polling remains side-effect-free.
if [ "${1:-}" = "dns-check" ]; then
  shift
  exec sh "$MODDIR/scripts/dnscheck.sh" "${1:-text}" "${2:-example.com}"
fi

# 管理器检测
detect_manager() {
  if [ -d /data/adb/ksu ] || [ -d /data/adb/ksud ]; then echo "KernelSU"
  elif [ -d /data/adb/apd ]; then echo "APatch"
  elif [ -d /data/adb/magisk ]; then echo "Magisk"
  else echo "unknown"; fi
}

# LSPosed 检测（目录存在 + 版本）
detect_lsposed() {
  LSP=""
  for p in /data/adb/lspd /data/adb/modules/zygisk_lsposed /data/adb/modules/riru_lsposed; do
    if [ -d "$p" ]; then LSP="$p"; break; fi
  done
  if [ -z "$LSP" ]; then echo "none"; return; fi
  V=$(grep -m1 '^version=' "$LSP/module.prop" 2>/dev/null | cut -d= -f2-)
  # 只凭管理器 APK/config 目录存在不能证明 LSPosed daemon 正在运行。
  # 必须检测真实 lspd 进程，避免「管理器已安装」被误报为「Hook 层运行中」。
  _lspd_live=false
  if command -v pidof >/dev/null 2>&1 && pidof lspd >/dev/null 2>&1; then
    _lspd_live=true
  elif ps -A 2>/dev/null | grep -E '[ /]lspd([[:space:]]|$)' >/dev/null 2>&1; then
    _lspd_live=true
  fi
  if [ "$_lspd_live" = true ]; then
    echo "active|${V:-unknown}"
  else
    echo "installed|${V:-unknown}"
  fi
}

ROOT=$(id -u 2>/dev/null)
SELINUX=$(getenforce 2>/dev/null || echo "unknown")
HOSTS_LINES=0
if [ -f "$PG/hosts" ]; then HOSTS_LINES=$(wc -l < "$PG/hosts" 2>/dev/null | tr -d ' '); fi
[ -z "$HOSTS_LINES" ] && HOSTS_LINES=0
FWWAIT=""
if iptables -w 5 -L >/dev/null 2>&1; then FWWAIT="-w 5"; fi
IPT4=$(iptables $FWWAIT -S PGUARD 2>/dev/null | wc -l | tr -d ' ')
IPT6=$(ip6tables $FWWAIT -S PGUARD 2>/dev/null | wc -l | tr -d ' ')
MODVER=$(grep -m1 '^version=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2-)
LAST=$(cat "$PG/last_apply" 2>/dev/null || echo "never")
LSPOSED=$(detect_lsposed)

# Per-app modern LSPosed ad Hook: distinguish local config from Remote Files publication.
# Publication success does NOT prove that a target package is selected in LSPosed scope.
HOOK_ADS_ENABLED=$(pg_get hook_ads_enabled 0 2>/dev/null | tr -d ' \r')
case "$HOOK_ADS_ENABLED" in 1) ;; *) HOOK_ADS_ENABLED=0 ;; esac
HOOK_ADS_TARGETS=$(pg_list hook_targets 2>/dev/null | awk -F'|' '$1 != "" && $3 == "1" && $1 ~ /(^|,)(splash=1|feed=1|overlay=1|ads_splash=1|ads_feed=1|ads_overlay=1)(,|$)/ {n++} END {print n+0}' | tr -d ' ')
case "$HOOK_ADS_TARGETS" in ''|*[!0-9]*) HOOK_ADS_TARGETS=0 ;; esac
# Read-only member diagnostics are independent of the ad-filtering master switch.
HOOK_MEMBER_DIAG_TARGETS=$(pg_list hook_targets 2>/dev/null | awk -F'|' '$1 != "" && $3 == "1" && $1 ~ /(^|,)member_diag=1(,|$)/ {n++} END {print n+0}' | tr -d ' ')
case "$HOOK_MEMBER_DIAG_TARGETS" in ''|*[!0-9]*) HOOK_MEMBER_DIAG_TARGETS=0 ;; esac
HOOK_MEMBER_DIAG_ENABLED=0
[ "$HOOK_MEMBER_DIAG_TARGETS" -gt 0 ] 2>/dev/null && HOOK_MEMBER_DIAG_ENABLED=1
HOOK_PRIVACY_ENABLED=$(pg_get hook_privacy_enabled 0 2>/dev/null | tr -d ' \r')
case "$HOOK_PRIVACY_ENABLED" in 1) ;; *) HOOK_PRIVACY_ENABLED=0 ;; esac
HOOK_PRIVACY_TARGETS=$(pg_list hook_targets 2>/dev/null | awk -F'|' '$1 != "" && $3 == "1" && $1 ~ /(^|,)(privacy=1|exif_strip=1|clipboard_read_block=1|clipboard_isolate=1|sensor_accel=1|sensor_gyro=1|sensor_light=1|sensor_magnet=1|sensor_pressure=1|sensor_prox=1|sensor_rate_limit=1|mic_silence=1)(,|$)/ {n++} END {print n+0}' | tr -d ' ')
case "$HOOK_PRIVACY_TARGETS" in ''|*[!0-9]*) HOOK_PRIVACY_TARGETS=0 ;; esac
HOOK_WIFI_SCAN_ENABLED=$(pg_get block_wifi_scan 0 2>/dev/null | tr -d ' \r')
case "$HOOK_WIFI_SCAN_ENABLED" in 1) ;; *) HOOK_WIFI_SCAN_ENABLED=0 ;; esac
HOOK_WIFI_SCAN_TARGETS=$(pg_list hook_targets 2>/dev/null | awk -F'|' '$1 != "" && $3 == "1" && $1 ~ /(^|,)wifi_scan_block=1(,|$)/ {n++} END {print n+0}' | tr -d ' ')
case "$HOOK_WIFI_SCAN_TARGETS" in ''|*[!0-9]*) HOOK_WIFI_SCAN_TARGETS=0 ;; esac
HOOK_NOTIFICATION_LISTEN_ENABLED=$(pg_get block_notif_listen 0 2>/dev/null | tr -d ' \r')
case "$HOOK_NOTIFICATION_LISTEN_ENABLED" in 1) ;; *) HOOK_NOTIFICATION_LISTEN_ENABLED=0 ;; esac
HOOK_NOTIFICATION_LISTEN_TARGETS=$(pg_list hook_targets 2>/dev/null | awk -F'|' '$1 != "" && $3 == "1" && $1 ~ /(^|,)notification_listen_block=1(,|$)/ {n++} END {print n+0}' | tr -d ' ')
case "$HOOK_NOTIFICATION_LISTEN_TARGETS" in ''|*[!0-9]*) HOOK_NOTIFICATION_LISTEN_TARGETS=0 ;; esac
HOOK_NOTIFICATION_PERMISSION_HIDE_ENABLED=$(pg_get hide_notif_perm 0 2>/dev/null | tr -d ' \r')
case "$HOOK_NOTIFICATION_PERMISSION_HIDE_ENABLED" in 1) ;; *) HOOK_NOTIFICATION_PERMISSION_HIDE_ENABLED=0 ;; esac
HOOK_NOTIFICATION_PERMISSION_HIDE_TARGETS=$(pg_list hook_targets 2>/dev/null | awk -F'|' '$1 != "" && $3 == "1" && $1 ~ /(^|,)notification_permission_hide_block=1(,|$)/ {n++} END {print n+0}' | tr -d ' ')
case "$HOOK_NOTIFICATION_PERMISSION_HIDE_TARGETS" in ''|*[!0-9]*) HOOK_NOTIFICATION_PERMISSION_HIDE_TARGETS=0 ;; esac
HOOK_CLIPBOARD_ISOLATE_ENABLED=$(pg_get clipboard_isolate 0 2>/dev/null | tr -d ' \r')
case "$HOOK_CLIPBOARD_ISOLATE_ENABLED" in 1) ;; *) HOOK_CLIPBOARD_ISOLATE_ENABLED=0 ;; esac
HOOK_CLIPBOARD_ISOLATE_TARGETS=$(pg_list hook_targets 2>/dev/null | awk -F'|' '$1 != "" && $3 == "1" && $1 ~ /(^|,)clipboard_isolate=1(,|$)/ {n++} END {print n+0}' | tr -d ' ')
case "$HOOK_CLIPBOARD_ISOLATE_TARGETS" in ''|*[!0-9]*) HOOK_CLIPBOARD_ISOLATE_TARGETS=0 ;; esac
_HOOK_XPOSED_DIR=${PG_XPOSED_DIR:-/data/local/tmp/privacyguard}
HOOK_REMOTE_STATUS=unknown
HOOK_REMOTE_TARGETS=0
if [ -r "$_HOOK_XPOSED_DIR/xposed-remote.status" ]; then
  _hook_remote=$(awk -F= '$1=="status" {print $2; exit}' "$_HOOK_XPOSED_DIR/xposed-remote.status" 2>/dev/null | tr -d ' \r')
  case "$_hook_remote" in ok|failed|framework_missing) HOOK_REMOTE_STATUS=$_hook_remote ;; *) HOOK_REMOTE_STATUS=unknown ;; esac
  _hook_target_count=$(awk -F= '$1=="targets" {print $2; exit}' "$_HOOK_XPOSED_DIR/xposed-remote.status" 2>/dev/null | tr -d ' \r')
  case "$_hook_target_count" in ''|*[!0-9]*) HOOK_REMOTE_TARGETS=0 ;; *) HOOK_REMOTE_TARGETS=$_hook_target_count ;; esac
fi

# Read the authoritative native FX Hook overlays written by the unified APK.
# Legacy settings.conf fields below are retained for older clients only.
HOOK_NATIVE_CONFIG_FOUND=0
HOOK_NATIVE_CONFIG_USERS=0
HOOK_NATIVE_PRIVACY_ENABLED=0
HOOK_NATIVE_PRIVACY_TARGETS=0
HOOK_NATIVE_WIFI_SCAN_ENABLED=0
HOOK_NATIVE_WIFI_SCAN_TARGETS=0
HOOK_NATIVE_NOTIFICATION_LISTEN_ENABLED=0
HOOK_NATIVE_NOTIFICATION_LISTEN_TARGETS=0
HOOK_NATIVE_NOTIFICATION_PERMISSION_HIDE_ENABLED=0
HOOK_NATIVE_NOTIFICATION_PERMISSION_HIDE_TARGETS=0
HOOK_NATIVE_CLIPBOARD_ISOLATE_ENABLED=0
HOOK_NATIVE_CLIPBOARD_ISOLATE_TARGETS=0
HOOK_NATIVE_MEMBER_DIAG_ENABLED=0
HOOK_NATIVE_MEMBER_DIAG_TARGETS=0
HOOK_NATIVE_TARGETS=0
for _native_cfg in "$PG"/fx-native-hook-targets-*.conf; do
  [ -f "$_native_cfg" ] && [ ! -L "$_native_cfg" ] && [ -s "$_native_cfg" ] || continue
  if ! grep -qx 'schema_version=1' "$_native_cfg" ||
     ! grep -qx '^\[list:targets\]$' "$_native_cfg"; then
    continue
  fi
  HOOK_NATIVE_CONFIG_FOUND=1
  HOOK_NATIVE_CONFIG_USERS=$((HOOK_NATIVE_CONFIG_USERS + 1))
  _native_flags=$(awk -F= '
    $1=="privacy_enabled" {p=$2}
    $1=="wifi_scan_enabled" {w=$2}
    $1=="notification_listen_enabled" {n=$2}
    $1=="notification_permission_hide_enabled" {np=$2}
    $1=="clipboard_isolate_enabled" {c=$2}
    END {printf "%s|%s|%s|%s|%s", p,w,n,np,c}
  ' "$_native_cfg")
  _native_privacy=$(printf '%s' "$_native_flags" | cut -d '|' -f1)
  _native_wifi=$(printf '%s' "$_native_flags" | cut -d '|' -f2)
  _native_notif=$(printf '%s' "$_native_flags" | cut -d '|' -f3)
  _native_notif_perm=$(printf '%s' "$_native_flags" | cut -d '|' -f4)
  _native_clipboard=$(printf '%s' "$_native_flags" | cut -d '|' -f5)
  [ "$_native_privacy" = 1 ] && HOOK_NATIVE_PRIVACY_ENABLED=1
  [ "$_native_wifi" = 1 ] && HOOK_NATIVE_WIFI_SCAN_ENABLED=1
  [ "$_native_notif" = 1 ] && HOOK_NATIVE_NOTIFICATION_LISTEN_ENABLED=1
  [ "$_native_notif_perm" = 1 ] && HOOK_NATIVE_NOTIFICATION_PERMISSION_HIDE_ENABLED=1
  [ "$_native_clipboard" = 1 ] && HOOK_NATIVE_CLIPBOARD_ISOLATE_ENABLED=1
  _native_counts=$(awk '
    /^\[list:targets\]$/ {inlist=1; next}
    /^\[/ {if (inlist) exit}
    inlist && NF {
      targets++
      if ($0 ~ /(^|,)member_diag=1(,|$)/) member++
      if ($0 ~ /(^|,)(privacy=1|exif_strip=1|clipboard_read_block=1|clipboard_isolate=1|sensor_accel=1|sensor_gyro=1|sensor_light=1|sensor_magnet=1|sensor_pressure=1|sensor_prox=1|sensor_rate_limit=1|mic_silence=1|camera_access_block=1|location_access_block=1|mic_access_block=1|media_store_query_block=1)(,|$)/) privacy++
      if ($0 ~ /(^|,)wifi_scan_block=1(,|$)/) wifi++
      if ($0 ~ /(^|,)notification_listen_block=1(,|$)/) notif++
      if ($0 ~ /(^|,)notification_permission_hide=1(,|$)/) notif_perm++
      if ($0 ~ /(^|,)clipboard_isolate=1(,|$)/) clipboard++
    }
    END {printf "%d|%d|%d|%d|%d|%d|%d", targets,member,privacy,wifi,notif,notif_perm,clipboard}
  ' "$_native_cfg")
  HOOK_NATIVE_TARGETS=$((HOOK_NATIVE_TARGETS + $(printf '%s' "$_native_counts" | cut -d '|' -f1)))
  HOOK_NATIVE_MEMBER_DIAG_TARGETS=$((HOOK_NATIVE_MEMBER_DIAG_TARGETS + $(printf '%s' "$_native_counts" | cut -d '|' -f2)))
  HOOK_NATIVE_PRIVACY_TARGETS=$((HOOK_NATIVE_PRIVACY_TARGETS + $(printf '%s' "$_native_counts" | cut -d '|' -f3)))
  HOOK_NATIVE_WIFI_SCAN_TARGETS=$((HOOK_NATIVE_WIFI_SCAN_TARGETS + $(printf '%s' "$_native_counts" | cut -d '|' -f4)))
  HOOK_NATIVE_NOTIFICATION_LISTEN_TARGETS=$((HOOK_NATIVE_NOTIFICATION_LISTEN_TARGETS + $(printf '%s' "$_native_counts" | cut -d '|' -f5)))
  HOOK_NATIVE_NOTIFICATION_PERMISSION_HIDE_TARGETS=$((HOOK_NATIVE_NOTIFICATION_PERMISSION_HIDE_TARGETS + $(printf '%s' "$_native_counts" | cut -d '|' -f6)))
  HOOK_NATIVE_CLIPBOARD_ISOLATE_TARGETS=$((HOOK_NATIVE_CLIPBOARD_ISOLATE_TARGETS + $(printf '%s' "$_native_counts" | cut -d '|' -f7)))
done
[ "$HOOK_NATIVE_MEMBER_DIAG_TARGETS" -gt 0 ] && HOOK_NATIVE_MEMBER_DIAG_ENABLED=1

# VPN 状态（无配置文件时给空态默认值）
VPN_MODE=$(grep -m1 '^vpn_mode=' "$PG/settings.conf" 2>/dev/null | cut -d= -f2-)
VPN_MODE=${VPN_MODE:-direct}
VPN_NODE=$(grep -m1 '^vpn_node=' "$PG/settings.conf" 2>/dev/null | cut -d= -f2-)
# A chain existing is not proof that interception is active. Require both a
# real OUTPUT jump to our chain and at least one TCP redirect rule. This avoids
# false "Proxy ON" status after partial firewall cleanup or a failed commit.
VPN_ON=false
VPN_RULES_ACTIVE=false
_VPN_CHAIN_RULES=$(iptables $FWWAIT -t nat -S PGVPN 2>/dev/null)
_VPN_CHAIN_RC=$?
if [ "$_VPN_CHAIN_RC" -eq 0 ]; then
  _VPN_HOOK=$(iptables $FWWAIT -t nat -S OUTPUT 2>/dev/null | grep -E '^-A OUTPUT -j PGVPN([[:space:]]|$)|^-A OUTPUT .* -j PGVPN([[:space:]]|$)' | head -1)
  _VPN_REDIRECT=$(printf '%s\n' "$_VPN_CHAIN_RULES" | grep -E '^-A PGVPN ' | grep -F ' -p tcp ' | grep -F ' -j REDIRECT ' | grep -E -- '--to-ports [0-9]+' | head -1)
  if [ -n "$_VPN_HOOK" ] && [ -n "$_VPN_REDIRECT" ]; then VPN_RULES_ACTIVE=true; fi
fi
VPN_SUBS=0; VPN_NODES=0; VPN_CHN=0
if [ -f "$PG/settings.conf" ]; then
  VPN_SUBS=$(pg_list_enabled vpn_sub 2>/dev/null | wc -l | tr -d ' ')
  VPN_NODES=$(pg_list_enabled vpn_node 2>/dev/null | wc -l | tr -d ' ')
fi
[ -s "$PG/chnroute" ] && VPN_CHN=$(wc -l < "$PG/chnroute" | tr -d ' ')
VPN_NODE_ESC=$(echo "$VPN_NODE" | sed 's/\\/\\\\/g;s/"/\\"/g')

# DNS forwarding health is based on the live NAT rules, not config alone.
# This reports rule presence only; it does not claim upstream DNS resolution works.
DNS_FORWARD_STATUS="unknown"
DNS_FORWARD_TARGET=""
if command -v iptables >/dev/null 2>&1; then
  _dns_rules=$(iptables $FWWAIT -t nat -S PGNAT 2>/dev/null)
  _dns_rc=$?
  if [ $_dns_rc -eq 0 ]; then
    _dns_udp=$(printf '%s\n' "$_dns_rules" | grep -E -- '-p udp .*--dport 53 .*--to-destination' | head -1)
    _dns_tcp=$(printf '%s\n' "$_dns_rules" | grep -E -- '-p tcp .*--dport 53 .*--to-destination' | head -1)
    DNS_FORWARD_TARGET=$(printf '%s\n' "$_dns_udp" | sed -n 's/.*--to-destination \([^ ]*\).*/\1/p')
    [ -n "$DNS_FORWARD_TARGET" ] || DNS_FORWARD_TARGET=$(printf '%s\n' "$_dns_tcp" | sed -n 's/.*--to-destination \([^ ]*\).*/\1/p')
    _dns_hook=$(iptables $FWWAIT -t nat -S OUTPUT 2>/dev/null | grep -E -- '^-A OUTPUT -j PGNAT([[:space:]]|$)|^-A OUTPUT .* -j PGNAT([[:space:]]|$)' | head -1)
    if [ -z "$_dns_udp" ] && [ -z "$_dns_tcp" ]; then
      DNS_FORWARD_STATUS="inactive"
    elif [ -z "$_dns_hook" ]; then
      # A populated chain without an OUTPUT jump is not active forwarding.
      DNS_FORWARD_STATUS="inactive"
    elif [ -n "$_dns_udp" ] && [ -n "$_dns_tcp" ]; then
      DNS_FORWARD_STATUS="active"
    else
      DNS_FORWARD_STATUS="partial"
    fi
  fi
fi

# IPv6 DNS forwarding is reported independently. Some FX modes intentionally use
# IPv4-only forwarding, so this is diagnostic only and never changes firewall rules.
DNS_FORWARD_V6_STATUS="unknown"
if command -v ip6tables >/dev/null 2>&1; then
  _dns6_rules=$(ip6tables $FWWAIT -t nat -S PGNAT 2>/dev/null)
  _dns6_rc=$?
  if [ "$_dns6_rc" -eq 0 ]; then
    _dns6_udp=$(printf '%s\n' "$_dns6_rules" | grep -E -- '-p udp .*--dport 53 .*--to-destination' | head -1)
    _dns6_tcp=$(printf '%s\n' "$_dns6_rules" | grep -E -- '-p tcp .*--dport 53 .*--to-destination' | head -1)
    _dns6_hook=$(ip6tables $FWWAIT -t nat -S OUTPUT 2>/dev/null | grep -E -- '^-A OUTPUT -j PGNAT([[:space:]]|$)|^-A OUTPUT .* -j PGNAT([[:space:]]|$)' | head -1)
    if [ -z "$_dns6_udp" ] && [ -z "$_dns6_tcp" ]; then
      DNS_FORWARD_V6_STATUS="inactive"
    elif [ -z "$_dns6_hook" ]; then
      DNS_FORWARD_V6_STATUS="inactive"
    elif [ -n "$_dns6_udp" ] && [ -n "$_dns6_tcp" ]; then
      DNS_FORWARD_V6_STATUS="active"
    else
      DNS_FORWARD_V6_STATUS="partial"
    fi
  fi
fi

# 隐藏 VPN/节点开关 + 隐藏链(PGHKS/PGHIDE)是否生效 + 隐藏强度
VPN_HIDE=false
if grep -q '^vpn_hide=1' "$PG/settings.conf" 2>/dev/null; then VPN_HIDE=true; fi
VPN_HIDE_ON=false
if [ "$VPN_HIDE" = "true" ] && iptables $FWWAIT -L PGHKS >/dev/null 2>&1; then VPN_HIDE_ON=true; fi
VPN_HIDE_LEVEL=0
if [ "$VPN_HIDE" = "true" ]; then
  VPN_HIDE_LEVEL=$(pg_conf vpn 2>/dev/null | grep -m1 '^hide_level=' | cut -d= -f2- | tr -d ' ')
  case "$VPN_HIDE_LEVEL" in ''|*[!0-9]*) VPN_HIDE_LEVEL=1 ;; esac
fi
# 内置代理核心（sing-box 已随模块打包，默认启用；显式 vpn_core=0 才视为关闭）
VPN_CORE=false
_VPN_CORE_CFG=""
grep -q '^vpn_core=1' "$PG/settings.conf" 2>/dev/null && _VPN_CORE_CFG=1
grep -q '^vpn_core=0' "$PG/settings.conf" 2>/dev/null && _VPN_CORE_CFG=0
# 架构（与 vpncore.sh 保持同一映射）
PG_ARCH=$(getprop ro.product.cpu.abi 2>/dev/null)
[ -z "$PG_ARCH" ] && PG_ARCH=$(uname -m 2>/dev/null)
case "$PG_ARCH" in
  arm64*|aarch64) PG_ARCH=arm64 ;;
  armv7*|armeabi*) PG_ARCH=arm ;;
  x86_64|amd64) PG_ARCH=amd64 ;;
  *86*) PG_ARCH=386 ;;
  *) PG_ARCH=arm64 ;;
esac
# 内置内核（随模块分发，无需联网）
VPN_CORE_BUILTIN=false
[ -f "$MODDIR/bin/$PG_ARCH/sing-box" ] && VPN_CORE_BUILTIN=true
# 决策：显式 1→开；显式 0→关；未配置但有内置内核→默认开。
# 内置内核是随模块分发的实体文件，若不默认开启，UI 会一直显示「核心未安装」，
# 与实际（bin/<arch>/sing-box 就在包里）不符，属误导性状态。
case "$_VPN_CORE_CFG" in
  1) VPN_CORE=true ;;
  0) VPN_CORE=false ;;
  *) if [ "$VPN_CORE_BUILTIN" = "true" ]; then VPN_CORE=true; fi ;;
esac
VPN_CORE_ON=false
if [ -f "$PG/singbox.json" ]; then
  if [ -s "$PG/bin/sing-box" ] || [ "$VPN_CORE_BUILTIN" = "true" ]; then VPN_CORE_ON=true; fi
fi
# A live PID alone is not proof that sing-box is running: PIDs can be reused.
# Validate the process command line before reporting the proxy core as active.
_vpncore_pid_matches() {
  _vpm_pid="$1"
  case "$_vpm_pid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$_vpm_pid" 2>/dev/null || return 1
  [ -r "/proc/$_vpm_pid/cmdline" ] || return 1
  _vpm_arg0=$(tr '\000' '\n' < "/proc/$_vpm_pid/cmdline" 2>/dev/null | sed -n '1p')
  _vpm_base=${_vpm_arg0##*/}
  [ "$_vpm_base" = "sing-box" ] || return 1
  # Require a sing-box run invocation; a helper process whose name merely
  # resembles the binary must not be reported as the active proxy core.
  _vpm_cmd=$(tr '\000' ' ' < "/proc/$_vpm_pid/cmdline" 2>/dev/null)
  case " $_vpm_cmd " in *" run "*) return 0 ;; *) return 1 ;; esac
}
VPN_CORE_PID=0
if [ -s "$PG/singbox.pid" ]; then
  _cp=$(cat "$PG/singbox.pid" 2>/dev/null)
  if _vpncore_pid_matches "$_cp"; then VPN_CORE_PID=$_cp; fi
fi

# Effective interception requires both the committed firewall path and a listener
# on the actual REDIRECT destination. This also supports user-managed cores when
# vpn_core=0; a managed PID alone is insufficient, and stale rules must not make
# the UI claim traffic is flowing after the listener exits.
VPN_LISTENER_PORT=$(pg_conf vpn 2>/dev/null | grep -m1 '^local_port=' | cut -d= -f2- | tr -d ' ')
case "$VPN_LISTENER_PORT" in *:*) VPN_LISTENER_PORT=${VPN_LISTENER_PORT##*:} ;; esac
case "$VPN_LISTENER_PORT" in ''|*[!0-9]*) VPN_LISTENER_PORT=7890 ;; esac
VPN_LISTENER_ON=false
if [ "$VPN_MODE" != "direct" ] && [ "$VPN_RULES_ACTIVE" = "true" ]; then
  if command -v ss >/dev/null 2>&1 && ss -tln 2>/dev/null | grep -E "[:.]${VPN_LISTENER_PORT}[[:space:]]" >/dev/null 2>&1; then
    VPN_LISTENER_ON=true
  fi
  if [ "$VPN_LISTENER_ON" != "true" ] && command -v netstat >/dev/null 2>&1 && netstat -tln 2>/dev/null | grep -E "[:.]${VPN_LISTENER_PORT}[[:space:]].*LISTEN" >/dev/null 2>&1; then
    VPN_LISTENER_ON=true
  fi
  if [ "$VPN_LISTENER_ON" != "true" ] && [ -r /proc/net/tcp ]; then
    _vpn_lp_hex=$(printf '%04X' "$VPN_LISTENER_PORT" 2>/dev/null)
    if [ -n "$_vpn_lp_hex" ] && awk -v p="$_vpn_lp_hex" 'NR>1 {split($2,a,":"); if (toupper(a[2])==p && $4=="0A") found=1} END {exit !found}' /proc/net/tcp 2>/dev/null; then VPN_LISTENER_ON=true
    elif [ -r /proc/net/tcp6 ] && awk -v p="$_vpn_lp_hex" 'NR>1 {split($2,a,":"); if (toupper(a[2])==p && $4=="0A") found=1} END {exit !found}' /proc/net/tcp6 2>/dev/null; then VPN_LISTENER_ON=true
    fi
  fi
  if [ "$VPN_LISTENER_ON" = "true" ]; then VPN_ON=true; fi
fi

# TUN mode does not use PGVPN/REDIRECT. Report it active only when the managed
# sing-box process is verified, the committed config contains a TUN inbound,
# and the kernel reports fx0 UP. This proves interface readiness, not end-to-end egress.
if [ "$VPN_MODE" = "tun" ] && [ "$VPN_CORE_PID" != "0" ] && [ -s "$PG/singbox.json" ] && command -v ip >/dev/null 2>&1; then
  if grep -Fq '"type":"tun"' "$PG/singbox.json" && ip -o link show dev fx0 2>/dev/null | grep -E '<[^>]*UP([,>])' >/dev/null 2>&1; then
    VPN_ON=true
    VPN_LISTENER_ON=true
  fi
fi

vpn_status_text() {
  if [ "$VPN_MODE" = "direct" ]; then echo "直连(未启用)"; return; fi
  if [ "$VPN_ON" = "true" ]; then
    echo "已生效($VPN_MODE 节点:${VPN_NODE:-未选})"
  else
    echo "未生效(检查节点/本地客户端端口)"
  fi
}

if [ "$1" = "text" ]; then
  echo "管理器: $(detect_manager)"
  echo "Root: $ROOT"
  echo "SELinux: $SELINUX"
  echo "LSPosed: $LSPOSED"
  echo "应用内 Hook: ads_enabled=$HOOK_ADS_ENABLED ads_targets=$HOOK_ADS_TARGETS member_diag_enabled=$HOOK_MEMBER_DIAG_ENABLED member_diag_targets=$HOOK_MEMBER_DIAG_TARGETS RemoteFiles=$HOOK_REMOTE_STATUS published_targets=$HOOK_REMOTE_TARGETS (LSPosed scope still must be checked in Manager)"
  echo "Hosts 规则: $HOSTS_LINES 行"
  echo "防火墙规则: v4=$IPT4 v6=$IPT6"
  echo "VPN: $(vpn_status_text) (规则=$VPN_RULES_ACTIVE 监听=$VPN_LISTENER_ON:$VPN_LISTENER_PORT)"
  echo "DNS 明文转发规则(IPv4): $DNS_FORWARD_STATUS${DNS_FORWARD_TARGET:+ (目标=$DNS_FORWARD_TARGET)}"
  echo "DNS 明文转发规则(IPv6，仅状态诊断): $DNS_FORWARD_V6_STATUS"
  if [ "$VPN_HIDE" = "true" ]; then
    if [ "$VPN_HIDE_ON" = "true" ]; then
      echo "隐藏VPN: 已生效(DNS全劫持+QUIC/STUN/痕迹端口封锁+tun隐藏, 强度L$VPN_HIDE_LEVEL)"
    else
      echo "隐藏VPN: 已开启但未生效(检查节点/本地客户端端口)"
    fi
  fi
  if [ "$VPN_CORE" = "true" ]; then
    if [ "$VPN_CORE_PID" != "0" ]; then
      echo "代理核心: sing-box 运行中(pid=$VPN_CORE_PID)"
    elif [ "$VPN_CORE_ON" = "true" ]; then
      echo "代理核心: 已安装未运行(将在下次应用时启动)"
    elif [ "$VPN_CORE_BUILTIN" = "true" ]; then
      echo "代理核心: 已内置($PG_ARCH)，将在下次应用时释放并启动"
    else
      echo "代理核心: 未安装(导入节点并应用后自动下载)"
    fi
  fi
  echo "上次应用: $LAST"
  exit 0
fi

# JSON 输出（供 WebUI 桥接调用）
printf '{"manager":"%s","root":%s,"selinux":"%s","lsposed":"%s","lsposed_status":"%s","lsposed_version":"%s","hosts_rules":%s,"ipt_v4":%s,"ipt_v6":%s,"version":"%s","last_apply":"%s","conf_exists":%s,"vpn_mode":"%s","vpn_on":%s,"vpn_rules_active":%s,"vpn_listener_on":%s,"vpn_listener_port":%s,"vpn_node":"%s","vpn_subs":%s,"vpn_nodes":%s,"vpn_chn":%s,"vpn_hide":%s,"vpn_hide_on":%s,"vpn_hide_level":%s,"vpn_core":%s,"vpn_core_pid":%s,"vpn_core_builtin":%s,"vpn_core_arch":"%s","dns_forward_status":"%s","dns_forward_target":"%s","dns_forward_v6_status":"%s","hook_ads_enabled":"%s","hook_ads_targets":%s,"hook_member_diag_enabled":"%s","hook_member_diag_targets":%s,"hook_privacy_enabled":"%s","hook_privacy_targets":%s,"hook_wifi_scan_enabled":"%s","hook_wifi_scan_targets":%s,"hook_notification_listen_enabled":"%s","hook_notification_listen_targets":%s,"hook_notification_permission_hide_enabled":"%s","hook_notification_permission_hide_targets":%s,"hook_clipboard_isolate_enabled":"%s","hook_clipboard_isolate_targets":%s,"hook_remote_status":"%s","hook_remote_targets":%s,"hook_native_config_found":"%s","hook_native_config_users":%s,"hook_native_privacy_enabled":"%s","hook_native_privacy_targets":%s,"hook_native_wifi_scan_enabled":"%s","hook_native_wifi_scan_targets":%s,"hook_native_notification_listen_enabled":"%s","hook_native_notification_listen_targets":%s,"hook_native_notification_permission_hide_enabled":"%s","hook_native_notification_permission_hide_targets":%s,"hook_native_clipboard_isolate_enabled":"%s","hook_native_clipboard_isolate_targets":%s,"hook_native_member_diag_enabled":"%s","hook_native_member_diag_targets":%s,"hook_native_targets":%s}\n' \
  "$(detect_manager)" \
  "$([ "$ROOT" = "0" ] && echo true || echo false)" \
  "$SELINUX" \
  "$(echo "$LSPOSED" | cut -d'|' -f1)" \
  "$(echo "$LSPOSED" | awk -F'|' '{if ($1=="active") print "active"; else if ($1=="installed") print "installed"; else print "none"}')" \
  "$(echo "$LSPOSED" | cut -d'|' -f2)" \
  "$HOSTS_LINES" \
  "$IPT4" \
  "$IPT6" \
  "$MODVER" \
  "$LAST" \
  "$([ -f "$PG/settings.conf" ] && echo true || echo false)" \
  "$VPN_MODE" \
  "$VPN_ON" \
  "$VPN_RULES_ACTIVE" \
  "$VPN_LISTENER_ON" \
  "$VPN_LISTENER_PORT" \
  "$VPN_NODE_ESC" \
  "$VPN_SUBS" \
  "$VPN_NODES" \
  "$VPN_CHN" \
  "$VPN_HIDE" \
  "$VPN_HIDE_ON" \
  "$VPN_HIDE_LEVEL" \
  "$VPN_CORE" \
  "$VPN_CORE_PID" \
  "$VPN_CORE_BUILTIN" \
  "$PG_ARCH" \
  "$DNS_FORWARD_STATUS" \
  "$DNS_FORWARD_TARGET" \
  "$DNS_FORWARD_V6_STATUS" \
  "$HOOK_ADS_ENABLED" \
  "$HOOK_ADS_TARGETS" \
  "$HOOK_MEMBER_DIAG_ENABLED" \
  "$HOOK_MEMBER_DIAG_TARGETS" \
  "$HOOK_PRIVACY_ENABLED" \
  "$HOOK_PRIVACY_TARGETS" \
  "$HOOK_WIFI_SCAN_ENABLED" \
  "$HOOK_WIFI_SCAN_TARGETS" \
  "$HOOK_NOTIFICATION_LISTEN_ENABLED" \
  "$HOOK_NOTIFICATION_LISTEN_TARGETS" \
  "$HOOK_NOTIFICATION_PERMISSION_HIDE_ENABLED" \
  "$HOOK_NOTIFICATION_PERMISSION_HIDE_TARGETS" \
  "$HOOK_CLIPBOARD_ISOLATE_ENABLED" \
  "$HOOK_CLIPBOARD_ISOLATE_TARGETS" \
  "$HOOK_REMOTE_STATUS" \
  "$HOOK_REMOTE_TARGETS" \
  "$HOOK_NATIVE_CONFIG_FOUND" \
  "$HOOK_NATIVE_CONFIG_USERS" \
  "$HOOK_NATIVE_PRIVACY_ENABLED" \
  "$HOOK_NATIVE_PRIVACY_TARGETS" \
  "$HOOK_NATIVE_WIFI_SCAN_ENABLED" \
  "$HOOK_NATIVE_WIFI_SCAN_TARGETS" \
  "$HOOK_NATIVE_NOTIFICATION_LISTEN_ENABLED" \
  "$HOOK_NATIVE_NOTIFICATION_LISTEN_TARGETS" \
  "$HOOK_NATIVE_NOTIFICATION_PERMISSION_HIDE_ENABLED" \
  "$HOOK_NATIVE_NOTIFICATION_PERMISSION_HIDE_TARGETS" \
  "$HOOK_NATIVE_CLIPBOARD_ISOLATE_ENABLED" \
  "$HOOK_NATIVE_CLIPBOARD_ISOLATE_TARGETS" \
  "$HOOK_NATIVE_MEMBER_DIAG_ENABLED" \
  "$HOOK_NATIVE_MEMBER_DIAG_TARGETS" \
  "$HOOK_NATIVE_TARGETS"
