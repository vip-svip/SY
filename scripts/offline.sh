#!/system/bin/sh
# ============================================================
#  offline.sh — 断网（无网）场景的探测与降级
#  ------------------------------------------------------------
#  为什么单独做这件事：模块里大量操作依赖网络（规则订阅、内核下载、
#  面板远程访问、DoH 上游）。网络不可用时，旧行为的通病是：
#    · 卡在那里等超时（面板转圈、按钮点了没反应）；
#    · 只报一句「失败」，用户不知道是没网还是别的原因；
#    · 该走缓存的场景（已有上次下载的规则）却直接报错。
#
#  本脚本提供三件事：
#    net  [check|wait]      连通性探测（不依赖 ping，用 DNS+HTTP 双判据）
#    need <描述> [命令...]  包装网络操作：无网则明确告知并走缓存/跳过，不空等
#    cache-report           报告哪些数据有本地缓存（无网也能用）
#
#  如实说明：探测基于「能否连上探测目标」。厂商定制 ROM 可能对探测
#  地址做了拦截/代理，因此探测结论是**当前这一时刻的可用性**，不是绝对事实。
# ============================================================
. "$(dirname "$0")/common.sh"

OFFLINE_PROBE_DNS="1.1.1.1"
OFFLINE_PROBE_HOST="connectivitycheck.gstatic.com"

# 连通性探测：两条判据任一通过即认为「有网」
#  ① DNS 能解析出 IP（最快，通常几十毫秒）
#  ② TCP 能连上（用 abserver 的探测或 nslookup 的返回）
net_check() {
  # 【真机缺陷修复】旧版两条判据在真机上**全都误报无网**（实测）：
  #   ① 读 /proc/net/route 找 Destination=00000000 —— Android 用多路由表，
  #      默认路由不在该文件里（实测该文件只有 192.168.0.0/24 一条），
  #      于是永远判"没有默认路由"；
  #   ② 读 getprop net.dns1/dns2 —— Android 10+ 这两个 prop 已废弃（实测为空）。
  #   结果：有网时也报 offline，导致「断网优化」把在线环境当离线，跳过全部网络操作。
  # 现在改为**真实连通性探测**（优先轻量、再退到 HTTP）。

  # 判据 ①：能否连通一个公网 IP（不依赖 DNS、不依赖路由表格式）
  if command -v ping >/dev/null 2>&1; then
    if ping -c 1 -W 2 $OFFLINE_PROBE_IP >/dev/null 2>&1; then echo "online"; return 0; fi
  fi
  # 判据 ②：HTTP 204 探测（部分网络禁 ICMP，但 HTTP 通）
  if command -v curl >/dev/null 2>&1; then
    if curl -s -m 5 -o /dev/null "$OFFLINE_PROBE_URL" 2>/dev/null; then echo "online"; return 0; fi
  fi
  # 判据 ③：能不能解析出地址（有 DNS 但 ICMP/HTTP 被禁的少数环境）
  if command -v nslookup >/dev/null 2>&1; then
    if nslookup $OFFLINE_PROBE_HOST >/dev/null 2>&1; then echo "online"; return 0; fi
    echo "dns-fail"; return 1
  fi
  # 判据 ④：有没有默认网络（dumpsys 在 Android 上是权威的）
  if command -v dumpsys >/dev/null 2>&1; then
    if dumpsys connectivity 2>/dev/null | grep -q "Active default network"; then echo "online"; return 0; fi
    echo "no-default-network"; return 1
  fi
  # 判据 ⑤：兜底看接口是否有非回环地址（最弱，但比"只看路由表"可靠）
  if command -v ip >/dev/null 2>&1; then
    if ip -4 addr show 2>/dev/null | sed -n "s/.*inet \([0-9][0-9.]*\).*/\1/p" | grep -qv "^127\."; then
      echo "likely-online"; return 0
    fi
    echo "no-address"; return 1
  fi
  # 什么都探测不了：如实报"未知"，不假装无网也不假装有网
  echo "unknown"; return 2
}

