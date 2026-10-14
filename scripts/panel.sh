#!/system/bin/sh
# ============================================================
#  panel.sh — 管理面板 Web 服务 控制脚本
#  内置超轻量 Web 服务(基于 abserver serve)，随模块生命周期启停，
#  支持本地 + 局域网访问，自带身份验证。
#  用法: panel.sh {start|stop|restart|status|info|ensure|token|port|url}
#
#  关键修复: 用 setsid + nohup 让 serve 进程完全脱离调用方会话，
#            避免 service.sh 结束后被系统连带回收，导致面板显示"已停止"。
# ============================================================
. "$(dirname "$0")/common.sh"

PANEL_PORT=$(cfg_get PANEL_PORT 8848)
PANEL_TOKEN_FILE="$DATA_DIR/config/panel.token"
PANEL_PID_FILE="$RUN/panel.pid"
PANEL_LOG="$LOGS/panel.log"
mkdir -p "$(dirname "$PANEL_TOKEN_FILE")"

# 十六进制端口，用于 /proc/net/tcp 检测
port_hex() { printf '%04X' "$PANEL_PORT" 2>/dev/null; }

# 端口是否处于 LISTEN 状态 (无需 netstat/ss 依赖)
port_listening() {
  hex=$(port_hex)
  # /proc/net/tcp 与 tcp6 中 state=0A 表示 LISTEN
  for f in /proc/net/tcp /proc/net/tcp6; do
    [ -f "$f" ] || continue
    awk -v H="$hex" 'NR>1 {split($2,a,":"); if(a[2]==H && $4=="0A"){found=1}} END{exit found?0:1}' "$f" 2>/dev/null && return 0
  done
  return 1
}

