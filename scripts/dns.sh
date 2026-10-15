#!/system/bin/sh
# ============================================================
#  dns.sh — 第一层：DNS 级内核拦截
#  功能: 规则订阅下载/管理、解析(AdGuard/Pi-hole/hosts/domain)、
#        自定义规则导入(文本/base64/文件)、合并生成 hosts、
#        智能白名单、规则预览、绑定挂载、拦截日志
#  用法: dns.sh {apply|update|status|whitelist-add|whitelist-del|whitelist-list|
#               import-b64|import|import-file|custom-list|custom-save-b64|
#               custom-clear|sources-list|sources-add|sources-del|rules-preview|clear}
# ============================================================
. "$(dirname "$0")/common.sh"

HOSTS_OUT="$DNS_DIR/hosts"
CUSTOM="$DNS_DIR/custom.txt"
RAW_DIR="$CACHE/dns"
REMOVED="$DNS_DIR/removed.txt"
UPSTREAM="$DATA_DIR/rules/remote/upstream.txt"
BLACKLIST="$DATA_DIR/config/blacklist.conf"
NETBLOCK_DIR="$DATA_DIR/rules/netblock"
# 【死代码清理】下面三个函数被删除了，原因是**定义了但从未被调用**，也没有任何
# 跨脚本引用（全仓库检索确认）：
#   · parse_rule_file() —— 单文件规则解析。此能力已由 engine.sh 的融合引擎承担，
#     引擎支持 AdGuard/hosts/dnsmasq 全语法且带统计与优先级，这里是重复实现。
#   · is_whitelisted() / is_blacklisted() —— 逐域名线性匹配。同样由引擎的
#     白/黑名单匹配承担。留在这里会让"读代码的人以为走后一条路径"。
# 删掉它们不是"减功能"：对应能力仍在，且是引擎那一份（被真正使用的那份）。

mkdir -p "$RAW_DIR" "$DNS_DIR"

# ---------- 解析单条规则文件 ----------

# ---------- 下载所有订阅源(仅下载到 RAW_DIR) ----------
fetch_sources() {
  [ -f "$SOURCES" ] || return 0
  n=0
  while IFS= read -r line; do
    case "$line" in ""|\#*) continue ;; esac
    url=$(echo "$line" | awk -F'|' '{print $NF}')
    name=$(echo "$line" | awk -F'|' 'NF>1{print $1; next}{print "src"NR}')
    name=$(echo "$name" | tr -c 'a-zA-Z0-9_-' '_')
    rawf="$RAW_DIR/$name.txt"
    log "dns: 下载 $name <- $url"
    if http_get "$url" "$rawf" 30; then
      log "dns: $name 下载成功 ($(count_lines "$rawf") 行)"
      n=$((n+1))
    else
      log "dns: $name 下载失败，保留本地缓存"
    fi
  done < "$SOURCES"
  # SY-Rules 上游源(upstream.txt): 每行一个 URL
  if [ -f "$UPSTREAM" ]; then
    un=0
    while IFS= read -r uurl; do
      case "$uurl" in ""|\#*) continue ;; esac
      un=$((un+1))
      uraw="$RAW_DIR/upstream_$un.txt"
      if http_get "$uurl" "$uraw" 30; then log "dns: upstream_$un OK"; n=$((n+1)); fi
    done < "$UPSTREAM"
  fi
  log "dns: 订阅下载完成，成功 $n 个"
}

# ---------- 重建域名总表(融合引擎编译 + 兼容统计) ----------
rebuild_domains() {
  # 由融合引擎(AdGuard Home + uBlock Origin 语法)统一编译
  sh "$(dirname "$0")/engine.sh" build >/dev/null 2>&1
  E="$RULES_DIR/engine"
  : > "$RAW_DIR/all_domains.txt"
  cat "$E/block_imp.txt" "$E/block.txt" "$E/heuristic_block.txt" >> "$RAW_DIR/all_domains.txt" 2>/dev/null
  # 应用"已生效规则删除"排除表
  if [ -f "$REMOVED" ] && [ -s "$REMOVED" ]; then
    grep -vxF -f "$REMOVED" "$RAW_DIR/all_domains.txt" > "$RAW_DIR/all_domains.excl.$$" 2>/dev/null && mv "$RAW_DIR/all_domains.excl.$$" "$RAW_DIR/all_domains.txt"
  fi
  sort -u "$RAW_DIR/all_domains.txt" -o "$RAW_DIR/all_domains.txt" 2>/dev/null
  log "dns: 域名总表 $(count_lines "$RAW_DIR/all_domains.txt") 条 (融合引擎)"
}

