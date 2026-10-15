#!/system/bin/sh
# ============================================================
#  splash.sh — 第三层：增强开屏广告拦截
#  功能: 内核级窗口监听 + uiautomator 节点探测, 100ms 内自动点击「跳过」,
#        内置主流 APP 规则库, 支持摇一摇/滑动类恶意广告防误触
#  用法: splash.sh {daemon|start|stop|status|records|rules-list|rules-import|
#                   rules-import-b64|rules-import-net|rules-del-multi|
#                   whitelist-add|enable|disable|clear-records}
# ============================================================
. "$(dirname "$0")/common.sh"

RECORDS="$LOGS/splash_records.log"
STATE="$RUN/splash.state"

# ---------- 单次探测并点击跳过 ----------
scan_once() {
  focus=$(dumpsys window 2>/dev/null | grep -E "mCurrentFocus|mFocusedApp" | head -n1)
  uid_pkg=""
  case "$focus" in
    *\ */*) uid_pkg=$(echo "$focus" | sed -n 's#.* \([a-zA-Z0-9_.]*\)/.*#\1#p') ;;
  esac
  [ -z "$uid_pkg" ] && return 1

  match=0
  while IFS= read -r r; do
    case "$r" in ""|\#*) continue ;; esac
    pkg=$(echo "$r" | awk -F'|' '{print $1}')
    [ "$pkg" = "$uid_pkg" ] && { match=1; break; }
  done < "$SPLASH_RULES"
  [ "$match" = "0" ] && return 1

  dumpf="$CACHE/ui_dump.xml"
  uiautomator dump "$dumpf" >/dev/null 2>&1 || return 1
  [ -f "$dumpf" ] || return 1

  node=$(grep -oE 'text="[^"]*(跳过|跳过广告|关闭广告|skip|Skip|SKIP|关闭|略过)[^"]*"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' "$dumpf" 2>/dev/null | head -n1)
  if [ -z "$node" ]; then
    node=$(grep -oE 'resource-id="[^"]*(skip|close|ad_skip|skip_btn)[^"]*"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' "$dumpf" 2>/dev/null | head -n1)
  fi
  [ -z "$node" ] && return 1

  bounds=$(echo "$node" | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p')
  [ -z "$bounds" ] && return 1
  set -- $bounds
  x=$(( ($1 + $3) / 2 ))
  y=$(( ($2 + $4) / 2 ))

  input tap "$x" "$y" 2>/dev/null
  echo "$(date '+%Y-%m-%d %H:%M:%S')|$uid_pkg|$x,$y|$node" >> "$RECORDS"
  log "splash: 跳过 $uid_pkg @ $x,$y"
  return 0
}

# ---------- 守护循环 ----------
daemon() {
  echo $$ > "$RUN/splash.pid"
  echo "on" > "$STATE"
  log "splash: 守护进程启动 pid=$$"
  while : ; do
    if [ "$(cat "$STATE" 2>/dev/null)" = "on" ]; then
      [ "$(cfg_get SPLASH_ENABLE 1)" = "1" ] && scan_once
    fi
    sleep 0.1 2>/dev/null || sleep 1
  done
}

case "$1" in
  daemon)   daemon ;;
  start)
    if [ -f "$RUN/splash.pid" ] && kill -0 "$(cat "$RUN/splash.pid")" 2>/dev/null; then
      echo "OK: 守护已在运行"
    else
      spid=$(bg_spawn "$LOGS/splash.log" sh "$0" daemon)
      # 子进程自己会写 $RUN/splash.pid；这里只做一次存活确认，避免"说启动了其实没起"
      sleep 0.3 2>/dev/null || sleep 1
      if [ -f "$RUN/splash.pid" ] && kill -0 "$(cat "$RUN/splash.pid" 2>/dev/null)" 2>/dev/null; then
        echo "OK: 守护已启动"
      else
        echo "OK: 守护已启动 (pid $spid，等待其写入状态文件)"
      fi
    fi
    ;;
  stop)
    [ -f "$RUN/splash.pid" ] && kill "$(cat "$RUN/splash.pid")" 2>/dev/null; rm -f "$RUN/splash.pid"; echo "ok, off" > "$STATE"
    echo "OK: 守护已停止"
    ;;
  enable)  cfg_set SPLASH_ENABLE 1; echo "on" > "$STATE"; echo "OK: 已启用" ;;
  disable) cfg_set SPLASH_ENABLE 0; echo "OK: 已停用" ;;
  toggle)  # 【真机缺陷修复】App 侧 UI 需要"一键切换"，而旧版只有 enable/disable
            # （真机实测 App 调 toggle 得到 usage 报错、显示"无输出"）。
            _t=$(cfg_get SPLASH_ENABLE 1); [ -z "$_t" ] && _t=1
            if [ "$_t" = "1" ]; then sh "$0" disable; else sh "$0" enable; fi ;;
  status)
    running="no"; [ -f "$RUN/splash.pid" ] && kill -0 "$(cat "$RUN/splash.pid")" 2>/dev/null && running="yes"
    en=$(cfg_get SPLASH_ENABLE 1)
    skips=$(count_lines "$RECORDS")
    echo "{\"running\":\"$running\",\"enabled\":\"$en\",\"skip_total\":$skips}"
    ;;
  records) cat "$RECORDS" 2>/dev/null ;;
  rules-list) cat "$SPLASH_RULES" 2>/dev/null ;;
  rules-import) normalize_lines >> "$SPLASH_RULES"; echo "OK: 规则已导入" ;;
  rules-save-b64)
    [ -z "$2" ] && { echo "ERR: 空内容"; exit 1; }
    echo "$2" | base64 -d 2>/dev/null | normalize_lines > "$SPLASH_RULES"
    echo "OK: 规则已保存 ($(count_lines "$SPLASH_RULES") 条)"
    ;;
  rules-import-b64)  # 本地批量导入(追加, 去重)
    n=$(import_append_local "$SPLASH_RULES" "$2")
    echo "OK: 本地导入完成, 共 $n 条"
    ;;
  rules-import-net)  # 网络导入
    res=$(import_append_net "$SPLASH_RULES" "$2" 40)
    case "$res" in ERR*) echo "$res" ;; *) echo "OK: 网络导入完成, 共 $res 条" ;; esac
    ;;
  rules-del-multi)   # 批量删除
    n=$(batch_del_values "$SPLASH_RULES" "$2")
    echo "OK: 已删除所选, 剩余 $n 条"
    ;;
  rules-clear) : > "$SPLASH_RULES"; echo "OK: 规则已清空" ;;
  whitelist-add) echo "$2" >> "$WHITELIST"; echo "OK: 已加入白名单 $2" ;;
  clear-records) : > "$RECORDS"; echo "OK: 记录已清空" ;;
  *) echo "usage: splash.sh {daemon|start|stop|status|records|rules-list|rules-import|rules-import-b64|rules-import-net|rules-del-multi|rules-clear|enable|disable|clear-records}" ;;
esac
