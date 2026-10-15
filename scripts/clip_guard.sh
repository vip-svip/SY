#!/system/bin/sh
# ============================================================
#  clip_guard.sh — 剪贴板读取监视
#  ------------------------------------------------------------
#  先说清楚它能做什么、不能做什么（不夸大）:
#   · Android 10+ 起后台应用默认读不到剪贴板，能被读的时机是应用在前台
#     或持有焦点/输入法/无障碍服务时；
#   · 系统**没有**提供「谁读了剪贴板」的公开接口。dumpsys clipboard 在
#     Android 10~14 上多数 ROM 不含读取者历史，各 ROM 输出格式也不同。
#     所以本脚本是尽力而为的启发式：能抓到就记，抓不到就明确记
#     「本 ROM 无法枚举读取者」，绝不假装成功。
#   · 轮询间隔可配（CLIPGUARD_INTERVAL，默认 60s，最小 15s）；
#     分段睡眠，关闭功能后 15s 内即可退出（旧实现硬编码 3600s，
#     关掉功能后最长 1 小时才停 —— 真实缺陷）。
#
#  用法: clip_guard.sh {apply|remove|status|readers}
# ============================================================
. "$(dirname "$0")/common.sh"

CG_PID="$RUN/clipguard.pid"
CG_STATE="$DATA_DIR/rules/privacy/clip.readers"
CG_TRUST="$DATA_DIR/rules/privacy/clip_trusted.conf"
mkdir -p "$(dirname "$CG_STATE")" 2>/dev/null

cg_android() { [ -f /system/build.prop ] || [ -n "$SY_FORCE_APPLY" ]; }

cg_record() {
  r="$1"
  case "$r" in com.android.systemui|com.android.inputmethod*|android|com.android.*) return ;; esac
  [ -f "$CG_TRUST" ] && grep -qxF "$r" "$CG_TRUST" 2>/dev/null && return
  [ -f "$CG_STATE" ] && grep -qxF "$r" "$CG_STATE" 2>/dev/null && return
  echo "$r" >> "$CG_STATE" 2>/dev/null
  log "clip_guard: clipreader $r（剪贴板读取者，启发式判定）"
  [ "$(cfg_get CLIPGUARD_ALERT 1)" = "1" ] || return 0
  # 通知三路回退：Android 10+ 用 cmd notification post；旧版用 am broadcast
  if command -v cmd >/dev/null 2>&1 && cmd notification post -S bigtext -t "SY" tag_sy "$r 读取了剪贴板" >/dev/null 2>&1; then
    :
  elif command -v am >/dev/null 2>&1; then
    am broadcast -a android.intent.action.SHOW_TOAST --es msg "$r 读取了剪贴板" >/dev/null 2>&1
  else
    log "clip_guard: 本机无 cmd/am，告警无法弹出（已写日志）"
  fi
}

cg_loop() {
  echo $$ > "$CG_PID"
  interval=$(cfg_get CLIPGUARD_INTERVAL 60)
  case "$interval" in ""|*[!0-9]*) interval=60 ;; esac
  [ "$interval" -lt 15 ] && interval=15
  while :; do
    [ "$(cfg_get CLIPGUARD_ENABLE 0)" = "1" ] || { log "clip_guard: 功能已关闭，监视退出"; break; }
    out=$(dumpsys clipboard 2>/dev/null)
    if [ -z "$out" ]; then
      [ -f "$CG_STATE" ] || {
        echo "# 本 ROM 的 dumpsys clipboard 无输出，无法枚举读取者" > "$CG_STATE"
        log "clip_guard: dumpsys clipboard 无输出，本 ROM 不支持读取者枚举（如实记录）"
      }
    else
      readers=$(printf '%s' "$out" | grep -oE "com\.[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+)+" | sort -u | head -n 50)
      for r in $readers; do cg_record "$r"; done
    fi
    slept=0
    while [ "$slept" -lt "$interval" ]; do
      sleep 15; slept=$((slept+15))
      [ "$(cfg_get CLIPGUARD_ENABLE 0)" = "1" ] || break
    done
  done
  # 只在文件里确实还是自己时才删，避免误删新实例的 pid
  [ "$(cat "$CG_PID" 2>/dev/null)" = "$$" ] && rm -f "$CG_PID"
}

