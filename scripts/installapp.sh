#!/system/bin/sh
# ============================================================
#  installapp.sh — 内置管理器 App 的安装 / 卸载 / 状态
#
#  为什么要单独一个脚本：
#    安装 APK 这件事要在三个地方发生 —— 模块安装时（customize.sh）、
#    面板里点按钮、以及开机兜底。三处逻辑必须一致，否则会出现
#    "安装时成功、开机后失效"这种难查的问题。
#
#  几个必须处理的坑（都是实测踩出来的）：
#    1. APK 放在 /data/adb/modules 下时 SELinux 上下文是 module 的，
#       installd 读不了，必须先 chcon 成 apk_data_file。
#    2. Android 11+ 多用户，必须显式 --user 0，否则装到当前用户之外
#       或者干脆不装。
#    3. `pm install` 失败时退出码经常还是 0，必须匹配输出里的 Success。
#    4. 部分设备 pm 走会话式安装才成功，所以要有 install-create 兜底。
#
#  用法: installapp.sh {install|remove|status|reinstall}
# ============================================================
. "$(dirname "$0")/common.sh"

PKG="com.syfusion.manager"
APK_SRC="$MODDIR/app/SYManager.apk"
STAGE="/data/local/tmp/SYManager.apk"
LOGF="$LOGS/installapp.log"

ia_log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGF"
}

# pm 是否可用
ia_have_pm() {
  command -v pm >/dev/null 2>&1 || [ -x /system/bin/pm ]
}

ia_installed() {
  ia_have_pm || return 1
  pm path "$PKG" 2>/dev/null | grep -q "^package:"
}

ia_version() {
  # 从 dumpsys 里抠 versionName，用于展示
  dumpsys package "$PKG" 2>/dev/null \
    | sed -n 's/.*versionName=\([^ ]*\).*/\1/p' | head -n1
}

# 准备一个 installd 能读的 APK 副本
ia_stage() {
  [ -f "$APK_SRC" ] || return 1
  cp -f "$APK_SRC" "$STAGE" 2>/dev/null || return 1
  chmod 0644 "$STAGE" 2>/dev/null
  chown 0:0 "$STAGE" 2>/dev/null
  # 关键：/data/adb 下的文件默认是 adb_data_file，installd 打不开
  chcon u:object_r:apk_data_file:s0 "$STAGE" 2>/dev/null
  return 0
}

# 静默卸载（签名冲突或需要全新安装时用）
ia_uninstall_quiet() {
  pm uninstall --user 0 "$PKG" >/dev/null 2>&1
  pm uninstall "$PKG" >/dev/null 2>&1
  rm -f "$LOGF.installerr" 2>/dev/null
  sleep 1
  return 0
}

# 安装后置：① 启用无障碍服务 ② 探测 Xposed 前提 ③ 拉起 App
# 【真机缺陷修复】旧版完全没做这三件事 —— 这正是"无障碍跳广告不生效"、
# "hook 永远 events=0"的直接原因：App 装了但服务没开、LSPosed 没勾选，
# 面板也不告诉用户还差什么。
ia_post_install() {
  acc="$PKG/com.syfusion.manager.SyAccessibilityService"
  cur=$(settings get secure enabled_accessibility_services 2>/dev/null)
  case "$cur" in
    *com.syfusion.manager*) log "installapp: 无障碍服务已启用" ;;
    "null"|"")
      settings put secure enabled_accessibility_services "$acc" >/dev/null 2>&1
      settings put secure accessibility_enabled 1 >/dev/null 2>&1
      log "installapp: 无障碍服务此前为空，已启用" ;;
    *)
      settings put secure enabled_accessibility_services "$cur:$acc" >/dev/null 2>&1
      settings put secure accessibility_enabled 1 >/dev/null 2>&1
      log "installapp: 已在现有服务后追加 SY 服务" ;;
  esac
  if [ -d /data/adb/lspd/modules ]; then
    if find /data/adb/lspd/modules -maxdepth 3 2>/dev/null | grep -q "syfusion"; then
      log "installapp: LSPosed 已识别 SY 模块（Xposed hook 可生效）"
    else
      log "installapp: LSPosed 存在但未勾选 SY —— hook 不会生效，请在 LSPosed 里启用并勾选作用域"
    fi
  else
    log "installapp: 未检测到 LSPosed，Xposed 注入不可用（无障碍跳广告仍可用）"
  fi
  am start -n "$PKG/.MainActivity" >/dev/null 2>&1
  return 0
}

