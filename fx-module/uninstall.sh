#!/system/bin/sh
# PrivacyGuard 卸载清理 —— 完整还原模块触碰过的全部系统状态
#
# 模块运行期间修改的东西（按还原手段分组）：
#   A. 内存态（卸载即需还原, 重启也会消失）:
#      iptables PGUARD/PGNAT 链 / hosts bind mount / su 路径遮蔽 mount /
#      SELinux deny 规则 / sysctl / setprop persist.* / settings put / Wi-Fi MAC
#   B. 属性伪装（resetprop 只改内存视图, 重启自动还原; 卸载时用快照尽力即时还原）:
#      post-fs-data.sh 伪装的全部 ro.* 属性 ← backup/props.snapshot
#   C. 用户数据（不还原, 备份后删除）:
#      settings.conf / hosts 生成物 / 订阅缓存 → /sdcard 备份
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
# 若仍有模块自有挂载无法解除，必须保留源目录以便重试，避免删除活跃挂载源。
PG_KEEP_DATA=0
PG_FW_INCOMPLETE=0
PG_CLEANUP_INCOMPLETE=0
PG=${PG:-/data/adb/privacyguard}
STATE_DIR=$PG
XDIR=/data/local/tmp/privacyguard
BK="$PG/backup"
# Validate all watcher teardown logs before invoking network helpers.
_mitm_warn() {
  _msg="PrivacyGuard uninstall warning: $*"
  echo "$_msg" >&2
  if command -v log >/dev/null 2>&1; then log -p w -t PrivacyGuardUninstall "$_msg" 2>/dev/null; fi
}

for _fx_log in \
  "$PG/vpn-external-watchdog.log" \
  "$PG/yulong-root-proxy.log" \
  "$PG/yulong-root-proxy-package-watch.log" \
  "$PG/localdns-watchdog.log" \
  "$PG/yulong-ad-schedule.log" \
  "$PG/yulong-trusted-network.log"; do
  if [ -L "$_fx_log" ] || { [ -e "$_fx_log" ] && [ ! -f "$_fx_log" ]; }; then
    _mitm_warn "network teardown log is a symlink or non-regular file ($_fx_log); preserving state and aborting cleanup"
    exit 1
  fi
done
unset _fx_log

case "$PG" in /*) : ;; *) echo "FX uninstall: state directory must be absolute; aborting cleanup" >&2; exit 1 ;; esac
case "$PG" in *//*|*/../*|*/..|*/./*|*/.) echo "FX uninstall: state directory path is unsafe; aborting cleanup" >&2; exit 1 ;; esac
if [ -L "$PG" ] || { [ -e "$PG" ] && [ ! -d "$PG" ]; }; then
  echo "FX uninstall: state directory is a symlink or non-directory; preserving state and aborting cleanup" >&2
  exit 1
fi

# FX_QUICKJS_SCHEDULER_STOP_BEGIN
_FX_SCHEDULER_STATE_DIR=${PG:-${STATE_DIR:-/data/adb/privacyguard}}
if [ -f "$MODDIR/scripts/jsruntime/scheduler.sh" ]; then
  # Uninstall must still invoke the scheduler when it was never started and
  # its state/log directory does not exist. Never follow a symlink or special
  # file merely to create the shutdown log.
  _FX_SCHEDULER_LOG=/dev/null
  if [ -d "$_FX_SCHEDULER_STATE_DIR/jsruntime" ] && [ ! -L "$_FX_SCHEDULER_STATE_DIR/jsruntime" ] && \
      { { [ ! -e "$_FX_SCHEDULER_STATE_DIR/jsruntime/scheduler.log" ] && [ ! -L "$_FX_SCHEDULER_STATE_DIR/jsruntime/scheduler.log" ]; } || \
        { [ -f "$_FX_SCHEDULER_STATE_DIR/jsruntime/scheduler.log" ] && [ ! -L "$_FX_SCHEDULER_STATE_DIR/jsruntime/scheduler.log" ]; }; }; then
    _FX_SCHEDULER_LOG="$_FX_SCHEDULER_STATE_DIR/jsruntime/scheduler.log"
  fi
  if ! sh "$MODDIR/scripts/jsruntime/scheduler.sh" uninstall >> "$_FX_SCHEDULER_LOG" 2>&1; then
    _mitm_warn "scheduler PID record exists but QuickJS scheduler did not confirm shutdown; preserving state and aborting cleanup"
    exit 1
  fi
elif [ -s "$_FX_SCHEDULER_STATE_DIR/jsruntime/scheduler.pid" ]; then
  _mitm_warn "scheduler PID record exists but scheduler script is missing; aborting cleanup"
  exit 1
fi
unset _FX_SCHEDULER_STATE_DIR _FX_SCHEDULER_LOG
# FX_QUICKJS_SCHEDULER_STOP_END



