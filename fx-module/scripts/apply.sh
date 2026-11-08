#!/system/bin/sh
# PrivacyGuard apply.sh — 应用 settings.conf 到系统（hosts / iptables / sysctl / 属性 / xposed.conf）
# >>> pg-moddir (auto)
# 兼容相对路径/软链/su 调用：先尝试按 $0 推导，失败再逐级向上找 module.prop
# Every file this run creates (logs, staged hosts, fetched lists) must be
# private by default; individual writers still chmod 600 for clarity.
umask 077
# Correct permissions left behind by an earlier install.
chmod 600 "$PG/apply.log" 2>/dev/null || true
chmod 600 "$PG/apply.errors" 2>/dev/null || true

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

# 注意顺序：不能把 stderr 重定向进 $PG 内的文件来给 mkdir 报错——
# 重定向在命令执行前求值，$PG 不存在时重定向失败会让 mkdir 整条不执行，
# 随后 `exec >>` 也失败并使 shell 直接退出（静默失效）。先建目录，再开日志。
mkdir -p "$PG" 2>/dev/null || true
mkdir -p "$PG/cache" 2>/dev/null || true

# ---------- 单实例锁（并发安全）----------
# WebUI 的「应用」按钮可以连点、快速应用与刷新订阅也可能并发；两个 apply 同时跑会
# 互相踩 $PG/cache 下的临时文件（实测表现为 hosts 写失败、hosts/fw 半成品）。
# 用 mkdir 原子性做锁（POSIX sh 无 flock）。只对「真正会写系统状态」的模式加锁，
# status/vpn-core status 这类只读查询不锁。
APPLY_LOCK="$PG/apply.lock"
case "$1" in
  vpn-core)
    case "$2" in status) _APPLY_NOLOCK=1 ;; *) _APPLY_NOLOCK=0 ;; esac ;;
  "") _APPLY_NOLOCK=0 ;;
  fast|--quick|-q|full|vpn-sub|chn|vpn-core) _APPLY_NOLOCK=0 ;;
  *) _APPLY_NOLOCK=1 ;;   # 未知子命令马上 exit 2，无需锁
esac
if [ "${_APPLY_NOLOCK:-0}" != "1" ]; then
  _lk_w=0
  while ! mkdir "$APPLY_LOCK" 2>/dev/null; do
    # 陈旧锁（持有者已死）超过 120s 自动接管，避免一次崩溃把 apply 永久锁死
    _lk_pid=$(cat "$APPLY_LOCK/pid" 2>/dev/null)
    case "$_lk_pid" in
      ''|*[!0-9]*) ;;
      *)
        if ! kill -0 "$_lk_pid" 2>/dev/null; then
          _lk_pid_again=$(cat "$APPLY_LOCK/pid" 2>/dev/null)
          if [ "$_lk_pid_again" = "$_lk_pid" ] && ! kill -0 "$_lk_pid_again" 2>/dev/null; then
            _lk_stale="$PG/apply.lock.stale.$$"
            if mv "$APPLY_LOCK" "$_lk_stale" 2>/dev/null; then rm -rf "$_lk_stale" 2>/dev/null; fi
          fi
        fi ;;
    esac
    # Never evict a lock whose recorded owner is still alive, regardless of age.
    # A missing/malformed PID is ambiguous: the owner may have just mkdir'd the
    # lock and not yet published its PID. Age alone cannot distinguish that tiny
    # initialization window from an abandoned lock, so never evict it automatically.
    # This favors serialization safety over self-healing; after 60 waits we fail
    # closed with rc=75 and require explicit/manual stale-lock recovery.
    case "$_lk_pid" in
      ''|*[!0-9]*) : ;;
    esac
    _lk_w=$((_lk_w+1))
    if [ "$_lk_w" -ge 60 ]; then
      printf 'apply: 另一个 apply 正在运行（锁 %s），本次放弃\n' "$APPLY_LOCK"
      exit 75   # EX_TEMPFAIL
    fi
    sleep 0.5 2>/dev/null || sleep 1
  done
  echo $$ > "$APPLY_LOCK/pid" 2>/dev/null
  # 退出时释放（EXIT trap 覆盖正常/异常路径）
  # Subscription refresh is a transaction: if later apply/reload fails, restore the
  # previous settings and make a best-effort restart using the restored node selection.
  PG_SUB_TXN_ACTIVE=0
  PG_SUB_TXN_BACKUP=""
  PG_SUB_TXN_MARKER="$PG/vpn-sub.transaction"
  pg_apply_exit() {
    _pg_exit_rc=$?
    if [ "${PG_SUB_TXN_ACTIVE:-0}" = 1 ]; then
      if [ "$_pg_exit_rc" -eq 0 ]; then
        # Publish the commit decision atomically before deleting recovery data. If
        # power is lost after this point, startup can safely finish cleanup instead
        # of rolling back a transaction that already completed successfully.
        _pg_commit_tmp="$PG_SUB_TXN_MARKER.tmp.$$"
        if { printf '%s\n%s\n%s\n%s\n' "$PG_SUB_TXN_BACKUP" "${PG_SUB_TXN_CORE_WAS_RUNNING:-0}" "${PG_SUB_TXN_SHA256:-}" committed > "$_pg_commit_tmp"; } 2>/dev/null && mv -f "$_pg_commit_tmp" "$PG_SUB_TXN_MARKER" 2>/dev/null; then
          # Delete the backup first and the committed marker last. If either unlink
          # fails, the committed marker remains whenever possible and next apply can
          # safely retry cleanup without rolling back a transaction already committed.
          if rm -f "$PG_SUB_TXN_BACKUP" 2>/dev/null && rm -f "$PG_SUB_TXN_MARKER" 2>/dev/null; then
            pg_log "vpn-sub transaction committed; recovery cleanup completed"
          else
            pg_log "vpn-sub transaction committed; cleanup incomplete, committed marker/backup retained where possible for retry"
          fi
        else
          rm -f "$_pg_commit_tmp" 2>/dev/null
          _pg_exit_rc=1
          pg_log "vpn-sub transaction commit marker failed; recovery data retained"
          pg_log "vpn-sub commit-marker failure: attempting immediate rollback"
          # A failed commit-marker publish means the transaction is NOT committed.
          # Restore the previous settings now instead of returning failure while
          # leaving the newly-mutated subscription settings active.
          _pg_rollback_ok=0
          if [ -f "$PG_SUB_TXN_BACKUP" ]; then
            _pg_commit_bak_hash=$(pg_sub_sha256 "$PG_SUB_TXN_BACKUP" 2>/dev/null) || _pg_commit_bak_hash=""
            if [ -n "${PG_SUB_TXN_SHA256:-}" ] && [ "$_pg_commit_bak_hash" = "$PG_SUB_TXN_SHA256" ]; then
              _pg_commit_restore="$CONF.rollback.commit.$$"
              if cp "$PG_SUB_TXN_BACKUP" "$_pg_commit_restore" 2>/dev/null && mv -f "$_pg_commit_restore" "$CONF" 2>/dev/null; then
                _pg_rollback_ok=1
                if [ "${PG_SUB_TXN_CORE_WAS_RUNNING:-0}" = 1 ]; then
                  if ! pg_sub_validate_restored_core || ! pg_sub_restore_core_runtime; then
                    _pg_rollback_ok=0
                    pg_log "vpn-sub commit failure rollback: core/runtime restore failed; recovery evidence retained"
                  fi
                fi
              else
                rm -f "$_pg_commit_restore" 2>/dev/null
                pg_log "vpn-sub commit failure rollback ERROR: settings restore failed; recovery evidence retained"
              fi
            else
              pg_log "vpn-sub commit failure rollback ERROR: backup checksum mismatch; refusing restore"
            fi
          else
            pg_log "vpn-sub commit failure rollback ERROR: backup missing; recovery evidence retained"
          fi
          if [ "$_pg_rollback_ok" = 1 ]; then
            if rm -f "$PG_SUB_TXN_MARKER" 2>/dev/null; then
              rm -f "$PG_SUB_TXN_BACKUP" 2>/dev/null || pg_log "vpn-sub commit failure rollback: settings restored; orphan backup retained"
              pg_log "vpn-sub commit failure rollback: previous settings restored"
            else
              pg_log "vpn-sub commit failure rollback: settings restored but marker cleanup failed; recovery evidence retained"
            fi
          fi
        fi
      else
        pg_log "vpn-sub transaction failed (rc=$_pg_exit_rc); restoring prior settings and runtime best-effort"
        if [ -f "$PG_SUB_TXN_BACKUP" ]; then
          _pg_backup_hash=$(pg_sub_sha256 "$PG_SUB_TXN_BACKUP" 2>/dev/null) || _pg_backup_hash=""
          if [ -z "${PG_SUB_TXN_SHA256:-}" ] || [ "$_pg_backup_hash" != "$PG_SUB_TXN_SHA256" ]; then
            pg_log "vpn-sub rollback ERROR: backup SHA-256 mismatch; refusing to restore and retaining recovery evidence"
          else
            _pg_restore="$CONF.rollback.$$"
            if cp "$PG_SUB_TXN_BACKUP" "$_pg_restore" 2>/dev/null && mv -f "$_pg_restore" "$CONF" 2>/dev/null; then
              _pg_runtime_ok=1
              if [ "${PG_SUB_TXN_CORE_WAS_RUNNING:-0}" = 1 ]; then
              if ! pg_sub_validate_restored_core; then
                _pg_runtime_ok=0
                pg_log "vpn-sub rollback: restored settings failed sing-box config validation; recovery marker retained"
              elif ! pg_sub_restore_core_runtime; then
                _pg_runtime_ok=0
                pg_log "vpn-sub rollback: core lifecycle restoration failed; recovery marker retained for retry"
              fi
            fi
              if [ "$_pg_runtime_ok" = 1 ]; then
                # Restoration is complete; remove the marker first. If backup cleanup
                # fails, the remaining orphan is diagnostic only and is never auto-restored.
                if rm -f "$PG_SUB_TXN_MARKER" 2>/dev/null; then
                  if rm -f "$PG_SUB_TXN_BACKUP" 2>/dev/null; then
                    pg_log "vpn-sub rollback: previous settings restored; recovery evidence cleanup completed"
                  else
                    pg_log "vpn-sub rollback: previous settings restored; backup cleanup incomplete; orphan backup retained for diagnosis"
                  fi
                else
                  pg_log "vpn-sub rollback: previous settings restored; marker cleanup failed; recovery evidence retained for retry/manual review"
                fi
              else
                pg_log "vpn-sub rollback: previous settings restored but runtime recovery incomplete; marker/backup retained for retry"
              fi
              pg_log "vpn-sub rollback: runtime/network rollback is best-effort; full network-rule rollback is not atomic"
            else
              rm -f "$_pg_restore" 2>/dev/null
              pg_log "vpn-sub rollback ERROR: settings restore failed; backup retained at $PG_SUB_TXN_BACKUP"
            fi
          fi
        else
          pg_log "vpn-sub rollback ERROR: backup missing; transaction marker retained for recovery"
        fi
      fi
    fi
    # Rebuild manifests from the final settings snapshot (committed or rolled back)
    # before releasing the apply lock. This closes the config-to-runtime gap while
    # ensuring a failed transactional subscription update cannot leave manifests
    # describing settings that were just rolled back.
    for _fx_sync in sync-mitm-hosts.sh sync-urlrewrite.sh; do
      _fx_sync_path="$MODDIR/scripts/$_fx_sync"
      [ -x "$_fx_sync_path" ] || continue
      _fx_sync_out=$(FX_MODDIR="$MODDIR" PG="$PG" sh "$_fx_sync_path" 2>&1)
      _fx_sync_rc=$?
      [ -n "$_fx_sync_out" ] && printf '%s\n' "$_fx_sync_out" >> "$PG/apply.log"
      if [ "$_fx_sync_rc" -ne 0 ]; then
        pg_log "warning: $_fx_sync failed rc=$_fx_sync_rc; last-known-good manifest retained where possible"
      fi
    done
    # Keep the apply lock held through rollback; releasing it before restoring
    # settings/runtime lets a concurrent apply race the rollback transaction.
    rm -rf "$APPLY_LOCK" 2>/dev/null
    exit "$_pg_exit_rc"
  }
  trap 'pg_apply_exit' EXIT
  # Convert catchable termination signals into a non-zero exit so the EXIT
  # transaction handler always runs; without this, a signal can leave the
  # subscription backup and mutated settings without an explicit rollback.
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
fi

if [ -w "$PG" ]; then
  # 不要 : > apply.log 截断——日志可能正被并发进程/WebUI 读取，
  # 且截断会把上一轮失败线索抹掉。改为追加 + 显式分段标记。
  exec 3>&1
  exec >> "$PG/apply.log" 2>&1
else
  # PG 不可写时也保留 fd3：vpn-core 失败原因仍要能回传给 WebUI，
  # 否则向未打开的 fd3 写入会报 Bad file descriptor。
  exec 3>&1
fi
pg_err_reset
pg_log "=== apply start (pid $$) ==="
# v1.10.8: 升级用户配置迁移（老 settings.conf 补 [list:hosts_local] 段与内置规则/FX 条目；
# 幂等、只补缺失项。放在锁内执行，避免与并发 apply 同时改写 settings.conf）。
command -v pg_migrate_lists >/dev/null 2>&1 && pg_migrate_lists 2>/dev/null || true

# Recover an interrupted Hosts sidecar publication before any apply mode can
# consume or overwrite the caches. The apply lock is already held at this point.
# Marker paths are treated as untrusted input and constrained to our cache directory.
pg_hosts_sidecar_recover() {
  _hsr_marker="$PG/cache/sidecar.txn"
  [ -f "$_hsr_marker" ] || return 0
  _hsr_had_ip=$(sed -n 's/^had_ip=//p' "$_hsr_marker" | head -n1)
  _hsr_had_wlexc=$(sed -n 's/^had_wlexc=//p' "$_hsr_marker" | head -n1)
  _hsr_ip_backup=$(sed -n 's/^ip_backup=//p' "$_hsr_marker" | head -n1)
  _hsr_wlexc_backup=$(sed -n 's/^wlexc_backup=//p' "$_hsr_marker" | head -n1)
  _hsr_phase=$(sed -n 's/^phase=//p' "$_hsr_marker" | head -n1)
  case "$_hsr_phase" in active|committed) ;; *)
    pg_log "CRITICAL: invalid sidecar transaction phase; refusing to modify caches"
    return 1 ;;
  esac
  _hsr_ip_suffix=${_hsr_ip_backup#"$PG"/cache/subnet-ips.list.rollback.}
  _hsr_wlexc_suffix=${_hsr_wlexc_backup#"$PG"/cache/wlexc.rollback.}
  case "$_hsr_ip_suffix" in ''|*[!A-Za-z0-9._-]*|*/*) pg_log "CRITICAL: invalid IP backup suffix"; return 1 ;; esac
  case "$_hsr_wlexc_suffix" in ''|*[!A-Za-z0-9._-]*|*/*) pg_log "CRITICAL: invalid whitelist backup suffix"; return 1 ;; esac
  case "$_hsr_had_ip:$_hsr_had_wlexc" in 0:0|0:1|1:0|1:1) ;; *)
    pg_log "CRITICAL: invalid sidecar transaction marker flags; refusing to modify caches"
    return 1 ;;
  esac
  case "$_hsr_ip_backup" in "$PG"/cache/subnet-ips.list.rollback.*) ;; *)
    pg_log "CRITICAL: invalid IP sidecar recovery path; refusing to modify caches"
    return 1 ;;
  esac
  case "$_hsr_wlexc_backup" in "$PG"/cache/wlexc.rollback.*) ;; *)
    pg_log "CRITICAL: invalid whitelist sidecar recovery path; refusing to modify caches"
    return 1 ;;
  esac
  if [ "$_hsr_phase" = committed ]; then
    # Both new sidecars were published and the commit decision was persisted.
    # Do not roll back a completed generation just because cleanup was interrupted.
    if rm -f "$_hsr_ip_backup" "$_hsr_wlexc_backup" 2>/dev/null && rm -f "$_hsr_marker" 2>/dev/null; then
      pg_log "hosts sidecar recovery: completed committed-generation cleanup"
      return 0
    fi
    pg_log "hosts sidecar recovery: committed cleanup incomplete; marker retained for retry"
    return 1
  fi
  if [ "$_hsr_had_ip" = 1 ] && [ ! -f "$_hsr_ip_backup" ]; then
    pg_log "CRITICAL: IP sidecar recovery copy missing; marker retained"
    return 1
  fi
  if [ "$_hsr_had_wlexc" = 1 ] && [ ! -f "$_hsr_wlexc_backup" ]; then
    pg_log "CRITICAL: whitelist sidecar recovery copy missing; marker retained"
    return 1
  fi
  pg_log "hosts sidecar crash recovery: restoring previous complete cache generation"
  if [ "$_hsr_had_ip" = 1 ]; then
    _hsr_ip_restore="$PG/cache/subnet-ips.list.recover.$$"
    if ! cp -p "$_hsr_ip_backup" "$_hsr_ip_restore" 2>>"$PG/apply.log" ||
       ! mv -f "$_hsr_ip_restore" "$PG/cache/subnet-ips.list" 2>>"$PG/apply.log"; then
      rm -f "$_hsr_ip_restore" 2>/dev/null || true
      pg_log "CRITICAL: IP sidecar crash recovery failed; marker and backups retained"
      return 1
    fi
  else
    if ! rm -f "$PG/cache/subnet-ips.list" 2>>"$PG/apply.log"; then
      pg_log "CRITICAL: IP sidecar cleanup failed during recovery; marker retained"
      return 1
    fi
  fi
  if [ "$_hsr_had_wlexc" = 1 ]; then
    _hsr_wlexc_restore="$PG/cache/wlexc.tmp.recover.$$"
    if ! cp -p "$_hsr_wlexc_backup" "$_hsr_wlexc_restore" 2>>"$PG/apply.log" ||
       ! mv -f "$_hsr_wlexc_restore" "$PG/cache/wlexc.tmp" 2>>"$PG/apply.log"; then
      rm -f "$_hsr_wlexc_restore" 2>/dev/null || true
      pg_log "CRITICAL: whitelist sidecar crash recovery failed; marker and backups retained"
      return 1
    fi
  else
    if ! rm -f "$PG/cache/wlexc.tmp" 2>>"$PG/apply.log"; then
      pg_log "CRITICAL: whitelist sidecar cleanup failed during recovery; marker retained"
      return 1
    fi
  fi
  # Marker is removed only after both cache files match the prior generation.
  if rm -f "$_hsr_marker" 2>/dev/null; then
    rm -f "$_hsr_ip_backup" "$_hsr_wlexc_backup" 2>/dev/null || pg_log "hosts sidecar recovery succeeded; orphan backup cleanup incomplete"
    pg_log "hosts sidecar crash recovery: previous cache generation restored"
    return 0
  fi
  pg_log "CRITICAL: sidecar recovery succeeded but marker cleanup failed; marker retained"
  return 1
}

# Recover before dispatching any write-capable apply mode. Function definition must
# precede invocation in POSIX shell; otherwise recovery is an unknown command.
if [ "${_APPLY_NOLOCK:-0}" != 1 ]; then
  pg_hosts_sidecar_recover || {
    pg_fail hosts "检测到未完成的缓存事务且恢复失败；拒绝继续应用，保留恢复材料"
    exit 1
  }
fi

# ---------- 子命令分派 ----------
# WebUI 契约（详见交付报告）：
#   无参数 / "full"      = 完整重建：订阅下载 + hosts 重建 + 全部 iptables/sysctl/xposed（「刷新订阅」）
#   "fast" / "--quick"   = 快速应用：只做 iptables/vpn/轻量项，跳过订阅重下与 hosts 重建，
#                          复用 $PG/hosts（「应用」按钮必须用它，否则会卡 40s）
#   vpn-sub | chn | vpn-core   = 各自专项（见下）
#   其它任何参数          = 打印用法并 exit 2（**绝不能**落到全量分支：WebUI 会探测
#                          `apply.sh fast` 是否被支持，误当支持后同步等 40s 就是"卡死"）
APPLY_FAST=0
case "$1" in
  fast|--quick|-q) APPLY_FAST=1 ;;
esac

# ---------- 特殊子命令（WebUI VPN 页调用） ----------
# 同样需要 [ -f ] 守卫：vpncore.sh 缺失/未完整安装时，裸 source 会让 apply.sh
# 整体 exit=2（既不应用配置也不写日志，表现为"点了没反应"）。
if [ -f "$MODDIR/scripts/vpncore.sh" ]; then . "$MODDIR/scripts/vpncore.sh" 2>/dev/null; fi

# Validate a restored subscription snapshot before attempting to restart a previously
# running core. The generated sing-box config is derived from the restored settings.
# Missing/unsupported check tooling is handled by vpncore_check_conf's documented policy.
pg_sub_validate_restored_core() {
  command -v vpncore_genconf >/dev/null 2>&1 || return 1
  command -v vpncore_bin >/dev/null 2>&1 || return 1
  command -v vpncore_cfg >/dev/null 2>&1 || return 1
  _pg_vbin=$(vpncore_bin) || return 1
  vpncore_genconf "$_pg_vbin" || return 1
  _pg_vcfg=$(vpncore_cfg) || return 1
  _pg_vcheck=$(vpncore_check_conf "$_pg_vbin" "$_pg_vcfg")
  [ $? -eq 0 ] || { pg_log "vpn-sub recovery: restored config sing-box check failed: $_pg_vcheck"; return 1; }
  return 0
}

# Idempotent runtime restoration. A previous attempt may have stopped the core
# successfully but failed to start it; on retry, do not treat an already-stopped
# core as a stop failure. PID identity must be verified before deciding it is live.
pg_sub_restore_core_runtime() {
  command -v vpncore_pid >/dev/null 2>&1 || return 1
  command -v vpncore_pid_matches >/dev/null 2>&1 || return 1
  command -v vpncore_stop >/dev/null 2>&1 || return 1
  command -v vpncore_start >/dev/null 2>&1 || return 1
  _pg_pidfile=$(vpncore_pid 2>/dev/null) || return 1
  _pg_pid=$(cat "$_pg_pidfile" 2>/dev/null)
  _pg_core_live=0
  case "$_pg_pid" in
    ''|*[!0-9]*) ;;
    *) if kill -0 "$_pg_pid" 2>/dev/null && vpncore_pid_matches "$_pg_pid"; then _pg_core_live=1; fi ;;
  esac
  if [ "$_pg_core_live" = 1 ]; then
    if ! vpncore_stop >/dev/null 2>&1; then
      _pg_pid=$(cat "$_pg_pidfile" 2>/dev/null)
      case "$_pg_pid" in
        ''|*[!0-9]*) ;;
        *) if kill -0 "$_pg_pid" 2>/dev/null && vpncore_pid_matches "$_pg_pid"; then
          pg_log "vpn-sub recovery: old core remains alive after stop failure"
          return 1
        fi ;;
      esac
    fi
  fi
  # If a previous retry already stopped the core, go straight to start.
  vpncore_start >/dev/null 2>&1 || { pg_log "vpn-sub recovery: core start failed; transaction evidence retained for retry"; return 1; }
  return 0
}

pg_sub_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | awk 'NR==1 {print $1}'; return; fi
  if command -v toybox >/dev/null 2>&1; then toybox sha256sum "$1" 2>/dev/null | awk 'NR==1 {print $1}'; return; fi
  return 1
}