# 开机兜底：App 不在就装；无障碍服务丢了就恢复
ia_ensure() {
  changed=0
  if ! ia_installed; then
    log "installapp ensure: App 未安装，执行安装"
    ia_install >/dev/null 2>&1 && changed=1
  fi
  acc="$PKG/com.syfusion.manager.SyAccessibilityService"
  cur=$(settings get secure enabled_accessibility_services 2>/dev/null)
  case "$cur" in
    *com.syfusion.manager*) : ;;
    "null"|"")
      settings put secure enabled_accessibility_services "$acc" >/dev/null 2>&1
      settings put secure accessibility_enabled 1 >/dev/null 2>&1
      log "installapp ensure: 无障碍服务此前为空，已恢复"
      changed=1 ;;
    *)
      settings put secure enabled_accessibility_services "$cur:$acc" >/dev/null 2>&1
      settings put secure accessibility_enabled 1 >/dev/null 2>&1
      log "installapp ensure: 已在现有服务后追加 SY 服务"
      changed=1 ;;
  esac
  if [ "$changed" = "1" ]; then
    echo "OK: 内置 App/无障碍服务 已检查并恢复"
  else
    echo "OK: 内置 App 与无障碍服务均正常"
  fi
}

ia_try() {
  # 跑一条安装命令，成功返回 0
  out="$("$@" 2>&1)"
  ia_log "cmd: $* -> $out"
  case "$out" in
    *Success*|*success*) return 0 ;;
  esac
  return 1
}

ia_install() {
  if [ ! -f "$APK_SRC" ]; then
    echo "ERR: 未找到内置 App ($APK_SRC)"
    ia_log "apk missing"
    return 1
  fi
  if ! ia_have_pm; then
    echo "ERR: 当前环境没有 pm，无法安装 App"
    ia_log "pm not available"
    return 1
  fi

  ia_stage || { echo "ERR: 暂存 APK 失败"; return 1; }

  # 策略 1：标准安装
  if ia_try pm install -r --user 0 "$STAGE"; then
    rm -f "$STAGE" 2>/dev/null
    ia_post_install
    echo "OK: 内置 App 已安装（$(ia_version)）"
    return 0
  fi
  # 策略 2：不带 --user（老设备）
  if ia_try pm install -r "$STAGE"; then
    rm -f "$STAGE" 2>/dev/null
    ia_post_install
    echo "OK: 内置 App 已安装（兼容模式）"
    return 0
  fi
  # 【真机缺陷修复】策略 3：签名变更冲突 → 卸载后重装
  # 真机实测：旧 APK 用已丢失的密钥签，新版用 app/debug.keystore 签，
  # `pm install -r` 直接报 INSTALL_FAILED_UPDATE_INCOMPATIBLE 且永远装不上。
  # 这不是代码 bug 而是密钥更迭，必须允许"卸载旧的 → 装新的"。
  ia_uninstall_quiet
  if ia_try pm install --user 0 "$STAGE"; then
    rm -f "$STAGE" 2>/dev/null
    ia_post_install
    echo "OK: 内置 App 已安装（签名变更，已卸载重装）"
    return 0
  fi
  # 策略 4：会话式安装，绕过部分设备对直接路径安装的限制
  SZ=$(wc -c < "$STAGE" 2>/dev/null | tr -d " ")
  SID="$(pm install-create -r -S "$SZ" 2>/dev/null | sed -n 's/.*\[\([0-9]*\)\].*/\1/p' | head -n1)"
  if [ -n "$SID" ]; then
    if pm install-write -S "$SZ" "$SID" base "$STAGE" >/dev/null 2>&1 \
       && ia_try pm install-commit "$SID"; then
      rm -f "$STAGE" 2>/dev/null
      ia_post_install
      echo "OK: 内置 App 已安装（会话模式）"
      return 0
    fi
    pm install-abandon "$SID" >/dev/null 2>&1
  fi
  echo "ERR: 内置 App 安装失败，详见 $LOGF"
  echo "     可在面板「内置 App」页重试，或手动执行:"
  echo "     su -c 'sh $MODDIR/scripts/installapp.sh install'"
  return 1
}