# ============================================================
# A0. MITM 实验功能清理：先移除自己拥有的重定向，再停止引擎。
#     不触碰无法通过所有权标记验证的同名第三方链；失败时仍尝试停止进程。
# Stop and confirm the outer-VPN state watcher before removing any owned firewall
# rules. Otherwise a concurrent handover-triggered apply could recreate chains
# after uninstall has already started cleaning them.
if [ -x "$MODDIR/scripts/vpn-external-watchdog.sh" ]; then
  if ! sh "$MODDIR/scripts/vpn-external-watchdog.sh" stop "$MODDIR" "$PG" >/dev/null 2>&1; then
    PG_KEEP_DATA=1
    _mitm_warn "could not confirm stopping external-VPN watchdog; aborting uninstall before firewall cleanup to avoid a background apply recreating rules"
    exit 1
  fi
elif [ -s "$PG/vpn-external-watchdog.pid" ]; then
  PG_KEEP_DATA=1
  _mitm_warn "external-VPN watchdog PID record exists but script is missing; aborting uninstall before firewall cleanup because background apply cannot be ruled out"
  exit 1
fi
# Stop the DNS watchdog before Root Proxy, VPN core, or firewall teardown.
# Its recovery loop invokes apply.sh fast and can restart DNS/proxy services or
# recreate FX-owned OUTPUT/PGNAT hooks while uninstall is removing them.
if [ -x "$MODDIR/scripts/localdns-watchdog.sh" ]; then
  if ! sh "$MODDIR/scripts/localdns-watchdog.sh" stop "$MODDIR" "$PG" >/dev/null 2>&1; then
    PG_KEEP_DATA=1
    _mitm_warn "could not confirm stopping local DNS watchdog; aborting uninstall before firewall cleanup to avoid a background apply recreating rules"
    exit 1
  fi
elif [ -s "$PG/localdns-watchdog.pid" ]; then
  _wd_pid=$(cat "$PG/localdns-watchdog.pid" 2>/dev/null)
  case "$_wd_pid" in ''|*[!0-9]*|0|1)
    PG_KEEP_DATA=1
    _mitm_warn "local DNS watchdog PID marker is invalid and its script is missing; aborting uninstall before firewall cleanup"
    exit 1
    ;;
    *)
    if [ -r "/proc/$_wd_pid/cmdline" ]; then
      _wd_cmd=$(tr '\000' ' ' < "/proc/$_wd_pid/cmdline" 2>/dev/null)
      case "$_wd_cmd" in
        *"$MODDIR/scripts/localdns-watchdog.sh"*)
          kill -TERM "$_wd_pid" 2>/dev/null || :
          _wd_wait=0
          while [ "$_wd_wait" -lt 30 ] && kill -0 "$_wd_pid" 2>/dev/null; do
            _wd_cmd=$(tr '\000' ' ' < "/proc/$_wd_pid/cmdline" 2>/dev/null)
            case "$_wd_cmd" in *"$MODDIR/scripts/localdns-watchdog.sh"*) ;; *) break ;; esac
            sleep 0.2
            _wd_wait=$((_wd_wait+1))
          done
          _wd_cmd=''
          [ -r "/proc/$_wd_pid/cmdline" ] && _wd_cmd=$(tr '\000' ' ' < "/proc/$_wd_pid/cmdline" 2>/dev/null)
          case "$_wd_cmd" in
            *"$MODDIR/scripts/localdns-watchdog.sh"*)
              PG_KEEP_DATA=1
              _mitm_warn "local DNS watchdog still appears active; aborting uninstall before firewall cleanup"
              exit 1
              ;;
          esac
          ;;
        *)
          PG_KEEP_DATA=1
          _mitm_warn "local DNS watchdog PID marker belongs to another process; aborting uninstall before firewall cleanup"
          exit 1
          ;;
      esac
    else
      PG_KEEP_DATA=1
      _mitm_warn "local DNS watchdog PID marker exists but process identity cannot be checked; aborting uninstall before firewall cleanup"
      exit 1
    fi
    ;;
  esac
fi

if [ -f "$MODDIR/scripts/yulong-root-proxy-package-watch.sh" ]; then
  if ! sh "$MODDIR/scripts/yulong-root-proxy-package-watch.sh" stop "$MODDIR" "$PG" >> "$PG/yulong-root-proxy-package-watch.log" 2>&1; then
    PG_KEEP_DATA=1
    _mitm_warn "Root Proxy package watcher shutdown was not confirmed; aborting uninstall before firewall cleanup"
    exit 1
  fi
elif [ -e "$PG/yulong-root-proxy-package-watch.pid" ]; then
  PG_KEEP_DATA=1
  _mitm_warn "Root Proxy package watcher PID exists but its helper is missing; aborting uninstall"
  exit 1