# Crash recovery for SIGKILL/power loss (which cannot run EXIT traps). Marker format:
# line 1 = absolute backup path; line 2 = prior core state; line 3 = SHA-256;
# line 4 = active/committed phase. Two-line legacy markers remain recoverable.
# Recovery only runs under the apply lock and never deletes the marker/backup unless
# settings restore and required core restart both succeed.
PG_SUB_TXN_MARKER="$PG/vpn-sub.transaction"
if [ "${_APPLY_NOLOCK:-0}" != 1 ] && [ -f "$PG_SUB_TXN_MARKER" ] && [ "${PG_SUB_TXN_ACTIVE:-0}" != 1 ]; then
  _pg_crash_bak=$(sed -n '1p' "$PG_SUB_TXN_MARKER" 2>/dev/null)
  _pg_crash_core=$(sed -n '2p' "$PG_SUB_TXN_MARKER" 2>/dev/null)
  _pg_crash_hash=$(sed -n '3p' "$PG_SUB_TXN_MARKER" 2>/dev/null)
  _pg_crash_phase=$(sed -n '4p' "$PG_SUB_TXN_MARKER" 2>/dev/null)
  case "$_pg_crash_bak" in "$PG"/settings.conf.vpn-sub-backup.*) ;; *) _pg_crash_bak="" ;; esac
  _pg_crash_suffix=${_pg_crash_bak#"$PG"/settings.conf.vpn-sub-backup.}
  case "$_pg_crash_suffix" in ''|*[!A-Za-z0-9._-]*|*/*) _pg_crash_bak="" ;; esac
  case "$_pg_crash_core" in 0|1) ;; *) _pg_crash_bak="" ;; esac
  case "$_pg_crash_phase" in ''|active|committed) ;; *) _pg_crash_bak="" ;; esac
  if [ -n "$_pg_crash_bak" ] && [ "$_pg_crash_phase" = committed ]; then
    # Commit was published; only cleanup remains. Remove backup first and marker last
    # so a failed backup unlink leaves a committed marker for the next retry.
    if rm -f "$_pg_crash_bak" 2>/dev/null && rm -f "$PG_SUB_TXN_MARKER" 2>/dev/null; then
      pg_log "vpn-sub crash recovery: committed transaction cleanup completed"
    else
      pg_log "vpn-sub crash recovery: committed transaction cleanup incomplete; retry on next apply"
    fi
  elif [ -n "$_pg_crash_bak" ] && [ -s "$_pg_crash_bak" ]; then
    if [ -n "$_pg_crash_hash" ]; then
      case "$_pg_crash_hash" in ''|*[!0-9a-fA-F]*) _pg_crash_bak="" ;; esac
      [ "${#_pg_crash_hash}" -eq 64 ] || _pg_crash_bak=""
      _pg_actual_hash=$(pg_sub_sha256 "$_pg_crash_bak") || _pg_actual_hash=""
      [ -n "$_pg_crash_bak" ] && [ "$_pg_actual_hash" = "$_pg_crash_hash" ] || _pg_crash_bak=""
    else
      pg_log "vpn-sub crash recovery: legacy marker without checksum; accepting only validated in-module backup path"
    fi
  fi
  if [ -n "$_pg_crash_bak" ] && [ "$_pg_crash_phase" != committed ] && [ -s "$_pg_crash_bak" ]; then
    pg_log "vpn-sub crash recovery: stale transaction marker found; restoring previous settings"
    _pg_crash_tmp="$CONF.recovery.$$"
    if cp "$_pg_crash_bak" "$_pg_crash_tmp" 2>/dev/null && mv -f "$_pg_crash_tmp" "$CONF" 2>/dev/null; then
      _pg_crash_ok=1
      if [ "$_pg_crash_core" = 1 ]; then
        if ! pg_sub_validate_restored_core; then
          _pg_crash_ok=0
          pg_log "vpn-sub crash recovery incomplete: restored settings failed sing-box config validation; marker/backup retained"
        elif ! pg_sub_restore_core_runtime; then
          _pg_crash_ok=0
          pg_log "vpn-sub crash recovery incomplete: core lifecycle restoration failed; marker/backup retained for retry"
        fi
      fi
      if [ "$_pg_crash_ok" = 1 ]; then
        # Clear the marker first after successful restore. A leftover backup is safer
        # than a live marker pointing at a backup that was already deleted.
        if rm -f "$PG_SUB_TXN_MARKER" 2>/dev/null; then
          if rm -f "$_pg_crash_bak" 2>/dev/null; then
            pg_log "vpn-sub crash recovery: settings restored; recovery evidence cleanup completed"
          else
            pg_log "vpn-sub crash recovery: settings restored; backup cleanup incomplete; orphan backup retained for diagnosis"
          fi
        else
          pg_log "vpn-sub crash recovery: settings restored; marker cleanup failed; recovery evidence retained for retry/manual review"
        fi
        pg_log "vpn-sub crash recovery: core recovery completed where required; network rules still require normal apply reconciliation"
      fi
    else
      rm -f "$_pg_crash_tmp" 2>/dev/null
      pg_log "vpn-sub crash recovery ERROR: settings restore failed; marker/backup retained"
    fi
  else
    pg_log "vpn-sub crash recovery ERROR: transaction marker invalid or backup missing; preserving marker for manual recovery"
  fi
fi
# A backup without its transaction marker is ambiguous: it may be an old committed
# snapshot or a marker lost during a crash. Never restore it heuristically; report it
# for diagnosis rather than silently replacing current user settings.
if [ "${_APPLY_NOLOCK:-0}" != 1 ] && [ ! -f "$PG_SUB_TXN_MARKER" ]; then
  for _pg_orphan_bak in "$PG"/settings.conf.vpn-sub-backup.*; do
    [ -f "$_pg_orphan_bak" ] || continue
    pg_log "vpn-sub recovery NOTICE: orphan backup found without transaction marker ($_pg_orphan_bak); current settings left untouched pending manual review"
  done
fi
case "$1" in
  fast|--quick|-q|full)
    # 落到下面的正常 apply 流程（APPLY_FAST 已置位）；不做专项处理
    :
    ;;
  vpn-sub)
    # Snapshot settings before subscription code mutates node list/selection. Exit trap
    # commits only on rc=0; all later failures restore this snapshot.
    PG_SUB_TXN_BACKUP="$PG/settings.conf.vpn-sub-backup.$$"
    PG_SUB_TXN_CORE_WAS_RUNNING=0
    if [ "$(pg_get vpn_core 0)" = "1" ] && [ "$(pg_get vpn_mode direct)" != "direct" ]; then
      _pg_pre_pid=$(vpncore_pid 2>/dev/null)
      _pg_pre_pid=$(cat "$_pg_pre_pid" 2>/dev/null)
      case "$_pg_pre_pid" in ''|*[!0-9]*) ;; *) kill -0 "$_pg_pre_pid" 2>/dev/null && PG_SUB_TXN_CORE_WAS_RUNNING=1 ;; esac
    fi
    if [ ! -s "$CONF" ] || ! cp "$CONF" "$PG_SUB_TXN_BACKUP" 2>/dev/null; then
      pg_fail vpn-sub "无法备份旧 settings.conf，拒绝修改订阅配置"
      pg_summary "vpn-sub"
      exit 1
    fi
    PG_SUB_TXN_SHA256=$(pg_sub_sha256 "$PG_SUB_TXN_BACKUP")
    _pg_marker_tmp="$PG_SUB_TXN_MARKER.tmp.$$"
    if [ -z "$PG_SUB_TXN_SHA256" ] || ! { printf '%s\n%s\n%s\n%s\n' "$PG_SUB_TXN_BACKUP" "$PG_SUB_TXN_CORE_WAS_RUNNING" "$PG_SUB_TXN_SHA256" active > "$_pg_marker_tmp" && mv -f "$_pg_marker_tmp" "$PG_SUB_TXN_MARKER"; }; then
      rm -f "$_pg_marker_tmp" "$PG_SUB_TXN_BACKUP" 2>/dev/null
      pg_fail vpn-sub "无法持久化订阅事务标记，拒绝修改配置"
      pg_summary "vpn-sub"
      exit 1
    fi
    PG_SUB_TXN_ACTIVE=1
    # 更新全部启用的代理订阅：拉取 → 提取节点 URI → 重写 [list:vpn_node]
    if [ -f "$MODDIR/scripts/vpnsub.sh" ]; then . "$MODDIR/scripts/vpnsub.sh" 2>/dev/null; fi
    if ! command -v vpn_update_subs >/dev/null 2>&1; then
      pg_fail vpn-sub "vpnsub.sh 缺失/损坏，无法更新订阅"
      pg_summary "vpn-sub"
      exit 1
    fi
    # 写前先把被旧版截断的配置骨架补回来（幂等；配置完好时什么都不做）。
    # Repair failure must abort before subscription code rewrites the node section;
    # the transaction exit trap restores the pre-update settings snapshot.
    if ! command -v vpn_repair_conf >/dev/null 2>&1; then
      pg_fail vpn-sub "配置修复函数缺失，拒绝继续改写订阅节点"
      pg_summary "vpn-sub"
      exit 1
    fi
    if ! vpn_repair_conf; then
      pg_fail vpn-sub "settings.conf 骨架修复失败，已拒绝更新订阅以保护原配置"
      pg_summary "vpn-sub"
      exit 1
    fi
    vpn_update_subs
    n=$?
    if [ "$n" -ne 0 ]; then
      pg_summary "vpn-sub"
      echo "vpn-sub failed (rc=$n)"
      exit "$n"
    fi
    # 订阅更新/自动选优不仅改变 settings.conf：运行中的托管核心也必须加载
    # 新节点列表与 vpn_node。先确认旧核心已停止，再落入快速 apply 重建配置、
    # 重启核心并刷新接管规则；若停止失败则立即报错，不把旧运行态伪装成已更新。
    if [ "$(pg_get vpn_core 0)" = "1" ] && [ "$(pg_get vpn_mode direct)" != "direct" ]; then
      if command -v vpncore_stop >/dev/null 2>&1; then
        if ! vpncore_stop; then
          pg_fail vpn-sub "订阅已保存，但旧代理核心停止失败；未宣称运行配置已更新"
          pg_summary "vpn-sub"
          exit 1
        fi
      else
        pg_fail vpn-sub "vpncore_stop 不可用，无法安全重载订阅后的核心配置"
        pg_summary "vpn-sub"
        exit 1
      fi
    fi
    APPLY_FAST=1
    pg_log "vpn-sub: subscriptions persisted; continuing through fast apply to reconcile runtime state"
    ;;
  chn)
    # 仅下载大陆分流表
    # vpn_chn_download 定义在 vpnsub.sh 内，此前只在 vpn-sub 分支加载；
    # 直接从 chn 分支调用会 "not found"(exit 127)，导致 WebUI「下载大陆分流表」必失败。
    # 必须用 [ -f ] 守卫：POSIX 下 "." 是特殊内建命令，加载不存在的文件会让 shell
    # 立即退出(实测 exit=2)，后面的容错分支根本不可达。
    if ! command -v vpn_chn_download >/dev/null 2>&1; then
      if [ -f "$MODDIR/scripts/vpnsub.sh" ]; then . "$MODDIR/scripts/vpnsub.sh" 2>/dev/null; fi
    fi
    if ! command -v vpn_chn_download >/dev/null 2>&1; then
      pg_fail chn "vpnsub.sh 加载失败，无法下载大陆分流表"
      pg_summary "chn"
      exit 1
    fi
    vpn_chn_download
    n=$?
    pg_summary "chn"
    exit "$n"
    ;;
  vpn-core)
    # 手动启停本地代理核心（WebUI「启动核心」按钮）
    case "$2" in
      stop) vpncore_stop; pg_summary "vpn-core-stop" ;;
      status)
        _run=false
        _status_pidf=$(vpncore_pid)
        if [ -f "$_status_pidf" ]; then
          _status_pid=$(cat "$_status_pidf" 2>/dev/null)
          case "$_status_pid" in
            ''|*[!0-9]*) rm -f "$_status_pidf" 2>/dev/null ;;
            *)
              if kill -0 "$_status_pid" 2>/dev/null && vpncore_pid_matches "$_status_pid"; then
                _run=true
              else
                rm -f "$_status_pidf" 2>/dev/null
              fi
              ;;
          esac
        fi
        # builtin: 模块内 bin/<arch>/sing-box 是否存在（随包分发，无需联网）
        _blt=false
        _md=$(vpncore_moddir 2>/dev/null)
        if [ -n "$_md" ] && [ -f "$_md/bin/$(vpncore_arch)/sing-box" ]; then _blt=true; fi
        # 端口必须是数字：空值会让 printf 输出 "port":, —— 非法 JSON，
        # 前端 JSON.parse 会抛错，只能落到“状态未知/未内置”，属假状态。
        _lp=$(vpncore_conf local_port)
        case "$_lp" in ''|*[!0-9]*) _lp=7890 ;; esac
        printf '{"ok":1,"running":%s,"ver":"%s","arch":"%s","bin":"%s","port":%s,"builtin":%s}\n' \
          "$_run" "$(vpncore_ver)" "$(vpncore_arch)" "$(vpncore_bin)" \
          "$_lp" "$_blt" >&3
        ;;
      *)
        # 启动失败时把核心日志最后一行回传给 WebUI（写 fd3=原始 stdout）。
        # WebUI runCore() 只渲染最后一行非空输出；此前 stdout 全被重定向进
        # apply.log，桥层拿到空 out，用户只看到「核心启动失败」而无原因。
        if command -v vpn_core_ensure >/dev/null 2>&1; then
          vpn_core_ensure
          _rc=$?
        else
          pg_fail vpn-core "vpncore.sh 缺失/损坏，无法启动核心"
          _rc=1
        fi
        if [ "$_rc" -ne 0 ] && command -v vpncore_log >/dev/null 2>&1; then
          _why=$(tail -n 1 "$(vpncore_log)" 2>/dev/null)
          [ -n "$_why" ] && printf '%s\n' "$_why" >&3 2>/dev/null
        fi
        pg_summary "vpn-core"
        exit "$_rc"
        ;;
    esac
    exit $?
    ;;
  "")
    # 无参数 = 全量（保持既有行为）
    ;;
  *)
    # 未知子命令：明确失败，绝不误走全量（否则 WebUI 探测/误调用会同步等 40s）
    printf 'unknown subcommand: %s\n' "$1" >&3 2>/dev/null
    printf 'usage: apply.sh [full|fast] | vpn-sub | chn | vpn-core start|stop|status\n' >&3 2>/dev/null
    printf 'usage: apply.sh [full|fast] | vpn-sub | chn | vpn-core start|stop|status\n'
    exit 2
    ;;
esac

# vpn-core 子命令执行完 util.sh 里 PG_ERRS 计数已被 pg_summary 消费；这里确保后续
# 正常 apply 流程里 vpncore 函数可用（上面 source 失败时用最小兜底，避免 set -u 崩）
if ! command -v vpncore_ver >/dev/null 2>&1; then
  vpncore_ver() { echo "$SINGBOX_VER_DEFAULT"; }
  vpncore_arch() { echo "arm64"; }
  vpncore_bin() { echo "$PG/bin/sing-box"; }
  vpncore_pid() { echo "$PG/singbox.pid"; }
  vpncore_log() { echo "$PG/singbox.log"; }
  vpncore_conf() { echo ""; }
  vpncore_stop() { :; }
  vpn_core_ensure() { return 1; }
fi

# 配置文件存在性检查（没有配置时全部功能无从谈起）
if [ ! -f "$CONF" ]; then
  pg_fail conf "settings.conf 不存在，使用内置默认值"
  cat "$MODDIR/scripts/default.conf" > "$CONF" 2>>"$PG/apply.log"
fi

# 配置骨架自愈：旧版 vpnsub 的「空文件覆盖」事故会让 settings.conf 丢掉 vpn_mode /
# [conf:vpn] 等骨架（表现为「装完模块所有开关都读不到、VPN 一直 direct」）。
# 这里幂等修复：仅在骨架确实缺失时，用 default.conf 补骨架并保住用户的节点段。
# 必须放在所有 pg_get/pg_conf 读取之前。
if [ -f "$MODDIR/scripts/vpnsub.sh" ]; then
  if ! command -v vpn_repair_conf >/dev/null 2>&1; then
    if ! . "$MODDIR/scripts/vpnsub.sh" 2>/dev/null; then
      pg_fail conf "VPN 配置修复器加载失败；为避免应用损坏配置，已停止本次 apply"
      pg_summary "apply"
      exit 1
    fi
  fi
  if ! command -v vpn_repair_conf >/dev/null 2>&1; then
    pg_fail conf "VPN 配置修复器不可用；为避免应用损坏配置，已停止本次 apply"
    pg_summary "apply"
    exit 1
  fi
  if ! vpn_repair_conf; then
    pg_fail conf "settings.conf 骨架修复失败；原配置已保留，本次 apply 已安全中止"
    pg_summary "apply"
    exit 1
  fi
fi

# ---------- 公共读取器：vpn_hide 的隐藏分级参数（[conf:vpn] 段内，pg_get 只扫顶层键）----------
# 必须定义在顶层：VPN 段之外（如 Sysctl 段）也会按隐藏态判断 hide_level。
vpn_hide_conf() { pg_conf vpn 2>/dev/null | grep -m1 "^$1=" | cut -d= -f2 | tr -d ' '; }

# ---------- 提前在后台生成 LSPosed 配置（性能）----------
# gen_xposed_conf.sh 只读 settings.conf、只写 /data/local/tmp/privacyguard/，
# 与 apply 的其它阶段无依赖，可以并行执行。
# CA 信任同步不属于普通 apply：它会改变系统信任库，仅由用户明确执行 CA 启用/禁用
# 或 service.sh 在开机完成后按 ca-trust-optin 授权标记恢复，不在此处隐式接管。
_XPOSED_BG_PID=""
# Clear the previous LSPosed Remote Files result so a failed publish cannot
# inherit a stale success status from an earlier apply.
rm -f /data/local/tmp/privacyguard/xposed-remote.status 2>/dev/null
sh "$MODDIR/scripts/gen_xposed_conf.sh" 2>>"$PG/apply.log" &
_XPOSED_BG_PID=$!

# 带自定义超时的下载器（不改 util.sh 的 pg_fetch 语义：其它调用方仍需 15s）。
# 用途：hosts 规则源允许更短超时（并发下载 + 8s 上限），单源失败不再串行拖满 apply。
pg_fetch_t() {
  _ft_url="$1"; _ft_out="$2"; _ft_to="$3"
  if pg_have curl; then
    curl -fsSL --connect-timeout 4 --max-time "$_ft_to" -o "$_ft_out" "$_ft_url" 2>>"$PG/apply.log"
  elif pg_have wget; then
    wget -q -T "$_ft_to" -O "$_ft_out" "$_ft_url" 2>>"$PG/apply.log"
  else
    return 1
  fi
}

# ---------- 1. Hosts 拦截 ----------
# 性能（真机 40s→≤8s 的关键）：
#   a. 订阅下载并发（每条一个后台任务，全部并发 + 统一等待），不再串行等超时；
#   b. 规则下载结果按 URL 缓存，[conf] 里 hosts_cache_min 分钟内复用，避免每次「应用」
#      都重下 100k 行的大列表（默认 30 分钟；0=每次强制刷新）；
#   c. 102k 行文本的解析从「grep | while read」逐行 fork（实测 16s）改为单 awk 进程
#      （实测 0.35s）——这是卡死的主因，不是网络。
HOSTS_CACHE_MIN=$(vpn_hide_conf hosts_cache_min 2>/dev/null)
case "$HOSTS_CACHE_MIN" in ''|*[!0-9]*) HOSTS_CACHE_MIN=$(pg_conf vpn 2>/dev/null | grep -m1 '^hosts_cache_min=' | cut -d= -f2- | tr -d ' ') ;; esac
# 默认 120 分钟：订阅/规则源本身是低频数据，「应用」按钮不该每次都重下 100k 行。
# 刷新订阅走 `apply.sh full`/`vpn-sub`（可配合 [conf:vpn] hosts_cache_min=0 强制重下）。
case "$HOSTS_CACHE_MIN" in ''|*[!0-9]*) HOSTS_CACHE_MIN=120 ;; esac

# 把一份订阅文本（hosts/ADBLOCK/Clash 混合格式）一次 awk 解析成三类产物：
#   stdout: hosts 行（0.0.0.0 <domain>）
#   $1    : ip-cidr 暂存文件
#   $2    : 白名单例外文件（@@||domain^）
# 注意：全程单进程，不 fork；102k 行实测 ~0.35s。
hosts_parse_file() {
  _hp_f="$1"; _hp_ip="$2"; _hp_wle="$3"
  awk -v ipf="$_hp_ip" -v wlef="$_hp_wle" '
    function emit(d) { if (d != "") print "0.0.0.0 " d }
    { sub(/\r$/, ""); sub(/^[[:space:]]*-[[:space:]]+/, "") }
    # hosts 语法：0.0.0.0 d / 127.0.0.1 d / <ip> d
    /^0\.0\.0\.0[ \t]/   { sub(/^0\.0\.0\.0[ \t]+/, ""); sub(/[ \t].*$/, ""); emit($0); next }
    /^127\.0\.0\.1[ \t]/ { sub(/^127\.0\.0\.1[ \t]+/, ""); sub(/[ \t].*$/, ""); emit($0); next }
    /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[ \t]+[a-z0-9]/ {
      sub(/^[0-9.]+[ \t]+/, ""); sub(/[ \t].*$/, ""); emit($0); next
    }
    # Clash 语法
    /^(DOMAIN|DOMAIN-SUFFIX|HOST|HOST-SUFFIX),/ { n = split($0, a, ","); if (a[2] != "") emit(a[2]); next }
    /^(DOMAIN|HOST)-KEYWORD,/ {
      n = split($0, a, ","); k = a[2]
      if (k ~ /^[A-Za-z0-9-]+$/) { emit(k ".com"); emit("ads-" k ".com") }
      next
    }
    /^(DOMAIN|HOST)-WILDCARD,/ {
      n = split($0, a, ","); d = a[2]
      gsub(/^\*\./, "", d); gsub(/\*/, "", d)
      if (d ~ /\./) emit(d)
      next
    }
    # ADBLOCK: only an unmodified host rule is safe to compile into hosts.
    # Rules such as ||domain^$third-party, ||domain^$popup, domain=... or path
    # filters carry request context; widening them to a whole-domain hosts block
    # breaks first-party content. The MITM request-filter engine handles the
    # supported contextual subset after verifying the source cache checksum.
    /^@@\|\|[A-Za-z0-9.-]+\^$/ { d = $0; sub(/^@@\|\|/, "", d); sub(/\^$/, "", d); if (d ~ /^[A-Za-z0-9.-]+\.[A-Za-z][A-Za-z]+$/) print d > wlef; next }
    /^@@\|\|/ { next }
    /^\|\|[A-Za-z0-9.-]+\^$/ { d = $0; sub(/^\|\|/, "", d); sub(/\^$/, "", d); if (d ~ /^[A-Za-z0-9.-]+\.[A-Za-z][A-Za-z]+$/) emit(d); next }
    /^\|\|/ { next }
    # IP-CIDR / IP-CIDR6 / MIXED-IP-CIDR → 交给防火墙段
    /^(IP-CIDR6|MIXED-IP-CIDR|IP-CIDR),/ {
      n = split($0, a, ","); c = a[2]
      if (c ~ /^[0-9a-fA-F:.]+(\/[0-9]+)?$/) print c > ipf
      next
    }
  ' "$_hp_f"
}

# 下载一条规则源到缓存文件；优先复用未过期缓存。
# 用法: hosts_fetch_cached <url> <destfile>；返回 0=有可用内容
# 超时：真机实测 adguard filter_24（约 51k 行 / 2.3MB）单次要 8-10s，
# 压到 8s 会稳定失败（curl rc=28）→ hosts 丢大半个清单。这里给 20s；
# 关键是**并发**——多个源同时下，总耗时 ≈ 最慢那个，而不是累加。
hosts_fetch_cached() {
  _hf_url="$1"; _hf_dst="$2"
  # Sidecar communicates whether the successful result came from cache. The fetch
  # runs in a child subshell, so a shell variable cannot report this to the parent.
  _hf_cache_marker="$_hf_dst.cache-used"
  rm -f "$_hf_cache_marker" 2>/dev/null
  mkdir -p "$PG/cache/rules" 2>/dev/null
  _hf_key=$(printf '%s' "$_hf_url" | cksum | cut -d' ' -f1)
  _hf_cache="$PG/cache/rules/$_hf_key"
  _hf_stamp="$PG/cache/rules/$_hf_key.ts"
  _hf_sumfile="$_hf_cache.sha256"
  _hf_prev="$_hf_cache.prev"
  _hf_prev_sum="$_hf_prev.sha256"
  # Several configured entries may point to the same URL. build_hosts downloads
  # sources in parallel, so serialize cache read/backup/body+checksum commit per URL.
  # Otherwise two workers can interleave the data and sidecar renames and leave a
  # mismatched pair even though each download individually succeeded.
  _hf_lock="$PG/cache/rules/.lock.$_hf_key"
  _hf_lock_held=0
  _hf_wait=0
  while ! mkdir "$_hf_lock" 2>/dev/null; do
    _hf_owner=$(cat "$_hf_lock/pid" 2>/dev/null)
    case "$_hf_owner" in
      ''|*[!0-9]*) : ;;
      *) if ! kill -0 "$_hf_owner" 2>/dev/null; then
           _hf_owner2=$(cat "$_hf_lock/pid" 2>/dev/null)
           if [ "$_hf_owner2" = "$_hf_owner" ] && ! kill -0 "$_hf_owner2" 2>/dev/null; then
             _hf_stale="$_hf_lock.stale.$$"
             if mv "$_hf_lock" "$_hf_stale" 2>/dev/null; then rm -rf "$_hf_stale" 2>/dev/null; fi
           fi
         fi ;;
    esac
    _hf_wait=$((_hf_wait+1))
    if [ "$_hf_wait" -ge 200 ]; then
      _hf_hint=$(pg_url_hint "$_hf_url")
      pg_log "hosts: cache lock busy; refusing concurrent cache write for $_hf_hint"
      return 1
    fi
    sleep 0.1 2>/dev/null || sleep 1
  done
  _hf_lock_held=1
  printf '%s\n' "$$" > "$_hf_lock/pid" 2>/dev/null || { rmdir "$_hf_lock" 2>/dev/null || :; return 1; }
  _hf_unlock() {
    [ "$_hf_lock_held" = 1 ] || return 0
    _hf_owner=$(cat "$_hf_lock/pid" 2>/dev/null)
    if [ "$_hf_owner" = "$$" ]; then rm -f "$_hf_lock/pid" 2>/dev/null; rmdir "$_hf_lock" 2>/dev/null || :; fi
    _hf_lock_held=0
  }
  # Keep a verified previous generation. Cache content and sidecar are separate files,
  # so a power loss between their renames can leave a mismatched pair. The previous
  # generation lets us recover without trusting a checksum-less or corrupted file.
  _hf_pair_ok() {
    [ -s "$1" ] && [ -s "$2" ] || return 1
    _hf_pair_actual=$(_hf_sha256 "$1") || return 1
    _hf_pair_expected=$(cat "$2" 2>/dev/null | tr -d '[:space:]')
    [ "${#_hf_pair_expected}" -eq 64 ] || return 1
    case "$_hf_pair_expected" in *[!0-9a-fA-F]*) return 1 ;; esac
    [ "$_hf_pair_actual" = "$_hf_pair_expected" ]
  }
  # Cache checksum protects against truncated/modified cache files. This is an at-rest
  # integrity check, not publisher authenticity: a trusted expected digest must come from
  # an independent signed/verified channel to prove the remote source itself is authentic.
  _hf_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | awk 'NR==1 {print tolower($1)}'; return; fi
    if command -v toybox >/dev/null 2>&1; then toybox sha256sum "$1" 2>/dev/null | awk 'NR==1 {print tolower($1)}'; return; fi
    return 1
  }
  _hf_cache_ok=0
  if [ -s "$_hf_cache" ]; then
    _hf_actual=$(_hf_sha256 "$_hf_cache") || _hf_actual=""
    _hf_expected=$(cat "$_hf_sumfile" 2>/dev/null | tr -d '[:space:]')
    case "$_hf_expected" in
      '' )
        # One-time migration of legacy caches: calculate a baseline digest before reuse.
        if [ -n "$_hf_actual" ]; then
          _hf_sumtmp="$_hf_sumfile.$$"
          if printf '%s\n' "$_hf_actual" > "$_hf_sumtmp" && mv -f "$_hf_sumtmp" "$_hf_sumfile"; then _hf_cache_ok=1; fi
        fi
        ;;
      *[!0-9a-fA-F]* ) _hf_cache_ok=0 ;;
      * ) [ "${#_hf_expected}" -eq 64 ] && [ "$_hf_actual" = "$_hf_expected" ] && _hf_cache_ok=1 ;;
    esac
    if [ "$_hf_cache_ok" -ne 1 ]; then
      _hf_hint=$(pg_url_hint "$_hf_url")
      pg_log "hosts: cached rule checksum invalid; refusing cache for $_hf_hint"
    fi
  fi
  # Recover a verified previous generation when the current data/sidecar pair was
  # interrupted or tampered with. Never promote an unverified backup.
  if [ "$_hf_cache_ok" -ne 1 ] && _hf_pair_ok "$_hf_prev" "$_hf_prev_sum"; then
    _hf_restore_tmp="$_hf_cache.restore.$$"
    _hf_restore_sum="$_hf_sumfile.restore.$$"
    if cp -f "$_hf_prev" "$_hf_restore_tmp" 2>/dev/null &&
       cp -f "$_hf_prev_sum" "$_hf_restore_sum" 2>/dev/null &&
       [ "$(_hf_sha256 "$_hf_restore_tmp")" = "$(cat "$_hf_restore_sum" 2>/dev/null | tr -d '[:space:]')" ] &&
       mv -f "$_hf_restore_tmp" "$_hf_cache" 2>/dev/null &&
       mv -f "$_hf_restore_sum" "$_hf_sumfile" 2>/dev/null; then
      _hf_cache_ok=1
      # The verified previous generation may differ from what the current system
      # hosts was built from. Invalidate the build fingerprint so a failed current
      # apply cannot leave fast mode trusting stale generated output.
      rm -f "$PG/cache/hosts-config.cksum" 2>/dev/null || true
      _hf_hint=$(pg_url_hint "$_hf_url")
      pg_log "hosts: restored checksum-verified previous cache generation for $_hf_hint; hosts fingerprint invalidated"
    else
      rm -f "$_hf_restore_tmp" "$_hf_restore_sum" 2>/dev/null
    fi
  fi
  # Quick apply must never turn an ordinary local toggle/edit into a network
  # refresh. Reuse any checksum-verified cache regardless of age. If no verified
  # copy exists, fail the source and let build_hosts preserve the prior output.
  if [ "$_hf_cache_ok" -eq 1 ] && [ "${APPLY_FAST:-0}" = 1 ]; then
    cp -f "$_hf_cache" "$_hf_dst" 2>/dev/null && { : > "$_hf_cache_marker"; _hf_unlock; return 0; }
    _hf_hint=$(pg_url_hint "$_hf_url")
    pg_log "hosts: quick apply could not copy verified cache for $_hf_hint"
    rm -f "$_hf_dst" 2>/dev/null || true
    _hf_unlock
    return 1
  fi
  if [ "$_hf_cache_ok" -eq 1 ] && [ "$HOSTS_CACHE_MIN" -gt 0 ]; then
    _hf_age=$(($(date +%s) - $(cat "$_hf_stamp" 2>/dev/null || echo 0)))
    case "$_hf_age" in ''|*[!0-9]*) _hf_age=999999 ;; esac
    if [ "$_hf_age" -lt $((HOSTS_CACHE_MIN * 60)) ]; then
      cp -f "$_hf_cache" "$_hf_dst" 2>/dev/null && { : > "$_hf_cache_marker"; _hf_unlock; return 0; }
    fi
  fi
  # 未命中缓存 → 下载（20s 上限，抗大清单；并发执行故不拖总时长）
  # 只接受成功完成的下载。超时但已写入大量行并不代表清单完整；若将其提升为
  # 缓存，会静默覆盖完整规则。失败时保留旧缓存，首次下载失败则报告失败。
  if [ "${APPLY_FAST:-0}" = 1 ]; then
    _hf_hint=$(pg_url_hint "$_hf_url")
    pg_log "hosts: quick apply refuses network fetch because no verified local cache exists for $_hf_hint"
    rm -f "$_hf_dst" 2>/dev/null || true
    _hf_unlock
    return 1
  fi
  pg_fetch_t "$_hf_url" "$_hf_dst" 20
  _hf_rc=$?
  # Bound each downloaded source before hashing/parsing/cache promotion. Huge sources
  # can exhaust memory/CPU later even when the aggregate hosts guard would eventually
  # reject them. Reject, never truncate; the verified old cache remains eligible below.
  if [ "$_hf_rc" -eq 0 ] && [ -s "$_hf_dst" ]; then
    _hf_new_bytes=$(wc -c < "$_hf_dst" 2>/dev/null | tr -d ' ')
    _hf_new_lines=$(wc -l < "$_hf_dst" 2>/dev/null | tr -d ' ')
    case "$_hf_new_bytes:$_hf_new_lines" in *[!0-9:]*|:*) _hf_new_bytes=0; _hf_new_lines=0 ;; esac
    if [ "$_hf_new_bytes" -gt 25165824 ] || [ "$_hf_new_lines" -gt 200000 ]; then
      pg_fail fetch "规则源超过单源安全上限（${_hf_new_bytes} 字节/${_hf_new_lines} 行）：$_hf_url；拒绝新版本并尝试回退已校验缓存"
      _hf_rc=98
    fi
  fi
  if [ "$_hf_rc" -eq 0 ] && [ -s "$_hf_dst" ]; then
    _hf_newsum=$(_hf_sha256 "$_hf_dst") || _hf_newsum=""
    case "$_hf_newsum" in
      *[!0-9a-fA-F]*|'') _hf_rc=97 ;;
      *)
        [ "${#_hf_newsum}" -eq 64 ] || _hf_rc=97
        ;;
    esac
    if [ "$_hf_rc" -eq 0 ]; then
      _hf_cache_tmp="$_hf_cache.$$"
      _hf_sum_tmp="$_hf_sumfile.$$"
      # Preserve the current generation before replacement. Update the backup pair
      # first; current cache remains untouched if backup creation is interrupted.
      if [ "$_hf_cache_ok" -eq 1 ] && _hf_pair_ok "$_hf_cache" "$_hf_sumfile"; then
        _hf_prev_tmp="$_hf_prev.$$"
        _hf_prev_sum_tmp="$_hf_prev_sum.$$"
        if cp -f "$_hf_cache" "$_hf_prev_tmp" 2>/dev/null &&
           cp -f "$_hf_sumfile" "$_hf_prev_sum_tmp" 2>/dev/null &&
           [ "$(_hf_sha256 "$_hf_prev_tmp")" = "$(cat "$_hf_prev_sum_tmp" 2>/dev/null | tr -d '[:space:]')" ] &&
           mv -f "$_hf_prev_tmp" "$_hf_prev" 2>/dev/null &&
           mv -f "$_hf_prev_sum_tmp" "$_hf_prev_sum" 2>/dev/null; then
          :
        else
          rm -f "$_hf_prev_tmp" "$_hf_prev_sum_tmp" 2>/dev/null
          _hf_hint=$(pg_url_hint "$_hf_url")
          pg_log "hosts: previous cache generation could not be refreshed for $_hf_hint"
        fi
      fi
      if cp -f "$_hf_dst" "$_hf_cache_tmp" 2>/dev/null &&
         printf '%s\n' "$_hf_newsum" > "$_hf_sum_tmp" 2>/dev/null &&
         [ "$(_hf_sha256 "$_hf_cache_tmp")" = "$_hf_newsum" ] &&
         mv -f "$_hf_cache_tmp" "$_hf_cache" 2>/dev/null &&
         mv -f "$_hf_sum_tmp" "$_hf_sumfile" 2>/dev/null; then
        date +%s > "$_hf_stamp" 2>/dev/null || :
        # A successful cache promotion changes an effective source. If host-file
        # replacement later fails, removing the old fingerprint forces a retry.
        rm -f "$PG/cache/hosts-config.cksum" 2>/dev/null || true
        _hf_unlock
        return 0
      fi
      rm -f "$_hf_cache_tmp" "$_hf_sum_tmp" 2>/dev/null
      _hf_rc=97
    fi
  fi
  if [ -f "$_hf_dst" ]; then
    _hf_lines=$(wc -l < "$_hf_dst" 2>/dev/null | tr -d ' ')
    case "$_hf_lines" in ''|*[!0-9]*) _hf_lines=0 ;; esac
    [ "$_hf_lines" -gt 0 ] && pg_log "hosts: incomplete download rejected (curl rc=$_hf_rc, $_hf_lines partial lines): $_hf_hint"
  fi
  # 下载失败：回退旧缓存（宁可旧数据也不让 hosts 整段失效）
  if [ "$_hf_cache_ok" -eq 1 ] && [ -s "$_hf_cache" ]; then
    if cp -f "$_hf_cache" "$_hf_dst" 2>/dev/null; then
      _hf_hint=$(pg_url_hint "$_hf_url")
      pg_log "hosts: fetch failed, using checksum-verified cached copy for $_hf_hint"
      : > "$_hf_cache_marker"
      _hf_unlock
      return 0
    fi
    _hf_hint=$(pg_url_hint "$_hf_url")
    pg_log "hosts: failed to copy verified cache to destination; rejecting partial output for $_hf_hint"
  fi
  # Never leave a partial network response at the destination on failure. Callers
  # may inspect the destination independently of the return code; an empty/missing
  # file is safer than accidentally treating a truncated list as a valid source.
  rm -f "$_hf_dst" 2>/dev/null || :
  _hf_unlock
  return 1
}

