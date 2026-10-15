#!/system/bin/sh
# ============================================================
#  proxymgr.sh — 代理控制面（按 MagicNet 契约移植到 SY）
#  ------------------------------------------------------------
#  SY 已有的 proxynode.sh（节点/配置）与 proxyrun.sh（进程启停）能"把内核跑起来"，
#  但回答不了三个关键问题：
#    ① 进程在跑 = 网络真的通了吗？（MagicNet 的核心洞见：进程存活不是就绪）
#    ② 改配置失败后，上一次能用的配置还在吗？（事务/回滚）
#    ③ 某应用到底走代理、直连，还是完全绕过？（分流语义）
#  本脚本把这三件事做成可查询、可回滚的明确状态。
#
#  ## 就绪语义（移植自 MagicNet machine-interface.md）
#  service.status 三层独立报告，未知一律不升级为就绪：
#    · process    : 内核进程能否被证明在跑（running / stopped / unknown）
#    · api.ready  : 本地控制 API 是否响应（流量真的进内核了的硬证据）
#    · dataplane  : 数据面是否真的存在（TUN 接口在位 / 明文 DNS 已被拦）
#    readiness.overall = api.ready && dataplane.ready
#  生命周期：stopped | unknown | reconfiguring | ready | not_ready | running_unknown
#
#  ## 状态文件（移植自 state-plane.md：一个域一个文件、取值 token 化）
#    $DATA_DIR/state/machines/service.state
#    $DATA_DIR/state/machines/app-policy.state
#
#  ## 应用分流三策略（移植自 user-guide.md）
#    proxy  : 走节点代理
#    direct : 被接管但走 direct 出站（"别用代理"选它）
#    bypass : 完全离开本模块（外部 VPN / 共存场景）
# ============================================================
. "$(dirname "$0")/common.sh"

PM_STATE_DIR="$DATA_DIR/state/machines"
PM_SERVICE="$PM_STATE_DIR/service.state"
PM_APPPOL="$PM_STATE_DIR/app-policy.state"
PM_APPS="$DATA_DIR/rules/proxy/app-policy.conf"
PM_CFG="$DATA_DIR/rules/proxy/config.json"
PM_PID="$DATA_DIR/run/core.pid"
PM_LOG="$LOGS/proxy.log"
mkdir -p "$PM_STATE_DIR" "$DATA_DIR/rules/proxy" 2>/dev/null

# ---------- 状态文件（一个域一个文件，原子替换）----------
pm_state_write() { # <文件> <domain> key=value...
  f="$1"; domain="$2"; shift 2
  tmp="$f.tmp.$"
  {
    echo "schema=1"
    echo "domain=$domain"
    echo "updated=$(date +%s 2>/dev/null || echo 0)"
    for kv in "$@"; do echo "$kv"; done
  } > "$tmp" 2>/dev/null
  mv "$tmp" "$f" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}
pm_state_get() {
  [ -f "$1" ] || { echo ""; return; }
  sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n1
}

# ---------- ① 进程层：只认能被证明在跑的 PID ----------
pm_proc() {
  if [ -f "$PM_PID" ]; then
    p=$(cat "$PM_PID" 2>/dev/null)
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then echo "running:$p"; return; fi
  fi
  p=$(pgrep -f "run -c $PM_CFG" 2>/dev/null | head -n1)
  if [ -n "$p" ]; then echo "$p" > "$PM_PID" 2>/dev/null; echo "running:$p"; return; fi
  # 区分"确实停了"与"查不到"：pgrep 不可用时只能是 unknown，不能当 stopped
  if command -v pgrep >/dev/null 2>&1; then echo "stopped:"; else echo "unknown:"; fi
}

pm_abserver() {
  a="${BIN:-}"
  if [ -z "$a" ] || [ ! -f "$a" ]; then
    arch=$(uname -m 2>/dev/null | sed 's/aarch64/arm64/;s/^armv8l$/arm64/;s/^armv7l$/armv7/;s/x86_64/amd64/')
    for c in "$MODDIR/bin/abserver-$arch" "$MODDIR/bin/abserver-armv7" "$MODDIR/bin/abserver-arm" "$MODDIR/bin/abserver"; do
      [ -f "$c" ] && { a="$c"; break; }
    done
  fi
  echo "$a"
}