fi
if [ -f "$MODDIR/scripts/yulong-root-proxy.sh" ]; then
  if ! MP="$MODDIR" PG="$PG" CONF="$PG/settings.conf" sh "$MODDIR/scripts/yulong-root-proxy.sh" uninstall "$MODDIR" "$PG" >> "$PG/yulong-root-proxy.log" 2>&1; then
    PG_KEEP_DATA=1
    _mitm_warn "Root Proxy cleanup was not confirmed; aborting uninstall and preserving state"
    exit 1
  fi
fi
if [ -f "$MODDIR/scripts/mitm-redirect.sh" ]; then
  if ! sh "$MODDIR/scripts/mitm-redirect.sh" disable >/dev/null 2>&1; then
    _mitm_warn "could not confirm removal of owned MITM redirect rules; inspect iptables nat OUTPUT and PGMITM27 before using traffic interception again"
  fi
fi
if [ -f "$MODDIR/scripts/mitm-engine.sh" ]; then
  if ! sh "$MODDIR/scripts/mitm-engine.sh" stop >/dev/null 2>&1; then
    _mitm_warn "MITM listener did not confirm shutdown; inspect /proc and /data/adb/privacyguard/mitm/engine.log"
  fi
  if ! sh "$MODDIR/scripts/mitm-engine.sh" untrust-ca >/dev/null 2>&1; then
    _mitm_warn "could not confirm disabling the pg_mitm_ca certificate submodule; verify system trust state after uninstall"
  fi
fi

# A0.5 本地代理核心：在拆除防火墙/删除运行数据前停止由本模块管理的 sing-box。
#     仅通过 vpncore.sh 的 PID + /proc cmdline 身份校验停止，不使用 pkill -f。
#     若无法确认核心已停止，先移除后续自有重定向规则，但保留 $PG 以便人工重试，
#     避免删除 PID/日志后失去安全恢复线索。
if [ -f "$MODDIR/scripts/vpncore.sh" ]; then
  if ! sh "$MODDIR/scripts/vpncore.sh" stop >/dev/null 2>&1; then
    PG_KEEP_DATA=1
    _mitm_warn "could not confirm stopping the module-managed sing-box core; preserving $PG and PID/log state for retry"
  fi
else
  # 缺少管理脚本时不能宣称代理核心已停止；不猜测进程身份，也不盲目杀进程。
  if [ -s "$PG/singbox.pid" ]; then
    PG_KEEP_DATA=1
    _mitm_warn "vpncore.sh missing while a sing-box PID record exists; preserving $PG for manual cleanup"
  fi
fi


# ============================================================
# Stop Yulong-owned schedule and per-app network controllers before generic firewall teardown.
if [ -x "$MODDIR/scripts/yulong-ad-schedule.sh" ]; then
  if ! sh "$MODDIR/scripts/yulong-ad-schedule.sh" stop "$MODDIR" "$PG" uninstall >> "$PG/yulong-ad-schedule.log" 2>&1; then
    PG_KEEP_DATA=1
    PG_CLEANUP_INCOMPLETE=1
    _mitm_warn "could not confirm stopping Yulong ad schedule watcher; preserving state for retry"
    exit 1
  fi
elif [ -e "$PG/yulong-ad-schedule.pid" ]; then
  PG_KEEP_DATA=1
  _mitm_warn "Yulong ad schedule PID record exists but its helper is missing; aborting uninstall"
  exit 1
fi
if [ -f "$MODDIR/scripts/yulong-app-firewall.sh" ]; then
  if ! sh "$MODDIR/scripts/yulong-app-firewall.sh" uninstall >> "$PG/boot.log" 2>&1; then
    PG_KEEP_DATA=1
    PG_CLEANUP_INCOMPLETE=1
    _mitm_warn "Yulong per-app firewall cleanup was not confirmed; preserving state for retry"
  fi
fi
if [ -x "$MODDIR/scripts/yulong-trusted-network.sh" ]; then
  if ! sh "$MODDIR/scripts/yulong-trusted-network.sh" uninstall >> "$PG/yulong-trusted-network.log" 2>&1; then
    PG_KEEP_DATA=1
    PG_CLEANUP_INCOMPLETE=1
    _mitm_warn "trusted-network watcher cleanup was not confirmed; preserving state for retry"
  fi
fi
# A1. 防火墙链（filter PGUARD + nat PGNAT，v4/v6）
#     -w 自适应（同 apply.sh：老内核不认 -w 时裸跑）
# ============================================================
FWWAIT=""
if iptables -w 5 -L >/dev/null 2>&1; then
  FWWAIT="-w 5"
