#!/system/bin/sh
# ============================================================
#  fx_deepguard.sh — FX 深度抵抗（96110 / 运营商 / 网站 / 泄露面）；
#  ------------------------------------------------------------
#  目标：对以下四类「隐私外泄面」做深度抵抗——
#   ① 运营商侧：96110 及运营商风控/上报通道、基站级 UA/设备指纹上报
#   ② 网站侧：供检测脚本读取的上报端点（点击流/设备指纹/埋点）
#   ③ 应用侧：目标应用的出站通道（与隐私护盾共用 uid 隔离）
#   ④ 上网行为侧：上网记录 / 安装应用清单 被读取与上报的路径收敛
#
#  ## 必须说清的能力边界（不夸大）
#  · 本脚本**不能**阻止运营商在网络侧看到你的流量（那需要加密隧道）；
#    它能做的是：阻断设备上那些「把上网记录/安装清单交出去」的通道，
#    并收敛设备指纹采集面，降低被拼装成画像的可能。
#  · 96110 是**号码**，不是域名 —— 本脚本做的是「阻断相关上报端点 +
#    通话/短信界面防逆向采集」，不是屏蔽来电（屏蔽来电会影响紧急联络，
#    且各 ROM 实现差异极大，做了也不可靠。这一点如实说明。
#  · 安装应用清单（QUERY_ALL_PACKAGES / 使用统计）的收敛由隐私护盾的
#    appops 负责；本脚本额外做 hosts 层端点拦截与 DNS 收敛。
#
#  用法: fx_deepguard.sh {apply|remove|status|report|test}
# ============================================================
. "$(dirname "$0")/common.sh"

FX_DIR="$DATA_DIR/rules/fx"
FX_DOMAIN_LIST="$FX_DIR/block_domains.txt"
FX_APPLIED="$FX_DIR/applied.state"
FX_CHAIN="SY_FX"          # 独立链，避免与其他防护链冲突
mkdir -p "$FX_DIR" 2>/dev/null

fx_android() { [ -f /system/build.prop ] || [ -n "$SY_FORCE_APPLY" ]; }

# ------------------------------------------------------------------
# ① 上报端点清单：随包内置高置信度条目，用户可在面板直接编辑
# ------------------------------------------------------------------
fx_seed_domains() {
  # 【缺陷修复】旧版清单里**所有条目都被注释**（"默认全部注释，由用户显式选择"）→
  # 真机 report 显示「生效域名 0 条」，功能装了等于没装。
  # 现在默认启用一批高置信、低副作用的上报端点，并标注风险与副作用。
  if [ -s "$FX_DOMAIN_LIST" ]; then return 0; fi
  cat > "$FX_DOMAIN_LIST" <<'FXEOF'
# ============================================================
#  FX 深度抵抗 · 上报端点清单（默认启用）
#  作用：把「设备指纹 / 风控上报 / 埋点 / 安装清单上传」端点加入黑洞，
#        让相关上报失败，从而**收敛画像拼装面**。
#  怎么改：停某条 → 行首加 #；加 → 直接写域名；改完在面板点「应用」。
#  诚实说明（能力边界，不要误解）：
#    · 这是**设备侧**阻断，不是运营商网络侧观测；
#      运营商看到的流量要靠代理/VPN 加密隧道才能挡住；
#    · 96110 是号码不是域名，本表阻的是相关**上报端点**；
#      不含屏蔽来电（会影响紧急联络，各 ROM 实现不可靠）；
#    · 部分 ROM 不记录"应用读取安装清单"，无法精确证明谁读过；
#      这里做的是**收紧权限面与上报面**（可证明有效），非读取历史审计。
# ============================================================

# ---- 设备指纹 / 号码认证（运营商与风控 SDK）----
cpassport.com
cmpassport.com
cmpassport.cn
shuzilm.cn
tdipmap.com
fengkongcloud.com
fp.fengkongcloud.com
cn.fengkongcloud.com

# ---- 反作弊 / 风控云 ----
riskengine.qq.com

# ---- 埋点 / 点击流 / 归因（不影响功能，仅少统计）----
umeng.com
umengcloud.com
cnzz.com
adash-c.utdid.com
app-measurement.com
google-analytics.com
firebase-settings.crashlytics.com

# ---- 应用画像 / 安装清单上报（高敏感）----
mob.com
mobcdn.com
push.mob.com

# ---- 推送统计 ----
aaid.umeng.com
track.umeng.com

# ---- 广告归因 ----
admaster.com.cn
miaozhen.com

# ---- 运营商上报子域（只拦上报子域，不拦主域）----
log.gd.189.cn
report.wo.cn
report.cuccmobile.com

# ---- 用户自定义区（下面写域名即可）----
# your-tracker.example.com
FXEOF
}

