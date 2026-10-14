#!/system/bin/sh
# ============================================================
#  game_privacy.sh — 游戏隐私保护：不让游戏读取隐私
#  ------------------------------------------------------------
#  注意语义：这是「收回敏感能力」，**不是冻结应用、不是断网**。
#    · 只收回运行时（dangerous）权限 —— 这类 pm revoke 真实生效；
#      INTERNET 是 install-time 权限，revoke 对它无效，所以游戏联网不受影响，
#      目标是"能玩但别偷看"；
#    · appops 禁剪贴板读取与使用情况统计；
#    · 撤销前先确认"本来已授予"，只记录被本模块收走的，关闭时精确归还；
#    · 记录是**增量累积**的 —— 旧实现每次 apply 都清空记录，导致二次执行后
#      关闭功能再也无法归还已收走的权限（真实缺陷，已修）。
#
#  对象清单: $DATA_DIR/rules/privacy/game.conf（每行一个包名，# 注释）
#  权限清单: $DATA_DIR/rules/privacy/game_perms.conf（每行一个完整权限名）
#  状态文件: $DATA_DIR/rules/privacy/game_restore.state
#
#  用法: game_privacy.sh {apply|remove|status|check}
# ============================================================
. "$(dirname "$0")/common.sh"

GP_DIR="$DATA_DIR/rules/privacy"
GP_PKG="$GP_DIR/game.conf"
GP_PERM="$GP_DIR/game_perms.conf"
GP_DONE="$GP_DIR/game_restore.state"
TAB=$(printf '\t')
mkdir -p "$GP_DIR" 2>/dev/null

GP_DEFAULT_PERMS="android.permission.ACCESS_FINE_LOCATION
android.permission.ACCESS_COARSE_LOCATION
android.permission.READ_CONTACTS
android.permission.READ_PHONE_STATE
android.permission.READ_CALL_LOG
android.permission.READ_SMS
android.permission.RECORD_AUDIO
android.permission.CAMERA
android.permission.BODY_SENSORS"

gp_android() { [ -f /system/build.prop ] || [ -n "$SY_FORCE_APPLY" ]; }

# 有效行数（忽略注释与空行）—— 判断"有没有真的配了东西"，
# 不能用 [ -s file ]：模板文件全是注释，-s 为真但实际 0 条可用内容。
gp_count() {
  [ -f "$1" ] || { echo 0; return; }
  grep -v "^[[:space:]]*#" "$1" 2>/dev/null | grep -v "^[[:space:]]*$" | wc -l | tr -d " "
}

gp_done() {
  [ -f "$GP_DONE" ] || return 1
  grep -qF "$1${TAB}$2${TAB}$3" "$GP_DONE" 2>/dev/null
}
gp_record() {
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$GP_DONE"
}

# 权限是否真的已授予（$2 必须是全名，如 android.permission.CAMERA）
gp_granted() { dumpsys package "$1" 2>/dev/null | grep -F "$2" | grep -q "granted=true"; }