fi
# 重要：不要在下面的“重复跳转收敛/引用检查”之前先 -F/-X。
# 旧的先行清理只删除一次 OUTPUT 跳转；若存在重复跳转，它会在仍被引用时
# 清空链内容，导致卸载过程中流量策略突变。统一交给下方 _pg_fw_clean_chain：
# 先有界删除模块挂载点的重复引用，再查询确认无引用，最后才清空并删除链。
# v1.10.91: 删除重复跳转并验证链是否真的消失。单次 -D 只能移除一条规则；
# 旧版本/异常中断可能留下重复 OUTPUT 引用，导致 -X 失败但被静默忽略。
_pg_fw_warn() { PG_FW_INCOMPLETE=1; _mitm_warn "firewall cleanup incomplete: $*; inspect iptables/ip6tables and retry after reboot if necessary"; }
_pg_fw_call() {
  _pfc_bin=$1 _pfc_table=$2; shift 2
  if [ -n "$_pfc_table" ]; then
    "$_pfc_bin" $FWWAIT -t "$_pfc_table" "$@"
  else
    "$_pfc_bin" $FWWAIT "$@"
  fi
}
_pg_fw_clean_chain() {
  _pf_bin=$1 _pf_table=$2 _pf_chain=$3 _pf_parent=$4 _pf_target=$5
  if ! command -v "$_pf_bin" >/dev/null 2>&1; then
    # Missing firewall tooling means cleanup cannot be verified; never report a clean uninstall.
    _pg_fw_warn "$_pf_bin unavailable; cannot verify $_pf_table chain $_pf_chain cleanup"
    return 0
  fi
  # 最多清除 64 条模块自有父链跳转，防止异常/恶意规则导致无限循环。
  _pf_i=0
  while [ "$_pf_i" -lt 64 ]; do
    _pg_fw_call "$_pf_bin" "$_pf_table" -D "$_pf_parent" -j "$_pf_target" >/dev/null 2>&1 || break
    _pf_i=$((_pf_i+1))
  done
  # Never flush a chain while a jump to it is still present. This can happen
  # when an interrupted/legacy install left more duplicate hooks than the
  # bounded cleanup loop is allowed to remove, or when firewall deletion fails.
  # Preserve the chain contents and retry state rather than silently changing
  # traffic through a still-referenced chain during uninstall.
  # Query the whole table, not just the expected parent: another chain (including
  # a third-party chain) may reference a module-named chain. Flushing a referenced
  # chain can silently change that caller's traffic policy even if -X later fails.
  if _pf_table_rules=$(_pg_fw_call "$_pf_bin" "$_pf_table" -S 2>/dev/null); then
    if printf '%s\n' "$_pf_table_rules" | grep -E "^-A .* -j ${_pf_target}([[:space:]]|$)" >/dev/null 2>&1; then
      _pg_fw_warn "$_pf_bin ${_pf_table:-filter} still contains a reference to $_pf_target; preserving chain for retry"
      return 0
    fi
  else
    _pg_fw_warn "$_pf_bin ${_pf_table:-filter} table query failed; preserving $_pf_chain for retry"
    return 0
  fi
  _pg_fw_call "$_pf_bin" "$_pf_table" -F "$_pf_chain" >/dev/null 2>&1 || :
  _pg_fw_call "$_pf_bin" "$_pf_table" -X "$_pf_chain" >/dev/null 2>&1 || :
  # Distinguish an absent chain from a failed firewall query. A failed
  # `-S CHAIN` alone is ambiguous on some Android/legacy iptables builds;
  # first require a successful listing of the containing table.
  if _pf_after_rules=$(_pg_fw_call "$_pf_bin" "$_pf_table" -S 2>/dev/null); then
    # Verify the chain declaration in the successful whole-table snapshot.
    # A failed `-S CHAIN` is ambiguous on legacy Android iptables; it must
    # never be treated as proof that a chain was removed.
    if printf '%s\n' "$_pf_after_rules" | grep -E "^-N ${_pf_chain}([[:space:]]|$)" >/dev/null 2>&1; then
      _pg_fw_warn "$_pf_bin ${_pf_table:-filter} chain $_pf_chain still exists after cleanup"
    fi
  else
    _pg_fw_warn "$_pf_bin ${_pf_table:-filter} final table listing failed; cannot verify $_pf_chain cleanup"
    return 0
  fi
}
# 再次收敛本模块命名的链，兼容历史版本遗留的重复 OUTPUT 跳转。
for _pf_spec in \
  'iptables|filter|PGUARD|OUTPUT|PGUARD' \
  'ip6tables|filter|PGUARD|OUTPUT|PGUARD' \
  'iptables|nat|PGNAT|OUTPUT|PGNAT' \
  'ip6tables|nat|PGNAT|OUTPUT|PGNAT' \
  'iptables|nat|PGVPN|OUTPUT|PGVPN' \
  'ip6tables|nat|PGVPN6|OUTPUT|PGVPN6' \
  'iptables|raw|PGNF|OUTPUT|PGNF' \
  'ip6tables|raw|PGNF6|OUTPUT|PGNF6' \
  'iptables|filter|PGKS|OUTPUT|PGKS' \
  'ip6tables|filter|PGBLK6|OUTPUT|PGBLK6' \
  'iptables|nat|PGHIDE|OUTPUT|PGHIDE' \
  'iptables|filter|PGHKS|OUTPUT|PGHKS' \
  'ip6tables|filter|PGHKS|OUTPUT|PGHKS' \
  'iptables|mangle|PGMTU|OUTPUT|PGMTU'; do
  _oldifs=$IFS; IFS='|'; set -- $_pf_spec; IFS=$_oldifs
  _pg_fw_clean_chain "$1" "$2" "$3" "$4" "$5"