build_hosts() {
  pg_hosts_editor_seed_source || { pg_fail hosts "无法初始化系统 hosts 编辑源；拒绝重建并保留上一份 hosts"; return 1; }
  TMP="$PG/cache/hosts.tmp"
  : > "$TMP"
  # Build generated sidecars privately. Readers (VPN DNS/firewall) must never see
  # a partially written whitelist or IP list while subscriptions are being parsed.
  _hb_wlexc_stage="$PG/cache/wlexc.stage.$$"
  : > "$_hb_wlexc_stage" 2>/dev/null || { pg_fail hosts "无法创建白名单例外暂存文件；保留上一份规则"; return 1; }
  _hb_ip_stage="$PG/cache/subnet-ips.list.stage.$$"
  : > "$_hb_ip_stage" 2>/dev/null || { rm -f "$_hb_wlexc_stage"; pg_fail hosts "无法创建 IP 规则暂存文件；保留上一份规则"; return 1; }
  WL_EXC="$_hb_wlexc_stage"
  echo "# PrivacyGuard hosts (generated $(date '+%Y-%m-%d %H:%M:%S'))" >> "$TMP"
  # Include captured OEM baseline unless the editable source already contains it.
  if [ -s "$PG/cache/system-hosts.base" ] && [ ! -f "$PG/local/hosts.includes-system-base" ]; then
    echo "# --- 原始系统 hosts 基线（未合并下载订阅）---" >> "$TMP"
    cat "$PG/cache/system-hosts.base" >> "$TMP" || { pg_fail hosts "系统 hosts 基线读取失败"; return 1; }
  fi

  # ---- 订阅下载（并发）----
  # 每个 URL 一个后台任务写 <file>；父进程 wait 汇总。串行下载是 40s 的另一半根因。
  _hb_dir="$PG/cache/hostsdl.$$"
  mkdir -p "$_hb_dir" 2>/dev/null
  _hb_i=0
  _hb_list=""
  _hb_cosmetic_i=0
  _hb_cosmetic_list=""
  while IFS= read -r entry; do
    case "$entry" in http://*|https://*) ;; *) continue ;; esac
    # Web-layer filter sources (cosmetic selectors and context-aware ABP request
    # rules) are cached for MITM only. Never flatten them into hosts/IP-wide rules;
    # a failed fetch must not abort the hosts transaction or threaten connectivity.
    case "$entry" in
      *runningcheese/RunningCheese-Firefox/master/Restore/Adblock_Watermark.txt|*runningcheese/RunningCheese-Firefox/master/Restore/Adblock_Popup.txt|*NoAppDownload.txt|*cxfl-ublock.txt|*easylist_adult/*|*yokoffing/filterlists/main/adult_annoyance_list.txt|*DandelionSprout/adfilt/master/stayingonbrowser/*)
        _hb_cosmetic_i=$((_hb_cosmetic_i+1))
        echo "$entry" > "$_hb_dir/cu$_hb_cosmetic_i"
        ( hosts_fetch_cached "$entry" "$_hb_dir/cf$_hb_cosmetic_i"; echo "$?" > "$_hb_dir/crc$_hb_cosmetic_i" ) &
        _hb_cosmetic_list="$_hb_cosmetic_list $_hb_cosmetic_i"
        continue ;;
    esac
    _hb_i=$((_hb_i+1))
    echo "$entry" > "$_hb_dir/u$_hb_i"
    ( hosts_fetch_cached "$entry" "$_hb_dir/f$_hb_i"; echo "$?" > "$_hb_dir/rc$_hb_i" ) &
    _hb_list="$_hb_list $_hb_i"
  done <<__PGRULES__
$(pg_list_enabled rule)
__PGRULES__
  wait
  for _ci in $_hb_cosmetic_list; do
    _cu=$(cat "$_hb_dir/cu$_ci" 2>/dev/null)
    _crc=$(cat "$_hb_dir/crc$_ci" 2>/dev/null)
    if [ "$_crc" = "0" ] && [ -s "$_hb_dir/cf$_ci" ]; then
      _cn=$(wc -l < "$_hb_dir/cf$_ci" 2>/dev/null | tr -d ' ')
      _web_hint=$(pg_url_hint "$_cu")
      pg_log "web-filter: verified upstream cache ready $_web_hint ($_cn lines); request/cosmetic rules stay out of hosts/IP transaction"
    else
      _web_hint=$(pg_url_hint "$_cu")
      pg_log "web-filter: upstream fetch unavailable $_web_hint; keep bundled local rules and prior verified cache; hosts/IP transaction continues"
    fi
  done
  # ---- 解析（每个源一次 awk，仍是串行但每次单进程；总成本 ~0.3s/源）----
  # v1.10.7：把每个源的最终结果写进 substatus.db，供 WebUI「规则」页在条目下
  # 直接显示成功/失败与原因（用户反馈"规则里显示不出来下载的订阅报错"）。
  _ss_dir="$MODDIR/scripts/substatus.sh"
  _hb_sources_incomplete=0
  for _i in $_hb_list; do
    _entry=$(cat "$_hb_dir/u$_i" 2>/dev/null)
    _F="$_hb_dir/f$_i"
    _rc=$(cat "$_hb_dir/rc$_i" 2>/dev/null)
    _FIP="$_hb_dir/ip$_i"
    _cache_used=0
    [ -f "$_F.cache-used" ] && _cache_used=1
    if [ "$_rc" != "0" ] || [ ! -s "$_F" ]; then
      _hb_sources_incomplete=1
      # 区分具体原因。注意 curl 的 rc 语义有重叠：
      #   7 = 连接不上（端口拒绝/主机不可达）；6 = DNS 解析失败；
      #   28 = 超时；35 = TLS 握手；60 = 证书校验；22 = HTTP 错误码（如 404）
      #   rc=1 = 其它通用失败（curl 自身错误）
      # 单看 rc 分不清时，用 curl 的 stderr 尾巴补充判定（hosts_fetch_cached 会写
      # $PG/apply.log，这里再用轻量探测区分"域名解析"与"端口拒绝"）。
      _why=""
      case "$_rc" in
        6)  _why="DNS 解析失败（域名不存在或不可达）" ;;
        7)  _why="连接被拒绝/主机不可达" ;;
        28) _why="下载超时（网络慢或源被限速）" ;;
        35) _why="TLS 握手失败（源被重置或证书异常）" ;;
        56) _why="接收数据失败（连接被重置）" ;;
        60) _why="证书校验失败" ;;
        22) _why="HTTP 状态码异常（如 404/403）" ;;
      esac
      if [ -z "$_why" ]; then
        # rc=1 等通用码：用域名可解析性再细分，给用户可操作的提示
        _h=$(printf '%s' "$_entry" | sed -e 's#^[a-z]*://##' -e 's#[/:?#].*$##')
        if [ -n "$_h" ] && command -v ping >/dev/null 2>&1; then
          if ! ping -c 1 -W 2 "$_h" >/dev/null 2>&1; then
            case "$_h" in
              *[!0-9.]*) _why="DNS 解析失败或主机不可达（$_h）" ;;
              *) _why="主机不可达（$_h）" ;;
            esac
          fi
        fi
      fi
      [ -n "$_why" ] || _why="下载失败（curl rc=$_rc）"
      # 有旧缓存时说明"已回退缓存"，与彻底失败区分开
      _cached=""
      _ck=$(printf '%s' "$_entry" | cksum 2>/dev/null | awk '{print $1}')
      _cdir="$PG/cache/rulesrc"
      if [ -n "$_ck" ] && [ -s "$_cdir/$_ck.txt" ]; then
        _cached="，已用本地缓存 $(wc -l < "$_cdir/$_ck.txt" 2>/dev/null | tr -d ' ') 行"
      fi
      pg_fail fetch "订阅下载失败: $_entry — $_why$_cached"
      [ -f "$_ss_dir" ] && sh "$_ss_dir" record rule "$_entry" fail "$_why$_cached" "" 2>/dev/null
      continue
    fi
    _n_lines=$(wc -l < "$_F" 2>/dev/null | tr -d ' ')
    pg_log "hosts: source ready $entry ($_n_lines lines)"
    : > "$_FIP"
    # Subscription content is kept out of the local/system hosts text. The same source is
    # compiled by vpnrule.sh into the independent sing-box route layer; this parser is
    # retained only for IP-CIDR firewall staging and ADBLOCK whitelist exceptions.
    if ! hosts_parse_file "$_F" "$_FIP" "$WL_EXC" >/dev/null; then
      _hb_sources_incomplete=1
      pg_fail parse "规则源解析命令失败: $_entry"
      [ -f "$_ss_dir" ] && sh "$_ss_dir" record rule "$_entry" fail "下载成功，但解析命令失败；旧配置保留策略由应用事务决定" "下载源 $_n_lines 行" 2>/dev/null
      continue
    fi
    _parsed_ip_lines=$(wc -l < "$_FIP" 2>/dev/null | tr -d ' ')
    case "$_parsed_ip_lines" in ''|*[!0-9]*) _parsed_ip_lines=0 ;; esac
    if [ -s "$_FIP" ]; then
      cat "$_FIP" >> "$_hb_ip_stage" || _hb_sources_incomplete=1
    fi
    if [ "$_cache_used" = "1" ]; then
      [ -f "$_ss_dir" ] && sh "$_ss_dir" record rule "$_entry" cached "使用校验通过的本地缓存；本次未确认远端更新，规则仍需后续应用阶段验证" "缓存源 $_n_lines 行；解析出 $_parsed_ip_lines 条 IP-CIDR" 2>/dev/null
    else
      [ -f "$_ss_dir" ] && sh "$_ss_dir" record rule "$_entry" partial "下载与当前解析阶段完成；最终系统应用/实际拦截尚未确认" "源 $_n_lines 行；解析出 $_parsed_ip_lines 条 IP-CIDR" 2>/dev/null
    fi
  done
  if [ "$_hb_sources_incomplete" = 1 ]; then
    rm -rf "$_hb_dir" 2>/dev/null
    rm -f "$_hb_ip_stage" 2>/dev/null || true
    # The source set must be treated as one generation: losing even one
    # whitelist-exception/IP source can overblock or silently remove firewall
    # protection. Do not commit either output from a partial generation.
    rm -f "$PG/cache/hosts-config.cksum" 2>/dev/null || true
    pg_fail hosts "一个或多个订阅源没有可用的完整校验缓存或解析失败；为避免规则部分生效/误拦截，保留上一份 hosts 与 IP 规则。请修复源后执行完整刷新"
    return 1
  fi
  rm -rf "$_hb_dir" 2>/dev/null

  # ---- 手写规则（非 URL 的条目）原样写入 ----
  # v1.10.8: 分节标注来源。订阅下载的规则已在上面解析并入；这一段是「规则集里
  # 非 URL 的单条规则行」（老用法，保留兼容）。产物里加注释头，用户导出 hosts
  # 时能看出每段来自哪里。
  _hb_local_n=0
  {
    # 统计「非 URL 的手写规则行」条数。两个坑都要避开：
    #   ① 不能写 `grep -vc '^https\?://'` —— `-v` 统计的是**不匹配**的行（逻辑反向，
    #      URL 越多它越大，于是纯订阅配置也会打印孤儿注释头）；
    #   ② 不能用 BRE 的 `\?` —— 真机 toybox grep 不认（实测 `grep -v '^https\?://'`
    #      把 https/http 全留下）。必须用 `-E` 扩展正则。
    # 正确写法：先剔除 URL 行，再数剩余行数。
    _hb_any=$(pg_list_enabled rule | grep -vE '^https?://' | grep -vE '^builtin://' | grep -c . 2>/dev/null)
    case "$_hb_any" in ''|*[!0-9]*) _hb_any=0 ;; esac
    if [ "$_hb_any" -gt 0 ]; then
      echo "# --- 手写规则行（[list:rule] 中的非 URL 条目）---"
    fi
  } >> "$TMP" 2>/dev/null
  # v1.10.8: 内置规则集（builtin://<id>）——内容随模块打包在 rulefiles/<id>.txt，
  # 不联网、不走缓存；逐行原样并入 hosts（保留源文件里的 IP 映射，例如 10007 列表
  # 里把 mtalk.google.com 指向真实 Google IP 的条目，不能被改成 0.0.0.0）。
  pg_list_enabled rule | while IFS= read -r entry; do
    case "$entry" in
      http://*|https://*) : ;;
      builtin://*)
        _bn=${entry#builtin://}
        # IDs may already include .txt (legacy UI rows) or omit it (new rows).
        # Resolve the same safe filename used by fileedit.sh; never construct .txt.txt.
        case "$_bn" in *.txt) _bn_file="$_bn" ;; *) _bn_file="$_bn.txt" ;; esac
        # WebUI file editor user copy takes precedence over bundled immutable source.
        _bf="$PG/rulefiles-user/$_bn_file"
        [ -f "$_bf" ] || _bf="$MODDIR/rulefiles/$_bn_file"
        _ss2="$MODDIR/scripts/substatus.sh"
        if [ -r "$_bf" ]; then
          _bn_n=$(awk '!/^[[:space:]]*#/ && NF>=2 && $1 ~ /^[0-9A-Fa-f:.]+$/ && $2 ~ /^[A-Za-z0-9.-]+$/ {c++} END{print c+0}' "$_bf" 2>/dev/null)
          case "$_bn_n" in ''|*[!0-9]*) _bn_n=0 ;; esac
          if [ "$_bn_n" -gt 0 ]; then
            echo "# --- 内置规则集: $_bn（随模块打包，$_bn_n 条）---" >> "$TMP"
            awk '!/^[[:space:]]*#/ && NF>=2 && $1 ~ /^[0-9A-Fa-f:.]+$/ && $2 ~ /^[A-Za-z0-9.-]+$/ {print $1 " " tolower($2)}' "$_bf" >> "$TMP"
            pg_log "hosts: builtin ruleset $_bn merged ($_bn_n lines)"
            [ -f "$_ss2" ] && sh "$_ss2" record rule "$entry" ok "内置规则集，随模块打包" "$_bn_n 行" 2>/dev/null
          else
            echo "# --- 内置规则集: $_bn（该源无 DNS/hosts 层可表达条目，如装饰性过滤规则）---" >> "$TMP"
            [ -f "$_ss2" ] && sh "$_ss2" record rule "$entry" ok "内置规则集：源文件为装饰性规则，DNS 层无条目" "0 行" 2>/dev/null
          fi
        else
          pg_fail rule "内置规则集缺失: $_bn（重装模块可修复）"
          [ -f "$_ss2" ] && sh "$_ss2" record rule "$entry" fail "内置规则集缺失: rulefiles/$_bn.txt（重装模块可修复）" "" 2>/dev/null
        fi
        ;;
      *)
        _entry_type=$(printf '%s' "${entry%%,*}" | tr 'a-z' 'A-Z' | tr -d '[:space:]')
        case "$_entry_type" in
          DOMAIN|DOMAIN-SUFFIX|DOMAIN-KEYWORD|DOMAIN-REGEX|HOST|HOST-SUFFIX|IP-CIDR|IP-CIDR6|MIXED-IP-CIDR|PROCESS-NAME|PACKAGE-NAME|DST-PORT|SRC-PORT|PROTOCOL|NETWORK|RULE-SET|AND|OR|NOT|MATCH|FINAL)
            # These are route/compiler rules, not hosts-file lines. vpnrule.sh consumes
            # [list:rule]; copying them to /system/etc/hosts as raw comma-delimited text
            # made them look saved while producing no DNS behavior.
            : ;;
          *) echo "$entry" >> "$TMP" ;;
        esac ;;
    esac
  done

  # Legacy [list:hosts_local] entries are migrated once by pg_migrate_lists()
  # into the canonical $PG/local/hosts source. Do not merge the old list here:
  # doing so duplicates entries and makes the UI's file editor appear ineffective.

  # ---- 本地 hosts 文件（$PG/local/hosts，无扩展名）----
  # 独立于下载订阅；旧 hosts.local 在迁移时保留原件，只有新路径不存在时复制。
  mkdir -p "$PG/local" 2>/dev/null
  if [ ! -f "$PG/local/hosts" ] && [ -f "$PG/hosts.local" ]; then
    cp -p "$PG/hosts.local" "$PG/local/hosts" 2>/dev/null || pg_fail hosts "本地 hosts 迁移失败，继续保留旧文件"
  fi
  if [ -f "$PG/local/hosts" ]; then
    # Stream through a temporary file instead of capturing the entire transformed
    # hosts file in a shell variable; large local lists can exceed practical RAM.
    _hfl_tmp="$PG/cache/local-hosts.$$.tmp"
    if awk '
      { sub(/\r$/, "") }
      NR==1 { sub(/^\357\273\277/, "") }   # 去 UTF-8 BOM（老工具写出的文件可能带）
      /^[[:space:]]*#/ { next }
      /^[[:space:]]*$/ { next }
      {
        gsub(/[[:space:]]+/, " ")
        sub(/^ /, ""); sub(/ $/, "")
        if (NF >= 2 && $1 ~ /^[0-9.]+$/) { print $0; next }
        if (NF >= 2 && index($1, ":") > 0 && $1 ~ /^[0-9A-Fa-f:.]+$/) { print $0; next }
        if (NF == 1 && $1 ~ /^[0-9.]+$/) { next }
        if (NF == 1 && index($1, ":") > 0 && $1 ~ /^[0-9A-Fa-f:.]+$/) { next }
        _d = $1
        sub(/[\/:].*$/, "", _d)
        if (_d ~ /^[A-Za-z0-9.-]+$/) { print "0.0.0.0 " _d }
      }' "$PG/local/hosts" > "$_hfl_tmp" 2>/dev/null; then
      if [ -s "$_hfl_tmp" ]; then
        echo "# --- 本地 hosts 文件（local/hosts，无扩展名，用户手写，未经网络下载）---" >> "$TMP"
        cat "$_hfl_tmp" >> "$TMP" || pg_fail hosts "本地 hosts 流式合并写入失败"
        _hfl_count=$(wc -l < "$_hfl_tmp" | tr -d ' ')
        pg_log "hosts: merged $_hfl_count lines from local/hosts"
      fi
    else
      pg_fail hosts "本地 hosts 转换失败；本次跳过该文件，保留原文件"
    fi
    rm -f "$_hfl_tmp" 2>/dev/null || true
  fi

  # 追踪域名（conf 区，开关勾选才并入）
  if [ "$(pg_get block_track_domains 0)" = "1" ]; then
    pg_conf block_track_domains | grep -v '^#' | grep -v '^$' | while IFS= read -r d; do
      echo "0.0.0.0 $d"
    done >> "$TMP"
  fi
  if [ "$(pg_get geo_domains 0)" = "1" ]; then
    pg_conf geo_domains | grep -v '^#' | grep -v '^$' | while IFS= read -r d; do
      echo "0.0.0.0 $d"
    done >> "$TMP"
  fi

  # 隐私/遥测域名库（各开关对应的 [conf:*] 段，域名可由用户编辑）
  # waf_block 是已退役的旧分类开关；其中用户规则会迁移至 [list:block]，此处不再暗中执行。
  for sect in privacy_leak app_info app_list_upload usage_upload diag_upload isp_snoop net_privacy loc_leak; do
    if [ "$(pg_get $sect 0)" = "1" ]; then
      pg_conf "$sect" | grep -v '^#' | grep -v '^$' | while IFS= read -r d; do
        case "$d" in
          */*) : ;;                                # 网段/非法行跳过
          *.*) echo "0.0.0.0 $d" ;;
        esac
      done >> "$TMP"
      pg_log "hosts: merged [$sect] domain blocklist"
    fi
  done

  # FX 规则消费（DOMAIN/DOMAIN-SUFFIX → hosts；IP-CIDR 由防火墙段处理）
  # v1.10.8 性能：内置 FX 可能上万条（反诈域名库 2.1 万），原逐行 shell 循环每行 fork
  # sed/cut/echo 十余次，实机会卡到分钟级；改为一条 sed（展开字面 \n）+ 一条 awk（整表解析）。
  if [ "$(pg_get fx 0)" = "1" ]; then
    _fxraw="$PG/cache/fx.rules.$$"
    # Keep expansion output on disk so diagnostics can distinguish a valid IP/keyword-only
    # ruleset from an enabled source that produced no parseable rules. Do not report success
    # merely because the pipeline's final command returned zero.
    if pg_fx_expand > "$_fxraw" 2>>"$PG/apply.log"; then
      sed 's/\\n/\n/g' "$_fxraw" > "$_fxraw.norm" 2>>"$PG/apply.log" || : > "$_fxraw.norm"
      mv -f "$_fxraw.norm" "$_fxraw" 2>/dev/null || :
    else
      : > "$_fxraw"
      pg_fail fx "FX 规则展开命令失败；本次未将该规则源计为成功"
    fi
    _fx_counts=$(awk -F',' '
      $1=="DOMAIN" {e++}
      $1=="DOMAIN-SUFFIX" {s++}
      $1=="DOMAIN-KEYWORD" {k++}
      $1=="IP-CIDR" || $1=="IP-CIDR6" {i++}
      $1=="PACKAGE-NAME" {p++}
      $1=="PROCESS-NAME" {pr++}
      END {d=e+s; total=d+k+i+p+pr; printf "%d %d %d %d %d %d %d %d", d+0, e+0, s+0, k+0, i+0, p+0, pr+0, total+0}
    ' "$_fxraw" 2>/dev/null)
    set -- $_fx_counts
    _fx_domain_n=${1:-0}; _fx_exact_n=${2:-0}; _fx_suffix_n=${3:-0}; _fx_keyword_n=${4:-0}; _fx_ip_n=${5:-0}; _fx_package_n=${6:-0}; _fx_process_n=${7:-0}; _fx_total_n=${8:-0}
    case "$_fx_total_n" in ''|*[!0-9]*) _fx_total_n=0 ;; esac
    # Only compile syntactically valid DNS names into hosts. Route rules can contain
    # malformed values, CIDRs, regexes, or placeholders; accepting those here can
    # poison the system hosts file even when the VPN compiler correctly rejects them.
    awk -F',' '
      function valid_domain(d,n,a,i) {
        if (length(d)<1 || length(d)>253 || d !~ /^[A-Za-z0-9.-]+$/ || d ~ /[.][.]|^[.]|[.]$/) return 0
        n=split(d,a,".")
        for(i=1;i<=n;i++) if(length(a[i])<1 || length(a[i])>63 || a[i] !~ /^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$/) return 0
        return 1
      }
      ($1=="DOMAIN"||$1=="DOMAIN-SUFFIX") && (toupper($3)==""||toupper($3)=="REJECT"||toupper($3)=="BLOCK"||toupper($3)=="DROP"||toupper($3)=="DENY"||toupper($3)=="REJECT-DROP") {
        v=tolower($2); if(valid_domain(v) && !seen[v]++) print "0.0.0.0 " v
      }
    ' "$_fxraw" >> "$TMP" || pg_fail fx "FX 域名规则写入临时 hosts 失败"
    if [ "$_fx_total_n" -gt 0 ]; then
      pg_log "fx: normalized rules total=$_fx_total_n exact_domains=$_fx_exact_n suffix_domains=$_fx_suffix_n keywords_route_only=$_fx_keyword_n ip_cidrs=$_fx_ip_n package_rules=$_fx_package_n process_rules_route_only=$_fx_process_n"
      if [ "$(pg_get vpn_mode direct)" = "direct" ]; then
        [ "$_fx_suffix_n" -eq 0 ] || pg_log "fx: DIRECT hosts mode maps suffix roots and explicitly listed hostnames only; wildcard descendant matching requires the VPN route engine"
        [ "$_fx_keyword_n" -eq 0 ] || pg_log "fx: DIRECT hosts mode cannot enforce DOMAIN-KEYWORD rules; these require hostname-aware VPN routing"
      fi
      [ "$_fx_process_n" -eq 0 ] || pg_log "fx: PROCESS-NAME rules are parsed but are not reliable under the current REDIRECT ingress (process lookup cannot reliably match the original destination); do not count them as enforced"
    elif [ -n "$(pg_list_enabled fx 2>/dev/null)" ]; then
      pg_fail fx "FX 开关已启用，但已配置规则源未产生可识别的 DOMAIN/DOMAIN-SUFFIX/DOMAIN-KEYWORD/IP-CIDR/PACKAGE-NAME/PROCESS-NAME 规则；请检查源格式、下载与缓存"
    else
      pg_log "fx: enabled but no FX sources configured; no rules consumed"
    fi
    rm -f "$_fxraw" "$_fxraw.norm"
  fi

  # 黑名单规则：每条 [list:block] 记录自身的 on/off 就是唯一开关。
  # 识别纯域名、HOSTS 映射、DOMAIN/DOMAIN-SUFFIX 拒绝规则；未知高级语法安全跳过。
  pg_list_enabled block | while IFS= read -r b; do
    _btype=$(printf '%s\n' "$b" | cut -d',' -f1 | tr '[:lower:]' '[:upper:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$_btype" in
      DOMAIN|DOMAIN-SUFFIX)
        _bd=$(printf '%s\n' "$b" | awk -F',' '{a=toupper($1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", a); act=toupper($3); gsub(/^[[:space:]]+|[[:space:]]+$/, "", act); d=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", d); if((a=="DOMAIN" || a=="DOMAIN-SUFFIX") && (act==""||act=="REJECT"||act=="REJECT-DROP"||act=="BLOCK"||act=="DROP"||act=="DENY")) print tolower(d)}')
        case "$_bd" in *.*) ;; *) continue ;; esac
        case "$_bd" in *[!a-z0-9.-]*|*.|.*|*..*|-*|*.-*|*-.*) continue ;; esac
        echo "0.0.0.0 $_bd"
        continue
        ;;
      IP-CIDR,*|IP-CIDR6,*|MIXED-IP-CIDR,*) continue ;;
      0.0.0.0\ *|127.0.0.1\ *|::1\ *) echo "$b"; continue ;;
    esac
    case "$b" in *.*) ;; *) continue ;; esac
    case "$b" in
      [0-9]*.[0-9]*.[0-9]*.[0-9]*|*/*|*:*|*[!A-Za-z0-9.-]*|*.|.*|*..*) continue ;;
    esac
    echo "0.0.0.0 $b"
  done >> "$TMP"
  pg_log "ad-filter: consuming individually enabled [list:block] entries"

  # 白名单剔除（域名边界匹配：google.com 放行自身与子域，不误放 evilgoogle.com；
  # localhost / *.local 等单段名同样生效；ADBLOCK @@|| 例外一并并入）
  # 性能：原实现每个域名 fork 2 次（echo|sed、echo|sed），实测这段 1.1s。
  # 改成「一次 awk 归一 + 一次 awk 生成正则」——与之前的 hosts 解析同一思路。
  WL=$(mktemp "$PG/cache/wl.XXXXXX" 2>/dev/null) || WL="$PG/cache/wl.$$.list"
  _wl_norm() { sed 's/^\*\.//; s/[[:space:]]*$//'; }
  {
    # 用户白名单
    pg_list_enabled domain
    # ADBLOCK 例外（@@||domain^ 已由 hosts_parse_file 收集到 $WL_EXC）
    [ -s "$WL_EXC" ] && sed 's/^@@||//; s/\^.*//' "$WL_EXC"
    # 系统联网检测/门户探测域名保护（hosts_keep=1，默认开）
    if [ "$(pg_get hosts_keep 1)" = "1" ]; then
      printf '%s\n' connectivitycheck.gstatic.com connectivitycheck.platform.hicloud.com \
        connect.rom.miui.com www.msftconnecttest.com msftconnecttest.com \
        msftncsi.com captive.apple.com time.android.com time.windows.com
      pg_conf hosts_keep 2>/dev/null | grep -v '^#' | grep -v '^$'
    fi
  } | sed 's/^\*\.//; s/[[:space:]]*$//' | awk -v out="$WL" '
      function valid_domain(d, n, labels, i) {
        if (length(d) < 1 || length(d) > 253 || d !~ /^[A-Za-z0-9.-]+$/ || d ~ /[.][.]|^[.]|[.]$/) return 0
        n = split(d, labels, ".")
        for (i=1; i<=n; i++) {
          if (length(labels[i]) < 1 || length(labels[i]) > 63) return 0
          if (tolower(labels[i]) !~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/) return 0
        }
        return 1
      }
      # Strict label validation prevents malformed or ambiguous whitelist entries.
      # Generate each normalized suffix only once; keep matching boundary-aware.
      valid_domain($0) {
        d = tolower($0)
        if (seen[d]++) next
        gsub(/\./, "\\.", d)
        print "(^|[.[:space:]])" d "$" > out
      }
    ' 2>/dev/null || true
  if [ -s "$WL" ]; then
    # grep 无任何选中行时退出码为 1（属正常：全部命中白名单），
    # 原写法 `grep && mv` 会让白名单整体失效，残留本应剔除的条目。
    grep -Eiv -f "$WL" "$TMP" > "$TMP.2" 2>>"$PG/apply.log"
    case $? in
      0|1) mv -f "$TMP.2" "$TMP" ;;
      *)   rm -f "$TMP.2" ;;
    esac
  fi
  rm -f "$WL"

  # 基础映射在白名单之后追加，确保 localhost 永不被白名单条目误剔
  echo "127.0.0.1 localhost" >> "$TMP"
  echo "::1 ip6-localhost" >> "$TMP"

  # 去重：**不能用 sort -u** —— 它会把 `# --- ... ---` 分节注释按字典序全部抽到文件
  # 顶部（真机实测：三个段标题挤在 1-3 行，32 个域名全挤在下面，出处信息彻底失效），
  # 且会跨段去重把本地段里重复的条目"吞"掉。
  # 改用 awk 一次遍历：注释/空行原样保留在各自位置，仅对 hosts 行做全局去重
  # （保留首次出现，即"订阅在前、本地在后"时订阅优先，符合原有语义）。
  # 单进程，102k 行实测与 sort 同量级（~0.3s）。
  # 大规则集必须流式处理：禁止用命令替换把完整 hosts 文件装进 shell 变量，
  # 否则数十万行会同时占用内存并可能触发 OOM/截断。
  _hs_dedup_tmp="$PG/cache/hosts.dedup.$$"
  if awk '
    { line = $0 }
    line ~ /^[[:space:]]*#/ || line ~ /^[[:space:]]*$/ { print line; next }
    { if (seen[line]++) next; print line }
  ' "$TMP" > "$_hs_dedup_tmp" 2>>"$PG/apply.log"; then
    _hs_lines=$(wc -l < "$_hs_dedup_tmp" 2>/dev/null | tr -d ' ')
    _hs_bytes=$(wc -c < "$_hs_dedup_tmp" 2>/dev/null | tr -d ' ')
    case "$_hs_lines" in ''|*[!0-9]*) _hs_lines=0 ;; esac
    case "$_hs_bytes" in ''|*[!0-9]*) _hs_bytes=0 ;; esac
    # Safety ceiling protects Android hosts consumers and storage from accidental
    # megafeeds. Never truncate: reject the candidate and retain the previous file.
    if [ "$_hs_lines" -gt 300000 ] || [ "$_hs_bytes" -gt 50331648 ]; then
      rm -f "$_hs_dedup_tmp" "$TMP.2" "$_hb_ip_stage" 2>/dev/null
      pg_fail hosts "规则集合超出安全上限（${_hs_lines} 行/${_hs_bytes} 字节；上限 300000 行/50331648 字节），拒绝替换以避免静默截断；保留上一份 hosts"
      return 1
    fi
    if mv -f "$_hs_dedup_tmp" "$TMP"; then
      pg_log "hosts: streaming dedup complete lines=$_hs_lines bytes=$_hs_bytes"
    else
      rm -f "$_hs_dedup_tmp" "$_hb_ip_stage" 2>/dev/null
      pg_fail hosts "hosts 流式去重结果无法提交；保留未替换文件"
      return 1
    fi
  else
    rm -f "$_hs_dedup_tmp" "$_hb_ip_stage" 2>/dev/null
    pg_fail hosts "hosts 流式去重失败(可能空间不足?)；拒绝替换以保留上一份 hosts"
    return 1
  fi
  # Commit with a same-filesystem recovery inode. If the candidate fails validation
  # after the rename/write, util.sh restores the previous file before returning.
  if ! pg_commit_hosts_candidate "$TMP"; then
    rm -f "$_hb_ip_stage" 2>/dev/null || true
    return 1
  fi
  if [ "$_hb_sources_incomplete" = 0 ]; then
    # Preserve the previous IP list before publishing either sidecar. If the
    # second publish fails, restore the IP list so the two generated caches do
    # not knowingly represent different successful apply generations.
    _hb_ip_backup="$PG/cache/subnet-ips.list.rollback.$$"
    _hb_had_ip=0
    if [ -e "$PG/cache/subnet-ips.list" ]; then
      cp -p "$PG/cache/subnet-ips.list" "$_hb_ip_backup" 2>>"$PG/apply.log" || {
        rm -f "$_hb_ip_stage" "$_hb_wlexc_stage" "$_hb_ip_backup" 2>/dev/null || true
        pg_fail ip_block "无法备份现有 IP 规则列表；拒绝提交新缓存"
        return 1
      }
      _hb_had_ip=1
    fi
    # Keep the previous whitelist generation too: if the process dies after the
    # IP rename but before whitelist publication, startup recovery can restore both.
    _hb_wlexc_backup="$PG/cache/wlexc.rollback.$$"
    _hb_had_wlexc=0
    if [ -e "$PG/cache/wlexc.tmp" ]; then
      cp -p "$PG/cache/wlexc.tmp" "$_hb_wlexc_backup" 2>>"$PG/apply.log" || {
        rm -f "$_hb_ip_stage" "$_hb_wlexc_stage" "$_hb_ip_backup" "$_hb_wlexc_backup" 2>/dev/null || true
        pg_fail hosts "无法备份现有白名单例外列表；拒绝提交新缓存"
        return 1
      }
      _hb_had_wlexc=1
    fi
    # Durable transaction marker is written before publishing either sidecar.
    _hb_txn="$PG/cache/sidecar.txn.$$"
    if ! {
      printf 'pid=%s\n' "$$"
      printf 'had_ip=%s\n' "$_hb_had_ip"
      printf 'had_wlexc=%s\n' "$_hb_had_wlexc"
      printf 'ip_backup=%s\n' "$_hb_ip_backup"
      printf 'wlexc_backup=%s\n' "$_hb_wlexc_backup"
      printf 'phase=active\n'
    } > "$_hb_txn" || ! mv -f "$_hb_txn" "$PG/cache/sidecar.txn"; then
      rm -f "$_hb_ip_stage" "$_hb_wlexc_stage" "$_hb_ip_backup" "$_hb_wlexc_backup" "$_hb_txn" 2>/dev/null || true
      pg_fail hosts "无法创建缓存事务标记；拒绝提交新规则"
      return 1
    fi
    if ! mv -f "$_hb_ip_stage" "$PG/cache/subnet-ips.list" 2>>"$PG/apply.log"; then
      rm -f "$_hb_ip_stage" "$_hb_wlexc_stage" "$_hb_ip_backup" "$_hb_wlexc_backup" "$PG/cache/sidecar.txn" 2>/dev/null || true
      pg_fail ip_block "IP 规则暂存提交失败；保留上一份 IP-CIDR 列表"
      return 1
    fi
    # Publish whitelist exceptions last: VPN DNS sees the new exceptions only
    # after the matching IP sidecar has committed successfully.
    if ! mv -f "$_hb_wlexc_stage" "$PG/cache/wlexc.tmp" 2>>"$PG/apply.log"; then
      _hb_rollback_ok=1
      if [ "$_hb_had_ip" = 1 ]; then
        _hb_ip_rollback_tmp="$PG/cache/subnet-ips.list.rollback-restore.$$"
        if ! cp -p "$_hb_ip_backup" "$_hb_ip_rollback_tmp" 2>>"$PG/apply.log" ||
           ! mv -f "$_hb_ip_rollback_tmp" "$PG/cache/subnet-ips.list" 2>>"$PG/apply.log"; then
          rm -f "$_hb_ip_rollback_tmp" 2>/dev/null || true
          _hb_rollback_ok=0
          pg_log "CRITICAL: failed to restore subnet-ips.list; recovery copy preserved at $_hb_ip_backup"
        fi
      else
        rm -f "$PG/cache/subnet-ips.list" 2>/dev/null || _hb_rollback_ok=0
      fi
      if [ "$_hb_had_wlexc" = 1 ]; then
        _hb_wlexc_rollback_tmp="$PG/cache/wlexc.rollback-restore.$$"
        if ! cp -p "$_hb_wlexc_backup" "$_hb_wlexc_rollback_tmp" 2>>"$PG/apply.log" ||
           ! mv -f "$_hb_wlexc_rollback_tmp" "$PG/cache/wlexc.tmp" 2>>"$PG/apply.log"; then
          rm -f "$_hb_wlexc_rollback_tmp" 2>/dev/null || true
          _hb_rollback_ok=0
          pg_log "CRITICAL: failed to restore wlexc.tmp; recovery copy preserved at $_hb_wlexc_backup"
        fi
      else
        rm -f "$PG/cache/wlexc.tmp" 2>/dev/null || _hb_rollback_ok=0
      fi
      rm -f "$_hb_ip_stage" "$_hb_wlexc_stage" 2>/dev/null || true
      # Never delete recovery copies or transaction marker if rollback fails.
      if [ "$_hb_rollback_ok" = 1 ]; then
        rm -f "$_hb_ip_backup" "$_hb_wlexc_backup" "$PG/cache/sidecar.txn" 2>/dev/null || true
      else
        pg_log "CRITICAL: sidecar rollback incomplete; transaction marker and recovery copies preserved"
      fi
      pg_fail hosts "白名单例外列表提交失败；缓存回滚状态=$_hb_rollback_ok"
      return 1
    fi
    # Persist the commit decision before deleting backups. If this fails, leave the
    # active marker and both recovery copies; the next apply will roll back safely.
    _hb_commit_marker="$PG/cache/sidecar.txn.commit.$$"
    if ! {
      printf 'pid=%s\n' "$$"
      printf 'had_ip=%s\n' "$_hb_had_ip"
      printf 'had_wlexc=%s\n' "$_hb_had_wlexc"
      printf 'ip_backup=%s\n' "$_hb_ip_backup"
      printf 'wlexc_backup=%s\n' "$_hb_wlexc_backup"
      printf 'phase=committed\n'
    } > "$_hb_commit_marker" || ! mv -f "$_hb_commit_marker" "$PG/cache/sidecar.txn"; then
      rm -f "$_hb_commit_marker" 2>/dev/null || true
      pg_fail hosts "新缓存已发布但提交标记写入失败；保留旧缓存备份，等待下次恢复"
      return 1
    fi
    if rm -f "$_hb_ip_backup" "$_hb_wlexc_backup" 2>/dev/null && rm -f "$PG/cache/sidecar.txn" 2>/dev/null; then
      pg_log "hosts: IP and whitelist exception caches committed"
    else
      pg_log "hosts: caches committed; cleanup incomplete, committed marker retained for next apply"
    fi
  else
    # Keep the previous complete IP rule set. Committing a partial list would
    # silently remove rules from sources that failed to download/parse.
    rm -f "$_hb_ip_stage" "$_hb_wlexc_stage" 2>/dev/null || true
    pg_log "hosts: one or more sources failed; preserved previous complete subnet-ips.list and wlexc.tmp"
  fi
}

