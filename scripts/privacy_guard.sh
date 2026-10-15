#!/system/bin/sh
# ============================================================
#  privacy_guard.sh — 隐私护盾：FX/风控应用深度定制 + 能力面收紧
#  ------------------------------------------------------------
 #  按 SY 的约定实现：
 #   · 配置读写用 SY 的 cfg_get / cfg_set
 #   · iptables 链名用 SY_* 前缀（避免与其他模块的链名冲突）
 #   · 状态文件写到 $DATA_DIR/rules/privacy/ 下
#
#  三层手段：
#   ① 网络隔离：按 uid 掐断目标应用全部出站（IPv4+IPv6，REJECT 或 DROP）
#   ② appops 收紧：禁 QUERY_ALL_PACKAGES / GET_USAGE_STATS / 剪贴板 / 悬浮窗 / 通知监听
#   ③ 能力面收紧：禁用无障碍服务（可读全屏+自动点击）、移除设备管理员、收回危险运行时权限
#
#  为什么需要第 ③ 层：只掐网络挡不住这类应用 —— 它们真正的敏感能力是
#  无障碍（读全屏内容）、设备管理员、通知监听，这些与网络无关，iptables 拦不住。
#
#  安全约定：每一项都先探测「该组件存在/启用/已授予」再动手，探测不到就如实跳过；
#  原始状态记入状态文件，关闭/卸载时逐项精确还原，绝不把用户本来没给的权限"归还"成授予。
#
#  用法: privacy_guard.sh {apply|remove|status|check}
# ============================================================
. "$(dirname "$0")/common.sh"

PG_DIR="$DATA_DIR/rules/privacy"
PG_DONE="$PG_DIR/restore.state"     # 记录"本来有、被我收走的"，用于精确还原
PG_TARGETS="$PG_DIR/targets.conf"  # 目标包名（每行一个，逗号分隔也接受）
PG_CHAIN="SY_PG"                   # IPv4 链名（前缀 SY，避免与其他模块链名冲突）
PG_CHAIN6="SY_PG6"                 # IPv6 链名
TAB=$(printf '\t')
mkdir -p "$PG_DIR" 2>/dev/null

# 目标包名：优先读面板可编辑的 targets.conf，其次读 sy.conf 的 PRIVACY_PACKAGES
pg_packages() {
  # 目标包名来源：优先面板可编辑的 targets.conf，其次 sy.conf 的 PRIVACY_PACKAGES。
  # 逗号分隔的支持用 tr 拆行（这里不写字面 \n，避免转义层级出错）。
  if [ -s "$PG_TARGETS" ]; then
    grep -vE "^[[:space:]]*(#|$)" "$PG_TARGETS" 2>/dev/null | tr -d "\r" | grep -v "^[[:space:]]*$"
  else
    cfg_get PRIVACY_PACKAGES "" | tr "," "\n" | grep -v "^$"
  fi
}

# 单条目探测：包名 -> uid（未安装输出空）
pg_uid() {
  [ -z "$1" ] && return
  dumpsys package "$1" 2>/dev/null | sed -n 's/.*userId=\([0-9]*\).*/\1/p' | head -n1
}

# 已处理过就不重复（增量去重，避免二次 apply 清空历史导致无法还原）
pg_done() {
  [ -f "$PG_DONE" ] || return 1
  grep -qF "$1${TAB}$2${TAB}$3" "$PG_DONE" 2>/dev/null
}
pg_record() {
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$PG_DONE"
}

# 真实环境判定：防止在 PC/CI 上误改真实系统
pg_android() { [ -f /system/build.prop ] || [ -n "$SY_FORCE_APPLY" ]; }