done
unset _pf_spec _oldifs

# A1.5 Stop the optional local AdGuard Home engine only after the module-owned
# DNS/NAT hooks above have been removed. Never kill a PID without validating its
# cmdline; preserve the state directory if shutdown cannot be confirmed.
_DNS_ENGINE_STOP_OK=1
if [ -x "$MODDIR/scripts/adguardhome.sh" ]; then
  if ! sh "$MODDIR/scripts/adguardhome.sh" stop "$MODDIR" "$PG" >/dev/null 2>&1; then
    _DNS_ENGINE_STOP_OK=0
    PG_KEEP_DATA=1
    _mitm_warn "could not confirm stopping the FX-owned AdGuard Home front-end; preserving $PG for safe retry"
  fi
fi
# Do not make Unbound cleanup conditional on the AdGuard Home wrapper succeeding.
# If the front-end refuses to stop, its wrapper exits before stopping the resolver;
# at this point all FX OUTPUT/DNS hooks have already been detached, so independently
# validate and stop Unbound to avoid a root-owned recursive resolver leak.
if [ -x "$MODDIR/scripts/unbound.sh" ]; then
  if ! sh "$MODDIR/scripts/unbound.sh" stop "$MODDIR" "$PG" >/dev/null 2>&1; then
    _DNS_ENGINE_STOP_OK=0
    PG_KEEP_DATA=1
    _mitm_warn "could not confirm stopping the FX-owned Unbound resolver; preserving $PG for safe retry"
  fi
fi
[ "$_DNS_ENGINE_STOP_OK" = "1" ] || _mitm_warn "one or more local DNS processes could not be confirmed stopped; state retained"
# ============================================================
# A2. hosts bind mount 卸载（露出原始 /system/etc/hosts）
#     bind mount 是叠加挂载，umount 后原文件自动回来，无需拷贝还原
# ============================================================
# APEX 信任库覆盖层(A14+)与系统 cacerts 覆盖层：必须由 certmgr.sh
# 根据自己的 marker/挂载状态做有保护的卸载。这里绝不能无条件 umount，
# 否则若目标路径被其他模块/管理员挂载，会误卸载非 PrivacyGuard 的挂载。
# hosts 挂载只在 mount 表确认源文件属于本模块时才解除。
# 旧逻辑无条件 umount /system/etc/hosts，若该挂载点已被其他模块/管理员接管，
# 卸载会误拆第三方挂载。bind mount 的源路径是 $PG/hosts；未知来源一律保留并告警。
_hosts_mounts=$(mount 2>/dev/null)
case "$_hosts_mounts" in
  *"$PG/hosts on /system/etc/hosts "*)
    if ! umount /system/etc/hosts 2>/dev/null; then
      PG_KEEP_DATA=1
      _mitm_warn "could not unmount module-owned hosts bind mount; preserving $PG so the live bind-mount source is not deleted"
    fi
    ;;
  *" on /system/etc/hosts "*)
    _mitm_warn "hosts mount source is not PrivacyGuard-owned; preserving /system/etc/hosts mount to avoid disrupting another module"
    ;;
  *) : ;;
esac

# ============================================================
# A3. Root 检测路径遮蔽 mount 卸载（同上，umount 即还原）
# ============================================================
ROOTMASK_TRACK="$PG/rootmask.mounts"
if [ -f "$ROOTMASK_TRACK" ]; then
  while IFS= read -r p; do
    case "$p" in
      /system/xbin/su|/system/bin/su|/system/xbin/daemonsu|/system/bin/daemonsu|\
      /vendor/bin/su|/sbin/su|/system/xbin/busybox|/system/bin/busybox|\
      /system/app/Superuser.apk|/system/xbin/sugate|/system/xbin/sugate-mksh)
        if mount 2>/dev/null | grep -F " on $p " >/dev/null 2>&1; then
          if ! umount "$p" 2>/dev/null; then
            PG_KEEP_DATA=1
            PG_CLEANUP_INCOMPLETE=1
            echo "- 警告：遮蔽挂载仍占用，保留模块数据以便重试：$p" >&2
          fi
        fi
        ;;
      *) echo "- 忽略非法 rootmask 跟踪路径" ;;
    esac
  done < "$ROOTMASK_TRACK"
fi