# 取当前监听该端口的 pid (尽力而为)
pid_on_port() {
  hex=$(port_hex)
  inode=""
  for f in /proc/net/tcp /proc/net/tcp6; do
    [ -f "$f" ] || continue
    inode=$(awk -v H="$hex" 'NR>1{split($2,a,":"); if(a[2]==H && $4=="0A"){print $10; exit}}' "$f" 2>/dev/null)
    [ -n "$inode" ] && break
  done
  [ -z "$inode" ] && return 0
  for p in /proc/[0-9]*/fd/*; do
    tgt=$(readlink "$p" 2>/dev/null)
    case "$tgt" in
      *socket:\[$inode\]) echo "${p#/proc/}"; echo "${p#/proc/}" | cut -d/ -f1; return 0 ;;
    esac
  done
}

is_alive() { # pid
  [ -n "$1" ] && kill -0 "$1" 2>/dev/null
}

gen_token() {
  if [ ! -f "$PANEL_TOKEN_FILE" ] || [ "$(wc -c < "$PANEL_TOKEN_FILE" 2>/dev/null || echo 0)" -lt 8 ]; then
    if [ -x "$BIN" ]; then
      "$BIN" token > "$PANEL_TOKEN_FILE" 2>/dev/null
    fi
    [ -s "$PANEL_TOKEN_FILE" ] || head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$PANEL_TOKEN_FILE"
    chmod 0600 "$PANEL_TOKEN_FILE" 2>/dev/null
  fi
}

lan_ip() {
  ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
  [ -z "$ip" ] && ip=$(ifconfig 2>/dev/null | grep -oE 'inet [0-9.]+' | grep -v 127.0.0.1 | head -n1 | awk '{print $2}')
  echo "$ip"
}

start() {
  # 已在运行(进程存活 或 端口在监听)
  curpid=""
  [ -f "$PANEL_PID_FILE" ] && curpid=$(cat "$PANEL_PID_FILE" 2>/dev/null)
  if is_alive "$curpid" || port_listening; then
    # 端口在监听但 pid 文件丢了：不为了显示一个 pid 而遍历上万个 fd
    echo "OK: 面板已在运行 pid=${curpid:-未知(端口在监听)} 端口=$PANEL_PORT"
    return 0
  fi

  [ -x "$BIN" ] || { echo "ERR: 服务组件缺失 (bin/abserver)"; log "panel: 服务组件缺失"; return 1; }

  gen_token
  TOKEN=$(cat "$PANEL_TOKEN_FILE")
  rm -f "$PANEL_PID_FILE"

  # --- 关键: 用 setsid 脱离会话 + nohup 忽略挂断，确保 service.sh 退出后仍存活 ---
  # 用统一起进程函数（nohup/setsid 在部分 ROM 上不存在 → 旧版面板起不来）
  panel_pid=$(bg_spawn "$PANEL_LOG" "$BIN" serve \
      -addr ":$PANEL_PORT" \
      -webroot "$MODDIR/webroot" \
      -moddir "$MODDIR" \
      -datadir "$DATA_DIR" \
      -token "$TOKEN")
  echo "$panel_pid" > "$PANEL_PID_FILE"

  # --- 启动后校验: 等待进程存活并端口监听 (最多 ~5s) ---
  i=0
  while [ $i -lt 10 ]; do
    sleep 0.5 2>/dev/null || sleep 1
    if ! is_alive "$(cat "$PANEL_PID_FILE" 2>/dev/null)" && ! port_listening; then
      break
    fi
    if port_listening; then break; fi
    i=$((i+1))
  done

  pid=$(cat "$PANEL_PID_FILE" 2>/dev/null)
  if is_alive "$pid" || port_listening; then
    log "panel: 已启动 pid=$pid port=$PANEL_PORT"
    echo "OK: 面板已启动 http://127.0.0.1:$PANEL_PORT"
  else
    log "panel: 启动失败，见 $PANEL_LOG"
    echo "ERR: 面板启动失败，请查看日志 $PANEL_LOG"
    return 1
  fi
}

stop() {
  pid=""
  [ -f "$PANEL_PID_FILE" ] && pid=$(cat "$PANEL_PID_FILE" 2>/dev/null)
  if is_alive "$pid"; then
    kill "$pid" 2>/dev/null
  fi
  # 兜底: 按端口找进程并结束
  ppid=$(pid_on_port)
  [ -n "$ppid" ] && kill "$ppid" 2>/dev/null
  pkill -f "abserver serve" 2>/dev/null
  rm -f "$PANEL_PID_FILE"
  log "panel: 已停止"
  echo "OK: 面板已停止"
}

# 自愈: 未运行则拉起 (供 service.sh 重启后守护)
ensure() {
  if is_alive "$(cat "$PANEL_PID_FILE" 2>/dev/null)" || port_listening; then
    echo "OK: 面板运行中"
  else
    start
  fi
}

case "$1" in
  start)   start ;;
  stop)    stop ;;
  restart) stop; sleep 1; start ;;
  ensure)  ensure ;;
  info)
    # 合并 status + url：面板首页每 6 秒轮询一次，旧版要 fork 两个脚本
    # （panel.sh status 与 panel.sh url），而 url 内部还要 gen_token + lan_ip。
    # 合并成一次调用，减少一半的进程创建与 /proc 读取。
    running="no"; pid=""
    if [ -f "$PANEL_PID_FILE" ]; then
      pid=$(cat "$PANEL_PID_FILE" 2>/dev/null)
      if is_alive "$pid"; then running="yes"; else pid=""; rm -f "$PANEL_PID_FILE"; fi
    fi
    if [ "$running" = "no" ] && port_listening; then running="yes"; fi
    gen_token
    ip=$(lan_ip); [ -z "$ip" ] && ip="127.0.0.1"
    tok=$(cat "$PANEL_TOKEN_FILE" 2>/dev/null)
    printf '{"running":"%s","pid":"%s","port":%s,"lan_ip":"%s","url":"http://%s:%s/?token=%s"}\n' \
      "$running" "$pid" "$PANEL_PORT" "$ip" "$ip" "$PANEL_PORT" "$tok"
    ;;
  status)
    running="no"; pid=""
    if [ -f "$PANEL_PID_FILE" ]; then
      pid=$(cat "$PANEL_PID_FILE" 2>/dev/null)
      if is_alive "$pid"; then
        running="yes"
      else
        pid=""
        rm -f "$PANEL_PID_FILE"   # 清理失效 pid 文件
      fi
    fi
    # 端口兜底: 即使 pid 文件丢失，只要端口在监听就算运行。
    # 【性能】pid_on_port 要遍历 /proc/[0-9]*/fd/*（手机上万个 readlink），
    # 而面板首页每 6 秒轮询一次 status —— 会明显卡顿。
    # 所以这里不再主动扫 pid：端口在监听就报 running，pid 留空；
    # 只有调用方显式要 full 时才扫描。
    if [ "$running" = "no" ] && port_listening; then
      running="yes"
      if [ "${2:-}" = "full" ]; then pid=$(pid_on_port); else pid=""; fi
    fi
    ip=$(lan_ip)
    echo "{\"running\":\"$running\",\"pid\":\"$pid\",\"port\":$PANEL_PORT,\"lan_ip\":\"$ip\"}"
    ;;
  token)   gen_token; cat "$PANEL_TOKEN_FILE" ;;
  port)    echo "$PANEL_PORT" ;;
  url)
    gen_token
    ip=$(lan_ip); [ -z "$ip" ] && ip="127.0.0.1"
    echo "http://$ip:$PANEL_PORT/?token=$(cat "$PANEL_TOKEN_FILE")"
    ;;
  *) echo "usage: panel.sh {start|stop|restart|status|info|ensure|token|port|url}" ;;
esac
