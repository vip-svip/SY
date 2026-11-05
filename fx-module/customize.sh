#!/system/bin/sh
# FX 1.0.0 customize.sh — 模块安装脚本（KernelSU / Magisk / APatch 通用）
SKIPUNZIP=0

ui_print "==================================="
ui_print "  FX 1.0.0 — 隐私防护模块"
ui_print "  网络规则、VPN 与可选应用层扩展"
ui_print "==================================="
ui_print ""

# 环境检查
if [ -d /data/adb/ksu ] || [ -d /data/adb/ksud ]; then
  ui_print "[✓] KernelSU 环境"
elif [ -d /data/adb/apd ]; then
  ui_print "[✓] APatch 环境"
elif [ -d /data/adb/magisk ]; then
  ui_print "[✓] Magisk 环境"
else
  ui_print "[!] 未识别的管理器，继续安装（service 脚本将尽力工作）"
fi

# Framework presence is informational; app recommendations are shown in FX Hook target picker.
if [ -d /data/adb/lspd ] || [ -d /data/adb/modules/zygisk_lsposed ] || [ -d /data/adb/modules/riru_lsposed ]; then
  ui_print "[i] 检测到 LSPosed 相关目录（不代表框架已激活）"
else
  ui_print "[i] 未检测到 LSPosed 相关目录；Hook APK 仍会尝试安装"
fi
ui_print "    Hook 应用列表与按应用配置位于 FX Hook 原生 App 的 Hook 标签页。"
ui_print "    用户安装的应用会优先显示为建议评估对象；这是通用建议，不保证每个应用兼容。"
ui_print "    FX 会尝试安装随包提供的 Hook APK；刷入阶段失败时，开机服务会重试。"
ui_print "    Hook 应用列表与按应用配置位于 FX Hook 原生 App 的 Hook 标签页。"
ui_print "    安装结果日志：/data/adb/privacyguard/adhook-install.log"
ui_print ""
ui_print "- 备份可能被修改的系统状态..."
# bind mount 不改原文件本身，但为完整回滚记录原始 hosts 与关键属性
BK=/data/adb/privacyguard/backup
mkdir -p "$BK"
if [ -f /system/etc/hosts ] && [ ! -f "$BK/hosts.orig" ]; then
  cp /system/etc/hosts "$BK/hosts.orig" 2>/dev/null
  ui_print "  已备份 /system/etc/hosts -> backup/hosts.orig"
fi
if [ ! -f "$BK/props.orig" ]; then
  { getprop ro.boot.verifiedbootstate; getprop ro.boot.flash.locked
    getprop ro.boot.vbmeta.device_state; getprop ro.serialno
    getprop ro.build.version.security_patch
  } > "$BK/props.orig" 2>/dev/null
  ui_print "  已记录关键系统属性原始值 -> backup/props.orig"
fi

ui_print "- 设置权限..."
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh"       0 0 0755
set_perm "$MODPATH/post-fs-data.sh"  0 0 0755
set_perm "$MODPATH/action.sh"        0 0 0755
set_perm "$MODPATH/uninstall.sh"     0 0 0755
set_perm "$MODPATH/customize.sh"     0 0 0755
set_perm_recursive "$MODPATH/scripts" 0 0 0755 0755
set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644

# Install Hook APKs into /data/app as ordinary applications. This specific
# deployment path does not rely on KernelSU system/priv-app mounting. Failure
# is non-fatal: the service script retries after boot and logs the result.
ui_print "- 安装可选 LSPosed Hook 应用（普通 APK 安装，不依赖 Hook 的 system/priv-app 挂载）..."
if sh "$MODPATH/scripts/install_adhook_app.sh" "$MODPATH"; then
  ui_print "    Hook 应用列表与按应用配置位于 FX Hook 原生 App 的 Hook 标签页。"
  if [ ! -d /data/adb/lspd ] && [ ! -d /data/adb/modules/zygisk_lsposed ] && [ ! -d /data/adb/modules/riru_lsposed ]; then
    ui_print "  [!] 未检测到 LSPosed 框架；不会自动刷入可能不兼容的框架模块。"
    ui_print "      请先在 KernelSU 安装与当前 Android 版本兼容的 ZygiskNext 和 LSPosed 模块，重启后配置 Scope。"
  else
    ui_print "    Hook 应用列表与按应用配置位于 FX Hook 原生 App 的 Hook 标签页。"
  fi
else
  ui_print "  [!] Hook APK 尚未安装；FX 主模块继续安装，开机后会自动重试，详情见 adhook-install.log"
fi

# 内置代理内核：必须 0755（上面的 0644 递归设置会使其不可执行）
ui_print "- 配置内置代理内核..."
PG_ABI=$(getprop ro.product.cpu.abi 2>/dev/null)
[ -z "$PG_ABI" ] && PG_ABI=$(uname -m 2>/dev/null)
case "$PG_ABI" in
  arm64*|aarch64) PG_ARCH=arm64 ;;
  armv7*|armeabi*) PG_ARCH=arm ;;
  x86_64|amd64) PG_ARCH=amd64 ;;
  *86*) PG_ARCH=386 ;;
  *) PG_ARCH=arm64 ;;