# Compute a fingerprint from every local file source that can affect the generated
# hosts output, not just settings.conf. The paged editor writes PG/local/hosts, while
# user-edited builtin/FX rule files live in their own directories; a config-only hash
# previously let fast apply report success while silently reusing stale system hosts.
pg_hosts_input_signature() {
  _his_tmp="$PG/cache/hosts-input-signature.$$"
  : > "$_his_tmp" 2>/dev/null || return 1
  printf 'settings.conf\n' >> "$_his_tmp" || { rm -f "$_his_tmp"; return 1; }
  cksum "$CONF" >> "$_his_tmp" 2>/dev/null || { rm -f "$_his_tmp"; return 1; }
  for _his_f in \
    "$PG/local/hosts" "$PG/local/hosts.includes-system-base" "$PG/hosts.local" "$PG/cache/system-hosts.base" \
    "$PG"/rulefiles-user/*.txt "$PG"/fxrules-user/*.txt \
    "$MODDIR"/rulefiles/*.txt "$MODDIR"/fxrules/*.txt; do
    [ -f "$_his_f" ] || continue
    printf 'source=%s\n' "$_his_f" >> "$_his_tmp" || { rm -f "$_his_tmp"; return 1; }
    cksum "$_his_f" >> "$_his_tmp" 2>/dev/null || { rm -f "$_his_tmp"; return 1; }
  done
  _his_sig=$(cksum "$_his_tmp" 2>/dev/null | awk 'NR==1 {print $1 ":" $2}')
  rm -f "$_his_tmp" 2>/dev/null || true
  [ -n "$_his_sig" ] || return 1
  printf '%s\n' "$_his_sig"
}

# Capture and initialize the editable system hosts source before deciding whether
# its contents represent user changes. An unchanged OEM baseline alone must not switch
# on the full hosts blocker; editing or clearing that source is an explicit change.
pg_capture_system_hosts_base 2>/dev/null || true
pg_hosts_editor_seed_source 2>/dev/null || pg_log "hosts: editable system source initialization is pending"
# Auto-select the general hosts build whenever an enabled rule source or a user-owned
# hosts/block row exists. The retired hosts_block UI toggle is not required to activate
# a rule; each row's own enabled state controls whether it is consumed.
_hosts_block_on=$(pg_get hosts_block 0)
_fx_master_on=$(pg_get fx 0)
if [ "$_hosts_block_on" != "1" ]; then
  _auto_hosts_rules=0
  for _asect in rule block hosts_local; do
    if [ -n "$(pg_list_enabled "$_asect" 2>/dev/null | head -n 1)" ]; then _auto_hosts_rules=1; break; fi
  done
  if [ "$_auto_hosts_rules" != "1" ] && [ -f "$PG/local/hosts.includes-system-base" ] && [ -f "$PG/local/hosts" ]; then
    _auto_hosts_seed_sig=$(sed -n 's/^1://p' "$PG/local/hosts.includes-system-base" 2>/dev/null | head -n 1)
    _auto_hosts_current_sig=$(cksum "$PG/local/hosts" 2>/dev/null | awk 'NR==1 {print $1 ":" $2}')
    if [ -z "$_auto_hosts_seed_sig" ] || [ "$_auto_hosts_seed_sig" != "$_auto_hosts_current_sig" ]; then _auto_hosts_rules=1; fi
  elif [ "$_auto_hosts_rules" != "1" ] && [ -s "$PG/local/hosts" ] && grep -qEv '^[[:space:]]*(#|$)' "$PG/local/hosts" 2>/dev/null; then
    _auto_hosts_rules=1
  fi
  if [ "$_auto_hosts_rules" != "1" ]; then
    for _asect in block_track_domains geo_domains privacy_leak app_info app_list_upload usage_upload diag_upload isp_snoop net_privacy loc_leak; do
      if [ "$(pg_get "$_asect" 0)" = "1" ] && pg_conf "$_asect" 2>/dev/null | grep -v '^[[:space:]]*#' | grep -qE '[A-Za-z0-9-]+\.[A-Za-z0-9-]+'; then _auto_hosts_rules=1; break; fi
    done
  fi
  [ "$_auto_hosts_rules" = "1" ] && _hosts_block_on=1
fi
if [ "$_hosts_block_on" = "1" ] || [ "$_fx_master_on" = "1" ]; then
  # Capture the OEM baseline before the first bind overlay. This lets us switch back
  # to an FX-only hosts overlay without retaining unrelated block/telemetry lists.
  pg_capture_system_hosts_base 2>/dev/null || true
  # Initialize/migrate the editable system-hosts source before fingerprinting or
  # building. The source contains only OEM baseline + manual edits, never subscriptions.
  pg_hosts_editor_seed_source 2>/dev/null || pg_log "hosts: editable baseline source initialization failed; preserve existing generated hosts"
  # Fast mode may reuse generated hosts only when both settings and every local rule
  # source still match the last successful build. Remote subscriptions refresh only
  # in full mode; a successful build stores the resulting fingerprint.
  _hosts_sig=$(pg_hosts_input_signature 2>/dev/null)
  _hosts_sig_file="$PG/cache/hosts-config.cksum"
  _hosts_sig_old=$(cat "$_hosts_sig_file" 2>/dev/null)
  if [ "$APPLY_FAST" = "1" ] && [ -s "$PG/hosts" ] && [ -n "$_hosts_sig" ] && [ "$_hosts_sig" = "$_hosts_sig_old" ]; then
    pg_log "hosts: fast mode — 配置指纹未变化，复用既有 hosts ($(wc -l < "$PG/hosts") lines)"
  else
    if [ "$APPLY_FAST" = "1" ] && [ -s "$PG/hosts" ]; then
      pg_log "hosts: fast cache invalidated (effective hosts input fingerprint changed or unavailable); rebuilding from current rule sources"
    fi
    if [ "$_hosts_block_on" = "1" ]; then
      _hosts_build_cmd=build_hosts
    else
      _hosts_build_cmd=pg_build_fx_hosts
    fi
    if "$_hosts_build_cmd" && [ -s "$PG/hosts" ] && [ -n "$_hosts_sig" ]; then
      _hosts_sig_tmp="$_hosts_sig_file.$$"
      if printf '%s\n' "$_hosts_sig" > "$_hosts_sig_tmp" && mv -f "$_hosts_sig_tmp" "$_hosts_sig_file"; then
        _hosts_mode_tmp="$PG/cache/hosts-mode.$$"
        if [ "$_hosts_build_cmd" = "pg_build_fx_hosts" ]; then _hosts_mode=fx-only; else _hosts_mode=full; fi
        if printf '%s\n' "$_hosts_mode" > "$_hosts_mode_tmp" && mv -f "$_hosts_mode_tmp" "$PG/cache/hosts-mode"; then
          pg_log "hosts: saved successful configuration and local-source fingerprint (mode=$_hosts_build_cmd)"
        else
          rm -f "$_hosts_mode_tmp" 2>/dev/null || true
          rm -f "$PG/cache/hosts-mode" 2>/dev/null || true
          pg_log "hosts: warning — cannot save mode marker; early boot will skip mounting stale hosts"
        fi
      else
        rm -f "$_hosts_sig_tmp" 2>/dev/null
        pg_log "hosts: warning — could not save configuration fingerprint; next fast apply will rebuild"
      fi
    else
      pg_log "hosts: rebuild failed or configuration fingerprint unavailable; cache will not be trusted"
    fi
  fi
  if [ -f "$PG/hosts" ]; then
    # Distinguish our bind from a foreign module's mount. Never stack over an unknown source.
    _hosts_mount_state=$(pg_hosts_mount_state 2>/dev/null)
    case "$_hosts_mount_state" in
      owned) : ;; # Already mounted from the current module; idempotent.
      foreign)
        pg_fail hosts "/system/etc/hosts 已由其他模块挂载；为避免破坏共存，FX hosts 本次未挂载"
        ;;
      *)
        if mount --bind "$PG/hosts" /system/etc/hosts 2>>"$PG/apply.log" || \
           mount -o bind "$PG/hosts" /system/etc/hosts 2>>"$PG/apply.log"; then
          _hosts_mount_after=$(pg_hosts_mount_state 2>/dev/null)
          if [ "$_hosts_mount_after" != owned ]; then
            pg_fail hosts "mount 命令返回成功但无法确认本模块拥有 /system/etc/hosts 挂载；状态未知，不继续叠加挂载"
          fi
        else
          pg_fail hosts "bind mount /system/etc/hosts 失败(挂载点只读或 SELinux 拒绝)，稍后由 post-fs-data 重试"
        fi
        ;;
    esac
  else
    pg_fail hosts "hosts 文件未生成，跳过挂载"
  fi
else
  # Only release our own bind mount. A different module may own this target.
  _hosts_mount_state=$(pg_hosts_mount_state 2>/dev/null)
  case "$_hosts_mount_state" in
    owned)
      if umount /system/etc/hosts 2>/dev/null; then
        [ "$(pg_hosts_mount_state 2>/dev/null)" = owned ] && pg_fail hosts "已关闭 hosts/FX，但本模块 bind mount 仍存在；保留源文件并等待重试"
      else
        pg_fail hosts "已关闭 hosts/FX，但无法卸载本模块 bind mount；保留源文件并等待重试"
      fi
      ;;
    foreign) pg_log "hosts: disabled; foreign /system/etc/hosts mount preserved" ;;
    *) : ;;
  esac
  rm -f "$PG/cache/hosts-mode" "$PG/cache/hosts-config.cksum" 2>/dev/null || true
  pg_log "hosts: disabled (hosts_block=0 and fx=0)"
fi

# ---------- 2. 防火墙（iptables PGUARD 链）----------
# -w 5 自适应：部分非 GKI 老内核未移植 xt_waitlock，不认 -w（整条防火墙会静默失效）。
# 启动时探测一次：-w 可用则带锁运行（防并发），不可用则去掉 -w 降级运行。
FWWAIT=""
if iptables -w 5 -L >/dev/null 2>&1; then
  FWWAIT="-w 5"
fi
[ -z "$FWWAIT" ] && pg_log "fw: iptables -w unsupported on this kernel, running without lock (non-GKI legacy?)"
# fw4/fw6 的实际定义在下面「批量写规则」段（带缓冲）；这里不再定义，否则会被后者覆盖前
# 造成「定义的顺序看起来没事、实际用的是无缓冲版本」的隐蔽回归。

# ---------- 批量写规则（性能核心，真机实测）----------
# 逐条 `iptables -A` 每次都是一个独立进程（fork+exec+netlink 往返），真机实测单条约
# 8-20ms。全量 apply 有 150+ 条规则 → 2-3s 纯进程开销（profile: fw 段 3.1s、
# direct 清理段 3.0s）。`iptables-restore` 能把整张表的规则一次提交（1 次进程），
# 本脚本的 chnroute 段早已在用且真机验证可用。
#
# 实现策略：不改 150 处调用点，而是让 fw4/fw6 **自己**把 -A/-I 追加进队列文件，
# 由 fw_flush 一次性提交；-N/-F/-X/-D 这类结构性操作立即执行（必须保证链先存在）。
# 队列按「版本:表」分开，避免混表提交报错。
IPT_BATCH=0
pg_have iptables-restore && IPT_BATCH=1
# 一次 apply 生命周期内只要有任何队列写入失败，就禁止提交不完整的规则集。
_IPTQ_WRITE_FAIL=0
_IPTQ_D="$PG/cache/iptq.$$"
mkdir -p "$_IPTQ_D" 2>/dev/null

# 缓冲一条规则：fwbuf <4|6> <table> <规则词...>
# 注意：不要写 `printf -- '%s\n' "$*"`——Android 的 mksh printf 不认 `--` 作为
# 选项终止符，会把字面量 `--` 连同样式一起输出，queue 文件里就变成一行 "-- "，
# iptables-restore 解析该行时报 unknown option，整批规则被丢弃（真机实测：
# 表现为 PGVPN 链只有 -N 没规则、PGKS 空、而日志里一切"正常"）。
fwbuf() {
  _b_v="$1"; _b_t="$2"; shift 2
  if ! printf '%s\n' "$*" >> "$_IPTQ_D/${_b_v}_${_b_t}" 2>/dev/null; then
    _IPTQ_WRITE_FAIL=1
    pg_log "fw: queue write failed (${_b_v}/${_b_t}); refusing incomplete rule commit"
    return 1
  fi
  return 0
}

# 解析 fw4/fw6 的参数：仅缓冲 -A 追加规则。
# -I 必须立即执行：OUTPUT 链挂接和优先级插入不能留在队列里等待后续 flush。
# 用全局 _FW_TBL 返回表名，全局 _FW_ARGS 返回「去掉 -t <table> 后」的规则词
# （iptables-restore 的规则行不接受 -t，表由 *table 行指定）。
# 返回 0=应缓冲，1=应立即执行。
fw_should_buffer() {
  _FW_TBL=filter
  _FW_ARGS=""
  _fw_op=0; _fw_prev=""; _fw_skip=0
  for _fw_a in "$@"; do
    if [ "$_fw_skip" = "1" ]; then _fw_skip=0; continue; fi
    if [ "$_fw_prev" = "-t" ]; then
      _FW_TBL="$_fw_a"; _fw_prev=""; continue
    fi
    case "$_fw_a" in
      -t) _fw_prev="$_fw_a"; continue ;;
      -A) _fw_op=1 ;;
    esac
    _FW_ARGS="$_FW_ARGS $_fw_a"
  done
  [ "$_fw_op" = "1" ]
}

fw4() {
  if [ "$IPT_BATCH" = "1" ] && fw_should_buffer "$@"; then
    # Propagate queue-write failure immediately; callers use this status to
    # decide whether a protection chain is safe to activate.
    fwbuf 4 "$_FW_TBL" $_FW_ARGS
    return $?
  fi
  iptables  $FWWAIT "$@" 2>>"$PG/apply.log"
}
fw6() {
  if [ "$IPT_BATCH" = "1" ] && fw_should_buffer "$@"; then
    # Propagate queue-write failure immediately; callers use this status to
    # decide whether a protection chain is safe to activate.
    fwbuf 6 "$_FW_TBL" $_FW_ARGS
    return $?
  fi
  ip6tables $FWWAIT "$@" 2>>"$PG/apply.log"
}

# 提交所有缓冲规则。-n（=--noflush 的短选项）只追加，不动表内其它链。
# 失败时回退为逐条重放（宁可慢也不静默丢规则——防火墙丢规则等于防护失效）。
fw_flush() {
  [ "$IPT_BATCH" = "1" ] || return 0
  if [ "${_IPTQ_WRITE_FAIL:-0}" = "1" ]; then
    pg_log "fw: queue write failure recorded; refusing all queued rule commits"
    return 1
  fi
  _fl_fail=0
  for _fl_f in "$_IPTQ_D"/*; do
    [ -s "$_fl_f" ] || continue
    _fl_v=${_fl_f##*/}; _fl_v=${_fl_v%%_*}
    _fl_t=${_fl_f##*_}
    if [ "$_fl_v" = "4" ]; then
      _fl_cmd="iptables-restore"
    else
      _fl_cmd="ip6tables-restore"
    fi
    if ! command -v "$_fl_cmd" >/dev/null 2>&1; then
      _fl_fail=1; continue
    fi
    if { echo "*$_fl_t"; cat "$_fl_f"; echo 'COMMIT'; } | $_fl_cmd -n 2>>"$PG/apply.log"; then
      : > "$_fl_f"
    else
      pg_log "fw: $_fl_cmd 批量提交(${_fl_v}/${_fl_t})失败，回退逐条"
      _fl_line_fail=0
      _fl_ok_file="$_IPTQ_D/rollback_${_fl_v}_${_fl_t}_$$"
      : > "$_fl_ok_file"
      while IFS= read -r _fl_ln; do
        [ -n "$_fl_ln" ] || continue
        if [ "$_fl_v" = "4" ]; then
          if iptables $FWWAIT -t "$_fl_t" $_fl_ln 2>>"$PG/apply.log"; then
            printf '%s\n' "$_fl_ln" >> "$_fl_ok_file"
          else
            _fl_line_fail=1
          fi
        else
          if ip6tables $FWWAIT -t "$_fl_t" $_fl_ln 2>>"$PG/apply.log"; then
            printf '%s\n' "$_fl_ln" >> "$_fl_ok_file"
          else
            _fl_line_fail=1
          fi
        fi
      done < "$_fl_f"
      : > "$_fl_f"
      if [ "$_fl_line_fail" = "1" ]; then
        # The line-by-line fallback may have applied only part of a table queue.
        # Remove successfully appended -A rules in reverse order so the custom
        # chain is not left partially configured. Queue lines are generated by
        # fwbuf/nat helpers and should be append operations only.
        awk '{ a[NR]=$0 } END { for (i=NR; i>0; i--) print a[i] }' "$_fl_ok_file" | while IFS= read -r _fl_rb; do
          case "$_fl_rb" in
            '-A '*) _fl_rb="-D ${_fl_rb#-A }" ;;
            *) continue ;;
          esac
          if [ "$_fl_v" = "4" ]; then
            iptables $FWWAIT -t "$_fl_t" $_fl_rb 2>>"$PG/apply.log" || _fl_rb_fail=1
          else
            ip6tables $FWWAIT -t "$_fl_t" $_fl_rb 2>>"$PG/apply.log" || _fl_rb_fail=1
          fi
        done
        rm -f "$_fl_ok_file"
        pg_log "fw: $_fl_cmd 逐条回退不完整(${_fl_v}/${_fl_t})，已尝试逆序删除本批成功规则；拒绝挂接相关防护链"
        _fl_fail=1
      else
        rm -f "$_fl_ok_file"
        pg_log "fw: $_fl_cmd 逐条回退全部成功(${_fl_v}/${_fl_t})，规则已恢复"
      fi
    fi
  done
  return "$_fl_fail"
}

# 重建链（filter PGUARD + nat PGNAT + VPN/hide 链）
# 性能：这段原先 26 行、每行 1-2 次 fork（实测 ~0.4s），而且它是每次 apply 的固定成本。
# 改为按表批量：先在 nat 里 -D OUTPUT 跳转（链删前必须先摘），再逐表 -F/-X。
# 注意顺序：-D 必须在 -F/-X 之前，否则「链仍被引用」会导致 -X 失败 → 残留链在下一次
# 又叠加规则（这正是「重复 apply 规则翻倍」的根因）。
if [ "$IPT_BATCH" = "1" ] && pg_have ip6tables-restore; then
  # 先摘 OUTPUT 引用（nat: PGNAT/PGVPN/PGVPN6/PGHIDE；filter: PGUARD/PGKS/PGHKS；
  # mangle: PGMTU；v6 filter: PGBLK6/PGHKS）
  for _dt in nat filter mangle; do
    for _dc in PGNAT PGVPN PGVPN6 PGHIDE PGUARD PGKS PGHKS PGMTU; do
      # A previous interrupted apply may have inserted the same jump more than once.
      # Remove every module-owned reference before attempting to delete the chain.
      _dr=0
      while [ "$_dr" -lt 64 ] && iptables $FWWAIT -t "$_dt" -D OUTPUT -j "$_dc" 2>/dev/null; do
        _dr=$((_dr+1))
      done
    done
  done
  # IPv6 jumps must be detached from the same table in which they were
  # installed. The default-table-only loop misses nat/OUTPUT references
  # (notably PGNAT and PGVPN6), leaving chains undeletable after interrupted
  # applies and allowing stale redirects to survive a mode change.
  for _dt in nat filter mangle; do
    for _dc in PGNAT PGVPN PGVPN6 PGHIDE PGUARD PGKS PGBLK6 PGHKS PGMTU PGNF PGNF6; do
      _dr=0
      while [ "$_dr" -lt 64 ] && ip6tables $FWWAIT -t "$_dt" -D OUTPUT -j "$_dc" 2>/dev/null; do
        _dr=$((_dr+1))
      done
    done
  done
  # 再清/删链。★ 不能把多条链塞进同一个 iptables-restore 块：该命令是整批原子的，
  # 任一行失败（如某链在该表里不存在 → -X 报错）会导致整块回滚、所有链都清不掉。
  # 实测后果：切 direct 后 PGVPN 残留、且日志谎报已清空。故逐链独立提交。
  for _dt in nat filter mangle; do
    for _dc in PGNAT PGVPN PGVPN6 PGHIDE PGUARD PGKS PGHKS PGMTU PGNF PGNF6; do
      if iptables $FWWAIT -t "$_dt" -S "$_dc" >/dev/null 2>&1; then
        { echo "*$_dt"; echo "-F $_dc"; echo "-X $_dc"; echo 'COMMIT'; } | iptables-restore -n 2>/dev/null
        iptables $FWWAIT -t "$_dt" -S "$_dc" >/dev/null 2>&1 && {
          iptables $FWWAIT -t "$_dt" -F "$_dc" 2>/dev/null
          iptables $FWWAIT -t "$_dt" -X "$_dc" 2>/dev/null
        }
      fi
      if ip6tables $FWWAIT -t "$_dt" -S "$_dc" >/dev/null 2>&1; then
        { echo "*$_dt"; echo "-F $_dc"; echo "-X $_dc"; echo 'COMMIT'; } | ip6tables-restore -n 2>/dev/null
        ip6tables $FWWAIT -t "$_dt" -S "$_dc" >/dev/null 2>&1 && {
          ip6tables $FWWAIT -t "$_dt" -F "$_dc" 2>/dev/null
          ip6tables $FWWAIT -t "$_dt" -X "$_dc" 2>/dev/null
        }
      fi
    done
  done
else
  iptables  $FWWAIT -D OUTPUT -j PGUARD 2>/dev/null
  ip6tables $FWWAIT -D OUTPUT -j PGUARD 2>/dev/null
  iptables  $FWWAIT -F PGUARD 2>/dev/null && iptables  $FWWAIT -X PGUARD 2>/dev/null
  ip6tables $FWWAIT -F PGUARD 2>/dev/null && ip6tables $FWWAIT -X PGUARD 2>/dev/null
  iptables  $FWWAIT -t nat -D OUTPUT -j PGNAT 2>/dev/null
  ip6tables $FWWAIT -t nat -D OUTPUT -j PGNAT 2>/dev/null
  iptables  $FWWAIT -t nat -F PGNAT 2>/dev/null && iptables  $FWWAIT -t nat -X PGNAT 2>/dev/null
  ip6tables $FWWAIT -t nat -F PGNAT 2>/dev/null && ip6tables $FWWAIT -t nat -X PGNAT 2>/dev/null
  iptables  $FWWAIT -t nat -D OUTPUT -j PGVPN 2>/dev/null
  ip6tables $FWWAIT -t nat -D OUTPUT -j PGVPN6 2>/dev/null
  iptables  $FWWAIT -t nat -F PGVPN 2>/dev/null && iptables  $FWWAIT -t nat -X PGVPN 2>/dev/null
  ip6tables $FWWAIT -t nat -F PGVPN6 2>/dev/null && ip6tables $FWWAIT -t nat -X PGVPN6 2>/dev/null
  iptables  $FWWAIT -D OUTPUT -j PGKS 2>/dev/null
  ip6tables $FWWAIT -D OUTPUT -j PGBLK6 2>/dev/null
  iptables  $FWWAIT -F PGKS 2>/dev/null && iptables  $FWWAIT -X PGKS 2>/dev/null
  ip6tables $FWWAIT -F PGBLK6 2>/dev/null && ip6tables $FWWAIT -X PGBLK6 2>/dev/null
  iptables  $FWWAIT -t nat -D OUTPUT -j PGHIDE 2>/dev/null
  ip6tables $FWWAIT -D OUTPUT -j PGHKS 2>/dev/null
  iptables  $FWWAIT -t nat -F PGHIDE 2>/dev/null && iptables  $FWWAIT -t nat -X PGHIDE 2>/dev/null
  iptables  $FWWAIT -F PGHKS 2>/dev/null && iptables  $FWWAIT -X PGHKS 2>/dev/null
  ip6tables $FWWAIT -F PGHKS 2>/dev/null && ip6tables $FWWAIT -X PGHKS 2>/dev/null
  iptables  $FWWAIT -t mangle -D OUTPUT -j PGMTU 2>/dev/null
  iptables  $FWWAIT -t mangle -F PGMTU 2>/dev/null && iptables  $FWWAIT -t mangle -X PGMTU 2>/dev/null
fi

ANY_FW=0

# 外部 VPN 检测必须早于任何 PGNAT 规则（包括普通 DNS 转发）。
# 外部隧道已接管系统路由时，本模块不再插入 DNS/NAT 透明接管规则，避免破坏第三方 VPN。
_PG_EXT_VPN_IF=""
_PG_EXT_VPN_IFS=""
_PG_EXT_VPN_UID=""
_PG_EXT_VPN_ROUTE_OK=0
_PG_EXT_VPN_ROUTE_DEV=""
_PG_EXT_VPN_PROBE_UNKNOWN=0
_PG_VPN_INTERCEPTION_BLOCKED=0
VPN_EXTERNAL_UID=""
VPN_EXTERNAL_COMPAT=$(pg_get vpn_external_compat 1)
case "$VPN_EXTERNAL_COMPAT" in 1) ;; *) VPN_EXTERNAL_COMPAT=0 ;; esac
if command -v ip >/dev/null 2>&1; then
  # Link inventory is a prerequisite, but never infer the app VPN from the first
  # tun*/wg* entry. We need one active Android VpnInfo row and its matching owner UID.
  _PG_LINKS=$(ip -o link show 2>/dev/null)
  _PG_LINK_RC=$?
  if [ "$_PG_LINK_RC" -ne 0 ] || [ -z "$_PG_LINKS" ]; then
    _PG_EXT_VPN_PROBE_UNKNOWN=1
  else
    _PG_EXT_VPN_IFS=$(printf '%s\n' "$_PG_LINKS" | sed -n 's/^[0-9][0-9]*: \([^:@]*\).*/\1/p' | grep -E '^(tun[0-9]*|vpn[0-9]*|wg[0-9]*|ppp[0-9]*|ipsec[0-9]*|tap[0-9]*|utun[0-9]*|tailscale[0-9]*|zt[[:alnum:]_-]*)$' || true)
    _PG_EXT_VPN_INFO=$(vpncore_android_active_vpn_info 2>/dev/null || true)
    if [ -n "$_PG_EXT_VPN_INFO" ]; then
      _PG_EXT_VPN_IF=${_PG_EXT_VPN_INFO%%|*}
      _PG_EXT_VPN_UID=${_PG_EXT_VPN_INFO#*|}
      case " $_PG_EXT_VPN_IFS " in *" $_PG_EXT_VPN_IF "*) ;; *) _PG_EXT_VPN_IF=""; _PG_EXT_VPN_UID=""; _PG_EXT_VPN_PROBE_UNKNOWN=1 ;; esac
    elif [ -n "$_PG_EXT_VPN_IFS" ]; then
      # Could be WireGuard/Tailscale, a handover, or an app VPN whose VpnInfo
      # cannot be read. Never guess which interface owns the active app VPN.
      _PG_EXT_VPN_PROBE_UNKNOWN=1
      pg_log "vpn: tunnel-looking interface(s) found but no unique active Android VpnInfo/ownerUid; fail-safe suspension"
    fi
  fi
else
  _PG_EXT_VPN_PROBE_UNKNOWN=1
fi
if [ -n "$_PG_EXT_VPN_IF" ] || [ "$_PG_EXT_VPN_PROBE_UNKNOWN" = "1" ]; then
  _PG_VPN_INTERCEPTION_BLOCKED=1
fi
if [ "$_PG_EXT_VPN_PROBE_UNKNOWN" = "1" ]; then
  pg_log "vpn: active VpnInfo/interface state unavailable or ambiguous; suspend FX DNS/NAT/VPN takeover and fail-open rather than guess the outer tunnel"
fi
if [ -n "$_PG_EXT_VPN_IF" ]; then
  # The interface and UID come from the same validated active VpnInfo row. Do not
  # independently grep dumpsys and accidentally pair this interface with another VPN.
  VPN_EXTERNAL_UID=${_PG_EXT_VPN_UID:-}
  case "$VPN_EXTERNAL_UID" in ''|*[!0-9]*|0) VPN_EXTERNAL_UID="" ;; esac
  if [ "$VPN_EXTERNAL_COMPAT" = "1" ] && [ -n "$VPN_EXTERNAL_UID" ]; then
    # The root UID route table is not a reliable way to decide whether an Android
    # app VPN can carry FX's node socket. Android VPN per-app UID ranges often
    # exclude root. Instead, require sing-box >=1.12 and bind node, direct and DNS
    # sockets to the detected existing tunnel interface. SO_BINDTODEVICE makes a
    # failed outer tunnel fail closed rather than silently using wlan/cellular.
    _PG_VPN_ROUTE_HOST=$(pg_vpn_node_endpoint_host 2>/dev/null || true)
    _PG_VPN_ROUTE_OK=0
    _PG_EXT_VPN_ROUTE_OK=0
    _PG_EXT_VPN_ROUTE_TARGETS=""
    _PG_EXT_VPN_ROUTE_COUNT=0
    _PG_EXT_VPN_ROUTE_DEV=""
    _PG_SB_BIN=$(vpncore_bin 2>/dev/null || true)
    _PG_SB_VER=$(vpncore_core_version "$_PG_SB_BIN" 2>/dev/null || true)
    _PG_BIND_IF=$(vpncore_outer_tunnel_interface 2>/dev/null || true)
    if [ -z "$_PG_VPN_ROUTE_HOST" ]; then
      pg_log "vpn: automatic coexistence guard: selected FX node endpoint is missing/invalid; pausing interception"
    elif [ -z "$_PG_BIND_IF" ] || [ "$_PG_BIND_IF" != "$_PG_EXT_VPN_IF" ]; then
      pg_log "vpn: automatic coexistence guard: external tunnel interface could not be validated for explicit outbound binding; pausing interception"
    elif ! vpncore_ver_ge "$_PG_SB_VER" "1.12"; then
      pg_log "vpn: automatic coexistence guard: sing-box ${_PG_SB_VER:-unknown} lacks the verified modern DNS dial-field contract; need >=1.12 for fail-closed node/direct/DNS interface pinning"
    else
      _PG_EXT_VPN_ROUTE_OK=1
      _PG_EXT_VPN_ROUTE_TARGETS="$_PG_VPN_ROUTE_HOST"
      _PG_EXT_VPN_ROUTE_DEV="$_PG_BIND_IF"
      _PG_EXT_VPN_ROUTE_COUNT=1
      pg_log "vpn: automatic coexistence: existing outer tunnel $_PG_BIND_IF (owner UID $VPN_EXTERNAL_UID); sing-box $_PG_SB_VER will bind every node/direct/DNS outbound to that interface; endpoint host=$_PG_VPN_ROUTE_HOST. Generic FX DNS interception remains disabled to preserve outer VPN DNS."
    fi
  elif [ "$VPN_EXTERNAL_COMPAT" = "1" ]; then
    pg_log "vpn: automatic coexistence guard: external tunnel detected but VPNService owner UID is unknown; FX interception will pause safely"
  else
    pg_log "vpn: detected external tunnel $_PG_EXT_VPN_IF; FX transparent interception is suspended; independent VPN-hide rules may still apply"
  fi
fi

# ---------- 可信 DNS 目标（DNS 修复的核心）----------
# 原逻辑：dns_leak=1 时把除 [conf:custom_dns] 以外的 53 端口全部 REJECT，
# 但默认 custom_dns=0、global_dns=0 → 没有任何 DNAT 兜底 = 只封不转，
# 手机实际使用的 DHCP/运营商 DNS 全被拒 → 整机解析失败 → 用户看到「没网」。
# 现在：先算出一台可信 DNS；有它就「先重定向到这里」，再封其余；
#      没有可信 DNS 就 fail-open（不封 53），宁可不防泄露也不能把网络打死。
# Accept only real IPv4 literals for iptables DNAT targets. A dotted-quad regex
# alone also accepts values such as 999.999.999.999, which can make the DNS
# transaction fail and leave filtering without its intended resolver.
pg_first_valid_ipv4() {
  awk '
    /^[[:space:]]*#/ || NF == 0 { next }
    {
      ip=$NF
      n=split(ip, oct, ".")
      if (n != 4) next
      ok=1
      for (i=1; i<=4; i++) {
        if (oct[i] !~ /^[0-9]+$/ || length(oct[i]) > 3 || (oct[i]+0) > 255) ok=0
      }
      # The unspecified and limited-broadcast addresses are syntactically valid
      # IPv4 literals but are not usable unicast DNS resolver targets.
      if (ip == "0.0.0.0" || ip == "255.255.255.255") ok=0
      if (ok) { print ip; exit }
    }
  '
}

DNS_SAFE=""
if [ "$(pg_get dns_forward 1)" = "1" ]; then
  # 只认用户明确指定的 DNS：custom_dns=1 → [conf:custom_dns]，global_dns=1 → [conf:global_dns]。
  # 不在这里「猜」一个 DNS 硬塞给设备：猜错（比如在国外用国内 DNS）会再次把网络打死。
  if [ "$(pg_get custom_dns 0)" = "1" ]; then
    DNS_SAFE=$(pg_conf custom_dns 2>/dev/null | pg_first_valid_ipv4)
  fi
  if [ -z "$DNS_SAFE" ] && [ "$(pg_get global_dns 0)" = "1" ]; then
    DNS_SAFE=$(pg_conf global_dns 2>/dev/null | pg_first_valid_ipv4)
  fi
fi
# The local AdGuard Home filter and Unbound recursive resolver share one explicit engine switch.
# The engine switch and DNS forwarding must both be enabled; external-VPN Root Proxy additionally
# requires its own opt-in and a verified active VPN owner/interface. Every failed proof is fail-open.
DNS_AGH_ACTIVE=0
DNS_AGH_IPV6=0
_DNS_SAFE_CONFIGURED="$DNS_SAFE"
if [ "$(pg_get dns_forward 1)" = "1" ] && \
     [ "$(pg_get dns_engine_adguardhome 1)" = "1" ] && \
     [ "$(pg_get vpn_mode direct)" = "direct" ] && \
     [ "$_PG_VPN_INTERCEPTION_BLOCKED" = "0" ]; then
    if [ -x "$MODDIR/scripts/yulong-root-proxy.sh" ]; then
      sh "$MODDIR/scripts/yulong-root-proxy.sh" stop "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || :
    fi
    if sh "$MODDIR/scripts/fxdns.sh" ensure "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1; then
      DNS_SAFE="127.0.0.1"
      DNS_AGH_ACTIVE=1
      pg_log "dns: AdGuard Home ready; only FX anti-fraud domain rules are loaded"
    else
      pg_log "dns: AdGuard Home failed validation/health probe; keep configured resolver or fail-open"
    fi
else
  # This branch means local recursive DNS is intentionally ineligible (DNS
  # forwarding disabled, non-direct FX mode, or an external VPN owns the tunnel).
  # Stop the old watchdog before stopping its engines; otherwise it observes the
  # missing PID markers and repeatedly invokes apply.sh fast against a state that
  # policy intentionally keeps disabled. A later eligible apply will start it again.
  if [ -x "$MODDIR/scripts/localdns-watchdog.sh" ]; then
    if ! sh "$MODDIR/scripts/localdns-watchdog.sh" stop "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1; then
      pg_fail dns "无法确认本地 DNS 看门狗已停止；为避免恢复进程重新应用规则并与已停止的解析器冲突，终止本次 apply，保留当前 DNS 引擎"
      pg_log "CRITICAL dns: watchdog shutdown was not confirmed in the intentionally-disabled path; aborting before resolver teardown"
      # The EXIT trap releases the apply lock and rolls back any active settings
      # transaction. Never stop the resolver while an unverified watcher may
      # still re-enter apply.sh and recreate DNS interception.
      exit 1
    fi
  fi
  sh "$MODDIR/scripts/fxdns.sh" stop "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || :
  if [ -x "$MODDIR/scripts/yulong-root-proxy.sh" ] && [ "$(pg_get dns_engine_adguardhome 0)" = "1" ] && [ "$(pg_get dns_forward 0)" = "1" ] && [ "$(pg_get vpn_external_dns_proxy 0)" = "1" ] && [ -n "$_PG_EXT_VPN_IF" ] && [ "$_PG_EXT_VPN_PROBE_UNKNOWN" = "0" ] && [ -n "$VPN_EXTERNAL_UID" ] && [ "$VPN_EXTERNAL_COMPAT" = "1" ]; then
    if sh "$MODDIR/scripts/yulong-root-proxy.sh" ensure "$MODDIR" "$PG" "$_PG_EXT_VPN_IF" "$VPN_EXTERNAL_UID" >> "$PG/boot.log" 2>&1; then
      DNS_SAFE="127.0.0.1"
      DNS_AGH_ACTIVE=1
      pg_log "dns: Yulong Root Proxy validated; AdGuard DNS filtering enabled over the existing third-party VPN"
    else
      sh "$MODDIR/scripts/yulong-root-proxy.sh" stop "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || :
      pg_log "dns: Yulong Root Proxy could not prove its VPN egress; preserved external VPN DNS (fail-open)"
    fi
  else
    sh "$MODDIR/scripts/yulong-root-proxy.sh" stop "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || :
  fi
  if [ "$_PG_EXT_VPN_PROBE_UNKNOWN" = "1" ]; then
      pg_log "dns: AdGuard Home disabled because VPN interface state is unknown; no DNS override applied"
    elif [ -n "${_PG_EXT_VPN_IF:-}" ]; then
      pg_log "dns: AdGuard Home disabled while third-party VPN owns the tunnel; preserving VPN DNS behavior"
    elif [ "$(pg_get vpn_mode direct)" != "direct" ]; then
      pg_log "dns: AdGuard Home local engine is limited to FX direct mode; proxy/rule mode retains its own DNS path"
  else
    pg_log "dns: local recursive engine requires DNS forwarding, direct mode, and no external VPN"
  fi
fi
if [ -n "$DNS_SAFE" ]; then
  pg_log "dns: trusted resolver = $DNS_SAFE (明文 DNS 会重定向到它)"
