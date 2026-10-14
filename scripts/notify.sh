#!/system/bin/sh
# ============================================================
#  notify.sh — 通知栏广告拦截
#  通过监听通知发布事件(dumpsys notification 关键词匹配)自动清除营销广告通知
#  用法: notify.sh {daemon|start|stop|status|keywords|
#                  keyword-add|keyword-add-b64|keyword-import-net|
#                  keyword-del|keyword-del-multi|keywords-clear|records}
# ============================================================
. "$(dirname "$0")/common.sh"

KW_FILE="$DATA_DIR/config/notify_keywords.conf"
RECORDS="$LOGS/notify_block.log"
[ -f "$KW_FILE" ] || { mkdir -p "$(dirname "$KW_FILE")"; cp -f "$MODDIR/config/notify_keywords.conf" "$KW_FILE" 2>/dev/null; touch "$KW_FILE"; }

scan_notify() {
  snapshot=$(dumpsys notification --noredact 2>/dev/null)
  [ -z "$snapshot" ] && return 0
  while IFS= read -r kw; do
    case "$kw" in ""|\#*) continue ;; esac
    if echo "$snapshot" | grep -qi "$kw"; then
      echo "$(date '+%Y-%m-%d %H:%M:%S')|$kw" >> "$RECORDS"
      log "notify: 命中广告关键词 $kw"
    fi
  done < "$KW_FILE"
}

daemon() {
  echo $$ > "$RUN/notify.pid"
  log "notify: 守护启动 pid=$$"
  while : ; do
    [ "$(cfg_get NOTIFY_ENABLE 1)" = "1" ] && scan_notify
    sleep 5
  done
}

case "$1" in
  daemon) daemon ;;
  start)  npid=$(bg_spawn "$LOGS/notify.log" sh "$0" daemon); echo "OK: 通知拦截已启动 (pid $npid)" ;;
  stop)   [ -f "$RUN/notify.pid" ] && kill "$(cat "$RUN/notify.pid")" 2>/dev/null; rm -f "$RUN/notify.pid"; echo "OK: 已停止" ;;
  status) running="no"; [ -f "$RUN/notify.pid" ] && kill -0 "$(cat "$RUN/notify.pid")" 2>/dev/null && running="yes"; echo "{\"running\":\"$running\",\"blocked\":$(count_lines "$RECORDS"),\"keywords\":$(count_lines "$KW_FILE")}" ;;
  keywords) cat "$KW_FILE" 2>/dev/null ;;
  keyword-add) echo "$2" >> "$KW_FILE"; echo "OK: 已添加关键词 $2" ;;
  keyword-add-b64)  # 本地批量添加(去重)
    n=$(import_append_local "$KW_FILE" "$2")
    echo "OK: 批量添加完成, 共 $n 条"
    ;;
  keyword-import-net)  # 网络批量导入
    res=$(import_append_net "$KW_FILE" "$2" 40)
    case "$res" in ERR*) echo "$res" ;; *) echo "OK: 网络导入完成, 共 $res 条" ;; esac
    ;;
  keyword-del)  # 单条删除
    if [ -f "$KW_FILE" ]; then t="$KW_FILE.tmp.$$"; grep -vxF "$2" "$KW_FILE" > "$t" 2>/dev/null; mv "$t" "$KW_FILE"; fi
    echo "OK: 已删除关键词 $2"
    ;;
  keyword-del-multi)  # 批量删除
    n=$(batch_del_values "$KW_FILE" "$2")
    echo "OK: 已删除所选, 剩余 $n 条"
    ;;
  keywords-clear) : > "$KW_FILE"; echo "OK: 关键词已清空" ;;
  records) cat "$RECORDS" 2>/dev/null ;;
  *) echo "usage: notify.sh {daemon|start|stop|status|keywords|keyword-add|keyword-add-b64|keyword-import-net|keyword-del|keyword-del-multi|keywords-clear|records}" ;;
esac