esac
if [ -f "$MODPATH/bin/$PG_ARCH/sing-box" ]; then
  set_perm "$MODPATH/bin/$PG_ARCH/sing-box" 0 0 0755
  ui_print "  [✓] 内置 sing-box ($PG_ARCH) 就绪，离线可用"
  # 删除不匹配架构的内核，节省设备空间（如设备为 arm64 则移除 arm）
  for _a in arm64 arm amd64 386; do
    [ "$_a" = "$PG_ARCH" ] && continue
    if [ -d "$MODPATH/bin/$_a" ]; then
      [ -n "$MODPATH" ] && [ -n "$_a" ] && rm -rf "${MODPATH:?}/bin/$_a" 2>/dev/null
      ui_print "  [-] 移除不匹配架构内核 ($_a) 以节省空间"
    fi
  done
else
  ui_print "  [!] 无 $PG_ARCH 内置内核，首次启用 VPN 时将在线下载"
fi

# Runtime engines are shipped as binaries; recursive script permissions above do not
# cover bin/. Explicitly make each bundled engine executable on Android.
ui_print "- 配置 FX 运行引擎..."
for _engine in \
  "$MODPATH/bin/arm64/qjs" "$MODPATH/bin/arm64/pg-mitm" "$MODPATH/bin/arm/pg-mitm" \
  "$MODPATH/engines/adguardhome/AdGuardHome-android-arm64" \
  "$MODPATH/engines/unbound/unbound" "$MODPATH/engines/unbound/unbound-checkconf" \
  "$MODPATH/engines/unbound/unbound-anchor" "$MODPATH/engines/unbound/fx-dns-probe"; do
  if [ -f "$_engine" ]; then
    set_perm "$_engine" 0 0 0755
    ui_print "  [✓] $(basename "$_engine") 执行权限已设置"
  fi
done

ui_print "- 初始化配置目录..."
mkdir -p /data/adb/privacyguard
if [ ! -f /data/adb/privacyguard/settings.conf ]; then
  cp "$MODPATH/scripts/default.conf" /data/adb/privacyguard/settings.conf
  ui_print "  已生成默认配置 /data/adb/privacyguard/settings.conf"
else
  ui_print "  保留已有配置"
  # v1.10.8: 老配置迁移——补 [list:hosts_local] 段与内置规则集/FX 条目（默认关闭）。
  # 不做这一步，升级用户 WebUI 里根本看不到「内置规则集 / 内置 FX」（列表读 settings.conf）。
  if [ -f "$MODPATH/scripts/util.sh" ]; then
    . "$MODPATH/scripts/util.sh" 2>/dev/null
    if command -v pg_migrate_lists >/dev/null 2>&1; then
      pg_migrate_lists 2>/dev/null
      ui_print "  已为升级配置补齐 v1.10.8 内置规则集/本地 hosts 段（默认关闭，WebUI 可见）"
    fi
  fi
fi

ui_print "- 初始化独立 CA 子模块..."
# 首次安装且没有用户明确授权记录时，默认禁用系统级 CA 信任。
# 升级时绝不删除 ca-trust-optin，也不强制写入 disable 标记：证书管理器
# 的 release 命令会依据该授权标记和现有子模块状态保留用户选择。
if [ -f "$MODPATH/scripts/certmgr.sh" ]; then
  _pg_ca_state_dir=/data/adb/privacyguard
  _pg_ca_install_log="$_pg_ca_state_dir/ca-install.log"
  mkdir -p "$_pg_ca_state_dir" 2>/dev/null
  if [ ! -f /data/adb/privacyguard/ca-trust-optin ]; then
    if sh "$MODPATH/scripts/certmgr.sh" builtin release "$MODPATH/certs" >>"$_pg_ca_install_log" 2>&1; then
      if sh "$MODPATH/scripts/certmgr.sh" builtin disable pg_https_ca >>"$_pg_ca_install_log" 2>&1 && \
         sh "$MODPATH/scripts/certmgr.sh" builtin disable pg_mitm_ca >>"$_pg_ca_install_log" 2>&1; then
        ui_print "  未发现 CA 信任授权；CA 子模块默认禁用"
      else
        ui_print "  [!] CA 子模块已释放，但禁用/信任状态同步未确认；请检查 /data/adb/privacyguard/ca-install.log"
      fi
    else
      ui_print "  [!] CA 迁移/同步未完成；未宣称安装成功。若提示旧挂载，请完整重启后再管理证书；详情见 /data/adb/privacyguard/ca-install.log"
    fi
  else
    if sh "$MODPATH/scripts/certmgr.sh" builtin release "$MODPATH/certs" >>"$_pg_ca_install_log" 2>&1; then
      ui_print "  检测到已有 CA 信任授权；保留各子模块启用/禁用状态，不重置授权标记"
    else
      ui_print "  [!] 已保留原 CA 子模块状态，但信任视图迁移/同步未完成；请检查 /data/adb/privacyguard/ca-install.log，并按提示重启后重试"
    fi
  fi