else
  pg_log "dns: 未配置可信 DNS，明文 DNS 不拦截（fail-open，防止整机没网）"
fi

if [ "$(pg_get block_quic 0)" = "1" ]; then
  ANY_FW=1
  fw4 -N PGUARD; fw4 -A PGUARD -p udp --dport 443 -j REJECT
  fw6 -N PGUARD; fw6 -A PGUARD -p udp --dport 443 -j REJECT
fi
if [ "$(pg_get block_stun 1)" = "1" ]; then
  ANY_FW=1
  fw4 -N PGUARD 2>/dev/null; fw6 -N PGUARD 2>/dev/null
  for p in 3478 5349 19302 19303; do
    fw4 -A PGUARD -p udp --dport $p -j REJECT
    fw6 -A PGUARD -p udp --dport $p -j REJECT
  done
  for p in 3478 5349; do
    fw4 -A PGUARD -p tcp --dport $p -j REJECT
    fw6 -A PGUARD -p tcp --dport $p -j REJECT
  done
fi
if [ "$(pg_get block_dot 0)" = "1" ]; then
  ANY_FW=1
  fw4 -N PGUARD 2>/dev/null; fw6 -N PGUARD 2>/dev/null
  fw4 -A PGUARD -p tcp --dport 853 -j REJECT
  fw6 -A PGUARD -p tcp --dport 853 -j REJECT
  fw4 -A PGUARD -p udp --dport 853 -j REJECT
  fw6 -A PGUARD -p udp --dport 853 -j REJECT
fi
if [ "$_PG_VPN_INTERCEPTION_BLOCKED" = "1" ]; then
  # When an external tunnel is detected OR interface inspection is inconclusive,
  # generic PGNAT DNS redirection is
  # intentionally disabled. Do not leave a filter-only DNS lockdown behind:
  # the system/DHCP resolver may differ from DNS_SAFE and every lookup would fail.
  # The external VPN remains responsible for its own DNS policy in this state.
  if [ "$_PG_EXT_VPN_PROBE_UNKNOWN" = "1" ]; then
    pg_log "dns: VPN interface state unknown; skip plaintext-DNS lockdown and fail-open to avoid outage"
  elif [ -n "$_PG_EXT_VPN_IF" ]; then
    pg_log "dns: third-party VPN $_PG_EXT_VPN_IF owns the tunnel; skip local plaintext-DNS lockdown because FX DNS redirection is suspended (fail-open to avoid outage)"
  fi
elif [ "$(pg_get block_plain_dns 1)" = "1" ] || [ "$(pg_get dns_leak 1)" = "1" ]; then
  # 阻断明文 DNS（除可信 DNS 服务器外全部 REJECT udp/tcp 53）；
  # dns_leak=1 时同样强制 —— DNS 不能泄露给运营商。
  # 关键修复：只有在「确实有可信 DNS 可转发」时才封其余，否则 fail-open 不封，
  #           否则手机自带的 DHCP DNS 全被拒 = 整机解析失败 = 用户说的「没网」。
  # 只把语法有效的 DNS 地址加入 RETURN 例外。简单的点分数字正则会把
  # 999.1.1.1 等非法地址塞进 iptables-restore 队列，导致整批 filter 规则失败。
  # 仅在自定义 DNS 开关开启时，才允许其配置地址进入防火墙 RETURN 例外。
  # 配置文件可能保留已关闭功能的旧值；不能因 global_dns 开启就让旧自定义 DNS 绕过过滤。
  DNSLIST=""
  if [ "$(pg_get custom_dns 0)" = "1" ]; then
    DNSLIST=$(pg_conf custom_dns 2>/dev/null | awk '
    /^[[:space:]]*#/ || NF == 0 { next }
    {
      ip=$NF
      if (ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
        n=split(ip, oct, "."); ok=(n == 4)
        for (i=1; i<=4; i++) if (oct[i] !~ /^[0-9]+$/ || length(oct[i]) > 3 || oct[i]+0 > 255) ok=0
        if (ip == "0.0.0.0" || ip == "255.255.255.255") ok=0
        if (ok) print ip
        next
      }
      # Accept IPv6 literals made only of hexadecimal groups and colons.
      # Reject triple-colon forms explicitly: the :: compression scan below
      # would otherwise collapse ":::" once and incorrectly accept it.
      # Count groups and allow at most one :: compression marker.
      if (ip !~ /^[0-9A-Fa-f:]+$/ || index(ip, ":") == 0 || ip ~ /:::/) next
      d=ip; doubles=0; while (sub(/::/, ":", d)) doubles++
      if (doubles > 1) next
      n=split(ip, grp, ":"); ok=1; count=0
      for (i=1; i<=n; i++) if (grp[i] != "") {
        if (grp[i] !~ /^[0-9A-Fa-f]+$/ || length(grp[i]) > 4) ok=0
        count++
      }
      if (doubles == 0 && count != 8) ok=0
      if (doubles == 1 && count >= 8) ok=0
      if (ok) print ip
    }
  ')
  fi
  if [ -n "$DNS_SAFE" ]; then
    DNSLIST="$DNSLIST $DNS_SAFE"
  fi
  if [ "$DNS_AGH_ACTIVE" = "1" ] && [ "$DNS_AGH_IPV6" = "1" ]; then
    DNSLIST="$DNSLIST ::1"
  fi
  if [ -n "$DNS_SAFE" ]; then
    ANY_FW=1
    fw4 -N PGUARD 2>/dev/null; fw6 -N PGUARD 2>/dev/null
    DNSLIST_IPV6=0
    for d in $DNSLIST; do
      case "$d" in
        *:*) DNSLIST_IPV6=1
             fw6 -A PGUARD -p udp -d "$d" --dport 53 -j RETURN
             fw6 -A PGUARD -p tcp -d "$d" --dport 53 -j RETURN ;;
        *)   fw4 -A PGUARD -p udp -d "$d" --dport 53 -j RETURN
             fw4 -A PGUARD -p tcp -d "$d" --dport 53 -j RETURN ;;
      esac
    done
    fw4 -A PGUARD -p udp --dport 53 -j REJECT
    fw4 -A PGUARD -p tcp --dport 53 -j REJECT
    # DNS_SAFE is deliberately IPv4-only. Do not reject IPv6 DNS merely because
    # an IPv4 resolver exists: without a validated IPv6 exception (e.g. ::1 when
    # local DNS IPv6 DNAT is active), that would strand IPv6-only resolvers and
    # create a partial-network outage. Explicit DoT enforcement remains separate.
    if [ "$DNSLIST_IPV6" = "1" ]; then
      fw6 -A PGUARD -p udp --dport 53 -j REJECT
      fw6 -A PGUARD -p tcp --dport 53 -j REJECT
    else
      pg_log "dns: no validated IPv6 resolver exception; skip IPv6 plaintext-DNS rejection (fail-open for IPv6)"
    fi
  else
    # 没有可信 DNS：不拦明文 DNS（fail-open），并明确记日志
    pg_log "dns: 跳过明文 DNS 封锁（无可用可信 DNS，防止整机没网）"
  fi
fi
if [ "$(pg_get block_ipv6 0)" = "1" ]; then
  ANY_FW=1
  fw6 -N PGUARD 2>/dev/null
  fw6 -A PGUARD -o lo -j RETURN
  fw6 -A PGUARD -d fe80::/10 -j RETURN
  fw6 -A PGUARD -j REJECT
fi
if [ "$(pg_get block_multicast 0)" = "1" ]; then
  ANY_FW=1
  fw4 -N PGUARD 2>/dev/null; fw6 -N PGUARD 2>/dev/null
  fw4 -A PGUARD -d 224.0.0.0/4 -j DROP
  fw6 -A PGUARD -d ff00::/8 -j DROP
fi
if [ "$(pg_get conn_guard 0)" = "1" ]; then
  ANY_FW=1
  fw4 -N PGUARD 2>/dev/null; fw6 -N PGUARD 2>/dev/null
  fw4 -A PGUARD -m conntrack --ctstate INVALID -j DROP
  fw6 -A PGUARD -m conntrack --ctstate INVALID -j DROP
fi
# IP 泄露防护：STUN/SSDP/mDNS 是暴露真实内网/公网 IP 的主要通道（WebRTC 探测）
if [ "$(pg_get ip_leak 1)" = "1" ] || [ "$(pg_get block_webrtc_leak 1)" = "1" ]; then
  ANY_FW=1
  fw4 -N PGUARD 2>/dev/null; fw6 -N PGUARD 2>/dev/null
  for p in 3478 3479 5349 19302 19303 19304; do
    fw4 -A PGUARD -p udp --dport $p -j REJECT
    fw6 -A PGUARD -p udp --dport $p -j REJECT
  done
  fw4 -A PGUARD -p udp --dport 1900 -j DROP; fw6 -A PGUARD -p udp --dport 1900 -j DROP
  fw4 -A PGUARD -p udp --dport 5353 -j DROP; fw6 -A PGUARD -p udp --dport 5353 -j DROP
  pg_log "fw: ip_leak/webrtc STUN+SSDP+mDNS blocked"
fi
# VPN 泄露防护：阻断 STUN（VPN 下探测真实 IP 的主要手段）+ 本地发现端口
if [ "$(pg_get vpn_leak 1)" = "1" ]; then
  ANY_FW=1
  fw4 -N PGUARD 2>/dev/null; fw6 -N PGUARD 2>/dev/null
  for p in 3478 3479 5349 19302 19303 19304; do
    fw4 -A PGUARD -p udp --dport $p -j REJECT
    fw6 -A PGUARD -p udp --dport $p -j REJECT
  done
  fw4 -A PGUARD -p udp --dport 1900 -j DROP; fw6 -A PGUARD -p udp --dport 1900 -j DROP
  fw4 -A PGUARD -p udp --dport 5353 -j DROP; fw6 -A PGUARD -p udp --dport 5353 -j DROP
  pg_log "fw: vpn_leak STUN/local-discovery blocked"
  # A user can still disable a switch; record that so the effective state is auditable
  # rather than silently weaker than the defaults.
  _leak_off=""
  for _leak_key in dns_leak block_plain_dns block_stun ip_leak vpn_leak block_webrtc_leak; do
    if [ "$(pg_get "$_leak_key" 1)" = "0" ]; then
      _leak_off="$_leak_off $_leak_key"
    fi
  done
  if [ -n "$_leak_off" ]; then
    pg_log "fw: leak protection weakened by user setting:$_leak_off"
  fi
fi
# 网络隐私：SSDP/mDNS/NetBIOS 广播会暴露设备名与本地拓扑
if [ "$(pg_get net_privacy 0)" = "1" ]; then
  ANY_FW=1
  fw4 -N PGUARD 2>/dev/null; fw6 -N PGUARD 2>/dev/null
  fw4 -A PGUARD -p udp --dport 1900 -j DROP; fw6 -A PGUARD -p udp --dport 1900 -j DROP
  fw4 -A PGUARD -p udp --dport 5353 -j DROP; fw6 -A PGUARD -p udp --dport 5353 -j DROP
  for p in 137 138 139; do
    fw4 -A PGUARD -p udp --dport $p -j DROP
    fw4 -A PGUARD -p tcp --dport $p -j DROP
  done
  pg_log "fw: net_privacy SSDP/mDNS/NetBIOS blocked"
fi
# 定位泄露：SUPL 辅助定位明文上报（TCP/7275）+ 定位域已在 hosts 段并入
if [ "$(pg_get loc_leak 0)" = "1" ]; then
  ANY_FW=1
  fw4 -N PGUARD 2>/dev/null; fw6 -N PGUARD 2>/dev/null
  fw4 -A PGUARD -p tcp --dport 7275 -j REJECT
  fw6 -A PGUARD -p tcp --dport 7275 -j REJECT
  pg_log "fw: loc_leak SUPL/7275 blocked"
fi
if [ "$(pg_get echo_blackhole 0)" = "1" ]; then
  ANY_FW=1
  fw4 -N PGUARD 2>/dev/null
  pg_conf echo_blackhole | grep -v '^#' | grep -v '^$' | while IFS= read -r ip; do
    [ -n "$ip" ] || continue
    fw4 -A PGUARD -d "$ip" -j DROP 2>/dev/null
  done
fi
# DoT 强制：明文 DNS（udp/tcp 53）全部拒绝，DNS 只能走 853 加密通道
if [ "$(pg_get dot_enforce 0)" = "1" ]; then
  ANY_FW=1
  fw4 -N PGUARD 2>/dev/null; fw6 -N PGUARD 2>/dev/null
  fw4 -A PGUARD -p udp --dport 53 -j REJECT
  fw4 -A PGUARD -p tcp --dport 53 -j REJECT
  fw6 -A PGUARD -p udp --dport 53 -j REJECT
  fw6 -A PGUARD -p tcp --dport 53 -j REJECT
  pg_log "fw: dot_enforce plaintext DNS rejected (853 only)"
fi
# FX 规则（防火墙部分）：IP-CIDR,地址 → DROP；IP-CIDR6 → v6 DROP
# v1.10.8：pg_fx_expand 只展开一次（原先计一次数 + 再展开一次，内置条目多时白跑两遍）。
if [ "$(pg_get fx 0)" = "1" ]; then
  _fxip="$PG/cache/fx.ip.$$"
  pg_fx_expand 2>/dev/null | awk -F',' '($1=="IP-CIDR"||$1=="IP-CIDR6") && (toupper($3)==""||toupper($3)=="REJECT"||toupper($3)=="BLOCK"||toupper($3)=="DROP"||toupper($3)=="DENY"||toupper($3)=="REJECT-DROP") {print $2}' > "$_fxip" 2>/dev/null || : > "$_fxip"
  FXN=$(grep -c . "$_fxip" 2>/dev/null || echo 0)
  if [ "$FXN" -gt 0 ]; then
    _FX4_QUEUED=0; _FX6_QUEUED=0; _FX_ADD_FAIL=0
    fw4 -N PGUARD 2>/dev/null; fw6 -N PGUARD 2>/dev/null
    while IFS= read -r cidr; do
      [ -n "$cidr" ] || continue
      case "$cidr" in
        *:*)
          if fw6 -A PGUARD -d "$cidr" -j DROP 2>>"$PG/apply.log"; then _FX6_QUEUED=$((_FX6_QUEUED+1)); else _FX_ADD_FAIL=$((_FX_ADD_FAIL+1)); fi
          ;;
        *)
          if fw4 -A PGUARD -d "$cidr" -j DROP 2>>"$PG/apply.log"; then _FX4_QUEUED=$((_FX4_QUEUED+1)); else _FX_ADD_FAIL=$((_FX_ADD_FAIL+1)); fi
          ;;
      esac
    done < "$_fxip"
    if [ "$_FX4_QUEUED" -gt 0 ] || [ "$_FX6_QUEUED" -gt 0 ]; then ANY_FW=1; fi
    pg_log "fw: fx IP-CIDR queued ipv4=$_FX4_QUEUED ipv6=$_FX6_QUEUED add_failures=$_FX_ADD_FAIL; final activation depends on firewall batch commit and OUTPUT hook verification"
    if [ "$_FX_ADD_FAIL" -gt 0 ]; then pg_fail fx "FX IP-CIDR 部分规则未能加入防火墙待提交链；失败数=$_FX_ADD_FAIL"; fi
    if [ "$_FX4_QUEUED" -eq 0 ] && [ "$_FX6_QUEUED" -eq 0 ]; then
      pg_fail fx "FX IP-CIDR 源存在内容，但没有规则成功加入待提交链"
    fi
  fi
  rm -f "$_fxip"
fi
# FX 包名规则（独立于 sing-box 代理模式）：对明示 PACKAGE-NAME,...,REJECT 的应用
# 按 Android UID 加入 FX 自有 OUTPUT 链；避免 direct 模式下进程规则只被写入路由 JSON 却不执行。
# FX 内置清单只含 com.hicorenational.antifraud，不拦截通用 Package Installer/OEM 安全中心。
if [ "$(pg_get fx 0)" = "1" ]; then
  _fx_pkgs=$(pg_fx_expand 2>/dev/null | awk -F',' 'toupper($1)=="PACKAGE-NAME" && (toupper($3)==""||toupper($3)=="REJECT"||toupper($3)=="BLOCK"||toupper($3)=="DROP"||toupper($3)=="DENY"||toupper($3)=="REJECT-DROP") {print $2}' | awk '!seen[$0]++')
  if [ -n "$_fx_pkgs" ]; then
    fw4 -N PGUARD 2>/dev/null || :
    fw6 -N PGUARD 2>/dev/null || :
    _fx_app_added=0; _fx_app_failed=0
    while IFS= read -r _fx_pkg; do
      case "$_fx_pkg" in ''|*[!A-Za-z0-9_.]*) pg_log "fw: FX invalid package name skipped: $_fx_pkg"; continue ;; esac
      _fx_uid=$(stat -c %u "/data/data/$_fx_pkg" 2>/dev/null)
      case "$_fx_uid" in ''|*[!0-9]*|0) pg_log "fw: FX package not installed or UID unavailable: $_fx_pkg"; continue ;; esac
      if fw4 -A PGUARD -m owner --uid-owner "$_fx_uid" -j REJECT 2>>"$PG/apply.log"; then
        _fx_app_added=$((_fx_app_added+1))
      else
        _fx_app_failed=$((_fx_app_failed+1))
      fi
      # IPv6 filter may be unavailable on some devices; record independently rather
      # than silently claim dual-stack coverage.
      if ! fw6 -A PGUARD -m owner --uid-owner "$_fx_uid" -j REJECT 2>>"$PG/apply.log"; then
        pg_log "fw: FX IPv6 package rule unavailable for $_fx_pkg (UID=$_fx_uid)"
      fi
    done <<__PG_FX_PACKAGES__
$_fx_pkgs
__PG_FX_PACKAGES__
    if [ "$_fx_app_added" -gt 0 ]; then
      ANY_FW=1
      pg_log "fw: FX package-level reject queued count=$_fx_app_added; final activation depends on firewall batch commit"
    elif [ "$_fx_app_failed" -gt 0 ]; then
      pg_fail fx "FX 包名规则未能加入防火墙待提交链，失败数=$_fx_app_failed"
    fi
  fi
fi

# Hook 拦截：对 [list:hook] 勾选的应用按 UID 断网（切断广告 SDK 上报通道）
if [ "$(pg_get hook_block 0)" = "1" ]; then
  HBN=0
  fw4 -N PGUARD 2>/dev/null
  for pkg in $(pg_list_enabled hook); do
    HUID=$(stat -c %u "/data/data/$pkg" 2>/dev/null)
    if [ -n "$HUID" ] && [ "$HUID" != "0" ]; then
      fw4 -A PGUARD -m owner --uid-owner "$HUID" -j REJECT 2>/dev/null && HBN=$((HBN+1))
    fi
  done
  if [ "$HBN" -gt 0 ]; then
    ANY_FW=1
    pg_log "fw: hook_block $HBN app(s) cut off by uid"
  else
    pg_log "fw: hook_block on but no resolvable package (add package names in Hook list)"
  fi
fi
# 运营商嗅探防护：TR-069 远程管理端口（7547/7548 曾被蠕虫利用远程控制光猫/路由）
if [ "$(pg_get isp_snoop 0)" = "1" ]; then
  ANY_FW=1
  fw4 -N PGUARD 2>/dev/null
  fw4 -A PGUARD -p tcp --dport 7547 -j DROP
  fw4 -A PGUARD -p tcp --dport 7548 -j DROP
  pg_log "fw: isp_snoop TR-069 7547/7548 dropped"
fi

# ---------- 2b. NAT（PGNAT 链：DNS 重定向 / 透明代理）----------
ANY_NAT=0
# nat4/nat6 同样走批量队列（-A 缓冲、结构性操作立即执行），规则数不多但省的是进程开销。
# nat_flush 是 nat 表专用提交口，供需要「立即生效再读回」的位置调用。
nat4() {
  if [ "$IPT_BATCH" = "1" ]; then
    _n4_op=0
    for _n4_a in "$@"; do [ "$_n4_a" = "-A" ] && _n4_op=1; done
    if [ "$_n4_op" = "1" ]; then
      # Do not mask a failed NAT queue write from immediate callers.
      fwbuf 4 nat "$@"
      return $?
    fi
  fi
  iptables $FWWAIT -t nat "$@" 2>>"$PG/apply.log"
}
nat6() {
  if [ "$IPT_BATCH" = "1" ]; then
    _n6_op=0
    for _n6_a in "$@"; do [ "$_n6_a" = "-A" ] && _n6_op=1; done
    if [ "$_n6_op" = "1" ]; then
      # Do not mask a failed NAT queue write from immediate callers.
      fwbuf 6 nat "$@"
      return $?
    fi
  fi
  ip6tables $FWWAIT -t nat "$@" 2>>"$PG/apply.log"
}
# 提交 nat 表队列（只提交 nat 部分，filter/mangle 队列保持不动）
nat_flush() {
  [ "$IPT_BATCH" = "1" ] || return 0
  if [ "${_IPTQ_WRITE_FAIL:-0}" = "1" ]; then
    pg_log "fw: queue write failure recorded; refusing NAT queue commit"
    return 1
  fi
  _nf_fail=0
  for _nf in "$_IPTQ_D"/4_nat "$_IPTQ_D"/6_nat; do
    [ -s "$_nf" ] || continue
    _n_v=${_nf##*/}; _n_v=${_n_v%%_*}
    if [ "$_n_v" = "4" ]; then _n_cmd="iptables-restore"; else _n_cmd="ip6tables-restore"; fi
    if ! command -v "$_n_cmd" >/dev/null 2>&1; then
      pg_log "fw: $_n_cmd 不可用，nat 队列无法提交"
      _nf_fail=1
      continue
    fi
    if { echo '*nat'; cat "$_nf"; echo 'COMMIT'; } | $_n_cmd -n 2>>"$PG/apply.log"; then
      : > "$_nf"
    else
      pg_log "fw: $_n_cmd nat 批量提交失败，回退逐条"
      _nf_line_fail=0
      _nf_ok_file="$_IPTQ_D/rollback_nat_${_n_v}_$$"
      : > "$_nf_ok_file"
      while IFS= read -r _n_ln; do
        [ -n "$_n_ln" ] || continue
        if [ "$_n_v" = "4" ]; then
          if iptables $FWWAIT -t nat $_n_ln 2>>"$PG/apply.log"; then
            printf '%s\n' "$_n_ln" >> "$_nf_ok_file"
          else
            _nf_line_fail=1
          fi
        else
          if ip6tables $FWWAIT -t nat $_n_ln 2>>"$PG/apply.log"; then
            printf '%s\n' "$_n_ln" >> "$_nf_ok_file"
          else
            _nf_line_fail=1
          fi
        fi
      done < "$_nf"
      # 清空原队列，避免下次 flush 重复插入部分成功规则。
      : > "$_nf"
      if [ "$_nf_line_fail" = "1" ]; then
        # Roll back this partial batch in reverse order; never leave a knowingly
        # incomplete NAT chain attached after the caller receives failure.
        awk '{ a[NR]=$0 } END { for (i=NR; i>0; i--) print a[i] }' "$_nf_ok_file" | while IFS= read -r _nf_rb; do
          case "$_nf_rb" in
            '-A '*) _nf_rb="-D ${_nf_rb#-A }" ;;
            *) continue ;;
          esac
          if [ "$_n_v" = "4" ]; then
            iptables $FWWAIT -t nat $_nf_rb 2>>"$PG/apply.log" || pg_log "fw: NAT partial rollback failed(v4): $_nf_rb"
          else
            ip6tables $FWWAIT -t nat $_nf_rb 2>>"$PG/apply.log" || pg_log "fw: NAT partial rollback failed(v6): $_nf_rb"
          fi
        done
        pg_log "fw: NAT 逐条回退不完整(${_n_v}/nat)，已尝试逆序删除本批成功规则"
        _nf_fail=1
      fi
      rm -f "$_nf_ok_file"
    fi
  done
  return "$_nf_fail"
}

# DNS 兜底重定向（关键修复）：只要 filter 段会封明文 53，就必须先把 53 转到一台可信 DNS，
# 否则「只封不转」= 手机自带 DNS 全部被拒 = 整机没网。
# 目标优先用 [conf:custom_dns]，其次 [conf:global_dns]；都没有就不封（filter 段已 fail-open）。
DNS_FWD=""
if [ "$(pg_get dns_forward 1)" = "1" ] && [ -n "$DNS_SAFE" ] && [ "$_PG_VPN_INTERCEPTION_BLOCKED" = "0" ] && [ "$(pg_get vpn_mode direct)" != "tun" ]; then
  DNS_FWD="$DNS_SAFE"
fi
if [ "$DNS_AGH_ACTIVE" = "1" ]; then
  # Build IPv6 rules while the chain is unreferenced. They use direct ip6tables
  # writes; the hook is installed only after the combined DNS transaction commits.
  _agh6_ok=1
  ip6tables $FWWAIT -t nat -N PGNAT >/dev/null 2>&1 || _agh6_ok=0
  if [ "$_agh6_ok" = "1" ]; then
    # Unbound runs as root and performs recursive UDP/TCP 53 queries directly to
    # root/TLD/authoritative servers. Exempt only its DNS packets; a blanket UID-0
    # RETURN would bypass every other PGNAT rule for all root-owned applications.
    ip6tables $FWWAIT -t nat -A PGNAT -m owner --uid-owner 0 -p udp --dport 53 -j RETURN >> "$PG/apply.log" 2>&1 || _agh6_ok=0
    [ "$_agh6_ok" != "1" ] || ip6tables $FWWAIT -t nat -A PGNAT -m owner --uid-owner 0 -p tcp --dport 53 -j RETURN >> "$PG/apply.log" 2>&1 || _agh6_ok=0
    [ "$_agh6_ok" != "1" ] || ip6tables $FWWAIT -t nat -A PGNAT -p udp --dport 53 -j DNAT --to-destination '[::1]:53' >> "$PG/apply.log" 2>&1 || _agh6_ok=0
    [ "$_agh6_ok" != "1" ] || ip6tables $FWWAIT -t nat -A PGNAT -p tcp --dport 53 -j DNAT --to-destination '[::1]:53' >> "$PG/apply.log" 2>&1 || _agh6_ok=0
    [ "$_agh6_ok" != "1" ] || ip6tables $FWWAIT -t nat -A PGNAT -j RETURN >> "$PG/apply.log" 2>&1 || _agh6_ok=0
  fi
  if [ "$_agh6_ok" = "1" ]; then
    DNS_AGH_IPV6=1
  else
    ip6tables $FWWAIT -t nat -F PGNAT >/dev/null 2>&1 || :
    ip6tables $FWWAIT -t nat -X PGNAT >/dev/null 2>&1 || :
    DNS_AGH_ACTIVE=0
    DNS_SAFE="$_DNS_SAFE_CONFIGURED"
    DNS_FWD=""
    if [ "$(pg_get dns_forward 1)" = "1" ] && [ -n "$DNS_SAFE" ] && [ "$_PG_VPN_INTERCEPTION_BLOCKED" = "0" ] && [ "$(pg_get vpn_mode direct)" != "tun" ]; then DNS_FWD="$DNS_SAFE"; fi
    # The local recursive path is being abandoned in favor of the configured
    # resolver. Stop its watcher too, or it will keep re-applying a disabled chain.
    if [ -x "$MODDIR/scripts/localdns-watchdog.sh" ]; then
      if ! sh "$MODDIR/scripts/localdns-watchdog.sh" stop "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1; then
        pg_fail dns "IPv6 loopback NAT 不可用且无法确认本地 DNS 看门狗已停止；终止 apply 并保留解析器，避免残留恢复进程重建不完整 DNS 路径"
        pg_log "CRITICAL dns: watchdog shutdown was not confirmed after IPv6 loopback NAT failure; aborting before resolver teardown"
        exit 1
      fi
    fi
    sh "$MODDIR/scripts/fxdns.sh" stop "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || :
    pg_log "dns: IPv6 loopback NAT unavailable; AdGuard Home routing aborted and original resolver/fail-open restored"
  fi
fi
if [ -n "$DNS_FWD" ]; then
  ANY_NAT=1
  nat4 -N PGNAT 2>/dev/null
  if [ "$DNS_AGH_ACTIVE" = "1" ]; then
    # Only root-owned DNS packets may bypass the local DNAT; other root-owned
    # sockets must still pass through FX transparent-proxy rules. If either
    # exemption cannot be queued, refuse the entire NAT transaction.
    if ! nat4 -A PGNAT -m owner --uid-owner 0 -p udp --dport 53 -j RETURN || \
       ! nat4 -A PGNAT -m owner --uid-owner 0 -p tcp --dport 53 -j RETURN; then
      _IPTQ_WRITE_FAIL=1
      pg_log "dns: failed to queue narrow root-owned UDP/TCP 53 recursive DNS exemptions; refuse DNS redirection"
    fi
  fi
  nat4 -A PGNAT -p udp --dport 53 -j DNAT --to-destination "$DNS_FWD"
  nat4 -A PGNAT -p tcp --dport 53 -j DNAT --to-destination "$DNS_FWD"
  pg_log "dns: 明文 DNS 兜底重定向 udp+tcp/53 -> $DNS_FWD"
fi

# 自定义 DNS 重定向：用户明确启用 custom_dns 时使用，不再依赖已删除的 DNS 拦截总开关。
if [ "$(pg_get custom_dns 0)" = "1" ] && [ "$_PG_VPN_INTERCEPTION_BLOCKED" = "0" ] && [ "$(pg_get vpn_mode direct)" != "tun" ] && [ -z "$DNS_FWD" ]; then
  DNS1=$(pg_conf custom_dns | pg_first_valid_ipv4)
  if [ -n "$DNS1" ]; then
    ANY_NAT=1
    nat4 -N PGNAT 2>/dev/null
    # DNS normally uses UDP, but large responses and truncated replies fall back to TCP.
    # Redirect both transports; otherwise dns_block/custom_dns can appear to work for
    # ordinary lookups while TCP DNS silently escapes the selected resolver.
    nat4 -A PGNAT -p udp --dport 53 -j DNAT --to-destination "$DNS1" && \
    nat4 -A PGNAT -p tcp --dport 53 -j DNAT --to-destination "$DNS1" && \
      pg_log "dns: redirect udp+tcp/53 -> $DNS1"
  fi
fi
# 外部 VPN 检测已在 DNS/NAT 规则创建前完成。

# 全局 DNS 替换：强制接管 udp+tcp 53 → [conf:global_dns] 第一台
if [ "$(pg_get global_dns 0)" = "1" ] && [ "$_PG_VPN_INTERCEPTION_BLOCKED" = "0" ] && [ "$(pg_get vpn_mode direct)" != "tun" ] && [ -z "$DNS_FWD" ]; then
  GDIP=$(pg_conf global_dns | pg_first_valid_ipv4)
  if [ -n "$GDIP" ]; then
    ANY_NAT=1
    nat4 -N PGNAT 2>/dev/null
    nat4 -A PGNAT -p udp --dport 53 -j DNAT --to-destination "$GDIP"
    nat4 -A PGNAT -p tcp --dport 53 -j DNAT --to-destination "$GDIP"
    pg_log "dns: global_dns force udp+tcp/53 -> $GDIP"
  fi
fi
# 透明代理：[conf:transparent_proxy] proxy_ip/proxy_port → TCP 80/443 DNAT
# proxy_autoswitch=1 时仅在 Wi-Fi 默认路由下生效（移动网络直连）
if [ "$(pg_get transparent_proxy 0)" = "1" ] && [ "$_PG_VPN_INTERCEPTION_BLOCKED" = "0" ] && [ "$(pg_get vpn_mode direct)" != "tun" ]; then
  TPIP=$(pg_conf transparent_proxy | grep -m1 '^proxy_ip=' | cut -d= -f2- | tr -d ' ')
  TPPORT=$(pg_conf transparent_proxy | grep -m1 '^proxy_port=' | cut -d= -f2- | tr -d ' ')
  TPOK=1
  if [ "$(pg_get proxy_autoswitch 0)" = "1" ]; then
    # 真机 default 行形如 "default via 1.2.3.4 dev wlan0 proto dhcp metric 600"
    # 不能取 $NF（是 metric），要解析 dev 字段
    DEFIF=$(ip route 2>/dev/null | grep -m1 '^default' | sed -n 's/^default.* dev \([^ ]*\).*/\1/p')
    case "$DEFIF" in
      wlan*|eth*) : ;;
      *) TPOK=0; pg_log "proxy: autoswitch - not on wifi/eth (${DEFIF:-no-default-route}), direct" ;;
    esac
  fi
  if [ "$TPOK" = "1" ] && [ -n "$TPIP" ] && [ -n "$TPPORT" ]; then
    ANY_NAT=1
    nat4 -N PGNAT 2>/dev/null
    nat4 -A PGNAT -p tcp --dport 80 -j DNAT --to-destination "$TPIP:$TPPORT" && \
    nat4 -A PGNAT -p tcp --dport 443 -j DNAT --to-destination "$TPIP:$TPPORT" && \
      pg_log "proxy: transparent tcp 80/443 -> $TPIP:$TPPORT"
  elif [ "$TPOK" = "1" ]; then
    pg_log "proxy: transparent_proxy on but no proxy_ip/proxy_port set"
  fi