# ---------- ① 网络隔离 ----------
pg_network_apply() {
  if ! command -v iptables >/dev/null 2>&1; then
    echo "iptables 不可用：UID 级网络隔离无法生效"
    log "privacy_guard: iptables 不可用"
    return 1
  fi
  jump=$(cfg_get PRIVACY_JUMP REJECT)
  iptables -w -N "$PG_CHAIN" 2>/dev/null
  iptables -w -F "$PG_CHAIN" 2>/dev/null
  if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -w -N "$PG_CHAIN6" 2>/dev/null
    ip6tables -w -F "$PG_CHAIN6" 2>/dev/null
  fi
  n=0
  pg_packages > "$PG_DIR/.pkgs.$$" 2>/dev/null
  : > "$PG_DIR/targets.uid"
  while IFS= read -r pkg; do
    [ -z "$pkg" ] && continue
    uid=$(pg_uid "$pkg")
    if [ -z "$uid" ]; then
      log "privacy_guard: 目标未安装，跳过 $pkg"
      continue
    fi
    printf '%s %s\n' "$pkg" "$uid" >> "$PG_DIR/targets.uid"
    iptables -w -A "$PG_CHAIN" -m owner --uid-owner "$uid" -j "$jump" 2>/dev/null && n=$((n+1))
    command -v ip6tables >/dev/null 2>&1 && ip6tables -w -A "$PG_CHAIN6" -m owner --uid-owner "$uid" -j "$jump" 2>/dev/null
    log "privacy_guard: 出站封锁 $pkg (uid=$uid) -> $jump"
  done < "$PG_DIR/.pkgs.$$"
  rm -f "$PG_DIR/.pkgs.$$"
  iptables -w -C OUTPUT -j "$PG_CHAIN" 2>/dev/null || iptables -w -I OUTPUT 1 -j "$PG_CHAIN" 2>/dev/null
  command -v ip6tables >/dev/null 2>&1 && { ip6tables -w -C OUTPUT -j "$PG_CHAIN6" 2>/dev/null || ip6tables -w -I OUTPUT 1 -j "$PG_CHAIN6" 2>/dev/null; }
  [ "$n" = "0" ] && log "privacy_guard: 无已安装目标，网络隔离未产生规则"
}

pg_network_remove() {
  if command -v iptables >/dev/null 2>&1; then
    iptables -w -C OUTPUT -j "$PG_CHAIN" 2>/dev/null && iptables -w -D OUTPUT -j "$PG_CHAIN" 2>/dev/null
    iptables -w -F "$PG_CHAIN" 2>/dev/null; iptables -w -X "$PG_CHAIN" 2>/dev/null
  fi
  if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -w -C OUTPUT -j "$PG_CHAIN6" 2>/dev/null && ip6tables -w -D OUTPUT -j "$PG_CHAIN6" 2>/dev/null
    ip6tables -w -F "$PG_CHAIN6" 2>/dev/null; ip6tables -w -X "$PG_CHAIN6" 2>/dev/null
  fi
}

# ---------- ② appops 收紧 ----------
PG_OPS="QUERY_ALL_PACKAGES GET_USAGE_STATS READ_CLIPBOARD SYSTEM_ALERT_WINDOW ACCESS_NOTIFICATIONS RECEIVE_SENSITIVE_NOTIFICATIONS ACCESS_RESTRICTED_SETTINGS"
pg_ops_apply() {
  command -v appops >/dev/null 2>&1 || { log "privacy_guard: 无 appops"; return; }
  for pkg in "$@"; do
    for op in $PG_OPS; do
      pg_done op "$pkg" "$op" && continue
      cur=$(appops get --user 0 "$pkg" "$op" 2>/dev/null)
      case "$cur" in *": deny"*) continue ;; esac
      case "$cur" in
        *": allow"*)  orig="allow" ;;
        *": ignore"*) orig="ignore" ;;
        *"No operations"*|"") orig="default" ;;
        *) orig="default" ;;
      esac
      if appops set --user 0 "$pkg" "$op" deny >/dev/null 2>&1; then
        pg_record op "$pkg" "$op" "$orig"
        log "privacy_guard: 收紧 $op: $pkg（原值 $orig）"
      else
        log "privacy_guard: appops 不支持或拒绝 $pkg $op（如实记录，不当作成功）"
      fi
    done
  done
}