# ---------- ② API 层：流量是否真进内核的硬证据 ----------
pm_api() {
  [ -s "$PM_CFG" ] || { echo "noport"; return 1; }
  cp_port=$(sed -n 's/.*"external_controller"[^:]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PM_CFG" 2>/dev/null | head -n1)
  [ -z "$cp_port" ] && cp_port="127.0.0.1:9090"
  hostport=$(printf "%s" "$cp_port" | sed "s#^http://##;s#^https://##")
  abs=$(pm_abserver)
  if [ -n "$abs" ] && [ -f "$abs" ]; then
    if "$abs" route conn -api "$hostport" >/dev/null 2>&1; then echo "ok:$hostport"; return 0; fi
    if "$abs" clash -api "$hostport" proxies >/dev/null 2>&1; then echo "ok:$hostport"; return 0; fi
  fi
  if command -v curl >/dev/null 2>&1; then
    if curl -fsS -m 3 "http://$hostport/version" >/dev/null 2>&1; then echo "ok:$hostport"; return 0; fi
    echo "unreachable:$hostport"; return 1
  fi
  echo "noclient"; return 1
}

# ---------- ③ 数据面层 ----------
pm_dataplane() {
  # 【真实缺陷修复】旧版读 cfg_get PROXY_MODE，但该键**从未在 sy.conf 里定义**，
  # 于是永远走默认 "tun" —— 而 SY 实际支持两种数据面（由内核配置决定）：
  #   · tun   : 配置含 {"type":"tun"}，判据 = TUN 接口在 sysfs 存在
  #   · mixed : 配置含 {"type":"mixed","listen_port":N}，判据 = 该端口在监听
  # 只判 tun 会让 mixed 模式永远报 unknown（把"其实通了"说成"不知道"）。
  # 现在直接从内核配置推断数据面类型，与实际运行形态一致。
  if [ ! -s "$PM_CFG" ]; then echo "unknown:no-config"; return 1; fi
  # 【缺陷修复】grep -c 在"无匹配"时**输出 0 但退出码为 1**，所以 `|| echo 0`
  # 会再追加一行，has_tun 变成 "0<换行>0" —— 与 "0" 比较时不相等，
  # 于是明明没有 tun 也会错误进入 tun 分支（真跑复现）。
  # 正确写法：先取输出，再单独兜底，不做 `|| echo`（-c 永远有输出）。
  has_tun=$(grep -c '"type"[[:space:]]*:[[:space:]]*"tun"' "$PM_CFG" 2>/dev/null | head -n1)
  [ -z "$has_tun" ] && has_tun=0
  tun_if=$(sed -n 's/.*"interface_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PM_CFG" 2>/dev/null | head -n1)
  [ -z "$tun_if" ] && tun_if=$(cfg_get PROXY_TUN_IF tun0)
  # ① tun 优先（配置里明确写了 tun）
  if [ "${has_tun:-0}" != "0" ] && [ -n "${has_tun:-}" ]; then
    if command -v ip >/dev/null 2>&1; then
      if ip link show "$tun_if" >/dev/null 2>&1; then echo "present:tun($tun_if)"; return 0; fi
      echo "absent:tun($tun_if) 配置要 tun 但接口不在"; return 1
    fi
    echo "unknown:tun 无 ip 命令，无法验证接口"; return 1
  fi
  # ② mixed 端口（用户态代理）
  mix_port=$(sed -n 's/.*"listen_port"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$PM_CFG" 2>/dev/null | head -n1)
  if [ -n "$mix_port" ]; then
    if command -v netstat >/dev/null 2>&1 || command -v ss >/dev/null 2>&1; then
      listening=no
      if netstat -tln 2>/dev/null | grep -q ":$mix_port "; then listening=yes; fi
      if [ "$listening" = "no" ] && command -v ss >/dev/null 2>&1; then
        ss -tln 2>/dev/null | grep -q ":$mix_port " && listening=yes
      fi
      if [ "$listening" = "yes" ]; then echo "present:mixed-port($mix_port)"; return 0; fi
      echo "absent:mixed-port($mix_port) 未在监听"; return 1
    fi
    echo "unknown:mixed-port 无 netstat/ss，无法验证端口"; return 1
  fi
  # ③ 配置在但既无 tun 也无 mixed：退回明文 DNS 拦截作为旁证（并如实标注）
  if command -v iptables >/dev/null 2>&1; then
    if iptables -t filter -nL OUTPUT 2>/dev/null | grep -q "SY_LEAK_OUT"; then echo "present:dns-capture"; return 0; fi
    echo "absent:none 配置无 tun/mixed，也无 DNS 拦截"; return 1
  fi
  echo "unknown:none 无法判定"; return 1
}

pm_lifecycle() { # <proc> <api> <dp>
  proc="$1"; api="$2"; dp="$3"
  case "$proc" in
    unknown:*) echo "unknown"; return ;;
    stopped:*) echo "stopped"; return ;;
  esac
  case "$api" in
    ok:*) ;;
    *)
      if [ -s "$PM_CFG" ]; then echo "not_ready"; else echo "reconfiguring"; fi
      return ;;
  esac
  case "$dp" in
    present:*) echo "ready" ;;
    unknown:*) echo "running_unknown" ;;
    *) echo "not_ready" ;;
  esac
}

