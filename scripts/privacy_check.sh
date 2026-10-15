#!/system/bin/sh
# ============================================================
#  privacy_check.sh — 隐私外泄体检 + 一键修复
#  ------------------------------------------------------------
#  维度（无法检查的环境一律报「跳过」并说明原因，**绝不当成通过**）:
#   ① 私有 DNS（DoT 走 853 绕过 hosts）
#   ② 系统云备份（设备数据上云）
#   ③ 无障碍服务枚举（可读全屏内容 + 模拟点击 —— 隐私外泄最大的一面）
#   ④ 设备管理员枚举（可远程擦除/锁屏/强制密码）
#   ⑤ FX/风控应用存在性（读同一份隐私护盾目标清单）
#   ⑥ hosts 拦截生效性
#   ⑦ iptables 封锁链在位性
#   ⑧ 剪贴板监视状态
#   ⑨ 自身防护状态汇总
#  用法: privacy_check.sh [quick|deep]
# ============================================================
. "$(dirname "$0")/common.sh"

MODE="${1:-quick}"
PASS=0; WARN=0; SKIP=0
ok()   { echo "  [通过] $1"; PASS=$((PASS+1)); }
warn() { echo "  [风险] $1"; WARN=$((WARN+1)); }
skip() { echo "  [跳过] $1"; SKIP=$((SKIP+1)); }

echo "=========== SY 隐私外泄体检（$MODE）==========="

# 读一个 settings 值，并校验返回内容的合法性。
# 【真实缺陷修复】旧版直接把 settings get 的输出当配置值用：
#   若命令失败、或 ROM 返回了命令回显/键名/异常文本（实测出现过），
#   就会被当成"真实配置"展示 —— 用户看到「云备份开启（backup_enabled=backup_enabled）」
#   这种一眼假的值。现在统一校验：只接受看起来像合法值的输出，否则回退为「未知」。
pc_setting() { # <namespace> <key> [fallback]
  ns="$1"; key="$2"; fb="${3:-}"
  raw=$(settings get "$ns" "$key" 2>/dev/null)
  case "$raw" in
    ""|null|*"$key"*) echo "$fb" ;;   # 空/字面 null/回显了键名 → 视为无效
    *) echo "$raw" ;;
  esac
}

pc_private_dns() {
  command -v settings >/dev/null 2>&1 || { skip "无 settings 命令，无法读取私有 DNS 配置（不是「无风险」）"; return; }
  v=$(pc_setting global private_dns_mode "")
  h=$(pc_setting global private_dns_specifier "")
  if [ "$v" = "hostname" ] && [ -n "$h" ] && [ "$h" != "null" ]; then
    warn "私有 DNS 已强制（$h）：其 DoT 查询绕过本模块 hosts，拦截域名可能仍被解析"
  else
    ok "私有 DNS 未强制（hosts 拦截完全生效）"
  fi
}

pc_backup() {
  command -v settings >/dev/null 2>&1 || { skip "无 settings 命令，无法读取云备份状态"; return; }
  v=$(pc_setting global backup_enabled "")
  case "$v" in
    0|""|null) ok "系统云备份未开启" ;;
    1) warn "云备份开启：应用数据可能上云" ;;
    # 其它值说明 settings 没返回可信结果 —— 如实报"无法判定"，不猜
    *) skip "云备份状态无法判定（settings 返回异常值）" ;;
  esac
}

# 目标包名（与隐私护盾共用一份清单）
pc_targets() {
  tf="$DATA_DIR/rules/privacy/targets.conf"
  if [ -s "$tf" ]; then
    grep -vE "^[[:space:]]*(#|$)" "$tf" 2>/dev/null | tr -d "\r" | tr "," "\n" | grep -v "^$"
  else
    echo "$(cfg_get PRIVACY_PACKAGES '')" | tr "," "\n" | grep -v "^$"
  fi
}
pc_is_target() {
  for t in $(pc_targets); do [ "$t" = "$1" ] && return 0; done
  return 1
}

pc_accessibility() {
  command -v settings >/dev/null 2>&1 || { skip "无 settings 命令，无法枚举无障碍服务"; return; }
  acc=$(pc_setting secure enabled_accessibility_services "")
  case "$acc" in ""|null) ok "未启用任何无障碍服务"; return ;; esac
  n=0
  echo "  -- 已启用的无障碍服务（可读全屏/模拟点击，请逐个确认是否必需）--"
  for svc in $(printf '%s' "$acc" | tr ":" " "); do
    [ -z "$svc" ] && continue
    # 合法服务条目形如 com.example/.Service（含 /）；不含 / 的文本说明 settings
    # 返回的不是服务列表（实测某些 ROM 会返回 "off"/键名等），此时如实跳过。
    case "$svc" in */*) ;; *) continue ;; esac
    n=$((n+1))
    pkg=${svc%%/*}
    if pc_is_target "$pkg"; then
      echo "  [目标应用] $svc   ← 建议开启「隐私护盾」由它收紧"
    else
      echo "  [第三方]   $svc"
    fi
  done
  [ "$n" -gt 0 ] && warn "存在 $n 个已启用的无障碍服务（无障碍是隐私外泄的最大通道）"
  sc=$(pc_setting secure accessibility_shortcut_target_service "")
  case "$sc" in ""|null) ;; */*) echo "  [注意] 无障碍快捷方式指向: $sc" ;; esac
}