# ============================================================
# A4. SELinux deny 规则还原（k_sysfs/k_read 注入过的 allow 恢复；
#     sepolicy.rule 文件随模块目录删除，下次重启由系统默认策略接管）
# ============================================================
SEPOL=""
command -v magiskpolicy >/dev/null 2>&1 && SEPOL=magiskpolicy
[ -z "$SEPOL" ] && [ -x /data/adb/ap/bin/magiskpolicy ] && SEPOL=/data/adb/ap/bin/magiskpolicy
[ -z "$SEPOL" ] && [ -x /data/adb/magisk/magiskpolicy ] && SEPOL=/data/adb/magisk/magiskpolicy
if [ -n "$SEPOL" ]; then
  for DOM in untrusted_app untrusted_app_25 untrusted_app_27; do
    "$SEPOL" --live "allow $DOM sysfs file read open getattr" 2>/dev/null
    "$SEPOL" --live "allow $DOM proc file read open getattr" 2>/dev/null
    "$SEPOL" --live "allow $DOM proc_cpuinfo file read open getattr" 2>/dev/null
  done
fi

# ============================================================
# A5. sysctl 还原
#    kstack.defaults 有原值用原值（k_stack 开启时记录）；
#    其余恢复 Linux/Android 常见出厂默认（模块只在开关开启时改过它们）
# ============================================================
if [ -f "$PG/kstack.defaults" ]; then
  while IFS='=' read -r kn kv; do
    [ -n "$kn" ] && sysctl -w "kernel.$kn=$kv" 2>/dev/null
  done < "$PG/kstack.defaults"
fi
# 未保存原值的通用 sysctl 不再强行写入所谓“出厂默认”：不同 ROM/内核默认值
# 不同，卸载时猜值可能覆盖用户/厂商配置。只恢复模块明确留有快照的 k_stack 项；
# 其余临时 sysctl 通常随重启恢复。

# ============================================================
# A6. Wi-Fi MAC：ip link 修改重启后由驱动重置，无法用户态即时还原原 MAC
#     （记录在备份里供用户参考；原 MAC 通常印于机身/包装）
# ============================================================
WIF=$(ip link 2>/dev/null | grep -o '^[0-9]*: [a-z0-9]*' | awk '{print $2}' | grep -E '^wlan' | head -1)
CURMAC=$(ip link show "$WIF" 2>/dev/null | grep -oE '([0-9a-f]{2}:){5}[0-9a-f]{2}' | head -1)
[ -n "$CURMAC" ] && echo "wifi_mac_at_uninstall=$CURMAC" >> "$BK/uninstall-report.txt" 2>/dev/null

# ============================================================
# B. 属性伪装还原（resetprop 只改内存视图，重启必然还原；
#    卸载时按 post-fs-data 记录的 props.snapshot 尽力即时恢复）
# ============================================================
RP=""
command -v resetprop >/dev/null 2>&1 && RP=resetprop
[ -z "$RP" ] && [ -x /data/adb/ksu/bin/resetprop ] && RP=/data/adb/ksu/bin/resetprop
[ -z "$RP" ] && [ -x /data/adb/ap/bin/resetprop ] && RP=/data/adb/ap/bin/resetprop
[ -z "$RP" ] && [ -x /data/adb/magisk/resetprop ] && RP=/data/adb/magisk/resetprop
# Match post-fs-data.sh: some Magisk installations expose resetprop only as
# the `magisk resetprop` subcommand, not as a standalone binary.
[ -z "$RP" ] && [ -x /data/adb/magisk/magisk ] && RP="/data/adb/magisk/magisk resetprop"
if [ -n "$RP" ] && [ -f "$BK/props.snapshot" ]; then
  while IFS='=' read -r pk pv; do
    case "$pk" in
      ''|'#'*) continue ;;
    esac
    # 空值 = 原本不存在该属性 → 删除伪装值；有值 → 恢复。
    # resetprop 的退出码不足以证明属性视图已恢复；部分 ROM/属性服务
    # 会拒绝写入。读取回验失败时必须保留快照与模块脚本供重试。
    if [ -n "$pv" ]; then
      $RP "$pk" "$pv" 2>/dev/null || :
      _rp_back=$(getprop "$pk" 2>/dev/null | tr -d '\r')
      if [ "$_rp_back" != "$pv" ]; then
        PG_CLEANUP_INCOMPLETE=1
        PG_KEEP_DATA=1
        _mitm_warn "could not verify property restore: $pk; preserving property snapshot for retry/manual recovery"
      fi
    else
      $RP --delete "$pk" 2>/dev/null || :
      _rp_back=$(getprop "$pk" 2>/dev/null | tr -d '\r')
      if [ -n "$_rp_back" ]; then
        PG_CLEANUP_INCOMPLETE=1
        PG_KEEP_DATA=1
        _mitm_warn "could not verify property deletion: $pk; preserving property snapshot for retry/manual recovery"
      fi
    fi
  done < "$BK/props.snapshot"