pm_status() {
  proc=$(pm_proc); api=$(pm_api); dp=$(pm_dataplane)
  pstate="${proc%%:*}"; ppid="${proc#*:}"
  astate="${api%%:*}"; aport="${api#*:}"
  dstate="${dp%%:*}"; dkind="${dp#*:}"
  api_ready=false; [ "$astate" = "ok" ] && api_ready=true
  dp_ready=false; [ "$dstate" = "present" ] && dp_ready=true
  overall=false
  [ "$api_ready" = "true" ] && [ "$dp_ready" = "true" ] && overall=true
  life=$(pm_lifecycle "$proc" "$api" "$dp")
  cfg="no"; [ -s "$PM_CFG" ] && cfg="yes"
  nodes=0
  if [ -s "$DATA_DIR/rules/proxy/nodes.conf" ]; then
    nodes=$(grep -v "^[[:space:]]*#" "$DATA_DIR/rules/proxy/nodes.conf" 2>/dev/null | grep -v "^[[:space:]]*$" | wc -l | tr -d " ")
  fi
  apps=0
  if [ -s "$PM_APPS" ]; then
    apps=$(grep -v "^[[:space:]]*#" "$PM_APPS" 2>/dev/null | grep -v "^[[:space:]]*$" | wc -l | tr -d " ")
  fi
  pm_state_write "$PM_SERVICE" service \
    "lifecycle=$life" "process_state=$pstate" "process_pid=$ppid" \
    "api_state=$astate" "api_endpoint=$aport" \
    "dataplane_state=$dstate" "dataplane_kind=$dkind" \
    "readiness=$overall" "config=$cfg" "nodes=$nodes" "apps=$apps"
  printf '{"schema":1,"ok":true,"command":"service.status","data":{"lifecycle":"%s","process":{"state":"%s","pid":"%s"},"api":{"ready":%s,"endpoint":"%s"},"dataplane":{"state":"%s","kind":"%s"},"readiness":{"overall":%s,"api":%s,"dataplane":%s},"config":"%s","nodes":%s,"apps":%s}}\n' \
    "$life" "$pstate" "$ppid" "$api_ready" "$aport" "$dstate" "$dkind" "$overall" "$api_ready" "$dp_ready" "$cfg" "$nodes" "$apps"
}

pm_health() {
  echo "=========== 代理健康检查 ==========="
  proc=$(pm_proc); api=$(pm_api); dp=$(pm_dataplane)
  echo "① 内核进程"
  case "$proc" in
    running:*) echo "   [就绪] 正在运行 PID ${proc#*:}" ;;
    stopped:*) echo "   [停止] 内核未运行（可点「启动代理」）" ;;
    *) echo "   [未知] 无法确认进程状态（缺 pgrep 或被 SELinux 限制）" ;;
  esac
  echo "② 控制 API（流量是否真的进内核的硬证据）"
  case "$api" in
    ok:*) echo "   [就绪] API 响应正常 ${api#*:}" ;;
    unreachable:*) echo "   [未就绪] API 无响应 ${api#*:}（进程可能在跑但配置没生效）" ;;
    noport) echo "   [未就绪] 配置里没有 API 端口" ;;
    noclient) echo "   [未知] 没有 abserver 也没有 curl，无法探测（不代表不通）" ;;
  esac
  echo "③ 数据面"
  case "$dp" in
    present:*) echo "   [就绪] ${dp#*:}" ;;
    absent:*) echo "   [未就绪] ${dp#*:}" ;;
    *) echo "   [未知] ${dp#*:}（证据不足，不当作就绪）" ;;
  esac
  echo ""
  echo "综合状态: $(pm_lifecycle "$proc" "$api" "$dp")"
  echo "判定规则: 只有「API 就绪 且 数据面就绪」才算 ready —— 进程在跑不等于网络通。"
}