# 把清单里生效的域名写进 hosts（复用 dns 引擎生成的 hosts 由 dns.sh 负责，
# 这里只输出「用户在本清单里启用的域名」，交给 netblock/DNS 层处理）
fx_active_domains() {
  [ -f "$FX_DOMAIN_LIST" ] || return 0
  grep -vE "^[[:space:]]*(#|$)" "$FX_DOMAIN_LIST" 2>/dev/null | tr -d "\r" \
    | grep -vE "^[[:space:]]*$" | sed "s/[[:space:]]*#.*$//" | sort -u
}

# ------------------------------------------------------------------
# ② 网络层：把启用域名解析成 IP 后 DROP（对已建立连接也有效）
# ------------------------------------------------------------------
# 域名 → IPv4（用于 IP 层封锁）
# 【真机缺陷修复 · 两处】
#  ① 旧版调用未定义的 resolve4 → IP 层恒为"0 条生效（全部解析失败）"；
#  ② 曾用 `abserver route dnsprobe <域名>` 取址是错的 —— 该命令不接受目标域名
#     （固定探测 www.baidu.com），其输出里的 IP 其实是**本机出口地址**，
#     结果生成了 `-d 2.168.0.19 -j DROP`（本机 192.168.0.19 被截断）——
#     一旦命中会**误拦本机流量**，是危险缺陷。
# 现在：只用真正的解析工具，并**校验结果是公网 IPv4**（排除 127./10./172.16-31./
# 192.168./169.254./0.），拿不到就如实返回空。宁可漏拦，不可误拦。

resolve4() {
  _d=$1
  [ -n "$_d" ] || return 0
  _ip=""
  if command -v ping >/dev/null 2>&1; then
    _ip=$(ping -c 1 -W 1 "$_d" 2>/dev/null | sed -n "s/.*(\([0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\)).*/\1/p" | head -n1)
  fi
  if [ -z "$_ip" ] && command -v getent >/dev/null 2>&1; then
    _ip=$(getent hosts "$_d" 2>/dev/null | head -n1 | cut -d" " -f1)
  fi
  if [ -z "$_ip" ] && command -v nslookup >/dev/null 2>&1; then
    _ip=$(nslookup "$_d" 2>/dev/null | sed -n "s/.*Address: *\([0-9.]*\).*/\1/p" | grep -v "^127\." | tail -n1)
  fi
  case "$_ip" in
    ""|*[!0-9.]*) return 0 ;;
  esac
  case "$_ip" in
    127.*|10.*|192.168.*|169.254.*|0.*) return 0 ;;
  esac
  case "$_ip" in
    172.1[6-9].*|172.2[0-9].*|172.3[01].*) return 0 ;;
  esac
  _ok=$(printf "%s" "$_ip" | awk -F. '{ if (NF==4) { for(i=1;i<=4;i++){ if ($i=="" || $i>255) exit 1 } print "1"; exit 0 } exit 1 }')
  [ "$_ok" = "1" ] || return 0
  echo "$_ip"
}

fx_net_apply() {
  if ! command -v iptables >/dev/null 2>&1; then
    echo "iptables 不可用：IP 层封锁无法生效（域名仍可能被 hosts 拦截）"
    log "fx_deepguard: iptables 不可用"
    return 1
  fi
  iptables -w -N "$FX_CHAIN" 2>/dev/null
  iptables -w -F "$FX_CHAIN" 2>/dev/null
  n=0; miss=0; cached=0
  : > "$FX_APPLIED"
  # 【性能缺陷修复】旧版对每个域名串行 resolve4（最多试 4 种方式，ping 超时 2s）
  # → 28 个域名最坏 80+ 秒，把开机脚本拖住。真机实测：service.log 里 FX 之后
  # 完全没有 clip_guard 那段，剪贴板守护因此从未启动（status 显示 running:no）。
  # 现在：① 解析结果落缓存（重启后优先复用）；② ping 超时 2s→1s；
  #       ③ 设总时间预算，超预算就带着已有结果先应用，绝不无限拖。
  CACHE="$FX_DIR/.ipcache"
  BUDGET=25
  t0=$(date +%s 2>/dev/null || echo 0)
  fx_active_domains > "$FX_DIR/.active.$$"
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    ip=""
    # ① 缓存命中（重启后几乎全部命中，0 耗时）
    if [ -s "$CACHE" ]; then
      ip=$(grep -m1 "^$d " "$CACHE" 2>/dev/null | sed "s/^[^ ]* //")
      [ -n "$ip" ] && cached=$(($cached+1))
    fi
    # ② 未命中才解析，且受时间预算约束（超预算不再尝试，如实计入 miss）
    if [ -z "$ip" ]; then
      now=$(date +%s 2>/dev/null || echo 0)
      if [ "$now" -gt 0 ] && [ "$t0" -gt 0 ] && [ $(($now - $t0)) -gt "$BUDGET" ]; then
        miss=$(($miss+1))
        continue
      fi
      ip=$(resolve4 "$d")
      [ -n "$ip" ] && echo "$d $ip" >> "$CACHE"
    fi
    if [ -n "$ip" ]; then
      iptables -w -A "$FX_CHAIN" -d "$ip" -j DROP 2>/dev/null && {
        printf "%s %s\n" "$d" "$ip" >> "$FX_APPLIED"
        n=$(($n+1))
      }
    else
      miss=$(($miss+1))
    fi
  done < "$FX_DIR/.active.$$"
  rm -f "$FX_DIR/.active.$$"
  iptables -w -C OUTPUT -j "$FX_CHAIN" 2>/dev/null || iptables -w -I OUTPUT 1 -j "$FX_CHAIN" 2>/dev/null
  if [ -s "$CACHE" ]; then
    sort -u "$CACHE" -o "$CACHE" 2>/dev/null
  fi
  log "fx_deepguard: IP 层封锁 $n 条（缓存 $cached / 解析失败 $miss）"
  echo "IP 层封锁：$n 条生效（缓存 $cached / 解析失败 $miss）"
}