fi
# 恢复 logcat 防护触碰的持久属性。没有快照时绝不猜测/清空用户原值。
if [ -f "$BK/persist.log.tag.snapshot" ]; then
  _plto=$(cat "$BK/persist.log.tag.snapshot" 2>/dev/null | tr -d '\r')
  setprop persist.log.tag "$_plto" 2>/dev/null || :
  _pltback=$(getprop persist.log.tag 2>/dev/null | tr -d '\r')
  if [ "$_pltback" != "$_plto" ]; then
    PG_CLEANUP_INCOMPLETE=1
    PG_KEEP_DATA=1
    _mitm_warn "could not verify persist.log.tag restore; preserving snapshot for retry/manual recovery"
  fi
fi

# ============================================================
# A7. settings put 还原（Android Settings 数据库——真实持久修改，必须显式还原）
#     默认值来自 AOSP 出厂状态
# ============================================================
if [ -f "$PG/settings.snapshot" ]; then
  while IFS='|' read -r _sn _sk _sv; do
    [ -n "$_sn" ] && [ -n "$_sk" ] || continue
    case "$_sn$_sk" in *[!a-zA-Z0-9_.-]*)
      PG_CLEANUP_INCOMPLETE=1
      PG_KEEP_DATA=1
      _mitm_warn "ignored malformed settings snapshot entry (unsafe namespace/key); preserving snapshot for manual recovery"
      continue ;;
    esac
    case "$_sv" in
      null|'') settings delete "$_sn" "$_sk" >/dev/null 2>&1 ;;
      *) settings put "$_sn" "$_sk" "$_sv" >/dev/null 2>&1 ;;
    esac
    _sn_back=$(settings get "$_sn" "$_sk" 2>/dev/null | tr -d '\r')
    case "$_sv" in
      null|'') [ "$_sn_back" = null ] || [ -z "$_sn_back" ] ;;
      *) [ "$_sn_back" = "$_sv" ] ;;
    esac
    if [ "$?" -ne 0 ]; then
      PG_CLEANUP_INCOMPLETE=1
      PG_KEEP_DATA=1
      _mitm_warn "could not verify Settings restore: $_sn/$_sk (expected original value from snapshot); preserving snapshot for retry/manual recovery"
    fi
  done < "$PG/settings.snapshot"
fi

# ============================================================
# C. 用户数据备份 → 清理（顺序关键：先读快照/备份，最后才删目录）
# ============================================================
if [ -f "$PG/settings.conf" ]; then
  cp "$PG/settings.conf" /sdcard/privacyguard-settings-backup.conf 2>/dev/null
fi
# props/settings 快照一并备份（供极端情况手动恢复）
[ -f "$BK/props.snapshot" ] && cp "$BK/props.snapshot" /sdcard/privacyguard-props-backup.txt 2>/dev/null
[ -f "$PG/settings.snapshot" ] && cp "$PG/settings.snapshot" /sdcard/privacyguard-settings-snapshot.txt 2>/dev/null

# ============================================================
# A8. 内置系统级 CA 清理：删除两个子模块 + 解除 live 信任挂载
#     （ca_sync 在删完后自动卸载 overlay 挂载；重启后 magic-mount
#      不再存在，系统信任区彻底恢复；用户自装证书不受影响）
#     随后 cleanup restore 清理历史版本残留的隔离区/暂存/覆盖层数据：
#     卸载时显式请求“恢复”语义——把 ≤v1.7 被移入隔离区的用户证书
#     原样移回用户 CA 目录（数据不丢失）；cleanup 不带参数时绝不写用户区。
# ============================================================
if [ -f "$MODDIR/scripts/certmgr.sh" ]; then
  # v1.10.92：证书子模块清理/历史隔离区恢复是有状态操作；失败时保留数据目录，
  # 避免下面 rm -rf 删除 marker、恢复副本或重试所需文件。不得把失败吞掉后报告已清理。
  if ! sh "$MODDIR/scripts/certmgr.sh" builtin purge; then
    PG_KEEP_DATA=1
    PG_CLEANUP_INCOMPLETE=1
    _mitm_warn "built-in CA submodule purge failed; preserving $PG and certificate state for retry"
  fi
  if ! sh "$MODDIR/scripts/certmgr.sh" cleanup restore; then
    PG_KEEP_DATA=1
    PG_CLEANUP_INCOMPLETE=1
    _mitm_warn "historical certificate quarantine restore failed; preserving $PG and certificate state for retry"
  fi
fi

# ---- 二次确认代理核心已停止；绝不在此处使用弱于 vpncore.sh 的 PID 子串匹配兜底 ----
# A0.5 已调用 vpncore.sh stop（其按 argv 边界验证进程身份）。如果 PID 句柄仍存在，
# 说明停止未完成或身份无法确认；保留运行数据和 PID/日志供重试，避免误杀其他进程。
if [ -e "$PG/singbox.pid" ]; then
  PG_KEEP_DATA=1
  _mitm_warn "sing-box PID state remains after managed stop; preserving $PG for safe retry"