gp_apply() {
  [ "$(cfg_get GAME_PRIVACY_ENABLE 0)" = "1" ] || { gp_remove; return 0; }
  gp_android || { echo "(非 Android 环境，跳过)"; return 0; }
  command -v pm >/dev/null 2>&1 || { echo "pm 不可用：游戏隐私保护无法生效"; return 1; }

  if [ ! -s "$GP_PERM" ]; then
    printf '%s\n' $GP_DEFAULT_PERMS > "$GP_PERM"
    log "game_privacy: 已生成默认权限清单 $GP_PERM"
  fi

  if [ "$(gp_count "$GP_PKG")" = "0" ]; then
    echo "游戏清单为空（$GP_PKG）：每行写一个游戏包名才生效"
    echo "查包名：pm list packages -3 | grep -i <游戏名>"
    log "game_privacy: 清单无有效包名，跳过"
    return 0
  fi

  n=0
  while IFS= read -r pkg; do
    case "$pkg" in ""|"#"*) continue ;; esac
    if ! pm list packages --user 0 "$pkg" 2>/dev/null | grep -q "package:$pkg$"; then
      log "game_privacy: 清单里有未安装应用 $pkg"
      continue
    fi
    n=$((n+1))
    while IFS= read -r perm; do
      case "$perm" in ""|"#"*) continue ;; esac
      gp_done perm "$pkg" "$perm" && continue
      gp_granted "$pkg" "$perm" || continue
      if pm revoke --user 0 "$pkg" "$perm" >/dev/null 2>&1; then
        gp_record perm "$pkg" "$perm" ""
        log "game_privacy: 收回权限 $pkg <- $perm"
      else
        log "game_privacy: revoke 失败 $pkg $perm"
      fi
    done < "$GP_PERM"
    for op in READ_CLIPBOARD GET_USAGE_STATS; do
      gp_done op "$pkg" "$op" && continue
      cur=$(appops get --user 0 "$pkg" "$op" 2>/dev/null)
      case "$cur" in *": deny"*) continue ;; esac
      case "$cur" in
        *": allow"*)  orig="allow" ;;
        *": ignore"*) orig="ignore" ;;
        *) orig="default" ;;
      esac
      if appops set --user 0 "$pkg" "$op" deny >/dev/null 2>&1; then
        gp_record op "$pkg" "$op" "$orig"
        log "game_privacy: 禁 $op: $pkg（原值 $orig）"
      fi
    done
  done < "$GP_PKG" 2>/dev/null

  log "game_privacy: 应用完成（$n 个游戏）"
  echo "OK: 游戏隐私保护已应用（$n 个游戏；明细 $GP_DONE）"
}

gp_remove() {
  gp_android || return 0
  [ -f "$GP_DONE" ] || { log "game_privacy: 未启用过（无记录）"; echo "OK: 游戏隐私保护未启用过"; return 0; }
  n=0
  while IFS="$TAB" read -r kind pkg what orig; do
    [ -n "$pkg" ] || continue
    case "$kind" in
      perm) [ -n "$what" ] && pm grant --user 0 "$pkg" "$what" >/dev/null 2>&1 && n=$((n+1)) ;;
      op)   [ -n "$what" ] && appops set --user 0 "$pkg" "$what" "${orig:-default}" >/dev/null 2>&1 && n=$((n+1)) ;;
    esac
  done < "$GP_DONE"
  rm -f "$GP_DONE"
  log "game_privacy: 已归还 $n 项"
  echo "OK: 游戏隐私保护已关闭（归还 $n 项，逐项按原始值还原）"
}

gp_status() {
  rec=0; [ -f "$GP_DONE" ] && rec=$(wc -l < "$GP_DONE" 2>/dev/null | tr -d " ")
  printf '{"feature":"%s","packages":%s,"recorded":%s}\n' \
    "$(cfg_get GAME_PRIVACY_ENABLE 0)" "$(gp_count "$GP_PKG")" "${rec:-0}"
}

gp_check() {
  echo "== 游戏隐私保护自检 =="
  echo "开关: $(cfg_get GAME_PRIVACY_ENABLE 0)"
  echo "游戏清单($GP_PKG): $(gp_count "$GP_PKG") 条"
  grep -v "^[[:space:]]*#" "$GP_PKG" 2>/dev/null | grep -v "^[[:space:]]*$" | while IFS= read -r p; do
    gp_granted "$p" android.permission.ACCESS_FINE_LOCATION && echo "  $p → 有定位权限" || echo "  $p → 无定位权限"
  done
  rec=0; [ -f "$GP_DONE" ] && rec=$(wc -l < "$GP_DONE" 2>/dev/null | tr -d " ")
  echo "待还原记录: ${rec:-0} 项"
}

case "$1" in
  apply)  gp_apply ;;
  remove) gp_remove ;;
  status) gp_status ;;
  check)  gp_check ;;
  *) echo "usage: game_privacy.sh {apply|remove|status|check}"; exit 2 ;;
esac