fi
if [ "$ANY_NAT" = "1" ]; then
  nat4 -A PGNAT -j RETURN 2>/dev/null
  # Preserve the result of the firewall queue flush: a failed flush empties its
  # queue during fallback, so calling fw_flush again would lose the failure signal.
  _DNS_FW_FLUSH_OK=1
  fw_flush 2>/dev/null || _DNS_FW_FLUSH_OK=0
  # Do not activate the DNS/proxy hook unless both the preceding firewall
  # queues and this NAT queue committed successfully.
  if [ "$_DNS_FW_FLUSH_OK" = "1" ] && nat_flush; then
    if nat4 -I OUTPUT -j PGNAT && { [ "$DNS_AGH_IPV6" != "1" ] || nat6 -I OUTPUT -j PGNAT; }; then
      pg_log "dns/proxy: PGNAT committed and OUTPUT hook installed$( [ "$DNS_AGH_IPV6" = "1" ] && printf ' (IPv4+IPv6)' )"
    else
      # A failed hook install must not leave a populated orphan chain behind:
      # remove any duplicate jump that may have survived a partial/older apply,
      # then clear/delete only FX-owned PGNAT. Never touch unrelated NAT chains.
      while iptables $FWWAIT -t nat -D OUTPUT -j PGNAT 2>/dev/null; do :; done
      while ip6tables $FWWAIT -t nat -D OUTPUT -j PGNAT 2>/dev/null; do :; done
      if ip6tables $FWWAIT -t nat -F PGNAT 2>/dev/null && ip6tables $FWWAIT -t nat -X PGNAT 2>/dev/null; then
        pg_log "dns/proxy: IPv6 orphan PGNAT chain removed after hook failure"
      else
        pg_log "dns/proxy: IPv6 PGNAT cleanup incomplete; retained for next apply recovery"
      fi
      if iptables $FWWAIT -t nat -F PGNAT 2>/dev/null && iptables $FWWAIT -t nat -X PGNAT 2>/dev/null; then
        pg_log "dns/proxy: OUTPUT hook install failed; orphan PGNAT chain removed"
      else
        pg_log "dns/proxy: OUTPUT hook install failed; PGNAT cleanup incomplete, retained for next apply recovery"
      fi
      if [ "$DNS_AGH_ACTIVE" = "1" ]; then sh "$MODDIR/scripts/fxdns.sh" stop "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || :; fi
      pg_fail dns "PGNAT 规则已提交但 OUTPUT 跳转安装失败；已尝试清理孤立链，透明 DNS/代理未启用"
    fi
  else
    # Do not attach a partially populated chain after either firewall or NAT
    # commit failure. Clean the unhooked chain now instead of relying only on
    # a future apply to remove partial per-rule fallback commits.
    while iptables $FWWAIT -t nat -D OUTPUT -j PGNAT 2>/dev/null; do :; done
    while ip6tables $FWWAIT -t nat -D OUTPUT -j PGNAT 2>/dev/null; do :; done
    if ip6tables $FWWAIT -t nat -F PGNAT 2>/dev/null && ip6tables $FWWAIT -t nat -X PGNAT 2>/dev/null; then
      pg_log "dns/proxy: IPv6 unhooked PGNAT chain removed after commit failure"
    else
      pg_log "dns/proxy: IPv6 PGNAT cleanup incomplete; retained for next apply recovery"
    fi
    if iptables $FWWAIT -t nat -F PGNAT 2>/dev/null && iptables $FWWAIT -t nat -X PGNAT 2>/dev/null; then
      pg_log "dns/proxy: commit failed; unhooked PGNAT chain removed"
    else
      pg_log "dns/proxy: commit failed; PGNAT cleanup incomplete, retained for next apply recovery"
    fi
    if [ "$DNS_AGH_ACTIVE" = "1" ]; then sh "$MODDIR/scripts/fxdns.sh" stop "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || :; fi
    pg_fail dns "防火墙或 PGNAT 提交失败；已跳过 OUTPUT 接管并尝试清理孤立链，避免部分 DNS/代理规则生效"
  fi
fi

# ---------- 2c. VPN 透明代理（nat PGVPN + filter PGKS/PGBLK6）----------
# 架构（v1.10.5 改造，真机 1.14.3 实测）：
#   - 入站必须是 sing-box 的 redirect 类型：iptables REDIRECT 会把原始目的地址留在
#     conntrack 里，仅 redirect 入站会通过 SO_ORIGINAL_DST 取回它。
#     原先用 mixed（HTTP/SOCKS 协议入站）接 REDIRECT → 内核读不懂原始目的地址，
#     握手直接失败（实测 curl http://example.com → 400，日志
#     "inbound/mixed[in]: connection closed: read http request: EOF"）。
#   - 内核自身出站必须最先 RETURN（uid 0），否则它的上游连接被自己再 REDIRECT 一次 → 回环。
#   - vpn_mode=direct 是默认值且语义是「不接管」：本段必须一条接管规则都不建，
#     并且要能清掉上一次代理模式残留（幂等），核心没跑也不能因此断网。
#   nat PGVPN   : 核心自身/回环/本地端口豁免 → DNS 劫持 → LAN/CN 直连
#                 → 分应用(bypass/proxy) → 其余 TCP REDIRECT 到 local_port
#   filter PGKS : QUIC 防漏(udp/443) / udp_block / killswitch
#   nat PGVPN6 / filter PGBLK6 : ipv6 开关（走代理 / 全断防漏）
VPN_MODE=$(pg_get vpn_mode direct)
# Root-managed sing-box TUN cannot safely stack with an active/uncertain Android VPN.
# Fail closed before core startup and let direct cleanup remove stale FX interception.
if [ "$VPN_MODE" = "tun" ] && { [ "$_PG_VPN_INTERCEPTION_BLOCKED" = "1" ] || [ -n "$_PG_EXT_VPN_IF" ]; }; then
  pg_fail vpn "TUN 模式不能与已检测到/状态不明的外部 Android VPN 叠加；已回退直连以保护联网"
  pg_log "vpn: refusing TUN mode while an external VPN is active or uncertain"
  VPN_MODE=direct
fi
# VPN coexistence guard for the module's own transparent VPN. The detector runs before PGNAT above.
if [ "$_PG_VPN_INTERCEPTION_BLOCKED" = "1" ] && [ "$VPN_MODE" != "direct" ] && [ "$VPN_EXTERNAL_COMPAT" != "1" ]; then
  if [ "$_PG_EXT_VPN_PROBE_UNKNOWN" = "1" ]; then
    pg_log "vpn: external tunnel state unknown; bypassing PG VPN REDIRECT to avoid a possible VPN conflict"
  else
    pg_log "vpn: detected external tunnel $_PG_EXT_VPN_IF; bypassing PG VPN REDIRECT to avoid VPN conflict"
  fi
  VPN_MODE=direct
elif [ "$_PG_VPN_INTERCEPTION_BLOCKED" = "1" ] && [ "$VPN_MODE" != "direct" ] && [ "$VPN_EXTERNAL_COMPAT" = "1" ] && [ -z "$VPN_EXTERNAL_UID" ]; then
  pg_log "vpn: overlay requested but external VPN owner UID is unavailable (including inconclusive interface probe); fail-safe pause of PGVPN to avoid redirecting an outer tunnel into itself"
  VPN_MODE=direct
elif [ -n "$_PG_EXT_VPN_IF" ] && [ "$VPN_MODE" != "direct" ] && [ "$VPN_EXTERNAL_COMPAT" = "1" ] && [ "$_PG_EXT_VPN_ROUTE_OK" != "1" ]; then
  pg_log "vpn: explicit outer-tunnel outbound/DNS binding not verified; forcing safe direct mode instead of allowing FX node upstream to escape outside the outer tunnel"
  VPN_MODE=direct
elif [ -n "$_PG_EXT_VPN_IF" ] && [ "$VPN_MODE" != "direct" ] && [ "$VPN_EXTERNAL_COMPAT" = "1" ]; then
  pg_log "vpn: automatic guarded overlay allowed; external VPN UID is exempted from PGVPN, generic PGNAT DNS/transparent hooks remain disabled"
fi
VPN_ON=0
VPN_LP=""
# 读 [conf:vpn] local_port（与 vpncore 生成配置用的同一端口；REDIRECT --to-ports 只吃端口）
VPN_CFG_LP=$(pg_conf vpn 2>/dev/null | grep -m1 '^local_port=' | cut -d= -f2- | tr -d ' ')
case "$VPN_CFG_LP" in *:*) VPN_CFG_LP=${VPN_CFG_LP##*:} ;; esac
case "$VPN_CFG_LP" in ''|*[!0-9]*) VPN_CFG_LP=7890 ;; esac
# 模块自身/管理器 uid 豁免（防自代理：这些进程的流量不该进核心）
# KernelSU 管理器包名固定；Magisk/APatch 无独立常驻管理器 → 解析不到就跳过。
VPN_MOD_UIDS=""
for _mpkg in me.weishu.kernelsu com.topjohnwu.magisk; do
  _muid=$(stat -c %u "/data/data/$_mpkg" 2>/dev/null)
  case "$_muid" in ''|*[!0-9]*|0) ;; *) VPN_MOD_UIDS="$VPN_MOD_UIDS $_muid" ;; esac
done
if [ -n "$_PG_EXT_VPN_IF" ] && [ "$VPN_EXTERNAL_COMPAT" = "1" ] && [ -n "$VPN_EXTERNAL_UID" ]; then
  VPN_MOD_UIDS="$VPN_MOD_UIDS $VPN_EXTERNAL_UID"
  pg_log "vpn: external VPN app UID $VPN_EXTERNAL_UID is bypassed from PGVPN/PGVPN6 to prevent tunnel recursion"
fi
if [ "$VPN_MODE" = "direct" ]; then
  # 直连模式：零接管。显式停核心上游用不到的链（下面统一清理段已做），
  # 这里只记录语义，不建任何 PGVPN/PGKS 规则。
  pg_log "vpn: direct mode — 不接管任何流量（零 REDIRECT/DNAT 规则）"
fi
if [ "$VPN_MODE" != "direct" ]; then
  # vpn_node 可能是完整 URI（vless://uuid@host:443?...#name）或旧式 proto:host:port。
  # 这里统一归一成 proto:host:port（剥掉 //、userinfo、query、fragment），
  # 供 PGVPN REDIRECT 判定、PGKS 放行节点 host、日志展示使用。
  VPN_NODE=$(pg_get vpn_node "")
  # vmess URI 的 host/port 藏在 base64 JSON 里，先解码成 vless 式的 host:port
  case "$VPN_NODE" in
    vmess://*|vmess:*)
      _vm=$(printf '%s' "$VPN_NODE" | sed -e 's#^.*://##' -e 's/#.*$//' | base64 -d 2>/dev/null)
      if [ -n "$_vm" ]; then
        _va=$(printf '%s' "$_vm" | grep -o '"add"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
        _vp=$(printf '%s' "$_vm" | grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]*' | head -1 | grep -o '[0-9]*')
        if [ -n "$_va" ] && [ -n "$_vp" ]; then VPN_NODE="vmess:$_va:$_vp"; fi
      fi
      ;;
  esac
  # 归一成 host:port（剥 fragment/query/协议前缀/userinfo），VPN_PORT 只在这里赋值
  VPN_NODE=$(printf '%s' "$VPN_NODE" | sed -e 's/#.*$//' -e 's/?.*$//')
  case "$VPN_NODE" in
    *://*) VPN_NODE=${VPN_NODE#*://} ;;
  esac
  VPN_NODE=$(printf '%s' "$VPN_NODE" | sed -e 's#^[^@/]*@##')
  # 归一成 host + port：最后一段是数字才算端口（旧式 proto:host:port / 纯 host:port / URI 均可）
  # 注意：端口必须先单独取出再剥 proto，否则 proto:host:port 剥掉 proto 后端口会一起丢失
  VPN_PORT=''
  VPN_LAST=${VPN_NODE##*:}
  case "$VPN_LAST" in
    ''|*[!0-9]*) ;;
    *)
      VPN_PORT=$VPN_LAST
      VPN_NODE=${VPN_NODE%:*}
      # 剩下可能是 proto:host（旧式）或 host（URI 已剥过）；[v6] 形式不动
      case "$VPN_NODE" in
        \[*\]*) : ;;
        *:*) VPN_NODE=${VPN_NODE#*:} ;;
      esac
      ;;
  esac
  case "$VPN_NODE" in
    \[*\]*) VPN_HOST=$VPN_NODE ;;
    *) VPN_HOST=${VPN_NODE%%:*}; [ -n "$VPN_HOST" ] || VPN_HOST=${VPN_NODE:-proxy} ;;
  esac
  VPN_LIP=$(pg_conf vpn | grep -m1 '^local_ip=' | cut -d= -f2- | tr -d ' '); VPN_LIP=${VPN_LIP:-127.0.0.1}
  case "$VPN_LIP" in *:*) VPN_LIP=${VPN_LIP%%:*} ;; esac
  [ -n "$VPN_LIP" ] || VPN_LIP=127.0.0.1
  VPN_LP=$(pg_conf vpn | grep -m1 '^local_port=' | cut -d= -f2- | tr -d ' '); VPN_LP=${VPN_LP:-7890}
  # local_port 允许写成 127.0.0.1:7890 / :7890 / 7890，统一剥成纯端口（REDIRECT --to-ports 只接受端口）
  case "$VPN_LP" in *:*) VPN_LP=${VPN_LP##*:} ;; esac
  case "$VPN_LP" in ''|*[!0-9]*) VPN_LP=7890 ;; esac
  # 远端 DNS（vpn_dns_hijack / vpn_hide 都用：代理域名解析必须走远端，防 DNS 泄露所在地）
  VPN_RDNS=$(pg_conf vpn | grep -m1 '^remote_dns=' | cut -d= -f2- | tr -d ' '); VPN_RDNS=${VPN_RDNS:-1.1.1.1}
  # 本地客户端端口探测：netstat LISTEN → curl 连接探测 → 无工具则假定监听
  vpn_port_open() {
    # Android 12+ 的 toybox 已移除 netstat（官方替代是 ss），必须先判存在再调用
    if pg_have netstat && netstat -tln 2>/dev/null | grep -q ":$2[[:space:]].*LISTEN"; then return 0; fi
    if pg_have ss && ss -tln 2>/dev/null | grep -q ":$2[[:space:]]"; then return 0; fi
    if pg_have curl; then
      # 只有 curl 成功完成探测才接受；52/56 等“连接后断开/接收失败”不能当作端口就绪。
      # 此探测仍是 HTTP 层探测，非 HTTP 代理端口应优先由 netstat/ss 的 LISTEN 结果确认。
      curl -s --max-time 2 -o /dev/null "http://$1:$2" 2>/dev/null
      _vpn_curl_rc=$?
      if [ "$_vpn_curl_rc" -eq 0 ]; then return 0; fi
      pg_log "vpn: curl 端口探测失败 rc=$_vpn_curl_rc ($1:$2)"
      return 1
    fi
    # 无可用的监听检测工具时必须失败关闭，不能假定端口已监听后安装 REDIRECT。
    pg_log "vpn: 无 netstat/ss/curl，无法确认 $1:$2 正在监听；取消本次流量接管"
    return 1
  }
  if [ -z "$VPN_PORT" ]; then
    pg_fail vpn "未选择节点（在 VPN 页点选一个节点后重新应用）"
    VPN_LP=""
  elif ! vpn_port_open "$VPN_LIP" "$VPN_LP"; then
    # 本地端口无监听：vpn_core=1 时自动下载 sing-box 并按节点生成配置启动，
    # 实现「导入订阅即可用」，无需用户自己跑客户端。失败才报错。
    if [ "$(pg_get vpn_core 0)" = "1" ]; then
      pg_log "vpn: 本地端口 $VPN_LIP:$VPN_LP 无监听，尝试自动启动代理核心"
      if vpn_core_ensure; then
        VPN_ON=1
      else
        pg_fail vpn "代理核心自动启动失败（详见 apply.log / $(vpncore_log)）"
        VPN_LP=""
      fi
    else
      pg_fail vpn "本地端口 $VPN_LIP:$VPN_LP 无监听 — 先启动 sing-box/Clash 核心（或开启 VPN 配置里的『自动核心』）"
      VPN_LP=""
    fi
  else
    VPN_ON=1
    # 端口已监听：启用模块托管核心时，ensure 失败不能被忽略。
    # 否则端口可能属于错误/残留进程，后续仍会安装 REDIRECT，造成代理流量黑洞。
    if [ "$(pg_get vpn_core 0)" = "1" ]; then
      if vpn_core_ensure; then
        pg_log "vpn: existing listener passed managed-core verification"
      else
        pg_fail vpn "代理核心就绪校验失败；取消本次流量接管以避免断网"
        VPN_ON=0
        VPN_LP=""
      fi
    fi
  fi
fi
if [ "$VPN_ON" = "1" ] && [ "$VPN_MODE" != "tun" ]; then
  mkdir -p "$PG/cache" 2>/dev/null
  # 幂等：重复 apply 不能叠加规则。链在更上面的清理段已删，这里再兜一次底，
  # 保证即使在同一次 apply 里重复进入本段也不会出现重复 RETURN/REDIRECT。
  nat4 -F PGVPN 2>/dev/null
  nat4 -N PGVPN 2>/dev/null
  # (a) 核心自身 + 回环 + 本地端口豁免（必须排在所有 REDIRECT 之前，否则回环）
  #     真机实测：核心以 root 运行，其上游连接（去节点）若被再次 REDIRECT 到自己的
  #     监听端口，会立刻回环/超时——先 `-m owner --uid-owner 0 -j RETURN` 才通。
  #     **注意**：这里绝不能用旧代码的 `-m owner ! --uid-owner 0:9999 -j RETURN`——
  #     其语义是「非 0-9999 的 uid 全部 RETURN」，而普通应用 uid 恰好 >=10000，
  #     等于把要代理的应用全部放直连（实测：该写法下 uid2000 仍会被重定向，因为
  #     uid2000 落在 0:9999 内不属于"非 0-9999"；而 uid>=10000 的应用反而全部漏掉）。
  nat4 -A PGVPN -m owner --uid-owner 0 -j RETURN
  nat4 -A PGVPN -d 127.0.0.0/8 -j RETURN
  nat4 -A PGVPN -p tcp --dport "$VPN_LP" -j RETURN
  # 模块自身/管理器 uid 豁免（解析不到则跳过，不影响主流程）
  for _mu in $VPN_MOD_UIDS; do
    nat4 -A PGVPN -m owner --uid-owner "$_mu" -j RETURN 2>/dev/null
  done
  # (b) DNS over TCP only. REDIRECT is a TCP transparent-proxy mechanism here;
  # sending UDP/53 to the redirect inbound's port feeds datagrams to a TCP listener
  # and can break DNS for every app (often misdiagnosed as total internet loss).
  # UDP DNS must remain on the system resolver until a real TProxy/DNS inbound is
  # configured and runtime-tested. Do not claim UDP hijack support in this path.
  if [ "$(pg_get vpn_dns_hijack 0)" = "1" ]; then
    nat4 -A PGVPN -p tcp --dport 53 -j REDIRECT --to-ports "$VPN_LP"
    pg_log "vpn: DNS TCP/53 -> redirect :$VPN_LP; UDP/53 left untouched (no UDP transparent inbound)"
  fi
  # (c) LAN 直连（[list:vpn_direct] 网段）
  VPN_LAN_N=0
  if [ "$(pg_get vpn_lan_direct 0)" = "1" ]; then
    for cidr in $(pg_list_enabled vpn_direct); do
      case "$cidr" in
        *[!0-9./]*) continue ;;
        *.*.*|*/*) nat4 -A PGVPN -d "$cidr" -j RETURN 2>/dev/null && VPN_LAN_N=$((VPN_LAN_N+1)) ;;
      esac
    done
    [ "$VPN_LAN_N" -gt 0 ] && pg_log "vpn: lan direct x$VPN_LAN_N"
  fi
  # (d) CN 直连（rule 模式 + cn_direct=1）：chnroute 全量 RETURN，
  #     优先 iptables-restore 批量（数千条一次 syscall），无则逐条(截断3000)
  VPN_CN_N=0
  if [ "$VPN_MODE" = "rule" ] && [ "$(pg_get vpn_cn_direct 0)" = "1" ]; then
    if [ ! -s "$PG/chnroute" ]; then
      command -v vpn_chn_download >/dev/null 2>&1 || . "$MODDIR/scripts/vpnsub.sh" 2>/dev/null
      command -v vpn_chn_download >/dev/null 2>&1 && vpn_chn_download 2>>"$PG/apply.log"
    fi
    if [ -s "$PG/chnroute" ]; then
      VPN_CN_TOTAL=$(grep -cE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' "$PG/chnroute" | tr -d ' ')
      # 先把前面缓冲的豁免/DNS/LAN 规则落地（nat4 现在走批量队列），
      # 否则下面 restore 追加的 CN RETURN 会插在它们之前 → 顺序反了。
      nat_flush
      if pg_have iptables-restore; then
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' "$PG/chnroute" \
          | sed 's/^/-A PGVPN -d /;s/$/ -j RETURN/' > "$PG/cache/chn.nat"
        if { echo '*nat'; cat "$PG/cache/chn.nat"; echo 'COMMIT'; } \
           | iptables-restore -n 2>>"$PG/apply.log"; then
          VPN_CN_N=$VPN_CN_TOTAL
          pg_log "vpn: cn direct x$VPN_CN_N (iptables-restore)"
        else
          pg_fail vpn "iptables-restore 批量写入 nat 失败，降级逐条"
        fi
      fi
      if [ "$VPN_CN_N" -eq 0 ]; then
        head -3000 "$PG/chnroute" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' > "$PG/cache/chn.cap"
        while IFS= read -r cidr; do
          nat4 -A PGVPN -d "$cidr" -j RETURN 2>/dev/null
        done < "$PG/cache/chn.cap"
        VPN_CN_N=$(wc -l < "$PG/cache/chn.cap" | tr -d ' ')
        if [ "$VPN_CN_TOTAL" -gt 3000 ]; then
          pg_fail vpn "无 iptables-restore, chnroute $VPN_CN_TOTAL 条仅加载 $VPN_CN_N 条(慢且可能漏)"
        fi
        pg_log "vpn: cn direct x$VPN_CN_N (逐条降级)"
      fi
    else
      pg_fail vpn "chnroute 分流表不存在且下载失败（可在 VPN 页手动更新或检查 chnroute_url）"
    fi
  fi
  # (e) 分应用（[list:vpn_app] 包名 → uid）
  if [ "$(pg_get vpn_app_proxy 0)" = "1" ]; then
    VPN_APPMODE=$(pg_conf vpn | grep -m1 '^app_mode=' | cut -d= -f2- | tr -d ' '); VPN_APPMODE=${VPN_APPMODE:-bypass}
    VPN_UIDS=""
    for pkg in $(pg_list_enabled vpn_app); do
      AU=$(stat -c %u "/data/data/$pkg" 2>/dev/null)
      if [ -n "$AU" ] && [ "$AU" != "0" ]; then VPN_UIDS="$VPN_UIDS $AU"; fi
    done
    if [ -z "$VPN_UIDS" ]; then
      pg_fail vpn "分应用开启但列表为空或无法解析 uid（检查 [list:vpn_app] 包名）"
    elif [ "$VPN_APPMODE" = "only" ] || [ "$VPN_APPMODE" = "proxy" ]; then
      # only 模式：仅列表内应用走代理，其余直连
      for u in $VPN_UIDS; do
        nat4 -A PGVPN -m owner --uid-owner "$u" -p tcp -j REDIRECT --to-ports "$VPN_LP"
      done
      nat4 -A PGVPN -j RETURN
      pg_log "vpn: app proxy-only uids:$VPN_UIDS"
    else
      # bypass 模式：列表内应用直连，其余走代理
      for u in $VPN_UIDS; do
        nat4 -A PGVPN -m owner --uid-owner "$u" -j RETURN
      done
      pg_log "vpn: app bypass uids:$VPN_UIDS"
    fi
  fi
  # (f) 兜底：其余 TCP 全部进本地核心；挂链
  #     目标端口必须是 redirect 入站的监听端口（[conf:vpn] local_port），
  #     不是 mixed 端口——mixed 不认 SO_ORIGINAL_DST，REDIRECT 送进去必然 400。
  nat4 -A PGVPN -p tcp -j REDIRECT --to-ports "$VPN_LP"
  nat4 -A PGVPN -j RETURN
  # Never attach the traffic hook if the queued chain rules did not commit.
  # A partial PGVPN chain must not be advertised as active; killswitch policy below
  # remains independent and may still fail closed when the user explicitly enabled it.
  if fw_flush 2>/dev/null && nat_flush 2>/dev/null && nat4 -I OUTPUT -j PGVPN; then
    VPN_NAT_READY=1
    # VPN_PROTO 在 vmess 分支前未定义，这里从原始 URI 兜底取协议名（仅用于日志展示）
    VPN_PROTO=$(printf '%s' "$(pg_get vpn_node "")" | sed -n 's#^\([a-z0-9]*\)://.*#\1#p')
    [ -n "$VPN_PROTO" ] || VPN_PROTO=$(printf '%s' "$(pg_get vpn_node "")" | cut -d: -f1)
    pg_log "vpn: PGVPN up (mode=$VPN_MODE, redirect=:$VPN_LP, node=$VPN_PROTO:$VPN_HOST:$VPN_PORT)"
  else
    VPN_NAT_READY=0
    pg_fail vpn "PGVPN 规则提交或 OUTPUT 挂载失败；未启用透明代理接管"
  fi
  # (g) PGKS 防漏链：放行本地端口/已建连接/节点出口 → QUIC 拦截 → udp_block → killswitch
  #   uid 口径：应用 uid 是「非 0-9999」（普通应用 10000-19999，多用户/工作资料是
  #   >=1000000）。旧代码写死 10000:19999 会漏掉多用户下的应用 —— 这里统一用取反。
  fw4 -F PGKS 2>/dev/null
  fw4 -N PGKS 2>/dev/null
  fw4 -A PGKS -o lo -j ACCEPT
  fw4 -A PGKS -d 127.0.0.1 -p tcp --dport "$VPN_LP" -j ACCEPT
  fw4 -A PGKS -d 127.0.0.1 -p udp --dport "$VPN_LP" -j ACCEPT
  fw4 -A PGKS -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  if echo "$VPN_HOST" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    fw4 -A PGKS -d "$VPN_HOST" -j ACCEPT
  else
    pg_log "vpn: node host 为域名, killswitch 放行依赖 uid 排除(客户端需以 root 运行)"
  fi
  # QUIC/UDP filters can break a third-party VPN's outer tunnel, so disable them in explicit overlay mode.
  if [ -z "$_PG_EXT_VPN_IF" ] || [ "$VPN_EXTERNAL_COMPAT" != "1" ]; then
    fw4 -A PGKS -m owner ! --uid-owner 0:9999 -p udp --dport 443 -j REJECT
    # UDP 全断（客户端不支持 UDP 转发时；被劫持的 DNS 已在前面按本地端口放行）
    if [ "$(pg_get vpn_udp_block 0)" = "1" ]; then
      fw4 -A PGKS -m owner ! --uid-owner 0:9999 -p udp -j REJECT
      pg_log "vpn: udp blocked for apps"
    fi
  else
    pg_log "vpn: overlay mode skips QUIC/UDP block to preserve the external VPN tunnel"
  fi
  if [ "$(pg_get vpn_killswitch 0)" = "1" ] && { [ -z "$_PG_EXT_VPN_IF" ] || [ "$VPN_EXTERNAL_COMPAT" != "1" ]; }; then
    if [ "$(pg_get vpn_lan_direct 0)" = "1" ]; then
      for cidr in $(pg_list_enabled vpn_direct); do
        case "$cidr" in
          *[!0-9./]*) continue ;;
          *.*.*|*/*) fw4 -A PGKS -d "$cidr" -j ACCEPT 2>/dev/null ;;
        esac
      done
    fi
    if [ "$VPN_MODE" = "rule" ] && [ "$(pg_get vpn_cn_direct 0)" = "1" ] && [ "$VPN_CN_N" -gt 0 ]; then
      # 先提交 PGKS 已缓冲的前置规则（accpet/uid 等），否则下面 restore 追加的
      # CN 放行规则会插到「还没落地的规则」之前，顺序全乱。
      fw_flush 2>/dev/null
      if pg_have iptables-restore; then
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' "$PG/chnroute" \
          | sed 's/^/-A PGKS -d /;s/$/ -j ACCEPT/' > "$PG/cache/chn.fw"
        if { echo '*filter'; cat "$PG/cache/chn.fw"; echo 'COMMIT'; } \
           | iptables-restore -n 2>>"$PG/apply.log"; then
          pg_log "vpn: killswitch cn allow x$VPN_CN_N (iptables-restore)"
        else
          pg_fail vpn "iptables-restore 批量写入 filter 失败"
        fi
      else
        pg_fail vpn "killswitch+cn_direct 但无 iptables-restore: CN 放行无法批量(killswitch 生效但 CN 直连会被误断)"
      fi
    fi
    fw4 -A PGKS -m owner ! --uid-owner 0:9999 -j REJECT
    pg_log "vpn: killswitch on (app egress limited to vpn/lan/cn)"
  fi
  fw4 -A PGKS -j RETURN
  fw_flush 2>/dev/null; nat_flush 2>/dev/null
  fw4 -I OUTPUT -j PGKS
  # (h) IPv6：走代理(镜像 REDIRECT) 或 全断防漏
  if [ "$(pg_get vpn_ipv6 0)" = "1" ]; then
    nat6 -F PGVPN6 2>/dev/null
    nat6 -N PGVPN6 2>/dev/null
    # 与 v4 同一套豁免口径（核心自身/回环/本地端口），否则 v6 侧同样回环
    nat6 -A PGVPN6 -m owner --uid-owner 0 -j RETURN
    nat6 -A PGVPN6 -d ::1/128 -j RETURN
    nat6 -A PGVPN6 -p tcp --dport "$VPN_LP" -j RETURN
    for _mu in $VPN_MOD_UIDS; do
      nat6 -A PGVPN6 -m owner --uid-owner "$_mu" -j RETURN 2>/dev/null
    done
    # Same constraint as IPv4: never REDIRECT UDP/53 into the TCP redirect inbound.
    if [ "$(pg_get vpn_dns_hijack 0)" = "1" ]; then
      nat6 -A PGVPN6 -p tcp --dport 53 -j REDIRECT --to-ports "$VPN_LP"
    fi
    nat6 -A PGVPN6 -p tcp -j REDIRECT --to-ports "$VPN_LP"
    nat6 -A PGVPN6 -j RETURN
    if fw_flush 2>/dev/null && nat_flush 2>/dev/null && nat6 -I OUTPUT -j PGVPN6; then
      pg_log "vpn: ipv6 -> proxy (PGVPN6, 客户端需监听 ::1)"
    else
      pg_fail vpn "PGVPN6 规则提交或 OUTPUT 挂载失败；IPv6 代理接管未启用"
    fi
  elif [ -n "$_PG_EXT_VPN_IF" ] && [ "$VPN_EXTERNAL_COMPAT" = "1" ]; then
    pg_log "vpn: overlay mode skips IPv6 fail-closed filter to avoid breaking the external VPN tunnel; IPv6 leak protection is reduced"
  else
    fw6 -F PGBLK6 2>/dev/null
    fw6 -N PGBLK6 2>/dev/null
    fw6 -A PGBLK6 -o lo -j ACCEPT
    fw6 -A PGBLK6 -d fe80::/10 -j ACCEPT
    fw6 -A PGBLK6 -m owner ! --uid-owner 0:9999 -j REJECT
    fw6 -A PGBLK6 -j RETURN
    if fw_flush 2>/dev/null && fw6 -I OUTPUT -j PGBLK6; then
      pg_log "vpn: ipv6 blocked for apps (leak guard)"
    else
      ip6tables $FWWAIT -D OUTPUT -j PGBLK6 2>/dev/null || true
      pg_fail vpn "PGBLK6 规则提交或 OUTPUT 挂载失败；IPv6 防漏保护未启用"
    fi
  fi
  # ---------- vpn_hide：隐藏 VPN/节点（对外伪装成本机直连） ----------
  # 目标：对端(网站/服务/检测方)完全看不到代理痕迹，其观测到的"本机 IP"就是节点出口 IP。
  # 三层协同：nat 层(PGVPN 全接管+DNS 全劫持) / filter 层(PGKS 断 QUIC·STUN·本地痕迹端口) /
  #           LSPosed 层(MainHook vpnHide 隐藏 tun 网卡/TRANSPORT_VPN/代理端口)。
  # 隐藏强度（[conf:vpn] hide_level）：L0 仅 LSPosed 痕迹；L1(默认)+DNS 全劫持/防漏/TCP 指纹；
  #                                   L2 +ICMP/UDP 全禁+DoT 禁+MSS clamp（4 个 hide_* 键细控）。
  # 注：hide_* 在 [conf:vpn] 段内，须用 pg_conf vpn 读取（pg_get 只扫顶层键）。
  # vpn_hide_conf() 已在文件顶层定义（Sysctl 段也要用），此处不再重复定义。
  if [ "$(pg_get vpn_hide 0)" = "1" ] && { [ -z "$_PG_EXT_VPN_IF" ] || [ "$VPN_EXTERNAL_COMPAT" != "1" ]; }; then
    HIDE_FW=0
    HIDE_LEVEL=$(vpn_hide_conf hide_level); HIDE_LEVEL=${HIDE_LEVEL:-1}
    case "$HIDE_LEVEL" in 0|1|2) ;; *) HIDE_LEVEL=1 ;; esac
    # (1) DNS 全劫持：不经代理的域名(CN直连/LAN直连)也不能用明文 DNS 查询，
    #     否则 DNS 查询出口仍是本地运营商，暴露"人在节点所在地之外"。
    #     用 DNAT 到远端 DNS 而非 REDIRECT，避免应用看到 127.0.0.1 这种本地痕迹。
    if [ "$HIDE_LEVEL" != "0" ] && [ "$(pg_get vpn_dns_hijack 0)" != "1" ] && [ -n "$VPN_RDNS" ]; then
      nat4 -N PGHIDE 2>/dev/null
      nat4 -A PGHIDE -p udp --dport 53 -j DNAT --to-destination "$VPN_RDNS" 2>/dev/null
      nat4 -A PGHIDE -p tcp --dport 53 -j DNAT --to-destination "$VPN_RDNS" 2>/dev/null
      if fw_flush 2>/dev/null && nat_flush 2>/dev/null && nat4 -I OUTPUT -j PGHIDE; then
        pg_log "vpn_hide: dns 全劫持 -> $VPN_RDNS (DNAT，禁明文本地解析)"
      else
        # A failed/partial DNAT install must not leave a live hook or stale chain.
        iptables $FWWAIT -t nat -D OUTPUT -j PGHIDE 2>/dev/null || true
        ip6tables $FWWAIT -t nat -D OUTPUT -j PGHIDE 2>/dev/null || true
        iptables $FWWAIT -t nat -F PGHIDE 2>/dev/null || true
        iptables $FWWAIT -t nat -X PGHIDE 2>/dev/null || true
        pg_fail vpn_hide "PGHIDE DNS 规则提交或 OUTPUT 挂载失败；已尝试回滚 DNS 劫持链"
      fi
    fi
    # (2) QUIC/STUN/mDNS/SSDP/本地发现全断：这些是绕过代理直连、暴露真实地址的主要通道
    if [ "$HIDE_LEVEL" != "0" ]; then
    # Re-apply must rebuild, not append duplicate hide rules to a surviving chain.
    fw4 -F PGHKS 2>/dev/null; fw6 -F PGHKS 2>/dev/null
    fw4 -N PGHKS 2>/dev/null; fw6 -N PGHKS 2>/dev/null
    fw4 -A PGHKS -m owner ! --uid-owner 0:9999 -p udp --dport 443 -j REJECT
    fw6 -A PGHKS -m owner ! --uid-owner 0:9999 -p udp --dport 443 -j REJECT
    for p in 3478 3479 5349 19302 19303 19304 19005 19006; do
      fw4 -A PGHKS -p udp --dport $p -j REJECT
      fw6 -A PGHKS -p udp --dport $p -j REJECT
    done
    for p in 1900 5353 5355 137 138 139; do
      fw4 -A PGHKS -p udp --dport $p -j DROP
      fw6 -A PGHKS -p udp --dport $p -j DROP
    done
    # (3) 本地代理客户端痕迹端口封锁：代理客户端(7890/7891/7892/1080/1081/9090/9150 等)
    #     的监听端口被扫描/连接即暴露"本机跑着代理"。仅放行本模块 REDIRECT 目标端口。
    for p in 7890 7891 7892 7893 7894 1080 1081 1085 1086 1090 9090 9091 9150 3128 8080 8081 8082 20171; do
      [ "$p" = "$VPN_LP" ] && continue
      fw4 -A PGHKS -d 127.0.0.1 -p tcp --dport $p -j REJECT
      fw4 -A PGHKS -d 127.0.0.1 -p udp --dport $p -j REJECT
    done
    fw4 -A PGHKS -j RETURN
    fw6 -A PGHKS -j RETURN
    # Only report hide filtering as active when both IP-family queues committed and
    # both OUTPUT hooks were installed. A partial v4/v6 install is rolled back.
    if fw_flush 2>/dev/null && fw4 -I OUTPUT -j PGHKS && fw6 -I OUTPUT -j PGHKS; then
      HIDE_FW=1
      ANY_FW=1
      pg_log "vpn_hide: QUIC/STUN/mDNS/SSDP/本地痕迹端口已封锁 (PGHKS, IPv4+IPv6)"
    else
      iptables $FWWAIT -D OUTPUT -j PGHKS 2>/dev/null || true
      ip6tables $FWWAIT -D OUTPUT -j PGHKS 2>/dev/null || true
      pg_fail vpn_hide "PGHKS 规则提交或 IPv4/IPv6 OUTPUT 挂载失败；隐藏过滤未启用"
    fi
    fi
    # (4) IPv6：隐藏态下 IPv6 若直连会暴露与节点所在地不同的真实地址段 → 强制走代理或全断
    if [ "$HIDE_LEVEL" != "0" ] && [ "$(pg_get vpn_ipv6 0)" != "1" ]; then
      fw6 -N PGBLK6 2>/dev/null
      fw6 -A PGBLK6 -o lo -j ACCEPT
      fw6 -A PGBLK6 -d fe80::/10 -j ACCEPT
      fw6 -A PGBLK6 -m owner ! --uid-owner 0:9999 -j REJECT
      fw6 -A PGBLK6 -j RETURN
      if fw_flush 2>/dev/null && fw6 -I OUTPUT -j PGBLK6; then
        pg_log "vpn_hide: IPv6 强制全断(防真实 v6 地址段泄露)"
      else
        ip6tables $FWWAIT -D OUTPUT -j PGBLK6 2>/dev/null || true
        pg_fail vpn_hide "隐藏模式 PGBLK6 规则提交或 OUTPUT 挂载失败；IPv6 防泄漏未启用"
      fi
    fi
    # (5) TCP 指纹规范化：关掉 TCP 时间戳（L1 起，sysctl 段按隐藏态强制写入）。
    #     否则抓包方可见 timestamps/TSval 特征与普通手机不一致
    if [ "$HIDE_LEVEL" != "0" ]; then
      pg_log "vpn_hide: TCP 时间戳关闭(指纹规范化, L1)"
    fi
    # (6) 隐藏增强分级（[conf:vpn] hide_*，默认全 0 = L1 行为不变）
    if [ "$(vpn_hide_conf hide_icmp_block_all)" = "1" ]; then
      pg_log "vpn_hide: ICMP echo 全禁(L2，防 traceroute/存活探测暴露链路)"
    fi
    if [ "$(vpn_hide_conf hide_udp_block_all)" = "1" ]; then
      # 只留 DNS(经 PGHIDE 已 DNAT) 与本地回环；其余 UDP 全禁强制走 TCP
      # PGHKS 已在上方构建并以 RETURN 收尾；追加规则会落在 RETURN 之后，
      # 看起来配置成功但永远不会命中。插入链首才能真正启用 L2 UDP 阻断。
      # 注意：PGHKS 在 nat 之后命中，DNS udp/53 若已被 PGHIDE DNAT，
      # 目的端口仍为 53，但目标地址已改变；此规则仍会阻断普通应用 UDP，
      # 因此保留 DNS 的明确例外，避免 L2 自己把 DNS 一并断掉。
      fw4 -I PGHKS 1 -p udp -m owner ! --uid-owner 0:9999 -j REJECT
      fw6 -I PGHKS 1 -p udp -m owner ! --uid-owner 0:9999 -j REJECT 2>/dev/null
      fw4 -I PGHKS 1 -p udp --dport 53 -j RETURN
      fw6 -I PGHKS 1 -p udp --dport 53 -j RETURN 2>/dev/null
      pg_log "vpn_hide: UDP 全禁(强制 TCP, L2；DNS/回环按前置规则例外)"
    fi
    if [ "$(vpn_hide_conf hide_dot_block)" = "1" ]; then
      # PGHKS has a terminal RETURN from the common setup. Insert before it;
      # appending here would silently make these DoT rules ineffective.
      fw4 -I PGHKS 1 -p tcp --dport 853 -j REJECT
      fw6 -I PGHKS 1 -p tcp --dport 853 -j REJECT 2>/dev/null
      fw4 -I PGHKS 1 -p udp --dport 853 -j REJECT
      fw6 -I PGHKS 1 -p udp --dport 853 -j REJECT 2>/dev/null
      pg_log "vpn_hide: DoT(853) 已禁(L2，规则插入链首，避免终止 RETURN 后失效)"
    fi
    if [ "$(vpn_hide_conf hide_mtu_clamp)" = "1" ]; then
      # TCP MSS clamp 到 1380：节点链路 MTU 特征(如 1420/1500 异常)不外泄
      fw4 -t mangle -N PGMTU 2>/dev/null
      fw4 -t mangle -F PGMTU 2>/dev/null
      fw4 -t mangle -A PGMTU -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1380
      fw4 -t mangle -A PGMTU -j RETURN
      fw_flush 2>/dev/null
      fw4 -t mangle -I OUTPUT -j PGMTU
      pg_log "vpn_hide: TCP MSS clamp 1380(防节点 MTU 特征, L2)"
    fi
    # (7) 连通性兜底：DNS 劫持与痕迹端口封锁生效后，节点测速/订阅更新仍走本地端口，
    #     root 已豁免(PGHKS 只拦 10000:19999 与 127.0.0.1 目标端口，不影响 root)
    if [ "$HIDE_LEVEL" = "0" ]; then
      pg_log "vpn_hide: 强度L0：shell 层不发隐藏规则（仅 LSPosed 隐藏 tun/能力/代理痕迹）"
    else
      pg_log "vpn_hide: 隐藏规则已就绪(强度L$HIDE_LEVEL: DNS 全劫持+QUIC/STUN/痕迹端口封锁+v6 强制+TCP 指纹规范化)"
    fi
  elif [ "$(pg_get vpn_hide 0)" = "1" ] && [ -n "$_PG_EXT_VPN_IF" ] && [ "$VPN_EXTERNAL_COMPAT" = "1" ]; then
    pg_log "vpn_hide: suspended during external VPN overlay because DNS/UDP/IPv6 hiding rules can break the outer tunnel"
  fi
