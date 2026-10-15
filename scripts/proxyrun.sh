#!/system/bin/sh
# ============================================================
#  proxyrun.sh — 代理内核生命周期管理（内置内核，随包分发）
#  ------------------------------------------------------------
#  为什么单独做这个脚本：模块已内置 sing-box 内核
#  （bin/kernels/sing-box-{arm64,armv7,amd64}），也已有 gen_config「把节点
#  编译成内核配置」与 up/down「启动/停止」。但「内核在不在」「架构对不对」
#  「配置能不能过校验」「进程真起来没有」分散在 proxynode/route/kernel 三个
#  脚本里，面板要连调好几次才能回答"我的代理到底在跑吗"。
#  本脚本把这条链路做成一个入口 + 结构化状态。
#
#  子命令：status | ensure | start | stop | restart | selftest | core | pid
#
#  与泄露防护的关系（重要）：
#    「运营商在网络侧看你流量」这件事只有加密隧道能挡。内置内核 + 节点跑起来
#    之后出口经隧道，运营商侧只能看到"你连了某服务器"，看不到你访问了哪些站点。
#    所以：代理跑起来 = 运营商侧观测能力被真正削弱；没跑 = 那句话就是空话。
# ============================================================
. "$(dirname "$0")/common.sh"

PR_DIR="$DATA_DIR/rules/proxy"
PR_LOG="$LOGS/proxy.log"
PR_PID="$DATA_DIR/run/core.pid"
PR_CFG="$DATA_DIR/rules/proxy/config.json"
mkdir -p "$DATA_DIR/run" "$PR_DIR" 2>/dev/null

pr_arch() {
  abi=$(getprop ro.product.cpu.abi 2>/dev/null)
  case "$abi" in
    *arm64*|*aarch64*) echo arm64 ;;
    *armeabi-v7a*|*armv7*) echo armv7 ;;
    *armeabi*) echo armv7 ;;
    *x86_64*|*amd64*|*x64*) echo amd64 ;;
    *) echo arm64 ;;
  esac
}

pr_core() {
  arch=$(pr_arch)
  for c in \
    "$MODDIR/bin/kernels/sing-box-$arch" \
    "$MODDIR/bin/sing-box" \
    "$MODDIR/bin/kernels/sing-box" \
    "$MODDIR/bin/singbox"; do
    if [ -f "$c" ]; then
      [ -x "$c" ] || chmod 0755 "$c" 2>/dev/null
      echo "$c"; return 0
    fi
  done
  echo ""; return 1
}

pr_pid() {
  if [ -f "$PR_PID" ]; then
    p=$(cat "$PR_PID" 2>/dev/null)
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then echo "$p"; return 0; fi
  fi
  p=$(pgrep -f "run -c $PR_CFG" 2>/dev/null | head -n1)
  if [ -n "$p" ]; then echo "$p" > "$PR_PID"; echo "$p"; return 0; fi
  p=$(pgrep -f "sing-box" 2>/dev/null | head -n1)
  [ -n "$p" ] && { echo "$p"; return 0; }
  echo ""; return 1
}

pr_status() {
  core=$(pr_core)
  abi=$(getprop ro.product.cpu.abi 2>/dev/null); [ -z "$abi" ] && abi="unknown"
  pid=$(pr_pid)
  cfg="no"; [ -s "$PR_CFG" ] && cfg="yes"
  nodes=0; [ -s "$PR_DIR/nodes.conf" ] && nodes=$(grep -v "^[[:space:]]*#" "$PR_DIR/nodes.conf" 2>/dev/null | grep -v "^[[:space:]]*$" | wc -l | tr -d " ")
  port=$(cfg_get PROXY_PORT 2080); [ -z "$port" ] && port=2080
  ver=""; [ -n "$core" ] && ver=$("$core" version 2>/dev/null | head -n1 | sed -n "s/^sing-box version *//p")
  run=false; [ -n "$pid" ] && run=true
  printf '{"core":"%s","arch":"%s","abi":"%s","version":"%s","running":%s,"pid":"%s","config":"%s","nodes":%s,"port":%s}\n' \
    "$(basename "$core")" "$(pr_arch)" "$abi" "${ver:-unknown}" "$run" "$pid" "$cfg" "${nodes:-0}" "$port"
}