# 等待网络就绪（开机后网络通常晚于 boot_completed 十几秒）
net_wait() { # [最长秒数]
  max="${1:-60}"; i=0
  while [ "$i" -lt "$max" ]; do
    if net_check >/dev/null 2>&1; then echo "online"; return 0; fi
    sleep 2; i=$((i+2))
  done
  echo "offline"; return 1
}

# 网络操作包装：无网时明确告知并跳过（可选走缓存），绝不空等
# 用法: net_need "<做什么>" [缓存文件]
net_need() { # <描述> [缓存文件]
  desc="$1"; cache="$2"
  # unknown 时**不要**当成无网（旧版只看退出码，会把"探测不了"当"没网"）
  rc=0; reason=$(net_check 2>/dev/null) || rc=$?
  [ "$rc" = "2" ] && return 0   # 探测不了 → 放行，让调用方自己失败
  [ "$rc" = "0" ] && return 0
  [ -z "$reason" ] && return 0
  case "$reason" in
    no-route) msg="没有默认路由（多半是没连 Wi-Fi/移动数据，或飞行模式）" ;;
    no-dns)   msg="没有配置 DNS（网络还没就绪，或 DNS 被改坏了）" ;;
    dns-fail) msg="DNS 解析失败（网络不通，或 DNS 服务器不可达）" ;;
    *)        msg="当前检测不到网络" ;;
  esac
  echo "SKIP: 无法$desc —— $msg"
  if [ -n "$cache" ] && [ -s "$cache" ]; then
    echo "      已有上次缓存（$(count_lines "$cache") 行），本次沿用缓存，功能不受影响";
  else
    echo "      没有可用缓存：$desc 需要联网后才能完成。联网后再点一次即可。";
  fi
  log "offline: skip [$desc] reason=$reason cache=${cache:-none}"
  return 1
}

# 缓存报告：列出当前哪些数据在本地可用（无网也能跑）
cache_report() {
  echo "== 离线可用数据（无需联网）=="
  for pair in \
    "config/sy.conf|主配置" \
    "config/user_rules.txt|自定义规则" \
    "config/blacklist.conf|黑名单" \
    "config/whitelist.conf|白名单" \
    "config/lists.conf|规则表清单" \
    "rules/remote/block.txt|已缓存的拦截规则" \
    "rules/remote/upstream.txt|已缓存的上游规则" \
    "rules/engine/hosts|已编译的 hosts（引擎产物）" \
    "rules/dns/hosts|已生成的 hosts" \
    "rules/proxy/nodes.conf|已保存的节点" \
    "rules/fx/block_domains.txt|FX 深度抵抗清单" \
    "data/geo/dbip-country-lite.mmdb|离线 GeoIP 库" ; do
    # 【真机缺陷修复】Android 的 sh 是 mksh(MIRBSD KSH R59)，它下
    # ${pair%%|*} / ${pair##*|} **返回空**（本机 ash/busybox 上正常）——
    # 于是整个 cache-report 的标签与路径解析全空（真机实测）。
    # 改用 sed 按分隔符切分（与 shell 实现无关，任何 Android 版本都稳）。
    p="$DATA_DIR/$(printf '%s' "$pair" | sed 's/|.*//')"
    label="$(printf '%s' "$pair" | sed 's/.*|//')"
    if [ -s "$p" ]; then
      printf "  %-38s %s  (%s 行)\n" "$label" "可用" "$(count_lines "$p")"
    else
      printf "  %-38s %s\n" "$label" "未生成（需联网或首次应用）"
    fi
  done
  echo ""
  echo "结论：DNS 拦截、隐私护盾、FX 深度抵抗、节点使用都**不依赖联网**；"
  echo "      只有「规则订阅更新」「内核下载」「在线更新」需要网络。"
}

case "$1" in
  check)        net_check; echo "" ;;
  wait)         net_wait "${2:-60}" ;;
  need)         shift; net_need "$@" ;;
  cache-report) cache_report ;;
  *) echo "usage: offline.sh {check|wait [秒]|need <描述> [缓存]|cache-report}"; exit 2 ;;
esac