fi

# Remove only Hook APK packages managed by FX. This is package-manager cleanup only;
# it does not alter routing, DNS or firewall state. Failures are logged separately.
if [ -f "$MODDIR/scripts/remove_adhook_app.sh" ]; then
  if ! sh "$MODDIR/scripts/remove_adhook_app.sh" "$MODDIR" "$PG"; then
    _mitm_warn "one or more FX-managed Hook app packages could not be removed; see $PG/adhook-install.log"
  fi
fi

# A firewall cleanup verification failure also needs a retry path. Do not
# delete the module's cleanup state/source tree while PG* rules may still be
# active; otherwise the warning would recommend a retry after reboot but the
# scripts needed for that retry would already be gone.
if [ "$PG_FW_INCOMPLETE" = 1 ]; then
  PG_KEEP_DATA=1
fi
if [ "$PG_KEEP_DATA" = 1 ]; then
  _mitm_warn "cleanup is incomplete; preserving $PG and its state/source files for a safe retry"
  # Keep the source tree intact while an owned mount or certificate recovery may
  # still depend on it. XDIR contains transient UI/runtime files and is independent.
  rm -rf "$XDIR" 2>/dev/null
else
  rm -rf "$PG" "$XDIR" 2>/dev/null
fi

# ============================================================
# A9. 崩溃归因 / 转换器 / 信任库覆盖层构建残留清理
#     crashreport.sh 写 $PG/crashreport.txt（已随 $PG 删除）；
#     modconvert.sh 的临时目录 /data/local/tmp/pgmc.* 异常中断会残留；
#     CACERT 覆盖层构建目录若因异常中断未清，会留下挂载源。
# ============================================================
if [ "$PG_KEEP_DATA" = 1 ]; then
  # These temporary trees can be backing sources for a still-live certificate
  # overlay after an earlier unmount/purge failure. Keep them with the retry
  # state; deleting a mounted source can expose an empty/broken trust store.
  _mitm_warn "preserving certificate-overlay temporary paths because cleanup needs a retry"
else
  rm -rf /data/local/tmp/pgmc.* 2>/dev/null
  rm -rf /data/local/tmp/pg-trunc-cacerts* /data/local/tmp/pg-subst 2>/dev/null
  rm -f /data/local/tmp/live.lst /data/local/tmp/ovl.lst /data/local/tmp/diff.txt 2>/dev/null
fi

# The module manager removes the systemless APK overlay after this hook.
# Retire only FX-owned deployment markers; retain logs and unrelated state.
if [ -d "$PG" ] && [ ! -L "$PG" ]; then
  for _fx_marker in \
    "$PG/system-app-apk.sha256" \
    "$PG/system-app-retry" \
    "$PG/system-app-apk.sha256.tmp."* \
    "$PG/system-app-retry.tmp."*; do
    [ -f "$_fx_marker" ] && [ ! -L "$_fx_marker" ] && rm -f "$_fx_marker" 2>/dev/null || :
  done
fi
unset _fx_marker
if [ "$PG_KEEP_DATA" = 1 ]; then
  echo "PrivacyGuard 清理未完全完成：为保护重试所需的状态、脚本或挂载源，已保留 $PG；请查看警告并重试清理。" >&2
fi
if [ "$PG_FW_INCOMPLETE" = 1 ]; then
  echo "PrivacyGuard 防火墙清理未能全部确认；请检查 iptables/ip6tables 中的 PG* 自有链与引用。" >&2
fi
if [ "$PG_CLEANUP_INCOMPLETE" = 1 ]; then
  echo "PrivacyGuard 有一项或多项系统状态未能确认恢复（包括可能的 Settings 还原失败）；请查看 PrivacyGuardUninstall 警告。" >&2
fi
if [ "$PG_KEEP_DATA" != 1 ] && [ "$PG_FW_INCOMPLETE" != 1 ] && [ "$PG_CLEANUP_INCOMPLETE" != 1 ]; then
  echo "PrivacyGuard 已执行卸载清理；模块自有防火墙链与已跟踪恢复步骤未报告残留。"
fi
echo "- 防火墙/挂载/SELinux/sysctl/属性 已尝试即时还原；请检查以上警告和清理报告"
echo "- Settings 数据库按首次修改前快照恢复（仅恢复模块记录的键）"
echo "- 内置 CA 子模块(pg_mitm_ca/pg_https_ca)已删除，信任随之解除"
echo "- 内置代理内核与缓存(sing-box / cache)已随数据目录清除"
echo "- 用户证书区未主动写入；仅当历史隔离区(≤v1.7 用户CA禁用功能)有残留时，按原状移回原目录"
echo "- 配置已备份: /sdcard/privacyguard-settings-backup.conf"
echo "- 属性快照已备份: /sdcard/privacyguard-props-backup.txt"
echo "- 崩溃归因报告(crashreport.txt)与转换器临时目录已清理"