cg_apply() {
  cg_android || { echo "(非 Android 环境，跳过)"; return 0; }
  if [ "$(cfg_get CLIPGUARD_ENABLE 0)" != "1" ]; then cg_remove; return 0; fi
  # 【真机缺陷修复 A】旧判据用 `*clipguard*` 匹配 cmdline，但真实 cmdline 是
  # `.../clip_guard.sh loop` —— 带**下划线**，判据永远不匹配 → 每次都"重新启动"
  # → 监视进程叠加（真机实测出现两个 loop 实例：6949 与 12953）。
  # 改为匹配真实脚本名 clip_guard。
  # 【真机缺陷修复 B】旧版先 bg_spawn 再 cpid=$! —— 但 bg_spawn 内部自己 & 并 echo pid，
  # 外层 $! 拿到的是 **bg_spawn 子 shell 的 pid**（转瞬即逝），与 cg_loop 内部写的 $$
  # 互相冲突，于是 pid 文件里是个已死进程（真机实测 pid 文件=14459，实际存活 6949）。
  # 现在统一：pid 只由**真实 loop 进程**写（cg_loop 里的 $$），apply 不再猜。
  if [ -f "$CG_PID" ]; then
    old=$(cat "$CG_PID" 2>/dev/null)
    if [ -n "$old" ] && [ -d "/proc/$old" ]; then
      cmd=$(tr "\0" " " < "/proc/$old/cmdline" 2>/dev/null)
      case "$cmd" in
        *clip_guard.sh*)
          echo "OK: 剪贴板监视已在运行 (pid $old)"
          return 0 ;;
      esac
      log "clip_guard: pid $old 存在但不是监视进程（PID 复用），重新启动"
    fi
    rm -f "$CG_PID" 2>/dev/null
  fi
  # 兜底：pid 文件丢了但进程还在（例如上面判定误删），按 cmdline 找回来
  for pp in /proc/[0-9]*; do
    [ -r "$pp/cmdline" ] || continue
    cc=$(tr "\0" " " < "$pp/cmdline" 2>/dev/null)
    case "$cc" in
      *clip_guard.sh*loop*)
        echo "${pp#/proc/}" > "$CG_PID" 2>/dev/null
        echo "OK: 剪贴板监视已在运行 (pid ${pp#/proc/})"
        return 0 ;;
    esac
  done
  bg_spawn "$LOGS/clipguard.log" sh "$0" loop >/dev/null
  # 等子进程自己写 pid（cg_loop 第一件事就是 echo $$ > CG_PID），最多等 3 秒
  t=0
  while [ "$t" -lt 30 ]; do
    sleep 0.1 2>/dev/null || sleep 1
    if [ -s "$CG_PID" ]; then
      rp=$(cat "$CG_PID" 2>/dev/null)
      if [ -n "$rp" ] && [ -d "/proc/$rp" ]; then
        echo "OK: 剪贴板监视已启动 (pid $rp)"
        return 0
      fi
    fi
    t=$((t+1))
  done
  echo "WARN: 监视已启动但未能确认 pid（可能被 SELinux 限制）；可在状态里查看"
}

cg_remove() {
  if [ -f "$CG_PID" ]; then
    pid=$(cat "$CG_PID" 2>/dev/null)
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
    rm -f "$CG_PID"
    log "clip_guard: 监视已停止"
    echo "OK: 剪贴板监视已停止"
  else
    log "clip_guard: 本来就没在运行"
    echo "OK: 剪贴板监视本来就没在运行"
  fi
}

cg_status() {
  running="no"; pid=""
  if [ -f "$CG_PID" ]; then
    pid=$(cat "$CG_PID" 2>/dev/null)
    kill -0 "$pid" 2>/dev/null && running="yes" || pid=""
  fi
  # grep -c 无匹配时输出 0 但退出码 1，`|| echo 0` 会产生 "0\n0"（真机显示成两行）。
  # 正确写法：先取输出，再单独兜底。
  n=0; [ -f "$CG_STATE" ] && n=$(grep -v "^#" "$CG_STATE" 2>/dev/null | grep -c . | head -n1); [ -z "$n" ] && n=0
  printf '{"feature":"%s","running":"%s","pid":"%s","interval":"%s","readers":%s}\n' \
    "$(cfg_get CLIPGUARD_ENABLE 0)" "$running" "$pid" "$(cfg_get CLIPGUARD_INTERVAL 60)" "${n:-0}"
}

case "$1" in
  loop)    cg_loop ;;
  apply)   cg_apply ;;
  remove)  cg_remove ;;
  status)  cg_status ;;
  readers) [ -f "$CG_STATE" ] && cat "$CG_STATE" || echo "(暂无记录)" ;;
  *) echo "usage: clip_guard.sh {loop|apply|remove|status|readers}"; exit 2 ;;
esac