# ---------- ③ 能力面收紧 ----------
pg_perm_granted() { dumpsys package "$1" 2>/dev/null | grep -F "$2" | grep -q "granted=true"; }
PG_PERMS="android.permission.ACCESS_FINE_LOCATION android.permission.ACCESS_COARSE_LOCATION android.permission.READ_CONTACTS android.permission.READ_CALL_LOG android.permission.READ_SMS android.permission.RECORD_AUDIO android.permission.CAMERA android.permission.READ_PHONE_STATE android.permission.BODY_SENSORS android.permission.GET_ACCOUNTS android.permission.READ_EXTERNAL_STORAGE"
pg_perms_apply() {
  command -v pm >/dev/null 2>&1 || { log "privacy_guard: 无 pm"; return; }
  for pkg in "$@"; do
    for perm in $PG_PERMS; do
      pg_done perm "$pkg" "$perm" && continue
      pg_perm_granted "$pkg" "$perm" || continue   # 只处理真的已授予的
      if pm revoke --user 0 "$pkg" "$perm" >/dev/null 2>&1; then
        pg_record perm "$pkg" "$perm" ""
        log "privacy_guard: 收回权限 $pkg <- $perm"
      else
        log "privacy_guard: revoke 被拒 $pkg $perm"
      fi
    done
  done
}

pg_accessibility_apply() {
  command -v settings >/dev/null 2>&1 || { log "privacy_guard: 无 settings"; return; }
  enabled=$(settings get secure enabled_accessibility_services 2>/dev/null)
  case "$enabled" in ""|null) return ;; esac
  for pkg in "$@"; do
    hit=$(printf '%s' "$enabled" | tr ':' '\n' | grep "^$pkg/" | head -n1)
    [ -z "$hit" ] && continue
    pg_done acc "$pkg" "$hit" && continue
    new=$(printf '%s' "$enabled" | tr ':' '\n' | grep -v "^$pkg/" | tr '\n' ':' | sed 's/:$//')
    if settings put secure enabled_accessibility_services "$new" >/dev/null 2>&1; then
      pg_record acc "$pkg" "$hit" "removed"
      log "privacy_guard: 已禁用无障碍服务 $hit"
    else
      log "privacy_guard: 禁用无障碍失败（ROM 限制）$hit"
    fi
  done
}

pg_device_admin_apply() {
  command -v dpm >/dev/null 2>&1 || { log "privacy_guard: 无 dpm"; return; }
  raw=$(dpm list packages 2>/dev/null)
  case "$raw" in ""|*"No active admin"*|*"Error"*) return ;; esac
  for pkg in "$@"; do
    line=$(printf '%s' "$raw" | grep -F "$pkg" | head -n1)
    [ -z "$line" ] && continue
    # 注意：这里不能先按 "admin" 去重 —— 记录里存的是**真实接收器名**，
    # 键不一致会导致二次 apply 重复记录（真执行时抓到的缺陷）。先解析再判重。
    # 从输出解析真实接收器名：各应用不同，硬编码 .AdminReceiver 几乎必然失败
    comp=$(printf '%s' "$line" | sed -n 's/.*ComponentInfo{\([^}]*\)}.*/\1/p')
    if [ -n "$comp" ]; then
      rpkg=${comp%%/*}; rrecv=${comp#*/}
    else
      rpkg="$pkg"; rrecv=""
    fi
    pg_done dpm "$pkg" "$rrecv" && continue
    if [ -n "$rrecv" ] && dpm remove-active-admin "$rpkg" "$rrecv" >/dev/null 2>&1; then
      pg_record dpm "$pkg" "$rrecv" ""
      log "privacy_guard: 已移除设备管理员 $pkg (接收器 $rrecv)"
    else
      log "privacy_guard: 无法自动移除设备管理员 $pkg（接收器未解析到或系统拒绝），需在系统设置手动取消"
    fi
  done
}