elif [ "$(pg_get vpn_killswitch 0)" = "1" ] && [ "$VPN_MODE" != "direct" ] && [ "$VPN_MODE" != "tun" ]; then
  # VPN 未生效但 killswitch=1 → fail-closed：断开应用外联防裸奔（修复节点/客户端后恢复）
  fw4 -F PGKS 2>/dev/null
  fw4 -N PGKS 2>/dev/null
  fw4 -A PGKS -o lo -j ACCEPT
  fw4 -A PGKS -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  fw4 -A PGKS -m owner ! --uid-owner 0:9999 -j REJECT
  fw4 -A PGKS -j RETURN
  fw_flush 2>/dev/null
  fw4 -I OUTPUT -j PGKS
  pg_fail vpn "killswitch fail-closed：VPN 未生效，应用外联已断开（选节点/启动客户端后重新应用）"
fi

# ---------- 2c-2. 直连模式零接管收尾 ----------
# 硬约束：vpn_mode=direct 语义 = 不接管任何流量。上面的通用清理段已经删掉了
# PGVPN/PGVPN6/PGKS/PGBLK6/PGHIDE/PGHKS/PGMTU 这些链，但为了「切到 direct 后幂等、
# 且核心没跑也不阻断联网」这一点可被独立验证，这里再做一次显式收尾：
#   - 确认 OUTPUT 上没有任何本模块的 nat 跳转（PGVPN/PGVPN6/PGNAT 之外的 PGHIDE 也清）
#   - 直接模式下即使 vpn_killswitch=1 也不 fail-closed（direct 是用户明确选择直连，
#     不是「代理配置坏了」）
if [ "$VPN_MODE" = "direct" ]; then
  # ★ 真机踩坑（重要）：iptables-restore 是「整批原子」的 —— 只要块里有任意一行失败
  #   （例如 *nat 里 -X PGVPN6，而 PGVPN6 只在 filter 存在；或 *mangle 里 -X PGVPN），
  #   整个块全部回滚，**一条都不会执行**。实测：PGVPN 链连同 OUTPUT 跳转原样残留，
  #   而日志还打印「已清空」→ 直连模式零接管失效。
  #   因此这里改成「按链 × 按表」的小批次：每批只处理一条链，用 -C 先判断存在才删，
  #   失败也只影响那一条，不会整批回滚。再配 -w 与幂等语义。
  # 1) 先摘掉所有 OUTPUT 跳转（-D 逐条；不存在的链 -D 失败无副作用）
  for _dc in PGVPN PGVPN6 PGHIDE PGNAT; do
    _dr=0
    while [ "$_dr" -lt 64 ] && iptables $FWWAIT -t nat -D OUTPUT -j "$_dc" 2>/dev/null; do _dr=$((_dr+1)); done
    _dr=0
    while [ "$_dr" -lt 64 ] && ip6tables $FWWAIT -t nat -D OUTPUT -j "$_dc" 2>/dev/null; do _dr=$((_dr+1)); done
  done
  for _dc in PGKS PGHKS PGBLK6 PGUARD; do
    _dr=0
    while [ "$_dr" -lt 64 ] && iptables $FWWAIT -D OUTPUT -j "$_dc" 2>/dev/null; do _dr=$((_dr+1)); done
    _dr=0
    while [ "$_dr" -lt 64 ] && ip6tables $FWWAIT -D OUTPUT -j "$_dc" 2>/dev/null; do _dr=$((_dr+1)); done
  done
  for _spec in 'mangle PGMTU' 'raw PGNF'; do
    set -- $_spec
    _dr=0
    while [ "$_dr" -lt 64 ] && iptables $FWWAIT -t "$1" -D OUTPUT -j "$2" 2>/dev/null; do _dr=$((_dr+1)); done
  done
  _dr=0
  while [ "$_dr" -lt 64 ] && ip6tables $FWWAIT -t raw -D OUTPUT -j PGNF6 2>/dev/null; do _dr=$((_dr+1)); done
  # 2) 逐链逐表清空并删除，每批一条链（单条失败不影响其它链）
  for _t in nat filter mangle raw; do
    for _c in PGVPN PGVPN6 PGKS PGBLK6 PGHIDE PGHKS PGMTU PGNF PGNF6; do
      # 链不存在就跳过（cx 判断比「先试再吞错误」更明确）
      if iptables  $FWWAIT -t "$_t" -S "$_c" >/dev/null 2>&1; then
        { echo "*$_t"; echo "-F $_c"; echo "-X $_c"; echo 'COMMIT'; } \
          | iptables-restore  -n 2>/dev/null
        if iptables $FWWAIT -t "$_t" -S "$_c" >/dev/null 2>&1; then
          # 批量失败则单条重试（老内核/特殊表的兼容路径）
          iptables $FWWAIT -t "$_t" -F "$_c" 2>/dev/null
          iptables $FWWAIT -t "$_t" -X "$_c" 2>/dev/null
        fi
      fi
      if ip6tables $FWWAIT -t "$_t" -S "$_c" >/dev/null 2>&1; then
        { echo "*$_t"; echo "-F $_c"; echo "-X $_c"; echo 'COMMIT'; } \
          | ip6tables-restore -n 2>/dev/null
        if ip6tables $FWWAIT -t "$_t" -S "$_c" >/dev/null 2>&1; then
          ip6tables $FWWAIT -t "$_t" -F "$_c" 2>/dev/null
          ip6tables $FWWAIT -t "$_t" -X "$_c" 2>/dev/null
        fi
      fi
    done
  done
  # 3) 自检：直连模式下 nat/filter 里不得再有本模块的接管链
  # Verify both IP families and every table we touched. The previous check only
  # inspected IPv4 nat/filter, so stale IPv6 or raw/mangle hooks could be misreported as clean.
  _dir_left=0
  _dir_verify_ok=1
  for _ipt in iptables ip6tables; do
    if ! command -v "$_ipt" >/dev/null 2>&1; then
      _dir_verify_ok=0
      pg_log "vpn: direct cleanup verification unavailable: $_ipt command is missing"
    fi
  done
  if [ "$_dir_verify_ok" = "1" ]; then
    for _fam in 4 6; do
      if [ "$_fam" = "4" ]; then _ipt=iptables; else _ipt=ip6tables; fi
      for _t in nat filter mangle raw; do
        # Do not pipe the command directly into grep: that masks iptables -S
        # failures and can turn an unverifiable firewall into a false clean result.
        if ! _dir_rules=$("$_ipt" -t "$_t" -S 2>/dev/null); then
          _dir_verify_ok=0
          pg_log "vpn: direct cleanup verification failed: $_ipt table $_t could not be queried"
          continue
        fi
        _left=$(printf '%s\n' "$_dir_rules" | grep -cE '^(-N|-A) (PGVPN|PGVPN6|PGKS|PGBLK6|PGHIDE|PGHKS|PGMTU|PGNF|PGNF6)( |$)|^-A .* -j (PGVPN|PGVPN6|PGKS|PGBLK6|PGHIDE|PGHKS|PGMTU|PGNF|PGNF6)( |$)' || true)
        case "$_left" in ''|*[!0-9]*) _left=0 ;; esac
        _dir_left=$((_dir_left+_left))
      done
    done
  fi
  if [ "$_dir_verify_ok" != "1" ]; then
    pg_fail vpn "direct 模式清理结果无法完整验证：iptables/ip6tables 工具或表查询失败；不能报告已清理干净（见 apply.log）"
  elif [ "$_dir_left" -gt 0 ]; then
    pg_fail vpn "direct 模式清理不彻底：IPv4/IPv6 各表仍有 $_dir_left 条 PGVPN/PGKS 等规则（见 apply.log）"
  else
    pg_log "vpn: direct mode verified — IPv4/IPv6 nat/filter/mangle/raw 接管链均已清除"
  fi
  VPN_LP=""
  # 直连模式不需要本地代理核心：把它停掉，避免「direct 了但后台还挂着 sing-box」
  # （占内存，且它自己的上游连接会因 direct 无规则而直出，属无意义开销）。
  if command -v vpncore_stop >/dev/null 2>&1; then
    vpncore_stop
  fi
  # Do not emit a second unconditional “verified” success message here:
  # the verification branch above may have called pg_fail because tools/tables
  # were unavailable or stale rules remained.
fi

# ---------- 独立第三方 VPN 隐藏（FX 直连模式也可用） ----------
# vpn_hide 是系统痕迹/泄漏防护开关，不应依赖 FX 自己的节点代理模式。
# 第三方 VPN 已存在而 FX 为 direct 时，仅安装非侵入式的应用侧 UDP 痕迹过滤；
# 不 DNAT DNS、不封锁 IPv6、不改写第三方 VPN 的隧道 UID，避免绕过/破坏外层 VPN。
if [ "$(pg_get vpn_hide 0)" = "1" ] && [ "$VPN_MODE" = "direct" ] && [ "$_PG_EXT_VPN_PROBE_UNKNOWN" = "1" ]; then
  pg_fail vpn_hide "VPN 接口状态无法检查；为避免误伤未知外层 VPN，跳过独立 PGHKS 隐藏过滤"
fi

if [ "$(pg_get vpn_hide 0)" = "1" ] && [ "$VPN_MODE" = "direct" ] && [ -n "$_PG_EXT_VPN_IF" ]; then
  HIDE_LEVEL=$(vpn_hide_conf hide_level); HIDE_LEVEL=${HIDE_LEVEL:-1}
  case "$HIDE_LEVEL" in 0|1|2) ;; *) HIDE_LEVEL=1 ;; esac
  if [ "$HIDE_LEVEL" != "0" ]; then
    # Without a reliable VPNService UID, an owner-based UDP filter cannot safely
    # exempt the outer tunnel. Do not install broad rules that may break VPN traffic.
    if [ -z "$VPN_EXTERNAL_UID" ]; then
      pg_fail vpn_hide "检测到第三方 VPN ($_PG_EXT_VPN_IF)，但无法可靠解析 VPNService UID；为避免破坏外层隧道，跳过 PGHKS 防火墙过滤"
      # UID may have been available during a previous apply. Remove stale hooks
      # and the FX-owned PGHKS chains so the safe-skip path does not leave old
      # broad UDP filters active against the external tunnel.
      _PGHKS_STALE_N=0
      while [ "$_PGHKS_STALE_N" -lt 64 ] && iptables $FWWAIT -D OUTPUT -j PGHKS 2>/dev/null; do _PGHKS_STALE_N=$((_PGHKS_STALE_N + 1)); done
      _PGHKS_STALE_N=0
      while [ "$_PGHKS_STALE_N" -lt 64 ] && ip6tables $FWWAIT -D OUTPUT -j PGHKS 2>/dev/null; do _PGHKS_STALE_N=$((_PGHKS_STALE_N + 1)); done
      # Only flush/delete a chain after confirming no jump still references it.
      # A failed/limited hook-removal loop must never turn a live chain into an
      # empty chain that changes traffic semantics for a remaining reference.
      # Do not use a bare `iptables -S | grep -c ... || true` here: grep prints
      # zero even when iptables itself failed, which would incorrectly authorize
      # flushing/deleting a chain whose references could not be inspected.
      _PGHKS_REF4=1
      if _PGHKS_RULES4=$(iptables $FWWAIT -S 2>/dev/null); then
        _PGHKS_REF4=$(printf '%s\n' "$_PGHKS_RULES4" | grep -cE '^-A .* -j PGHKS([[:space:]]|$)' || true)
        case "$_PGHKS_REF4" in ''|*[!0-9]*) _PGHKS_REF4=1 ;; esac
      fi
      _PGHKS_REF6=1
      if _PGHKS_RULES6=$(ip6tables $FWWAIT -S 2>/dev/null); then
        _PGHKS_REF6=$(printf '%s\n' "$_PGHKS_RULES6" | grep -cE '^-A .* -j PGHKS([[:space:]]|$)' || true)
        case "$_PGHKS_REF6" in ''|*[!0-9]*) _PGHKS_REF6=1 ;; esac
      fi
      if [ "$_PGHKS_REF4" = "0" ]; then
        iptables $FWWAIT -F PGHKS 2>/dev/null && iptables $FWWAIT -X PGHKS 2>/dev/null || true
      else
        pg_fail vpn_hide "IPv4 PGHKS 仍有引用或状态不可查询；跳过清空/删除以避免破坏活动规则"
      fi
      if [ "$_PGHKS_REF6" = "0" ]; then
        ip6tables $FWWAIT -F PGHKS 2>/dev/null && ip6tables $FWWAIT -X PGHKS 2>/dev/null || true
      else
        pg_fail vpn_hide "IPv6 PGHKS 仍有引用或状态不可查询；跳过清空/删除以避免破坏活动规则"
      fi
      # Do not silently assume rollback succeeded: some Android builds reject
      # chain deletion while another hook/reference remains. Verify both families.
      _PGHKS_STALE_LEFT=0
      _PGHKS_VERIFY_UNKNOWN=0
      if _PGHKS_RULES4=$(iptables $FWWAIT -S 2>/dev/null); then
        _PGHKS_N=$(printf '%s\n' "$_PGHKS_RULES4" | grep -cE '(^-N PGHKS$|^-A .* -j PGHKS([[:space:]]|$))' || true)
        case "$_PGHKS_N" in ''|*[!0-9]*) _PGHKS_VERIFY_UNKNOWN=1; _PGHKS_N=0 ;; esac
        _PGHKS_STALE_LEFT=$((_PGHKS_STALE_LEFT + _PGHKS_N))
      else
        _PGHKS_VERIFY_UNKNOWN=1
      fi
      if _PGHKS_RULES6=$(ip6tables $FWWAIT -S 2>/dev/null); then
        _PGHKS_N=$(printf '%s\n' "$_PGHKS_RULES6" | grep -cE '(^-N PGHKS$|^-A .* -j PGHKS([[:space:]]|$))' || true)
        case "$_PGHKS_N" in ''|*[!0-9]*) _PGHKS_VERIFY_UNKNOWN=1; _PGHKS_N=0 ;; esac
        _PGHKS_STALE_LEFT=$((_PGHKS_STALE_LEFT + _PGHKS_N))
      else
        _PGHKS_VERIFY_UNKNOWN=1
      fi
      if [ "$_PGHKS_STALE_LEFT" -gt 0 ] || [ "$_PGHKS_VERIFY_UNKNOWN" = "1" ]; then
        pg_fail vpn_hide "VPN UID 未知且 PGHKS 清理未完全验证：残留计数=$_PGHKS_STALE_LEFT，防火墙查询未知=$_PGHKS_VERIFY_UNKNOWN；请检查 apply.log 与防火墙状态"
      else
        pg_log "vpn_hide: VPN UID 未知；已验证 PGHKS 双栈跳转与链均已清理"
      fi
    else
    _PGHKS_BUILD_OK=1
    fw4 -N PGHKS 2>/dev/null || true
    fw4 -F PGHKS 2>/dev/null || _PGHKS_BUILD_OK=0
    fw6 -N PGHKS 2>/dev/null || true
    fw6 -F PGHKS 2>/dev/null || _PGHKS_BUILD_OK=0
    # Always exempt the detected VPNService UID before any hide filter.
    fw4 -A PGHKS -m owner --uid-owner "$VPN_EXTERNAL_UID" -j RETURN 2>/dev/null || _PGHKS_BUILD_OK=0
    fw6 -A PGHKS -m owner --uid-owner "$VPN_EXTERNAL_UID" -j RETURN 2>/dev/null || _PGHKS_BUILD_OK=0
    fw4 -A PGHKS -m owner ! --uid-owner 0:9999 -p udp --dport 443 -j REJECT 2>/dev/null || _PGHKS_BUILD_OK=0
    fw6 -A PGHKS -m owner ! --uid-owner 0:9999 -p udp --dport 443 -j REJECT 2>/dev/null || _PGHKS_BUILD_OK=0
    for _hp in 3478 3479 5349 19302 19303 19304; do
      fw4 -A PGHKS -p udp --dport "$_hp" -j REJECT 2>/dev/null || _PGHKS_BUILD_OK=0
      fw6 -A PGHKS -p udp --dport "$_hp" -j REJECT 2>/dev/null || _PGHKS_BUILD_OK=0
    done
    fw4 -A PGHKS -j RETURN 2>/dev/null || _PGHKS_BUILD_OK=0
    fw6 -A PGHKS -j RETURN 2>/dev/null || _PGHKS_BUILD_OK=0
    # Flush queued rules before installing hooks. Remove stale duplicate hooks first,
    # then install both families as one best-effort transaction.
    if [ "$_PGHKS_BUILD_OK" = "1" ] && fw_flush 2>/dev/null; then
      _PGHKS_HOOK_OK=1
      _PGHKS_HOOK_N=0
      while [ "$_PGHKS_HOOK_N" -lt 64 ] && iptables $FWWAIT -D OUTPUT -j PGHKS 2>/dev/null; do _PGHKS_HOOK_N=$((_PGHKS_HOOK_N + 1)); done
      _PGHKS_HOOK_N=0
      while [ "$_PGHKS_HOOK_N" -lt 64 ] && ip6tables $FWWAIT -D OUTPUT -j PGHKS 2>/dev/null; do _PGHKS_HOOK_N=$((_PGHKS_HOOK_N + 1)); done
      fw4 -I OUTPUT -j PGHKS || _PGHKS_HOOK_OK=0
      fw6 -I OUTPUT -j PGHKS || _PGHKS_HOOK_OK=0
      [ "$_PGHKS_HOOK_OK" != "1" ] || fw_flush 2>/dev/null || _PGHKS_HOOK_OK=0
    else
      _PGHKS_HOOK_OK=0
    fi
    if [ "$_PGHKS_HOOK_OK" = "1" ]; then
      pg_log "vpn_hide: third-party VPN detected ($_PG_EXT_VPN_IF); independent hide filters active (L$HIDE_LEVEL), outer VPN UID exempt=$VPN_EXTERNAL_UID; DNS/IPv6 left to external VPN to avoid tunnel breakage"
    else
      # Roll back partial hooks and the FX-owned chains; do not claim hide filters are active.
      iptables $FWWAIT -D OUTPUT -j PGHKS 2>/dev/null || true
      ip6tables $FWWAIT -D OUTPUT -j PGHKS 2>/dev/null || true
      fw_flush 2>/dev/null || true
      # Preserve command exit status: grep -c alone returns 0 matches even if
      # iptables -S failed, which is not proof that the chain has no references.
      _PGHKS_REF4=1
      if _PGHKS_RULES4=$(iptables $FWWAIT -S 2>/dev/null); then
        _PGHKS_REF4=$(printf '%s\n' "$_PGHKS_RULES4" | grep -cE '^-A .* -j PGHKS([[:space:]]|$)' || true)
        case "$_PGHKS_REF4" in ''|*[!0-9]*) _PGHKS_REF4=1 ;; esac
      fi
      _PGHKS_REF6=1
      if _PGHKS_RULES6=$(ip6tables $FWWAIT -S 2>/dev/null); then
        _PGHKS_REF6=$(printf '%s\n' "$_PGHKS_RULES6" | grep -cE '^-A .* -j PGHKS([[:space:]]|$)' || true)
        case "$_PGHKS_REF6" in ''|*[!0-9]*) _PGHKS_REF6=1 ;; esac
      fi
      if [ "$_PGHKS_REF4" = "0" ]; then
        iptables $FWWAIT -F PGHKS 2>/dev/null && iptables $FWWAIT -X PGHKS 2>/dev/null || true
      else
        pg_fail vpn_hide "回滚后 IPv4 PGHKS 仍有引用或状态不可查询；保留链并记录待清理"
      fi
      if [ "$_PGHKS_REF6" = "0" ]; then
        ip6tables $FWWAIT -F PGHKS 2>/dev/null && ip6tables $FWWAIT -X PGHKS 2>/dev/null || true
      else
        pg_fail vpn_hide "回滚后 IPv6 PGHKS 仍有引用或状态不可查询；保留链并记录待清理"
      fi
      pg_fail vpn_hide "第三方 VPN PGHKS 规则提交或双栈 OUTPUT 挂载失败；已尝试回滚，隐藏过滤未启用"
    fi
    fi
  else
    pg_log "vpn_hide: L0 selected; only platform hooks can hide VPN indicators, no firewall hide filters installed"
  fi
fi

# IP/CIDR 黑名单：每条 [list:block] 自身的启用状态就是开关；同时识别 IPv4/IPv6。
_BLOCK_IPS=$(pg_list_enabled block 2>/dev/null | awk '
function valid4(s,n,a,i,p,oct) {
  n=split(s,a,"/"); if(n>2 || split(a[1],oct,".")!=4) return 0
  for(i=1;i<=4;i++) if(oct[i]!~/^[0-9]+$/ || oct[i]+0>255) return 0
  if(n==2 && (a[2]!~/^[0-9]+$/ || a[2]+0>32)) return 0
  return 1
}
function valid6(s,n,a) {
  n=split(s,a,"/"); if(n>2 || index(a[1],":")==0 || a[1]!~/^[0-9A-Fa-f:.]+$/) return 0
  if(n==2 && (a[2]!~/^[0-9]+$/ || a[2]+0>128)) return 0
  return 1
}
function blocking(action) { action=toupper(action); return action==""||action=="REJECT"||action=="REJECT-DROP"||action=="BLOCK"||action=="DROP"||action=="DENY" }
{
  if ($0 ~ /^(IP-CIDR|IP-CIDR6|MIXED-IP-CIDR),/) {
    n=split($0,a,","); if(n>=2 && blocking(a[3]) && (valid4(a[2])||valid6(a[2]))) print a[2]
    next
  }
  if(valid4($0)||valid6($0)) print $0
}
')
if [ -n "$_BLOCK_IPS" ]; then
  ANY_FW=1
  fw4 -N PGUARD 2>/dev/null; fw6 -N PGUARD 2>/dev/null
  printf '%s\n' "$_BLOCK_IPS" | while IFS= read -r ip; do
    [ -n "$ip" ] || continue
    case "$ip" in *:*) fw6 -A PGUARD -d "$ip" -j DROP 2>/dev/null ;; *) fw4 -A PGUARD -d "$ip" -j DROP 2>/dev/null ;; esac
  done
  pg_log "fw: individually enabled [list:block] IP/CIDR rules applied"
fi

# 订阅 IP-CIDR/IP-CIDR6/MIXED-IP-CIDR 规则（build_hosts 暂存 → 统一入链）。
# 订阅源自己的每条启用状态已在生成 subnet-ips.list 时应用，不再依赖 IP 总开关。
if [ -s "$PG/cache/subnet-ips.list" ]; then
  ANY_FW=1
  fw4 -N PGUARD 2>/dev/null; fw6 -N PGUARD 2>/dev/null
  _subnet_unique="$PG/cache/subnet-ips.unique.$$"
  _subnet_apply="$PG/cache/subnet-ips.apply.$$"
  _subnet_seen=0; _subnet_queued=0; _subnet_failed=0
  if awk 'NF && !seen[$0]++ {print}' "$PG/cache/subnet-ips.list" > "$_subnet_unique" 2>>"$PG/apply.log"; then
    _subnet_seen=$(wc -l < "$_subnet_unique" 2>/dev/null | tr -d ' ')
    case "$_subnet_seen" in ''|*[!0-9]*) _subnet_seen=0 ;; esac
    # Per-rule iptables calls can overload older Android kernels with huge lists.
    # Keep the source order and make the cap explicit in logs; never pretend omitted
    # entries were installed. Domain filtering remains independent of this IP cap.
    head -n 4096 "$_subnet_unique" > "$_subnet_apply" || : > "$_subnet_apply"
    if [ "$_subnet_seen" -gt 4096 ]; then
      pg_fail fw "订阅 IP-CIDR 共 $_subnet_seen 条去重规则，单次最多提交 4096 条；其余规则本次未加载，请拆分/精简订阅"
    fi
    while IFS= read -r cidr; do
      [ -n "$cidr" ] || continue
      case "$cidr" in
        *:*) if fw6 -A PGUARD -d "$cidr" -j DROP 2>>"$PG/apply.log"; then _subnet_queued=$((_subnet_queued+1)); else _subnet_failed=$((_subnet_failed+1)); fi ;;
        *)   if fw4 -A PGUARD -d "$cidr" -j DROP 2>>"$PG/apply.log"; then _subnet_queued=$((_subnet_queued+1)); else _subnet_failed=$((_subnet_failed+1)); fi ;;
      esac
    done < "$_subnet_apply"
    if [ "$_subnet_failed" -gt 0 ]; then pg_fail fw "订阅 IP-CIDR 提交失败 $_subnet_failed 条；已排队 $_subnet_queued/$_subnet_seen（去重前源列表可能包含重复项）"; fi
    pg_log "fw: subscription IP-CIDR unique=$_subnet_seen queued=$_subnet_queued failed=$_subnet_failed cap=4096"
  else
    pg_fail fw "订阅 IP-CIDR 去重失败；本次跳过该批网段规则"
  fi
  rm -f "$_subnet_unique" "$_subnet_apply" 2>/dev/null
fi

# 不再隐式添加硬编码广告网段；所有 IP/CIDR 屏蔽必须来自用户单独启用的规则项。