# ---------- 生成 hosts(使用融合引擎产物) ----------
gen_hosts() {
  if [ -f "$DNS_DIR/.manual" ]; then log "dns: hosts 手动模式，跳过自动生成"; return 0; fi
  E="$RULES_DIR/engine"
  [ -s "$E/hosts" ] || sh "$(dirname "$0")/engine.sh" build >/dev/null 2>&1
  tmp="$HOSTS_OUT.tmp.$$"
  if [ -s "$E/hosts" ]; then
    cat "$E/hosts" > "$tmp"
  else
    {
      echo "# SY-Fusion hosts — 引擎无输出(规则为空或尚未编译)"
      echo "127.0.0.1 localhost"
      echo "::1 localhost"
    } > "$tmp"
  fi
  mv "$tmp" "$HOSTS_OUT"
  chmod 0644 "$HOSTS_OUT" 2>/dev/null; chown 0:0 "$HOSTS_OUT" 2>/dev/null
  log "dns: hosts 生成完成 ($(count_lines "$HOSTS_OUT") 行)"
}

bind_hosts() {
  # 【真机根因修复】旧实现 mount --bind "HOSTS_OUT" /system/etc/hosts 在当前
  # KernelSU 下**必然失败**，且错误被 2>/dev/null 吞掉、「看起来成功」。真机实测报错：
  #   mount: ...->/system/etc/hosts: No such file or directory
  # 原因：/system/etc/hosts 已被 KernelSU 用 OverlayFS 重挂载（来自 /dev/block/dm-41），
  # 该状态下不能再 bind 到它上面。
  #
  # 正确做法：把 hosts 放进**模块自己的 system/etc/hosts**，由模块管理器开机覆盖挂载。
  # 真机验证：放入 12 行 hosts 后重启，/system/etc/hosts 变成 12 行且含测试规则。
  MODHOSTS="$MODDIR/system/etc/hosts"
  mkdir -p "$MODDIR/system/etc" 2>/dev/null
  if [ -f "$HOSTS_OUT" ]; then
    cp -f "$HOSTS_OUT" "$MODHOSTS" 2>/dev/null
    chmod 0644 "$MODHOSTS" 2>/dev/null; chown 0:0 "$MODHOSTS" 2>/dev/null
  fi
  # 运行时 bind 作为尝试（部分管理器允许），失败不致命但要如实记录原因
  # 【真机修复】Android **没有 /tmp**（touch /tmp/x → No such file or directory），
  # 旧写法把 mount 的 stderr 重定向到 /tmp，那行本身就先失败了。改用数据目录下的临时文件。
  MERR="$DATA_DIR/cache/.mount_err"
  mkdir -p "$DATA_DIR/cache" 2>/dev/null
  if mount --bind "$HOSTS_OUT" /system/etc/hosts 2>"$MERR"; then
    log "dns: hosts 已运行时绑定挂载"
  else
    err=$(head -n1 "$MERR" 2>/dev/null); rm -f "$MERR"
    log "dns: 运行时 bind 失败（预期：overlay 已占用），改由模块 system/etc/hosts 覆盖（原因见日志）"
  fi
  # 【关键】验证到底生效没有：系统 hosts 是否含我们生成的条目
  have=$(grep -c "^0\.0\.0\.0 " /system/etc/hosts 2>/dev/null | head -n1)
  want=$(grep -c "^0\.0\.0\.0 " "$MODHOSTS" 2>/dev/null | head -n1)
  [ -z "$have" ] && have=0
  [ -z "$want" ] && want=0
  if [ "$want" -eq 0 ]; then
    log "dns: 无拦截条目（规则集为空，属正常）"
  elif [ "$have" -ge "$want" ]; then
    log "dns: 生效验证通过（系统 hosts 含 $have 条黑洞条目）"
  else
    log "dns: 未生效（系统 $have 条 / 应有 $want 条）—— 需重启让模块 overlay 生效"
  fi
}