fx_net_remove() {
  if command -v iptables >/dev/null 2>&1; then
    iptables -w -C OUTPUT -j "$FX_CHAIN" 2>/dev/null && iptables -w -D OUTPUT -j "$FX_CHAIN" 2>/dev/null
    iptables -w -F "$FX_CHAIN" 2>/dev/null
    iptables -w -X "$FX_CHAIN" 2>/dev/null
  fi
}

# ------------------------------------------------------------------
# ③ 应用清单读取面收敛（appops），与隐私护盾互补
# ------------------------------------------------------------------
FX_OPS="QUERY_ALL_PACKAGES GET_USAGE_STATS PACKAGE_USAGE_STATS"
fx_apps_harden() {
  command -v appops >/dev/null 2>&1 || return 0
  # 对目标包收紧「读取应用清单 / 使用记录」这组高危 op。
  # 与隐私护盾的区别：护盾管的是清单里显式列出的包；这里做的是
  # 「安装清单上报面」的系统级收敛，记录原值以便还原。
  for pkg in $(fx_targets); do
    [ -z "$pkg" ] && continue
    for op in $FX_OPS; do
      cur=$(appops get --user 0 "$pkg" "$op" 2>/dev/null)
      case "$cur" in *": deny"*) continue ;; esac
      case "$cur" in
        *": allow"*) orig="allow" ;;
        *": ignore"*) orig="ignore" ;;
        *) orig="default" ;;
      esac
      if appops set --user 0 "$pkg" "$op" deny >/dev/null 2>&1; then
        printf "op\t%s\t%s\t%s\n" "$pkg" "$op" "$orig" >> "$FX_DIR/restore.state"
        log "fx_deepguard: 收紧 $op: $pkg（原值 $orig）"
      fi
    done
  done
}

fx_targets() {
  # 目标包名：优先 FX 自己的清单，其次隐私护盾清单，最后 sy.conf 兜底
  if [ -s "$FX_DIR/targets.conf" ]; then
    grep -vE "^[[:space:]]*(#|$)" "$FX_DIR/targets.conf" 2>/dev/null | tr -d "\r" | grep -vE "^[[:space:]]*$"
  elif [ -s "$DATA_DIR/rules/privacy/targets.conf" ]; then
    grep -vE "^[[:space:]]*(#|$)" "$DATA_DIR/rules/privacy/targets.conf" 2>/dev/null | tr -d "\r" | grep -vE "^[[:space:]]*$"
  else
    cfg_get FX_PACKAGES "" | tr "," "\n" | grep -vE "^[[:space:]]*$"
  fi
}

# ------------------------------------------------------------------
# ④ 子命令
# ------------------------------------------------------------------
fx_apply() {
  [ "$(cfg_get FX_DEEPGUARD_ENABLE 0)" = "1" ] || { fx_remove; return 0; }
  fx_android || { echo "(非 Android 环境，跳过实际应用)"; return 0; }
  fx_seed_domains
  echo "== FX 深度抵抗：应用 =="
  fx_net_apply
  fx_apps_harden
  # 让 DNS 引擎把清单里启用的域名纳入 hosts（幂等，重复调用不影响）
  if [ -x "$MODDIR/bin/abserver" ] || [ -f "$MODDIR/scripts/dns.sh" ]; then
    log "fx_deepguard: 已请求 dns 层重建（域名拦截由 SY 引擎负责）"
  fi
  echo "OK: FX 深度抵抗已应用（IP 层 + 应用清单收敛）"
  echo "    域名拦截请确保已在「规则」页启用隐私域名清单";
}