if [ "$ANY_FW" = "1" ]; then
  fw4 -A PGUARD -j RETURN
  fw6 -A PGUARD -j RETURN
  _PGUARD_SKIP_HOOK=0
  if [ "$DNS_AGH_ACTIVE" = "1" ]; then
    if fw4 -I PGUARD 1 -m owner --uid-owner 0 -p udp --dport 53 -j RETURN 2>>"$PG/apply.log" && \
       fw4 -I PGUARD 1 -m owner --uid-owner 0 -p tcp --dport 53 -j RETURN 2>>"$PG/apply.log" && \
       fw6 -I PGUARD 1 -m owner --uid-owner 0 -p udp --dport 53 -j RETURN 2>>"$PG/apply.log" && \
       fw6 -I PGUARD 1 -m owner --uid-owner 0 -p tcp --dport 53 -j RETURN 2>>"$PG/apply.log"; then
      pg_log "fw: only root-owned UDP/TCP port 53 bypasses PGUARD for local recursive DNS queries"
    else
      _PGUARD_SKIP_HOOK=1
      pg_log "fw: cannot verify narrow recursive-DNS exemptions; PGUARD hook suppressed to avoid DNS recursion"
    fi
  fi
  # A third-party VPN's own outer socket must not be trapped by generic OUTPUT
  # filters (QUIC/STUN/DoT/IP blocks). Exempt its owner UID as the first rule;
  # if UID resolution or interface probing is uncertain, leave PGUARD detached.
  if [ "$_PG_VPN_INTERCEPTION_BLOCKED" = "1" ]; then
    if [ "$_PG_EXT_VPN_PROBE_UNKNOWN" = "1" ]; then
      _PGUARD_SKIP_HOOK=1
      pg_log "fw: VPN interface probe unknown; PGUARD OUTPUT hook suppressed to preserve network/VPN (other app filters temporarily inactive)"
    elif [ -z "$VPN_EXTERNAL_UID" ]; then
      _PGUARD_SKIP_HOOK=1
      pg_log "fw: external tunnel $_PG_EXT_VPN_IF detected but VPN owner UID is unknown; PGUARD OUTPUT hook suppressed to avoid breaking the outer tunnel"
    else
      if fw4 -I PGUARD 1 -m owner --uid-owner "$VPN_EXTERNAL_UID" -j RETURN 2>>"$PG/apply.log" && \
         fw6 -I PGUARD 1 -m owner --uid-owner "$VPN_EXTERNAL_UID" -j RETURN 2>>"$PG/apply.log"; then
        pg_log "fw: PGUARD bypasses detected external VPN owner UID $VPN_EXTERNAL_UID before all generic filter rules"
      else
        _PGUARD_SKIP_HOOK=1
        pg_log "fw: failed to queue external VPN owner exemption; PGUARD OUTPUT hook suppressed as fail-safe"
      fi
    fi
  fi
  # Do not attach PGUARD until the full queued rule set is committed.
  if fw_flush 2>>"$PG/apply.log"; then
    if [ "$_PGUARD_SKIP_HOOK" = "1" ]; then
      pg_log "fw: PGUARD rules committed detached; network safety takes priority while VPN state is uncertain"
    else
      # Both address families must attach successfully or the other side is rolled back.
      _PGUARD_HOOK4=0
      _PGUARD_HOOK6=0
      if fw4 -I OUTPUT -j PGUARD 2>>"$PG/apply.log"; then _PGUARD_HOOK4=1; fi
      if fw6 -I OUTPUT -j PGUARD 2>>"$PG/apply.log"; then _PGUARD_HOOK6=1; fi
      if [ "$_PGUARD_HOOK4" != "1" ] || [ "$_PGUARD_HOOK6" != "1" ]; then
        [ "$_PGUARD_HOOK4" != "1" ] || iptables $FWWAIT -D OUTPUT -j PGUARD 2>/dev/null || true
        [ "$_PGUARD_HOOK6" != "1" ] || ip6tables $FWWAIT -D OUTPUT -j PGUARD 2>/dev/null || true
        pg_fail fw "PGUARD OUTPUT 挂接失败(v4=$_PGUARD_HOOK4,v6=$_PGUARD_HOOK6)，已回滚成功的一侧"
      else
        # 若工具支持 -S，则两侧都必须至少有一条有效过滤规则（除末尾 RETURN 外）。
        RC4=$(iptables $FWWAIT -S PGUARD 2>/dev/null | grep -c '^-A')
        RC4=${RC4:-0}
        RC6=$(ip6tables $FWWAIT -S PGUARD 2>/dev/null | grep -c '^-A')
        RC6=${RC6:-0}
        _PGUARD_QUERY4=0; _PGUARD_QUERY6=0
        iptables $FWWAIT -S PGUARD >/dev/null 2>&1 && _PGUARD_QUERY4=1
        ip6tables $FWWAIT -S PGUARD >/dev/null 2>&1 && _PGUARD_QUERY6=1
        if { [ "$_PGUARD_QUERY4" = "1" ] && [ "$RC4" -le 1 ]; } || { [ "$_PGUARD_QUERY6" = "1" ] && [ "$RC6" -le 1 ]; }; then
          iptables $FWWAIT -D OUTPUT -j PGUARD 2>/dev/null || true
          ip6tables $FWWAIT -D OUTPUT -j PGUARD 2>/dev/null || true
          pg_fail fw "PGUARD 规则数异常(v4=$RC4,v6=$RC6)，已摘除 OUTPUT 挂接，防止空链造成假启用"
        else
          pg_log "fw: PGUARD chain active (v4 rules=$RC4, v6 rules=$RC6)"
        fi
      fi
    fi
  else
    pg_fail fw "PGUARD 规则队列提交失败，未挂接 OUTPUT；请查看 apply.log 并检查内核/iptables 支持"
  fi
else
  pg_log "fw: all off, chains cleared"
fi

# ---------- 3. Sysctl ----------
# set_sysctl KEY=VAL — 写入并检测：内核无该节点/权限拒绝时记录失败原因
set_sysctl() {
  _sk="$1"
  _out=$(sysctl -w "$_sk" 2>&1)
  _rc=$?
  if [ $_rc -ne 0 ]; then
    pg_fail sysctl "$_sk 写入失败: $(echo "$_out" | head -1 | cut -c1-80)"
  fi
}
# vpn_hide 的 sysctl 优先于通用 sysctl 段：先按隐藏态写入，再由通用段按自身开关覆盖
# （通用段默认 key 全 0，不会覆盖；若用户同时开通用键则以通用段为准）
if [ "$(pg_get vpn_hide 0)" = "1" ]; then
  # L1 起关闭 TCP 时间戳（抓包方看不到 timestamps/TSval 指纹）；hide_level=0 时不动
  if [ "$(vpn_hide_conf hide_level)" != "0" ]; then
    set_sysctl net.ipv4.tcp_timestamps=0
  fi
  # L2 增强：ICMP echo 全禁（防 traceroute/存活探测暴露链路）
  if [ "$(vpn_hide_conf hide_icmp_block_all)" = "1" ]; then
    set_sysctl net.ipv4.icmp_echo_ignore_all=1
  fi
fi
if [ "$(pg_get disable_tcp_timestamps 0)" = "1" ] || [ "$(pg_get hide_tcp_fingerprint 0)" = "1" ]; then
  set_sysctl net.ipv4.tcp_timestamps=0
fi
if [ "$(pg_get disable_icmp 0)" = "1" ]; then
  set_sysctl net.ipv4.icmp_echo_ignore_all=1
elif [ "$(pg_get vpn_hide 0)" = "1" ] && [ "$(vpn_hide_conf hide_icmp_block_all)" = "1" ]; then
  : # L2 ICMP 已置 1，不要被下面的通用 else 复位
else
  set_sysctl net.ipv4.icmp_echo_ignore_all=0
fi
if [ "$(pg_get random_src_port 0)" = "1" ]; then
  set_sysctl net.ipv4.ip_local_port_range="1024 65535"
fi
if [ "$(pg_get block_udp_tracking 0)" = "1" ]; then
  set_sysctl net.ipv4.conf.all.rp_filter=1
fi
# k_stack 内核信息泄露防护（免编译 sysctl 降级路线；完全随机化需定制内核）
if [ "$(pg_get k_stack 0)" = "1" ]; then
  # 首次开启时记录系统原始值，关闭时恢复
  if [ ! -f "$PG/kstack.defaults" ]; then
    { echo "kptr_restrict=$(cat /proc/sys/kernel/kptr_restrict 2>/dev/null || echo 1)"
      echo "dmesg_restrict=$(cat /proc/sys/kernel/dmesg_restrict 2>/dev/null || echo 1)"
      echo "perf_event_paranoid=$(cat /proc/sys/kernel/perf_event_paranoid 2>/dev/null || echo 3)"
    } > "$PG/kstack.defaults" 2>/dev/null
  fi
  KS_KPTR=$(pg_conf k_stack | grep -m1 '^kptr_restrict=' | cut -d= -f2- | tr -d ' '); KS_KPTR=${KS_KPTR:-2}
  KS_DMESG=$(pg_conf k_stack | grep -m1 '^dmesg_restrict=' | cut -d= -f2- | tr -d ' '); KS_DMESG=${KS_DMESG:-1}
  KS_PERF=$(pg_conf k_stack | grep -m1 '^perf_event_paranoid=' | cut -d= -f2- | tr -d ' '); KS_PERF=${KS_PERF:-3}
  set_sysctl kernel.kptr_restrict="$KS_KPTR"
  set_sysctl kernel.dmesg_restrict="$KS_DMESG"
  set_sysctl kernel.perf_event_paranoid="$KS_PERF"
elif [ -f "$PG/kstack.defaults" ]; then
  # 关闭：恢复开启前记录的系统原始值（sysctl 重启后本就会还原）
  while IFS='=' read -r kn kv; do
    [ -n "$kn" ] && set_sysctl "kernel.$kn=$kv"
  done < "$PG/kstack.defaults"
  rm -f "$PG/kstack.defaults"
fi
# SELinux/内核日志泄露：dmesg_restrict 拒绝非 root 读内核日志（含 SELinux 拒绝记录）
if [ "$(pg_get block_sepolicy_logs 0)" = "1" ]; then
  set_sysctl kernel.dmesg_restrict=1
fi
# 回声黑洞：忽略广播 ping（smurf 放大向量）
if [ "$(pg_get echo_blackhole 0)" = "1" ]; then
  set_sysctl net.ipv4.icmp_echo_ignore_broadcasts=1
fi
# 运营商嗅探防护：拒绝 ICMP 重定向注入与源路由（中间人/流量劫持向量）
if [ "$(pg_get isp_snoop 0)" = "1" ]; then
  set_sysctl net.ipv4.conf.all.accept_redirects=0
  set_sysctl net.ipv4.conf.default.accept_redirects=0
  set_sysctl net.ipv4.conf.all.secure_redirects=0
  set_sysctl net.ipv4.conf.all.accept_source_route=0
  set_sysctl net.ipv6.conf.all.accept_redirects=0
  set_sysctl net.ipv6.conf.default.accept_redirects=0
fi

# ---------- 3b. Wi-Fi MAC 伪装（ip link，需驱动支持；蓝牙 MAC 无法用 ip link 设置）----------
if [ "$(pg_get spoof_wifi_mac 0)" = "1" ]; then
  WM=$(pg_conf spoof_wifi_mac | grep -m1 '^wifi_mac=' | cut -d= -f2- | tr -d ' ')
  case "$WM" in
    *:*:*:*:*:*)
      WIF=$(ip link 2>/dev/null | grep -o '^[0-9]*: [a-z0-9]*' | awk '{print $2}' | grep -E '^wlan' | head -1)
      if [ -n "$WIF" ]; then
        ip link set dev "$WIF" down 2>>"$PG/apply.log"
        if ip link set dev "$WIF" address "$WM" 2>>"$PG/apply.log"; then
          pg_log "wifi_mac: $WIF -> $WM"
        else
          pg_fail wifi_mac "$WIF 驱动拒绝改 MAC(部分厂商内核不支持)"
        fi
        ip link set dev "$WIF" up 2>>"$PG/apply.log" || pg_fail wifi_mac "$WIF 拉起失败(网卡已 down!)"
      else
        pg_fail wifi_mac "未找到 wlan 接口(设备未开 Wi-Fi 或命名非 wlan*)"
      fi
      ;;
    *) pg_log "wifi_mac: invalid mac in [conf:spoof_wifi_mac], skip" ;;
  esac
fi

# ---------- 4. 系统设置（settings put）----------
# put_setting NAMESPACE KEY VALUE — 失败记录（settings 服务未起/SELinux 拒绝）
put_setting() {
  # 记录每个设置首次被模块修改前的原值，卸载时按原状恢复，不能猜测 ROM 默认值。
  # 文件格式为 namespace|key|value；null/空值代表修改前不存在该键。
  _ps_ns="$1"; _ps_key="$2"; _ps_val="$3"
  _ps_snap="$PG/settings.snapshot"
  if [ -d "$PG" ] && ! grep -F -q "$_ps_ns|$_ps_key|" "$_ps_snap" 2>/dev/null; then
    _ps_old=$(settings get "$_ps_ns" "$_ps_key" 2>/dev/null | tr -d '\r')
    case "$_ps_old" in *'|'*|*'\n'*) _ps_old=null ;; esac
    printf '%s|%s|%s\n' "$_ps_ns" "$_ps_key" "${_ps_old:-null}" >> "$_ps_snap" 2>/dev/null
  fi
  # v1.10.8: `settings` 在 MIUI 上只是 `#!/system/bin/sh` + `cmd settings "$@"` 的
  # wrapper（/system/bin/settings 仅 35 字节）。实测：
  #   settings put ...             → rc=0，值写对
  #   settings put ... 2>/dev/null → rc=0，值写对
  #   settings put ... 2>>文件      → **rc=1，值没写**（wrapper 的 stderr 重定向
  #                                  触发 `Failure calling service settings:
  #                                   Failed transaction (2147483646)`）
  # 旧逻辑用 `2>>"$PG/apply.log"`，于是每次「应用」都稳定产生 3~4 条假失败，
  # 而且这些设置**真的没生效**（不是误报，是被这个 wrapper 坑掉）。
  # 现在：stderr 一律丢弃（不以它判定成败），成败只看「写后读回」，并给
  # Binder 一点时间最多重试 6 次（开机早期 settings 服务未就绪时读回可能还是旧值，
  # 实测开机 apply 出现 "anr_show_background 未生效(读回=[1])" 假失败）。
  _ps_try=0; _ps_rc=0
  while [ "$_ps_try" -lt 6 ]; do
    _ps_try=$((_ps_try + 1))
    # MIUI 的 settings 是 shell wrapper：cmd 的 "Failed transaction" 会跑到
    # **stdout**（2>/dev/null 拦不住），直接进 apply.log。日志里那几行不是失败，
    # 最终以读回值为准；这里把 put 的 stdout 也丢掉，保持日志干净。
    settings put "$_ps_ns" "$_ps_key" "$_ps_val" >/dev/null 2>&1
    _ps_rc=$?
    _ps_back=$(settings get "$_ps_ns" "$_ps_key" 2>/dev/null | tr -d '\r')
    if [ "$_ps_back" = "$_ps_val" ]; then
      [ "$_ps_rc" -eq 0 ] || pg_log "settings: $_ps_ns $_ps_key 已生效（rc=$_ps_rc 但读回=$_ps_val）"
      return 0
    fi
    case "$_ps_try" in
      1) _ps_sleep=0.5 ;;
      2) _ps_sleep=1 ;;
      3) _ps_sleep=2 ;;
      *) _ps_sleep=3 ;;
    esac
    sleep "$_ps_sleep" 2>/dev/null || sleep 1
  done
  # 键在本 ROM 不存在/只读（非 AOSP 标准，null）→ 记日志，不计失败
  if [ "$_ps_back" = "null" ] || [ -z "$_ps_back" ]; then
    pg_log "settings: $_ps_ns $_ps_key 在本 ROM 不可写（读回=[$_ps_back]），跳过不计失败"
    return 0
  fi
  pg_fail settings "settings put $_ps_ns $_ps_key 未生效（读回=[$_ps_back]，期望=$_ps_val）"
}
if [ "$(pg_get anr_off 0)" = "1" ]; then
  put_setting secure anr_show_background 0
fi
if [ "$(pg_get crash_upload_off 0)" = "1" ]; then
  put_setting global send_action_app_error 0
fi
if [ "$(pg_get ad_id_unify 0)" = "1" ]; then
  put_setting secure limit_ad_tracking 1
  put_setting secure advertising_id 00000000-0000-0000-0000-000000000000
fi

# ---------- 5. AGPS / WiFi 扫描 / 被动定位 ----------
if [ "$(pg_get block_agps 0)" = "1" ]; then
  put_setting global assisted_gps_enabled 0
fi
if [ "$(pg_get block_wifi_scan 0)" = "1" ]; then
  # 仅全局阈值（应用级由 LSPosed 处理）
  put_setting global wifi_scan_always_enabled 0
fi
# 被动定位（Wi-Fi/基站）总开关：关掉后台扫描与 AGPS 两个被动定位源
if [ "$(pg_get disable_passive_loc 0)" = "1" ]; then
  put_setting global assisted_gps_enabled 0
  put_setting global wifi_scan_always_enabled 0
  # 部分 ROM 支持的网络定位全局开关（无则静默忽略——该键非 AOSP 标准失败不算错）
  put_setting global network_location 0
  pg_log "loc: passive sources (agps+wifi-scan) off"
fi
# logcat 采集防护：persist.log.tag=S 把应用日志静音（读取方只能拿到空缓冲）。
# 该属性可能已由用户/ROM 设置；首次改写前保存原值，且关闭此功能时不再擅自清空用户值。
if [ "$(pg_get block_logcat 0)" = "1" ]; then
  _pltsnap="$PG/backup/persist.log.tag.snapshot"
  if [ ! -f "$_pltsnap" ]; then
    mkdir -p "$PG/backup" 2>/dev/null || :
    getprop persist.log.tag 2>/dev/null | tr -d '\r' > "$_pltsnap" 2>/dev/null || :
  fi
  if [ -f "$_pltsnap" ]; then
    setprop persist.log.tag S 2>>"$PG/apply.log" || pg_fail setprop "persist.log.tag=S 失败"
    pg_log "logcat: persist.log.tag=S (silent; original value snapshotted)"
  else
    pg_fail setprop "persist.log.tag 原值快照失败；为避免覆盖用户属性，跳过修改"
  fi
fi

# ---------- 5b. Root/管理器痕迹遮蔽（bind mount 空文件）----------
# hide_su / block_rootcheck_libs：把常见检测路径用空文件遮蔽
# （Android 11+ 大部分路径已不存在 → mount 失败属预期，统计成功数供参考，不算错误）
mount_empty() {
  SRC="$PG/empty"
  TRACK="$PG/rootmask.mounts"
  [ -f "$SRC" ] || : > "$SRC"
  _ok=0; _skip=0
  for p in "$@"; do
    [ -e "$p" ] || { _skip=$((_skip+1)); continue; }
    # Do not stack another bind mount on repeated apply. A tracked live mount
    # belongs to this module; an untracked mount is left untouched.
    if grep -F -x "$p" "$TRACK" >/dev/null 2>&1; then
      if mount 2>/dev/null | grep -F " on $p " >/dev/null 2>&1; then
        _skip=$((_skip+1)); continue
      fi
    elif mount 2>/dev/null | grep -F " on $p " >/dev/null 2>&1; then
      _skip=$((_skip+1)); continue
    fi
    if mount --bind "$SRC" "$p" 2>/dev/null; then
      grep -F -x "$p" "$TRACK" >/dev/null 2>&1 || printf '%s\n' "$p" >> "$TRACK"
      _ok=$((_ok+1))
    else
      _skip=$((_skip+1))
    fi
  done
  [ $_ok -gt 0 ] && pg_log "hide: $_ok 路径遮蔽成功, $_skip 路径不存在/已挂载/被拒(预期)"
  return 0
}
if [ "$(pg_get hide_su 0)" = "1" ]; then
  mount_empty /system/xbin/su /system/bin/su /system/xbin/daemonsu /system/bin/daemonsu /vendor/bin/su /sbin/su
  pg_log "hide: su paths masked"
fi
if [ "$(pg_get block_rootcheck_libs 0)" = "1" ]; then
  mount_empty /system/xbin/busybox /system/bin/busybox /system/app/Superuser.apk /system/xbin/sugate /system/xbin/sugate-mksh
  pg_log "hide: rootcheck lib paths masked"
fi

# ---------- 5c. 内核层(免编译): SELinux 规则注入 k_sysfs / k_read ----------
# 多机型免编译方案：规则写入模块 sepolicy.rule（Magisk/APatch/KernelSU
# 开机自动加载）+ 立即生效（magiskpolicy --live / ksud sepolicy patch）
pg_sepol_tool() {
  if pg_have magiskpolicy; then echo magiskpolicy; return 0; fi
  if [ -x /data/adb/ap/bin/magiskpolicy ]; then echo /data/adb/ap/bin/magiskpolicy; return 0; fi
  if pg_have ksud && ksud sepolicy 2>&1 | grep -q patch; then echo ksud; return 0; fi
  return 1
}
pg_sepol() {  # pg_sepol "deny DOM TYPE CLASS PERMS..."
  [ -n "$SEPOL_TOOL" ] || return 1
  if [ "$SEPOL_TOOL" = "ksud" ]; then
    ksud sepolicy patch "$1" 2>/dev/null
  else
    "$SEPOL_TOOL" --live "$1" 2>/dev/null
  fi
}
SEPOL_TOOL=$(pg_sepol_tool)
SEPOL_RULES=""
for DOM in untrusted_app untrusted_app_25 untrusted_app_27; do
  if [ "$(pg_get k_sysfs 0)" = "1" ]; then
    SEPOL_RULES="$SEPOL_RULES
deny $DOM sysfs file read open getattr"
  fi
  if [ "$(pg_get k_read 0)" = "1" ]; then
    SEPOL_RULES="$SEPOL_RULES
deny $DOM proc file read open getattr
deny $DOM proc_cpuinfo file read open getattr"
  fi
done
SEPOL_RULES=$(printf '%s\n' "$SEPOL_RULES" | sed '/^$/d')
if [ -z "$SEPOL_RULES" ]; then
  rm -f "$MODDIR/sepolicy.rule"
  # 尽力恢复当前会话（重启后由系统默认策略接管）
  if [ -n "$SEPOL_TOOL" ]; then
    for DOM in untrusted_app untrusted_app_25 untrusted_app_27; do
      pg_sepol "allow $DOM sysfs file read open getattr" 2>>"$PG/apply.log" || true
      pg_sepol "allow $DOM proc file read open getattr" 2>>"$PG/apply.log" || true
      pg_sepol "allow $DOM proc_cpuinfo file read open getattr" 2>>"$PG/apply.log" || true
    done
  fi
  pg_log "sepolicy: rules cleared"
else
  printf '%s\n' "$SEPOL_RULES" > "$MODDIR/sepolicy.rule" 2>>"$PG/apply.log" \
    || pg_fail sepolicy "sepolicy.rule 写入失败(模块目录只读?)"
  chmod 644 "$MODDIR/sepolicy.rule" 2>/dev/null
  if [ -n "$SEPOL_TOOL" ]; then
    printf '%s\n' "$SEPOL_RULES" | while IFS= read -r RULE; do
      [ -n "$RULE" ] || continue
      if pg_sepol "$RULE" 2>>"$PG/apply.log"; then
        pg_log "sepolicy: $RULE"
      else
        pg_fail sepolicy "注入失败: $RULE (策略版本不兼容?)"
      fi
    done
  else
    pg_log "sepolicy: 无 magiskpolicy/ksud, 已写 sepolicy.rule 待下次启动由管理器加载"
  fi
fi

# ---------- 5d. 网络过滤器加固 k_netfilter ----------
# 前端承诺: 内核层丢弃追踪数据包(STUN/SSDP/UPnP)。
# 真正的 netfilter 内核钩子需自编译内核模块; 本模块走免编译路线,
# 因此降级为 raw 表规则实现同等效果(对应用层等价, 不拦内核内部流量), 并如实标注。
# 配置: k_netfilter 总开关 + [conf:k_netfilter] hook_netfilter/drop_tracking_packets/drop_proto
#       注意 drop_proto 可有多行(每行一个协议), 必须全部收集。
knf_true() { case "$1" in 1|[Tt][Rr][Uu][Ee]|on|yes) return 0;; *) return 1;; esac; }
pg_knf_on() { knf_true "$(pg_get k_netfilter 0)"; }
# 幂等：重建前先收敛旧挂载，再确认整张 raw 表没有任何链引用。
# 只删一次 OUTPUT 跳转会留下历史重复引用；在仍被引用时 -F 会清空
# 被调用链，造成“开关显示启用但规则失效”。对 IPv4/IPv6 分别处理，
# 查询失败时保留旧链并禁止重建该族，避免把未知状态当作清理成功。
_pg_knf_prepare_family() {
  _pk_bin=$1 _pk_chain=$2 _pk_ok=1 _pk_i=0
  while [ "$_pk_i" -lt 64 ]; do
    "$_pk_bin" $FWWAIT -t raw -D OUTPUT -j "$_pk_chain" >/dev/null 2>&1 || break
    _pk_i=$((_pk_i+1))
  done
  if _pk_rules=$("$_pk_bin" $FWWAIT -t raw -S 2>/dev/null); then
    if printf '%s\n' "$_pk_rules" | grep -E "^-A .* -j ${_pk_chain}([[:space:]]|$)" >/dev/null 2>&1; then
      pg_fail netfilter "$_pk_bin raw 仍有规则引用 $_pk_chain；保留链，跳过本族重建"
      return 1
    fi
  else
    pg_fail netfilter "$_pk_bin raw 规则表查询失败；保留 $_pk_chain 并跳过本族重建"
    return 1
  fi
  if "$_pk_bin" $FWWAIT -t raw -F "$_pk_chain" >/dev/null 2>&1; then
    "$_pk_bin" $FWWAIT -t raw -X "$_pk_chain" >/dev/null 2>&1 || {
      pg_fail netfilter "$_pk_bin 无法删除旧链 $_pk_chain；跳过本族重建"
      return 1
    }
  else
    # 链不存在与 flush 失败需区分；整表查询成功且无链声明时才算已清理。
    if printf '%s\n' "$_pk_rules" | grep -E "^-N ${_pk_chain}([[:space:]]|$)" >/dev/null 2>&1; then
      pg_fail netfilter "$_pk_bin 无法清空旧链 $_pk_chain；跳过本族重建"
      return 1
    fi
  fi
  return 0
}
_PGNF4_READY=0; _PGNF6_READY=0
_pg_knf_prepare_family iptables PGNF && _PGNF4_READY=1
_pg_knf_prepare_family ip6tables PGNF6 && _PGNF6_READY=1
if pg_knf_on; then
  _knf_seg=$(pg_conf k_netfilter 2>/dev/null)
  _knf_hook=$(printf '%s\n' "$_knf_seg" | awk -F= '/^hook_netfilter=/{print $2}' | head -1)
  _knf_drop=$(printf '%s\n' "$_knf_seg" | awk -F= '/^drop_tracking_packets=/{print $2}' | head -1)
  # drop_proto 可能多行, 全部收集成空格分隔串
  _knf_proto=$(printf '%s\n' "$_knf_seg" | awk -F= '/^drop_proto=/{print $2}' | tr '\n' ' ')
  [ -n "$_knf_hook" ] || _knf_hook=true
  [ -n "$_knf_drop" ] || _knf_drop=true
  [ -n "$_knf_proto" ] || _knf_proto="STUN SSDP UPnP"
  if knf_true "$_knf_hook"; then
    if [ "$_PGNF4_READY" != "1" ] || [ "$_PGNF6_READY" != "1" ]; then
      pg_fail netfilter "旧 PGNF 链清理未能双栈确认；本轮不创建或挂载追踪包过滤规则"
    else
    fw4 -t raw -N PGNF  2>/dev/null
    fw6 -t raw -N PGNF6 2>/dev/null
    if knf_true "$_knf_drop"; then
      case " $_knf_proto " in
        *STUN*)
          fw4 -t raw -A PGNF -p udp --dport 3478 -j DROP      2>/dev/null  # STUN
          fw4 -t raw -A PGNF -p udp --dport 5349 -j DROP      2>/dev/null  # STUNS
          fw4 -t raw -A PGNF -p udp --dport 19302:19309 -j DROP 2>/dev/null # Google STUN 段
          fw6 -t raw -A PGNF6 -p udp --dport 3478 -j DROP     2>/dev/null
          fw6 -t raw -A PGNF6 -p udp --dport 5349 -j DROP     2>/dev/null
          ;;
      esac
      case " $_knf_proto " in
        *SSDP*)
          fw4 -t raw -A PGNF  -p udp --dport 1900 -j DROP 2>/dev/null     # SSDP
          fw6 -t raw -A PGNF6 -p udp --dport 1900 -j DROP 2>/dev/null
          ;;
      esac
      case " $_knf_proto " in
        *UPnP*)
          fw4 -t raw -A PGNF  -p tcp --dport 2869 -j DROP 2>/dev/null     # UPnP HTTP
          fw4 -t raw -A PGNF  -p udp --dport 3702 -j DROP 2>/dev/null     # WS-Discovery
          fw6 -t raw -A PGNF6 -p tcp --dport 2869 -j DROP 2>/dev/null
          fw6 -t raw -A PGNF6 -p udp --dport 3702 -j DROP 2>/dev/null
          ;;
      esac
    fi
    # fw4/fw6 的 -A 在批量模式下只写入队列；必须先提交两族规则，再挂 OUTPUT，
    # 否则 PGNF/PGNF6 可能以空链状态先被挂载，导致开关显示开启但规则未生效。
    if fw_flush 2>>"$PG/apply.log"; then
      _KNF_HOOK4=0; _KNF_HOOK6=0
      iptables  $FWWAIT -t raw -A OUTPUT -j PGNF  2>>"$PG/apply.log" && _KNF_HOOK4=1
      ip6tables $FWWAIT -t raw -A OUTPUT -j PGNF6 2>>"$PG/apply.log" && _KNF_HOOK6=1
      if [ "$_KNF_HOOK4" = "1" ] && [ "$_KNF_HOOK6" = "1" ] && \
         iptables $FWWAIT -t raw -C OUTPUT -j PGNF >/dev/null 2>&1 && \
         ip6tables $FWWAIT -t raw -C OUTPUT -j PGNF6 >/dev/null 2>&1; then
        pg_log "netfilter: 追踪包丢弃已挂载(proto=${_knf_proto% }, raw 表降级实现)"
      else
        [ "$_KNF_HOOK4" != "1" ] || iptables $FWWAIT -t raw -D OUTPUT -j PGNF 2>/dev/null || true
        [ "$_KNF_HOOK6" != "1" ] || ip6tables $FWWAIT -t raw -D OUTPUT -j PGNF6 2>/dev/null || true
        pg_fail netfilter "PGNF 双栈 OUTPUT 挂载或验证失败；已尝试回滚成功的一侧"
      fi
    else
      pg_fail netfilter "PGNF/PGNF6 规则队列提交失败；未挂载 OUTPUT，避免空链假启用"
    fi
    fi
  else
    pg_log "netfilter: hook_netfilter=false, 未挂载"
  fi
else
  pg_log "netfilter: disabled"
fi

# ---------- 6. 生成 LSPosed 配置 ----------
wait "$_XPOSED_BG_PID" 2>/dev/null
# wait 的退出码在多进程下不够可靠 → 以产物是否存在为准（原实现也是这个判据）。
if [ ! -s /data/local/tmp/privacyguard/xposed.conf ]; then
  pg_fail xposed "xposed.conf 未生成(LSPosed 层将读不到新配置)"
fi
pg_log "xposed.conf generated"
# If either independent Hook master is enabled and at least one per-app target
# is selected, require successful Remote Files publication. Do not gate privacy-only
# configurations on the ad master switch; that would let a failed publication look
# successful when ads are intentionally disabled.
_HOOK_ADS_ENABLED=$(pg_get hook_ads_enabled 0 2>/dev/null)
_HOOK_PRIVACY_ENABLED=$(pg_get hook_privacy_enabled 0 2>/dev/null)
_HOOK_TARGET_COUNT=$(pg_list hook_targets 2>/dev/null | awk -F'|' '$3 == "1" && $1 != "" {n++} END{print n+0}')
if { [ "$_HOOK_ADS_ENABLED" = "1" ] || [ "$_HOOK_PRIVACY_ENABLED" = "1" ]; } && [ "$_HOOK_TARGET_COUNT" -gt 0 ] 2>/dev/null && [ -d /data/adb/lspd ]; then
  if ! grep -q '^status=ok$' /data/local/tmp/privacyguard/xposed-remote.status 2>/dev/null; then
    pg_fail xposed "LSPosed Remote Files 配置发布未确认；应用内 Hook 将保持关闭，避免 UI 假报生效"
  else
    pg_log "LSPosed Remote Files target config published"
  fi
fi

# ---------- 7. 完成 ----------
# Start a single guarded watcher only when the complete local DNS chain and
# netfilter transaction succeeded. It delegates rollback to apply.sh; it never
# mutates firewall rules itself.
if [ "${DNS_AGH_ACTIVE:-0}" = "1" ] && \
   [ -s "$PG/dns/fxdns.pid" ] && [ -s "$PG/dns/fxdns.conf" ] && \
   [ -x "$MODDIR/scripts/localdns-watchdog.sh" ]; then
  if ! sh "$MODDIR/scripts/localdns-watchdog.sh" start "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1; then
    # With no verified monitor, try to fail open. Never stop the DNS engines
    # unless both firewall families positively confirm that OUTPUT no longer
    # references PGNAT: a failed -D/flush must not turn a live redirect into a
    # black hole pointing at stopped localhost resolvers.
    pg_fail dns "本地递归 DNS 看门狗未能验证存活；尝试撤销 FX NAT 接管；只有确认双栈 OUTPUT 均已摘除后才停止 DNS 引擎"
    _pg_dns_v4_detached=0
    _pg_dns_v6_detached=0
    _pg_dns_n=0
    while iptables $FWWAIT -t nat -D OUTPUT -j PGNAT 2>/dev/null; do
      _pg_dns_n=$((_pg_dns_n+1))
      [ "$_pg_dns_n" -lt 64 ] || break
    done
    if iptables $FWWAIT -t nat -S OUTPUT >/dev/null 2>&1; then
      if ! iptables $FWWAIT -t nat -S OUTPUT 2>/dev/null | grep -E -- '(^-A OUTPUT .* -j PGNAT([[:space:]]|$)|^-A OUTPUT .* -g PGNAT([[:space:]]|$))' >/dev/null 2>&1; then
        _pg_dns_v4_detached=1
      fi
    fi
    _pg_dns_n=0
    while ip6tables $FWWAIT -t nat -D OUTPUT -j PGNAT 2>/dev/null; do
      _pg_dns_n=$((_pg_dns_n+1))
      [ "$_pg_dns_n" -lt 64 ] || break
    done
    if ip6tables $FWWAIT -t nat -S OUTPUT >/dev/null 2>&1; then
      if ! ip6tables $FWWAIT -t nat -S OUTPUT 2>/dev/null | grep -E -- '(^-A OUTPUT .* -j PGNAT([[:space:]]|$)|^-A OUTPUT .* -g PGNAT([[:space:]]|$))' >/dev/null 2>&1; then
        _pg_dns_v6_detached=1
      fi
    fi
    if [ "$_pg_dns_v4_detached" = 1 ] && [ "$_pg_dns_v6_detached" = 1 ]; then
      # Only mutate the chain after the jumps are verified absent.
      if ! iptables $FWWAIT -t nat -F PGNAT 2>/dev/null || ! iptables $FWWAIT -t nat -X PGNAT 2>/dev/null; then
        pg_log "CRITICAL dns: IPv4 PGNAT chain cleanup incomplete; OUTPUT is verified detached, retry cleanup on next apply"
      fi
      if ! ip6tables $FWWAIT -t nat -F PGNAT 2>/dev/null || ! ip6tables $FWWAIT -t nat -X PGNAT 2>/dev/null; then
        pg_log "CRITICAL dns: IPv6 PGNAT chain cleanup incomplete; OUTPUT is verified detached, retry cleanup on next apply"
      fi
      sh "$MODDIR/scripts/localdns-watchdog.sh" stop "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || :
      sh "$MODDIR/scripts/fxdns.sh" stop "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || :
    else
      pg_log "CRITICAL dns: could not positively verify both IPv4/IPv6 OUTPUT jumps detached (v4=$_pg_dns_v4_detached v6=$_pg_dns_v6_detached); leaving local DNS engines running to avoid black-holing redirected traffic"
    fi
  fi
fi
date '+%Y-%m-%d %H:%M:%S' > "$PG/last_apply"
pg_summary "apply"
exit $?