else
  ui_print "  [!] 未找到 certmgr.sh，未安装 CA"
fi
# 不分发静态共享 CA 私钥：此前 P12 使用公开固定密码，无法安全用于全系统 MITM 签发。
rm -f "$MODPATH/certs/pg-https-ca.p12" "$MODPATH/certs/pg-mitm-ca.p12" 2>/dev/null

# Preserve rule-set configuration on upgrade. Older packages blanket-deleted every
# builtin:// row from [list:rule] after pg_migrate_lists() had just registered them,
# and also deleted historical subscription URLs. That made the rule page appear empty.
# Migrations above are targeted, versioned and idempotent; never destructively scrub
# user-owned [list:rule]/[list:fx] content here. Legacy blacklist rows are handled by
# pg_migrate_lists() with a backup and moved to a disabled optional ruleset.
# FX upgrade-safe network defaults: append missing keys only; never replace an existing
# setting. Older installers rewrote vpn_mode/hosts/DNS values on every upgrade and
# could silently change the user's network path. Keep the helper parameterized so the
# regression test can exercise the exact production logic with a temporary config.
pg_add_missing_network_defaults() {
  _pg_cfg=${1:-/data/adb/privacyguard/settings.conf}
  [ -f "$_pg_cfg" ] || return 0
  _pg_tmp="${_pg_cfg}.pgnew.$$"
  (umask 077; cp -p "$_pg_cfg" "$_pg_tmp") 2>/dev/null || { rm -f "$_pg_tmp" 2>/dev/null; return 1; }
  chmod 600 "$_pg_tmp" 2>/dev/null || { rm -f "$_pg_tmp"; return 1; }
  _pg_changed=0
  for _kv in 'lsposed_enabled=0' 'vpn_mode=direct' 'vpn_dns_hijack=0' 'vpn_killswitch=0' 'vpn_udp_block=0' 'vpn_hide=0' 'vpn_leak=0' 'block_quic=0' 'block_stun=0' 'block_dot=0' 'block_multicast=0'; do
    _k=${_kv%%=*}; _v=${_kv#*=}
    if ! grep -q "^${_k}=" "$_pg_tmp"; then
      printf '%s=%s\n' "$_k" "$_v" >> "$_pg_tmp" || { rm -f "$_pg_tmp"; return 1; }
      _pg_changed=1
    fi
  done
  if [ "$_pg_changed" != 1 ]; then
    rm -f "$_pg_tmp"
    return 0
  fi
  mv -f "$_pg_tmp" "$_pg_cfg" || { rm -f "$_pg_tmp"; return 1; }
  chmod 600 "$_pg_cfg" 2>/dev/null || true
  return 0
}
if [ -f /data/adb/privacyguard/settings.conf ]; then
  if pg_add_missing_network_defaults /data/adb/privacyguard/settings.conf; then
    ui_print "  已补齐缺失的兼容默认项；已有网络设置原样保留"
  else
    ui_print "  [!] 兼容默认项补齐失败；原 settings.conf 已保留，请检查权限/存储空间"
  fi
fi

if [ -f /data/adb/privacyguard/settings.conf ]; then
  chown 0:0 /data/adb/privacyguard/settings.conf 2>/dev/null || true
  if ! chmod 600 /data/adb/privacyguard/settings.conf 2>/dev/null; then
    ui_print "  [!] 无法将 settings.conf 权限收紧为 600；请检查 /data/adb/privacyguard/settings.conf"
  fi
fi
ui_print "- 清理历史版本残留的证书覆盖层/暂存区(如有)..."
# 历史版本(≤v1.7)曾把用户 CA 移入 certs-quarantine 隔离区做"禁用";
# 现版本安装时不写用户证书区 — 隔离区原样保留, 卸载时由 uninstall.sh 的
# cleanup restore 移回原目录(用户数据不丢), 避免安装阶段重新触发“用户证书”警告。
# 本次只卸旧 live 覆盖层、删暂存区。
if [ -f "$MODPATH/scripts/certmgr.sh" ]; then
  CR=$(sh "$MODPATH/scripts/certmgr.sh" cleanup 2>/dev/null)
  [ -n "$CR" ] && ui_print "  $CR"
fi

ui_print ""
ui_print "- 安装完成！"
ui_print "- 内置代理内核：无需联网，导入节点即可用（离线可用）"
ui_print "- 重启后生效，或在管理器中点击『执行操作』立即应用"
ui_print "- KernelSU/APatch 用户：点击模块的『WebUI』按钮打开配置面板"
ui_print "- Magisk 用户：通过任意浏览器打开配置面板导出的配置文件"
ui_print "  使用『生成配置』→ 导出 settings.conf → 放入"
ui_print "  /data/adb/privacyguard/settings.conf 后执行操作"
ui_print ""