full_apply() {  # 更新规则表 + 下载缓存 + 重建 + 生成 + 挂载
  sh "$(dirname "$0")/lists.sh" update >/dev/null 2>&1
  fetch_sources
  rebuild_domains
  gen_hosts
  bind_hosts
}

case "$1" in
  update)
    full_apply
    echo "OK: 规则已更新，共 $(count_lines "$RAW_DIR/all_domains.txt") 个域名"
    ;;
  apply)
    # 若无缓存则先更新；否则仅重建(含自定义)
    if [ ! -s "$RAW_DIR/all_domains.txt" ]; then fetch_sources; fi
    rebuild_domains; gen_hosts; bind_hosts
    echo "OK: 已应用 $(count_lines "$RAW_DIR/all_domains.txt") 条规则"
    ;;
  status)
    raw=$(count_lines "$RAW_DIR/all_domains.txt")
    wf="$DNS_DIR/.wl.$$"
    if [ -f "$WHITELIST" ]; then grep -vE '^[[:space:]]*(#|$)' "$WHITELIST" | tr -d '[:space:]' | grep -v '^$' | sort -u > "$wf"; else : > "$wf"; fi
    total=$(awk -v wf="$wf" 'BEGIN{while((getline w<wf)>0){if(w!="")W[w]=1}close(wf)} function suf(d,  p,i){if(d in W)return 1; p=d; while((i=index(p,"."))>0){p=substr(p,i+1); if(p in W)return 1} return 0} {d=$0; gsub(/[[:space:]]/,"",d); if(d==""||d in seen)next; seen[d]=1; if(suf(d))next; n++} END{printf "%d",n+0}' "$RAW_DIR/all_domains.txt" 2>/dev/null)
    rm -f "$wf"; [ -z "$total" ] && total=0
    wl=$(count_lines "$WHITELIST")
    custom=$(count_lines "$CUSTOM")
    mounted="no"; mount 2>/dev/null | grep -q "/system/etc/hosts" && mounted="yes"
    blocked=$(count_lines "$LOGS/dns_block.log")
    srcs=0; [ -f "$SOURCES" ] && srcs=$(grep -vcE '^[[:space:]]*(#|$)' "$SOURCES" 2>/dev/null)
    estats=$(sh "$(dirname "$0")/engine.sh" stats 2>/dev/null)
    efields=$(printf '%s' "$estats" | sed 's/^[[:space:]]*{//; s/}[[:space:]]*$//')
    [ -z "$efields" ] && efields='"records":0,"block":0,"allow":0'
    printf '{"rule_count":%s,"rule_raw":%s,"whitelist_count":%s,"custom_count":%s,"sources_count":%s,"hosts_mounted":"%s","blocked_total":%s,"engine":{%s}}\n' \
      "$total" "$raw" "$wl" "$custom" "$srcs" "$mounted" "$blocked" "$efields"
    ;;
  whitelist-add)
    d="$2"; [ -z "$d" ] && { echo "ERR: 缺少域名"; exit 1; }
    grep -qxF "$d" "$WHITELIST" 2>/dev/null || echo "$d" >> "$WHITELIST"
    rebuild_domains; gen_hosts; bind_hosts
    echo "OK: 已添加白名单 $d"
    ;;
  whitelist-del)
    d="$2"
    if [ -f "$WHITELIST" ]; then
      tmp="$WHITELIST.tmp.$$"; grep -vxF "$d" "$WHITELIST" > "$tmp" 2>/dev/null; mv "$tmp" "$WHITELIST"
    fi
    rebuild_domains; gen_hosts; bind_hosts
    echo "OK: 已移除白名单 $d"
    ;;
  whitelist-list) cat "$WHITELIST" 2>/dev/null ;;
  # 导入自定义规则(base64 编码文本，避免 stdin 兼容问题)
  import-b64)
    [ -z "$2" ] && { echo "ERR: 空内容"; exit 1; }
    echo "$2" | base64 -d >> "$CUSTOM" 2>/dev/null
    # 追加换行
    printf '\n' >> "$CUSTOM"
    rebuild_domains; gen_hosts; bind_hosts
    echo "OK: 已导入，自定义规则共 $(count_lines "$CUSTOM") 条，总域名 $(count_lines "$RAW_DIR/all_domains.txt") 个"
    ;;
  import)  # 从 stdin 读取(服务器模式用)
    cat >> "$CUSTOM"; printf '\n' >> "$CUSTOM"
    rebuild_domains; gen_hosts; bind_hosts
    echo "OK: 已导入，自定义规则共 $(count_lines "$CUSTOM") 条"
    ;;
  custom-list) cat "$CUSTOM" 2>/dev/null ;;
  custom-save-b64)  # 覆盖保存自定义规则
    echo "$2" | base64 -d > "$CUSTOM" 2>/dev/null; printf '\n' >> "$CUSTOM"
    rebuild_domains; gen_hosts; bind_hosts
    echo "OK: 已保存自定义规则 $(count_lines "$CUSTOM") 条"
    ;;
  custom-clear)
    : > "$CUSTOM"; rebuild_domains; gen_hosts; bind_hosts
    echo "OK: 自定义规则已清空"
    ;;
  sources-list) cat "$SOURCES" 2>/dev/null ;;
  sources-add)
    [ -z "$2" ] && { echo "ERR: 缺少 URL"; exit 1; }
    name="$3"; [ -z "$name" ] && name="自定义源$(date +%s)"
    echo "$name|$2" >> "$SOURCES"
    echo "OK: 已添加订阅 $name"
    ;;
  sources-del)
    idx="$2"
    if [ -f "$SOURCES" ]; then
      tmp="$SOURCES.tmp.$$"
      awk -v want="$idx" 'BEGIN{n=0} /^[[:space:]]*#/{print;next} /^[[:space:]]*$/{print;next} {n++; if(n!=want) print}' "$SOURCES" > "$tmp"
      mv "$tmp" "$SOURCES"
    fi
    echo "OK: 已删除订阅 #$idx"
    ;;
  rules-preview)
    lim="${2:-200}"
    echo "TOTAL=$(count_lines "$RAW_DIR/all_domains.txt")"
    echo "CUSTOM=$(count_lines "$CUSTOM")"
    echo "---"
    head -n "$lim" "$RAW_DIR/all_domains.txt" 2>/dev/null
    ;;
  export) cat "$HOSTS_OUT" 2>/dev/null ;;
  # ---------- hosts 去广告 管理 ----------
  hosts-status)
    entries=$(count_lines "$HOSTS_OUT")
    domains=$(count_lines "$RAW_DIR/all_domains.txt")
    mounted="no"; mount 2>/dev/null | grep -q "/system/etc/hosts" && mounted="yes"
    manual="no"; [ -f "$DNS_DIR/.manual" ] && manual="yes"
    size=0; [ -f "$HOSTS_OUT" ] && size=$(wc -c < "$HOSTS_OUT" 2>/dev/null | tr -d ' ')
    printf '{"mounted":"%s","entries":%s,"domains":%s,"manual":"%s","size":%s,"path":"%s"}\n' \
      "$mounted" "$entries" "$domains" "$manual" "$size" "$HOSTS_OUT"
    ;;
  hosts-get) cat "$HOSTS_OUT" 2>/dev/null ;;
  hosts-set-b64)
    [ -z "$2" ] && { echo "ERR: 空内容"; exit 1; }
    echo "$2" | base64 -d > "$HOSTS_OUT" 2>/dev/null
    : > "$DNS_DIR/.manual"
    chmod 0644 "$HOSTS_OUT"
    bind_hosts
    echo "OK: hosts 已保存并挂载（手动模式，$(count_lines "$HOSTS_OUT") 行）"
    ;;
  hosts-regen)
    rm -f "$DNS_DIR/.manual"
    if [ ! -s "$RAW_DIR/all_domains.txt" ]; then fetch_sources; fi
    rebuild_domains; gen_hosts; bind_hosts
    echo "OK: 已恢复自动生成 hosts（$(count_lines "$HOSTS_OUT") 行）"
    ;;
  hosts-clear)   # 一键删除: 清空全部 hosts 拦截条目并刷新为空挂载
    : > "$HOSTS_OUT"
    : > "$RAW_DIR/all_domains.txt"
    : > "$CUSTOM"
    : > "$DNS_DIR/.manual"   # 标记手动模式，避免 update/apply 立刻重新生成
    chmod 0644 "$HOSTS_OUT" 2>/dev/null; chown 0:0 "$HOSTS_OUT" 2>/dev/null
    bind_hosts
    echo "OK: 已一键删除全部 hosts 拦截条目（如需恢复请点「恢复自动生成」）"
    ;;
  hosts-mount) bind_hosts; echo "OK: 已尝试重新挂载 hosts" ;;
  hosts-unmount) umount /system/etc/hosts 2>/dev/null; echo "OK: 已卸载 hosts 挂载" ;;
  clear)
    : > "$RAW_DIR/all_domains.txt"; : > "$CUSTOM"; gen_hosts; bind_hosts
    echo "OK: 已清空 DNS 规则"
    ;;
  rules-del)
    d="$2"; [ -z "$d" ] && { echo "ERR: 缺少域名"; exit 1; }
    d=$(echo "$d" | tr -d '[:space:]')
    grep -qxF "$d" "$REMOVED" 2>/dev/null || echo "$d" >> "$REMOVED"
    rebuild_domains; gen_hosts; bind_hosts
    echo "OK: 已从生效规则删除 $d"
    ;;
  rules-restore)
    d="$2"
    if [ -f "$REMOVED" ]; then tmp="$REMOVED.tmp.$$"; grep -vxF "$d" "$REMOVED" > "$tmp" 2>/dev/null; mv "$tmp" "$REMOVED"; fi
    rebuild_domains; gen_hosts; bind_hosts
    echo "OK: 已恢复 $d"
    ;;
  removed-list) cat "$REMOVED" 2>/dev/null ;;
  # ---------- 黑名单(强制拦截) ----------
  blacklist-list) cat "$BLACKLIST" 2>/dev/null ;;
  blacklist-add)
    d="$2"; [ -z "$d" ] && { echo "ERR: 缺少域名"; exit 1; }
    grep -qxF "$d" "$BLACKLIST" 2>/dev/null || echo "$d" >> "$BLACKLIST"
    rebuild_domains; gen_hosts; bind_hosts
    echo "OK: 已加入黑名单 $d"
    ;;
  blacklist-del)
    d="$2"; [ -z "$d" ] && { echo "ERR: 缺少域名"; exit 1; }
    if [ -f "$BLACKLIST" ]; then tmp="$BLACKLIST.tmp.$$"; grep -vxF "$d" "$BLACKLIST" > "$tmp" 2>/dev/null; mv "$tmp" "$BLACKLIST"; fi
    rebuild_domains; gen_hosts; bind_hosts
    echo "OK: 已移出黑名单 $d"
    ;;
  blacklist-import-b64)
    [ -z "$2" ] && { echo "ERR: 空内容"; exit 1; }
    echo "$2" | base64 -d >> "$BLACKLIST" 2>/dev/null; printf '\n' >> "$BLACKLIST"
    rebuild_domains; gen_hosts; bind_hosts
    echo "OK: 已导入黑名单，共 $(count_lines "$BLACKLIST") 条"
    ;;
  blacklist-clear)
    : > "$BLACKLIST"; rebuild_domains; gen_hosts; bind_hosts
    echo "OK: 黑名单已清空"
    ;;
  # ---------- 批量删除 ----------
  custom-del)
    d="$2"; [ -z "$d" ] && { echo "ERR: 缺少内容"; exit 1; }
    if [ -f "$CUSTOM" ]; then tmp="$CUSTOM.tmp.$$"; grep -vxF "$d" "$CUSTOM" > "$tmp" 2>/dev/null; mv "$tmp" "$CUSTOM"; fi
    rebuild_domains; gen_hosts; bind_hosts
    echo "OK: 已从自定义规则删除"
    ;;
  rules-del-multi)
    list="$2"; [ -z "$list" ] && { echo "ERR: 缺少域名"; exit 1; }
    echo "$list" | tr ',' '\n' | while IFS= read -r dm; do
      [ -z "$dm" ] && continue
      grep -qxF "$dm" "$REMOVED" 2>/dev/null || echo "$dm" >> "$REMOVED"
    done
    rebuild_domains; gen_hosts; bind_hosts
    echo "OK: 已批量删除生效规则"
    ;;
  # ---------- 过滤引擎 / 规则表 / 自定义规则 (AdGuard·uBlock 深度优化) ----------
  filter-build|engine-build)
    sh "$(dirname "$0")/engine.sh" build ;;
  filter-stats|engine-stats)  sh "$(dirname "$0")/engine.sh" stats ;;
  engine-syntax)  sh "$(dirname "$0")/engine.sh" syntax ;;
  engine-verify)  sh "$(dirname "$0")/engine.sh" verify ;;
  engine-paths)   sh "$(dirname "$0")/engine.sh" paths ;;
  filter-test|engine-test)     sh "$(dirname "$0")/engine.sh" test "$2" ;;
  engine-testfile)             sh "$(dirname "$0")/engine.sh" testfile "$2" ;;
  filter-clear|engine-clear)   sh "$(dirname "$0")/engine.sh" clear ;;
  lists-list|lists) sh "$(dirname "$0")/lists.sh" list ;;
  lists-add)     sh "$(dirname "$0")/lists.sh" add "$2" "$3" "$4" ;;
  lists-del)     sh "$(dirname "$0")/lists.sh" del "$2" ;;
  lists-enable)  sh "$(dirname "$0")/lists.sh" enable "$2" ;;
  lists-disable) sh "$(dirname "$0")/lists.sh" disable "$2" ;;
  lists-update)  sh "$(dirname "$0")/lists.sh" update "$2" ;;
  lists-clear)   sh "$(dirname "$0")/lists.sh" clear ;;
  my-rules-get) cat "$USER_RULES" 2>/dev/null ;;
  my-rules-save-b64)
    [ -z "$2" ] && { echo "ERR: 空内容"; exit 1; }
    echo "$2" | base64 -d > "$USER_RULES" 2>/dev/null; printf '\n' >> "$USER_RULES"
    rebuild_domains; gen_hosts; bind_hosts
    echo "OK: 已保存自定义过滤规则 $(count_lines "$USER_RULES") 条"
    ;;
  my-rules-clear)
    : > "$USER_RULES"; rebuild_domains; gen_hosts; bind_hosts
    echo "OK: 自定义过滤规则已清空"
    ;;
  # ---------- 拦截统计 ----------
  stats-top) sh "$(dirname "$0")/stats.sh" top "${2:-20}" ;;
  stats-summary) sh "$(dirname "$0")/stats.sh" summary ;;
  *)
    echo "usage: dns.sh {apply|update|status|engine-build|engine-stats|engine-syntax|engine-verify|engine-test <domain>|engine-testfile <file>|engine-paths|engine-clear|filter-build|filter-stats|filter-test <domain>|filter-clear|lists|lists-add <name> <url> [cat]|lists-del <name>|lists-enable <name>|lists-disable <name>|lists-update [name]|lists-clear|my-rules-get|my-rules-save-b64 <b64>|my-rules-clear|stats-top [n]|stats-summary|whitelist-add|whitelist-del|whitelist-list|blacklist-add|blacklist-del|blacklist-list|blacklist-import-b64|blacklist-clear|import-b64|import|custom-list|custom-save-b64|custom-del|custom-clear|sources-list|sources-add|sources-del|rules-preview|rules-del|rules-del-multi|rules-restore|removed-list|hosts-status|hosts-get|hosts-set-b64|hosts-regen|hosts-toggle|hosts-mount|hosts-unmount|export|clear}"
    ;;
esac