# ---------- 主流程 ----------
pg_apply() {
  [ "$(cfg_get PRIVACY_ENABLE 0)" = "1" ] || { pg_remove; return 0; }
  pg_android || { echo "(非 Android 环境，跳过实际应用)"; return 0; }
  pkgs=$(pg_packages)
  if [ -z "$(printf '%s' "$pkgs" | tr -d ' \n')" ]; then
    echo "PRIVACY_TARGETS 目标清单为空：请在面板「隐私护盾」页填写要隔离的包名"
    log "privacy_guard: 目标清单为空"
    return 0
  fi
  # shell 的分词会把多行拆成多个参数
  set -- $pkgs
  pg_network_apply
  pg_ops_apply "$@"
  pg_perms_apply "$@"
  pg_accessibility_apply "$@"
  pg_device_admin_apply "$@"
  log "privacy_guard: 应用完成（目标 $(printf '%s\n' "$@" | grep -c . ) 个）"
  echo "OK: 隐私护盾已应用（网络隔离 + appops + 能力面；明细见 $PG_DONE）"
}

pg_remove() {
  pg_android || return 0
  pg_network_remove
  n=0
  if [ -f "$PG_DONE" ]; then
    while IFS="$TAB" read -r kind pkg what orig; do
      [ -n "$pkg" ] || continue
      case "$kind" in
        op)   [ -n "$what" ] && appops set --user 0 "$pkg" "$what" "${orig:-default}" >/dev/null 2>&1 && n=$((n+1)) ;;
        perm) [ -n "$what" ] && pm grant --user 0 "$pkg" "$what" >/dev/null 2>&1 && n=$((n+1)) ;;
        acc)
          # 合并式还原：只把本模块移除的那个组件加回**当前**列表，
          # 不覆盖用户之后新启用的其他无障碍服务
          [ -n "$what" ] || continue
          cur_acc=$(settings get secure enabled_accessibility_services 2>/dev/null)
          case "$cur_acc" in ""|null) new_acc="$what" ;; *)
            case ":$cur_acc:" in
              *":$what:"*) new_acc="$cur_acc" ;;
              *) new_acc="$cur_acc:$what" ;;
            esac ;;
          esac
          settings put secure enabled_accessibility_services "$new_acc" >/dev/null 2>&1 && n=$((n+1)) ;;
        dpm)  log "privacy_guard: 设备管理员曾被本模块移除 $pkg —— 无法自动恢复，需在系统设置重新激活（如实说明）" ;;
      esac
    done < "$PG_DONE"
    rm -f "$PG_DONE"
  fi
  rm -f "$PG_DIR/targets.uid"
  log "privacy_guard: 已还原 $n 项"
  echo "OK: 隐私护盾已关闭（归还 $n 项，逐项按原始值还原）"
}

pg_status() {
  n=0; [ -f "$PG_DONE" ] && n=$(wc -l < "$PG_DONE" 2>/dev/null | tr -d ' ')
  tn=0; for p in $(pg_packages); do tn=$((tn+1)); done
  printf '{"feature":"%s","jump":"%s","targets":%s,"recorded":%s,"chain":"%s"}\n' \
    "$(cfg_get PRIVACY_ENABLE 0)" "$(cfg_get PRIVACY_JUMP REJECT)" "$tn" "${n:-0}" "$PG_CHAIN"
}

pg_check() {
  echo "== 隐私护盾自检 =="
  echo "开关: $(cfg_get PRIVACY_ENABLE 0)  动作: $(cfg_get PRIVACY_JUMP REJECT)"
  echo "目标清单: $PG_TARGETS"
  pg_packages | while IFS= read -r p; do [ -n "$p" ] && echo "  $p uid=$(pg_uid "$p")"; done
  if command -v iptables >/dev/null 2>&1; then
    iptables -nL "$PG_CHAIN" >/dev/null 2>&1 && echo "网络隔离链: 在位" || echo "网络隔离链: 未应用"
  else
    echo "网络隔离链: iptables 不可用"
  fi
  [ -f "$PG_DONE" ] && echo "已记录待还原: $(wc -l < "$PG_DONE") 项" || echo "已记录待还原: 0 项"
}

case "$1" in
  apply)  pg_apply ;;
  remove) pg_remove ;;
  status) pg_status ;;
  check)  pg_check ;;
  *) echo "usage: privacy_guard.sh {apply|remove|status|check}"; exit 2 ;;
esac