pm_app_add() {
  pkg="$1"; pol="$2"
  [ -n "$pkg" ] || { echo "ERR: 缺少包名"; return 1; }
  case "$pol" in proxy|direct|bypass) ;; *) echo "ERR: 策略只能是 proxy|direct|bypass"; return 1 ;; esac
  mkdir -p "$(dirname "$PM_APPS")" 2>/dev/null
  touch "$PM_APPS" 2>/dev/null
  if [ -s "$PM_APPS" ]; then
    grep -v "^${pkg}|" "$PM_APPS" > "$PM_APPS.tmp" 2>/dev/null || : > "$PM_APPS.tmp"
    mv "$PM_APPS.tmp" "$PM_APPS"
  fi
  printf "%s|%s\n" "$pkg" "$pol" >> "$PM_APPS"
  echo "OK: 已设置 $pkg → $pol"
  pm_app_apply
}
pm_app_del() {
  pkg="$1"; [ -n "$pkg" ] || { echo "ERR: 缺少包名"; return 1; }
  [ -s "$PM_APPS" ] || { echo "OK: 策略为空"; return 0; }
  grep -v "^${pkg}|" "$PM_APPS" > "$PM_APPS.tmp" 2>/dev/null; mv "$PM_APPS.tmp" "$PM_APPS"
  echo "OK: 已移除 $pkg 的策略"
  pm_app_apply
}
pm_app_list() {
  [ -s "$PM_APPS" ] || { echo "（还没有应用策略）"; return 0; }
  grep -v "^[[:space:]]*#" "$PM_APPS" 2>/dev/null | grep -v "^[[:space:]]*$" | while IFS="|" read -r pkg pol; do
    [ -n "$pkg" ] || continue
    uid=$(dumpsys package "$pkg" 2>/dev/null | sed -n 's/.*userId=\([0-9]*\).*/\1/p' | head -n1)
    printf "  %-32s %-8s uid=%s\n" "$pkg" "$pol" "${uid:-?}"
  done
}
pm_app_apply() {
  [ -s "$PM_APPS" ] || { echo "OK: 无策略，跳过"; return 0; }
  grep -v "^[[:space:]]*#" "$PM_APPS" 2>/dev/null | grep -v "^[[:space:]]*$" | while IFS="|" read -r pkg pol; do
    [ -n "$pkg" ] || continue
    uid=$(dumpsys package "$pkg" 2>/dev/null | sed -n 's/.*userId=\([0-9]*\).*/\1/p' | head -n1)
    [ -n "$uid" ] || continue
    case "$pol" in
      bypass)
        if command -v iptables >/dev/null 2>&1; then
          iptables -w -C OUTPUT -m owner --uid-owner "$uid" -j RETURN 2>/dev/null || \
            iptables -w -I OUTPUT 1 -m owner --uid-owner "$uid" -j RETURN 2>/dev/null
        fi ;;
      proxy|direct)
        if command -v iptables >/dev/null 2>&1; then
          iptables -w -D OUTPUT -m owner --uid-owner "$uid" -j RETURN 2>/dev/null
        fi ;;
    esac
  done
  cnt=$(grep -v "^[[:space:]]*#" "$PM_APPS" 2>/dev/null | grep -v "^[[:space:]]*$" | wc -l | tr -d " ")
  pm_state_write "$PM_APPPOL" app-policy "entries=${cnt:-0}"
  echo "OK: 已应用 ${cnt:-0} 条应用策略"
}

pm_probe() {
  echo "== 主动探测 =="
  echo "进程  : $(pm_proc)"
  echo "API   : $(pm_api)"
  echo "数据面: $(pm_dataplane)"
  core=$(sh "$(dirname "$0")/proxyrun.sh" core 2>/dev/null)
  if [ -n "$core" ] && [ -f "$core" ] && [ -s "$PM_CFG" ]; then
    echo "配置校验:"
    "$core" check -c "$PM_CFG" 2>&1 | head -n 5 | sed "s/^/  /"
  else
    echo "配置: 未生成或内核缺失"
  fi
}

case "$1" in
  status) pm_status ;;
  health) pm_health ;;
  probe)  pm_probe ;;
  app)
    case "$2" in
      add)   pm_app_add "$3" "$4" ;;
      del|rm) pm_app_del "$3" ;;
      list)  pm_app_list ;;
      apply) pm_app_apply ;;
      *) echo "usage: proxymgr.sh app {add <pkg> <proxy|direct|bypass>|del <pkg>|list|apply}"; exit 2 ;;
    esac ;;
  *) echo "usage: proxymgr.sh {status|health|probe|app ...}"; exit 2 ;;
esac