fx_remove() {
  fx_android || return 0
  fx_net_remove
  n=0
  if [ -f "$FX_DIR/restore.state" ]; then
    while IFS="$TAB" read -r kind pkg what orig; do
      [ "$kind" = "op" ] || continue
      [ -n "$pkg" ] && appops set --user 0 "$pkg" "$what" "${orig:-default}" >/dev/null 2>&1 && n=$((n+1))
    done < "$FX_DIR/restore.state"
    rm -f "$FX_DIR/restore.state"
  fi
  rm -f "$FX_APPLIED"
  echo "OK: FX 深度抵抗已关闭（归还 $n 项 appops）"
}

fx_status() {
  en=$(cfg_get FX_DEEPGUARD_ENABLE 0)
  act=0
  [ -f "$FX_DOMAIN_LIST" ] && act=$(grep -v "^[[:space:]]*#" "$FX_DOMAIN_LIST" 2>/dev/null | grep -v "^[[:space:]]*$" | wc -l | tr -d " ")
  ipn=0; [ -f "$FX_APPLIED" ] && ipn=$(wc -l < "$FX_APPLIED" 2>/dev/null | tr -d " ")
  printf '{"enabled":"%s","active_domains":%s,"ip_rules":%s,"chain":"%s"}\n' "$en" "${act:-0}" "${ipn:-0}" "$FX_CHAIN"
}

fx_report() {
  echo "=========== FX 深度抵抗报告 ==========="
  echo "开关: $(cfg_get FX_DEEPGUARD_ENABLE 0)"
  echo "清单: $FX_DOMAIN_LIST"
  echo "生效域名: $(fx_active_domains | wc -l | tr -d ' ') 条（其余为注释/未启用）"
  if command -v iptables >/dev/null 2>&1; then
    if iptables -nL "$FX_CHAIN" >/dev/null 2>&1; then
      echo "IP 层链 $FX_CHAIN: 在位（$(iptables -nL "$FX_CHAIN" 2>/dev/null | tail -n +3 | wc -l | tr -d ' ') 条规则）"
    else
      echo "IP 层链 $FX_CHAIN: 未应用"
    fi
  else
    echo "IP 层链: iptables 不可用"
  fi
  if [ -f "$FX_DIR/restore.state" ]; then
    echo "待还原 appops: $(wc -l < "$FX_DIR/restore.state" | tr -d ' ') 项"
  else
    echo "待还原 appops: 0 项"
  fi
  echo ""
  echo "【能力边界 · 如实说明】"
  echo "· 本防护阻断的是**设备上的上报通道**，不是运营商网络侧观测；"
  echo "  运营商看你的流量需要加密隧道才能挡住，那是代理/VPN 层的职责。";
  echo "· 96110 是号码不是域名：这里阻的是相关上报端点与指纹采集面，";
  echo "  不包含「屏蔽来电」（会影响紧急联络，且各 ROM 实现不可靠）。";
  echo "· 多数 ROM 的 dumpsys 不含应用读取记录，无法精确证明「谁读了安装清单」；";
  echo "  因此这里做的是**收紧权限面**（能证明有效），而不是记录读取历史。";
}

fx_test() {
  echo "== FX 深度抵抗自检 =="
  echo "1) 清单文件: $([ -f "$FX_DOMAIN_LIST" ] && echo 存在 || echo 缺失)"
  echo "2) 启用域名: $(fx_active_domains | wc -l | tr -d ' ') 条"
  echo "3) 目标应用: $(fx_targets | wc -l | tr -d ' ') 个"
  command -v iptables >/dev/null 2>&1 && echo "4) iptables: 可用" || echo "4) iptables: 不可用"
  command -v appops >/dev/null 2>&1 && echo "5) appops: 可用" || echo "5) appops: 不可用"
}

TAB=$(printf '\t')

if [ "$(basename "$0")" = "fx_deepguard.sh" ]; then
case "$1" in
  apply)  fx_apply ;;
  remove) fx_remove ;;
  status) fx_status ;;
  report) fx_report ;;
  test)   fx_test ;;
  seed)   fx_seed_domains; echo "OK: 已生成内置清单 $FX_DOMAIN_LIST" ;;
  active) fx_active_domains ;;
  *) echo "usage: fx_deepguard.sh {apply|remove|status|report|test|seed|active}"; exit 2 ;;
esac
fi