pr_ensure() {
  core=$(pr_core)
  if [ -n "$core" ]; then echo "OK: 内核已就位 $core"; return 0; fi
  echo "内置内核未找到，尝试在线下载…"
  if [ -d "$MODDIR/bin/kernels" ]; then
    echo "ERR: bin/kernels 存在但没有匹配本机架构($(pr_arch))的内核：";
    ls "$MODDIR/bin/kernels" 2>/dev/null | sed "s/^/     /";
    return 1
  fi
  sh "$(dirname "$0")/proxynode.sh" core-ensure
}

pr_start() {
  core=$(pr_core)
  [ -z "$core" ] && { echo "ERR: 没有可用内核（先跑 proxyrun.sh ensure）"; return 1; }
  if [ ! -s "$PR_CFG" ]; then
    sh "$(dirname "$0")/proxynode.sh" gen-config >/dev/null 2>&1
  fi
  [ -s "$PR_CFG" ] || { echo "ERR: 缺少内核配置。请先在面板选择节点以生成配置"; return 1; }
  sh "$(dirname "$0")/proxyrun.sh" stop >/dev/null 2>&1
  chk=$("$core" check -c "$PR_CFG" 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    case "$chk" in
      *"unknown command"*|*"invalid command"*|*"Usage:"*) : ;;
      *) echo "ERR: 配置校验未通过：$(printf '%s' "$chk" | head -n 3 | tr "\n" " ")"; return 1 ;;
    esac
  fi
  : > "$PR_LOG" 2>/dev/null
  bg_spawn "$PR_LOG" "$core" run -c "$PR_CFG" >/dev/null 2>&1
  i=0
  while [ "$i" -lt 15 ]; do
    sleep 0.4
    pid=$(pr_pid)
    [ -n "$pid" ] && { echo "OK: 代理内核已启动（$(basename "$core")）PID $pid"; return 0; }
    i=$((i+1))
  done
  echo "ERR: 内核启动后立即退出。最近日志：";
  tail -n 5 "$PR_LOG" 2>/dev/null | sed "s/^/     /"
  return 1
}

pr_stop() {
  p=$(cat "$PR_PID" 2>/dev/null)
  [ -n "$p" ] && kill "$p" 2>/dev/null
  pkill -f "run -c $PR_CFG" 2>/dev/null
  c=$(pr_core); [ -n "$c" ] && pkill -f "$(basename "$c")" 2>/dev/null
  rm -f "$PR_PID" 2>/dev/null
  echo "OK: 代理内核已停止"; return 0
}

pr_selftest() {
  echo "== 代理链路自检 =="
  n=0; bad=0
  core=$(pr_core)
  echo "① 内核文件"
  if [ -n "$core" ]; then echo "   [OK] $core"; n=$((n+1));
  else echo "   [失败] 没找到匹配 $(pr_arch) 的内核"; bad=$((bad+1)); fi
  echo "② 内核可执行性（硬判据）"
  if [ -n "$core" ]; then
    if "$core" version >/dev/null 2>&1; then echo "   [OK] 内核能执行并报版本"; n=$((n+1));
    else echo "   [失败] 内核无法执行（架构不符/文件损坏）—— 这是「内核不生效」最直接的原因"; bad=$((bad+1)); fi
  fi
  echo "③ 节点"
  if [ -s "$PR_DIR/nodes.conf" ]; then echo "   [OK] 已有节点"; n=$((n+1));
  else echo "   [失败] 没有节点（先在面板导入订阅或节点）"; bad=$((bad+1)); fi
  echo "④ 内核配置"
  if [ -s "$PR_CFG" ]; then echo "   [OK] config.json 已生成"; n=$((n+1));
  else echo "   [注意] 未生成（选择节点后自动生成）"; fi
  echo "⑤ 运行进程"
  pid=$(pr_pid)
  if [ -n "$pid" ]; then echo "   [OK] 正在运行 PID $pid"; n=$((n+1));
  else echo "   [未运行] 属正常（可手动 start）"; fi
  echo ""
  echo "结果：$n 项通过，$bad 项失败"
}

case "$1" in
  status)   pr_status ;;
  ensure)   pr_ensure ;;
  start)    pr_start ;;
  stop)     pr_stop ;;
  restart)  pr_stop; pr_start ;;
  selftest) pr_selftest ;;
  core)     pr_core ;;
  pid)      pr_pid ;;
  *) echo "usage: proxyrun.sh {status|ensure|start|stop|restart|selftest|core|pid}"; exit 2 ;;
esac