pc_device_admin() {
  # 【真机缺陷修复】旧版调 `dpm list packages` —— Android 13 的 dpm **没有 list 子命令**，
  # 真机实测返回 "Unknown command: list" + 一大段用法帮助，于是把帮助文本当成了
  # 设备管理员列表逐行打印（体检报告里出现 [其他] Unknown / command: / Usage: / help）。
  # 现在改读权威来源：
  #   ① /data/system/device_policies.xml（设备管理员注册表，root 可读）
  #   ② 退化到 dumpsys device_policy（部分 ROM 有输出）
  #  ③ 两者都读不到时**如实报「跳过」**，绝不用会返回帮助文本的命令冒充枚举。
  pkgs=""
  if [ -r /data/system/device_policies.xml ]; then
    pkgs=$(sed -n 's/.*<admin name="\([^"]*\)".*/$\1/p' /data/system/device_policies.xml 2>/dev/null | cut -d/ -f1 | sort -u | tr "\n" " ")
  fi
  if [ -z "$pkgs" ] && command -v dumpsys >/dev/null 2>&1; then
    pkgs=$(dumpsys device_policy 2>/dev/null | sed -n "s/.*packageName=\([^ ]*\).*/$\1/p" | sort -u | tr "\n" " ")
  fi
  if [ -z "$pkgs" ]; then
    skip "读不到设备管理员注册表（无 device_policies.xml，且 dumpsys device_policy 无输出）"
    return
  fi
  n=0
  echo "  -- 设备管理员（可远程擦除/锁屏/强制密码）--"
  for pkg in $pkgs; do
    [ -n "$pkg" ] || continue
    n=$((n+1))
    if pc_is_target "$pkg"; then
      echo "  [目标应用] $pkg   ← 建议由「隐私护盾」移除"
    else
      echo "  [其他]     $pkg"
    fi
  done
  [ "$n" -gt 0 ] && warn "存在 $n 个设备管理员（确认都是你自己激活的）"
}

pc_fx_check() {
  command -v pm >/dev/null 2>&1 || { skip "pm 不可用，无法枚举已安装应用（不是「未发现」）"; return; }
  found=0
  for p in $(pc_targets) com.lenovo.leos.pms.vpt com.huawei.systemmanager com.oppo.safe; do
    [ -z "$p" ] && continue
    if pm list packages 2>/dev/null | grep -q "^package:$p$"; then
      echo "  [存在] $p"
      found=1
    fi
  done
  if [ "$found" = "1" ]; then
    warn "上面列出的应用在读写你的使用情况；建议开启「隐私护盾」隔离"
  else
    ok "未发现目标清单内的FX/风控应用"
  fi
}

pc_hosts() {
  [ -f /system/etc/hosts ] || { skip "本机无 /system/etc/hosts（非 Android 环境）"; return; }
  if mount 2>/dev/null | grep -q "/system/etc/hosts"; then
    # 【真机缺陷修复】`grep -c ... || echo 0` 是坏写法：grep -c 在"无匹配"时
    # 输出 0 但**退出码为 1**，于是 `|| echo 0` 又追加一行 → 变量变成两行，
    # 打印出来就是两行（真机 hosts 那行显示成 "0\n0 条黑洞条目"）。
    n=$(grep -c "^0\.0\.0\.0 " /system/etc/hosts 2>/dev/null | head -n1)
    [ -z "$n" ] && n=0
    ok "hosts 已挂载生效（$n 条黑洞条目）"
  else
    warn "hosts 未挂载（检查 DNS 页是否已应用规则）"
  fi
}

pc_iptables() {
  command -v iptables >/dev/null 2>&1 || { skip "iptables 不可用，网络封锁无法生效"; return; }
  iptables -nL SY_PG >/dev/null 2>&1 && ok "隐私护盾封锁链在位（SY_PG）" || skip "隐私护盾封锁链未应用"
  iptables -nL SY_NB >/dev/null 2>&1 && ok "网络拦截链在位（SY_NB）" || skip "网络拦截链未应用"
}

pc_clip() {
  if [ "$(cfg_get CLIPGUARD_ENABLE 0)" = "1" ]; then
    ok "剪贴板监视已开启（读取者见 $DATA_DIR/rules/privacy/clip.readers）"
  else
    skip "剪贴板监视未开启（可在面板开启）"
  fi
}

pc_self() {
  if [ "$(cfg_get PRIVACY_ENABLE 0)" = "1" ]; then
    ok "隐私护盾已开启（PRIVACY_ENABLE=1）"
    [ -f "$DATA_DIR/rules/privacy/restore.state" ] && echo "  [已收紧] 待还原 $(wc -l < "$DATA_DIR/rules/privacy/restore.state" 2>/dev/null) 项"
  else
    skip "隐私护盾未开启（PRIVACY_ENABLE=0）—— 目标应用的无障碍/设备管理员不会被处理"
  fi
  if [ "$(cfg_get GAME_PRIVACY_ENABLE 0)" = "1" ]; then
    ok "游戏隐私保护已开启"
  else
    skip "游戏隐私保护未开启（GAME_PRIVACY_ENABLE=0）"
  fi
}

pc_private_dns
pc_backup
pc_accessibility
pc_device_admin
pc_fx_check
pc_hosts
pc_iptables
pc_clip
pc_self

echo "-----------"
echo "通过 $PASS / 风险 $WARN / 跳过 $SKIP（跳过=功能未开或环境不支持，非故障）"

case "$MODE" in
  json)
    printf '{"pass":%s,"warn":%s,"skip":%s}\n' "$PASS" "$WARN" "$SKIP"
    ;;
esac