ia_remove() {
  ia_have_pm || { echo "ERR: 没有 pm"; return 1; }
  if ! ia_installed; then
    echo "OK: 内置 App 本来就没装"
    return 0
  fi
  out="$(pm uninstall --user 0 "$PKG" 2>&1)"
  ia_log "uninstall -> $out"
  case "$out" in
    *Success*|*success*) echo "OK: 内置 App 已卸载"; return 0 ;;
  esac
  out2="$(pm uninstall "$PKG" 2>&1)"
  ia_log "uninstall2 -> $out2"
  case "$out2" in
    *Success*|*success*) echo "OK: 内置 App 已卸载"; return 0 ;;
  esac
  echo "ERR: 卸载失败: $out2"
  return 1
}

# 内置 APK 的 SHA-256（面板用它做完整性核对，替代无法低成本读取的签名证书指纹）
ia_sha() {
  [ -f "$APK_SRC" ] || return 0
  (sha256sum "$APK_SRC" 2>/dev/null \
    || busybox sha256sum "$APK_SRC" 2>/dev/null \
    || toybox sha256sum "$APK_SRC" 2>/dev/null) | cut -d' ' -f1
}

ia_status() {
  if [ ! -f "$APK_SRC" ]; then
    echo '{"bundled":false,"installed":false,"note":"模块内未打包 App"}'
    return
  fi
  SZ=$(wc -c < "$APK_SRC" 2>/dev/null | tr -d ' ')
  SHA=$(ia_sha)
  if ia_installed; then
    V=$(ia_version)
    printf '{"bundled":true,"installed":true,"package":"%s","version":"%s","size":%s,"sha256":"%s"}\n' \
      "$PKG" "$V" "${SZ:-0}" "${SHA:-}"
  else
    printf '{"bundled":true,"installed":false,"package":"%s","size":%s,"sha256":"%s"}\n' \
      "$PKG" "${SZ:-0}" "${SHA:-}"
  fi
}

# 从面板直接拉起 App（部分 ROM 上 am start 会被后台限制拦住，
# 所以再退一步用 monkey，最后再退到提示用户点桌面图标）
ia_launch() {
  ia_installed || { echo "ERR: 尚未安装"; return 1; }
  out="$(am start -n "$PKG/.MainActivity" 2>&1)"
  case "$out" in
    *Error*|*error*|*Exception*) : ;;
    *) echo "OK: 已拉起 $PKG"; return 0 ;;
  esac
  out2="$(monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 2>&1)"
  case "$out2" in
    *Events\ injected*|*"injected: 1"*) echo "OK: 已拉起 $PKG"; return 0 ;;
  esac
  echo "ERR: 拉起失败（$out2），请从桌面图标打开"
  return 1
}

case "${1:-status}" in
  install)   ia_install ;;
  reinstall) ia_remove >/dev/null 2>&1; ia_install ;;
  remove)    ia_remove ;;
  status)    ia_status ;;
  ensure)    ia_ensure ;;
  launch)    ia_launch ;;
  *)         echo "usage: installapp.sh {install|remove|reinstall|status|launch}"; exit 2 ;;
esac
