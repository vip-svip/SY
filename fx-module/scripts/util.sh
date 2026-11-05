#!/system/bin/sh
# PrivacyGuard 公共函数库
PG=${PG:-/data/adb/privacyguard}
CONF=${CONF:-$PG/settings.conf}
MODDIR_PID=""

# pg_get KEY [DEFAULT] — 读取开关值（0/1）
pg_get() {
  _key="$1"
  _v=$(grep -m1 "^$_key=" "$CONF" 2>/dev/null | cut -d= -f2-)
  [ -n "$_v" ] || _v="${2:-0}"
  # 旧版 ad_protection_master 已废弃；每个功能只由其自身开关控制。
  echo "$_v"
}

# pg_conf KEY — 读取 [conf:KEY] 段内容（原样输出，可含多行）
pg_conf() {
  _start=$(grep -n "^\[conf:$1\]" "$CONF" 2>/dev/null | head -1 | cut -d: -f1)
  [ -z "$_start" ] && return 0
  _end=$(awk -v s="$_start" 'NR>s && /^\[/ {print NR; exit}' "$CONF" 2>/dev/null)
  if [ -n "$_end" ]; then
    sed -n "$((_start+1)),$((_end-1))p" "$CONF"
  else
    sed -n "$((_start+1)),\$p" "$CONF"
  fi
}

# pg_list NAME — 读取 [list:NAME] 段（每行: 内容|备注|勾选）
pg_list() {
  # Importers may append another [list:NAME] section to settings.conf. Merge all
  # occurrences instead of silently reading only the first one, or imported rules,
  # script subscriptions and MITM hostnames will appear saved but never activate.
  [ -r "$CONF" ] || return 0
  awk -v target="[list:$1]" '
    NR == 1 { sub(/^\357\273\277/, "", $0) }
    $0 == target { inlist = 1; found = 1; next }
    /^\[/ { inlist = 0 }
    inlist { print }
  ' "$CONF" 2>/dev/null
}

# pg_enabled NAME — 列表条目是否勾选（第3字段=1；跳过 # 注释行与空行）
pg_list_enabled() { pg_list "$1" | grep -v '^[[:space:]]*#' | awk -F'|' '$3=="1" && $1!=""{print $1}'; }

# Resolve the currently selected FX proxy endpoint before allowing an external-VPN
# overlay. A generic route (for example 1.1.1.1) does NOT prove that the node server
# itself is routed through the outer tunnel; split routes may treat it differently.
pg_vpn_node_endpoint_host() {
  _pveh_raw=$(pg_get vpn_node "")
  [ -n "$_pveh_raw" ] || return 1
  _pveh_host=""
  case "$_pveh_raw" in
    vmess://*|vmess:*)
      _pveh_payload=$_pveh_raw
      case "$_pveh_payload" in vmess://*) _pveh_payload=${_pveh_payload#vmess://} ;; vmess:*) _pveh_payload=${_pveh_payload#vmess:} ;; esac
      _pveh_payload=${_pveh_payload%%\#*}
      _pveh_payload=${_pveh_payload%%\?*}
      _pveh_json=$(printf '%s' "$_pveh_payload" | base64 -d 2>/dev/null || true)
      _pveh_host=$(printf '%s' "$_pveh_json" | sed -n 's/.*"add"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
      ;;
  esac
  if [ -z "$_pveh_host" ] && command -v vpn_node_hostport >/dev/null 2>&1; then
    _pveh_hp=$(vpn_node_hostport "$_pveh_raw" 2>/dev/null || true)
    case "$_pveh_hp" in
      \[*\]:*) _pveh_host=$(printf '%s' "$_pveh_hp" | sed -n 's/^\[\([^]]*\)\]:[0-9][0-9]*$/\1/p') ;;
      *:*) _pveh_host=${_pveh_hp%:*} ;;
    esac
  fi
  if [ -z "$_pveh_host" ]; then
    _pveh_s=$(printf '%s' "$_pveh_raw" | sed 's/#.*$//;s/?[^?]*$//')
    case "$_pveh_s" in *://*) _pveh_s=${_pveh_s#*://} ;; esac
    _pveh_s=${_pveh_s##*@}
    _pveh_s=${_pveh_s%%/*}
    case "$_pveh_s" in
      \[*\]:*) _pveh_host=$(printf '%s' "$_pveh_s" | sed -n 's/^\[\([^]]*\)\]:[0-9][0-9]*$/\1/p') ;;
      *)
        _pveh_port=${_pveh_s##*:}
        case "$_pveh_port" in ''|*[!0-9]*) return 1 ;; esac
        _pveh_host=${_pveh_s%:*}
        case "$_pveh_host" in
          vmess:*|vless:*|trojan:*|ss:*|hysteria:*|hysteria2:*|tuic:*|anytls:*|socks5:*|socks5h:*) _pveh_host=${_pveh_host#*:} ;;
        esac
        ;;
    esac
  fi
  case "$_pveh_host" in \[*\]) _pveh_host=${_pveh_host#\[}; _pveh_host=${_pveh_host%\]} ;; esac
  [ -n "$_pveh_host" ] || return 1
  printf '%s' "$_pveh_host" | LC_ALL=C grep -Eq '^[A-Za-z0-9._:-]+$' || return 1
  printf '%s\n' "$_pveh_host"
}

# Return one bounded, validated IP address for the selected node. Literals are
# never re-resolved; hostnames use the system resolver only when an explicit tool
# is available. If resolution is ambiguous/unavailable, the overlay guard fails
# closed rather than substituting a public test IP and claiming the node route is safe.
pg_vpn_node_endpoint_ip() {
  _pvei_host=$(pg_vpn_node_endpoint_host) || return 1
  case "$_pvei_host" in
    *:*) printf '%s\n' "$_pvei_host"; return 0 ;;
    *[!0-9.]* ) ;;
    *)
      printf '%s' "$_pvei_host" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' && { printf '%s\n' "$_pvei_host"; return 0; }
      ;;
  esac
  _pvei_ips=""
  if command -v getent >/dev/null 2>&1; then
    _pvei_ips=$(getent ahosts "$_pvei_host" 2>/dev/null | awk '{print $1}' | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$|^[0-9A-Fa-f]*:[0-9A-Fa-f:]+$' | head -4)
  fi
  if [ -z "$_pvei_ips" ] && command -v nslookup >/dev/null 2>&1; then
    _pvei_ips=$(nslookup "$_pvei_host" 2>/dev/null | awk '
      tolower($1)=="name:" {answer=1; next}
      answer && /Address/ {for(i=1;i<=NF;i++) if($i ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/ || $i ~ /^[0-9A-Fa-f]*:[0-9A-Fa-f:]+$/){print $i; break}}
    ' | awk '!seen[$0]++' | head -4)
  fi
  [ -n "$_pvei_ips" ] || return 1
  printf '%s\n' "$_pvei_ips" | awk '!seen[$0]++' | head -4
}

# pg_set KEY VALUE — 原子改写顶层配置；写入失败必须返回非零。
# 旧实现无论 awk/mv 是否失败都返回 0，订阅事务会因此误以为 vpn_node 已保存，
# 进而跳过回滚，造成“节点列表已更新、选择值未更新”的半提交状态。
pg_set() {
  _k="$1"; _val="$2"
  [ -f "$CONF" ] || return 1
  case "$_k" in ''|*[!A-Za-z0-9_.-]*) return 1 ;; esac
  case "$_val" in *'
'*|*'
'*) return 1 ;; esac
  _set_tmp="$CONF.tmp.$$"
  rm -f "$_set_tmp" 2>/dev/null || :
  if grep -q "^$_k=" "$CONF" 2>/dev/null; then
    if ! awk -v k="$_k" -v v="$_val" '
      BEGIN { done = 0 }
      !done && index($0, k "=") == 1 { print k "=" v; done = 1; next }
      { print }
      END { if (!done) exit 3 }
    ' "$CONF" > "$_set_tmp" 2>/dev/null; then
      rm -f "$_set_tmp" 2>/dev/null || :
      return 1
    fi
  else
    # 无该键：插到第一个段标记之前（保持在开关区），没有段头则安全追加到候选文件。
    _first=$(grep -n '^\[' "$CONF" 2>/dev/null | head -1 | cut -d: -f1)
    if [ -n "$_first" ]; then
      if ! awk -v n="$_first" -v line="$_k=$_val" 'NR==n{print line} {print}' "$CONF" > "$_set_tmp" 2>/dev/null; then
        rm -f "$_set_tmp" 2>/dev/null || :
        return 1
      fi
    else
      if ! { cat "$CONF" && printf '%s\n' "$_k=$_val"; } > "$_set_tmp"; then
        rm -f "$_set_tmp" 2>/dev/null || :
        return 1
      fi
    fi
  fi
  [ -s "$_set_tmp" ] || { rm -f "$_set_tmp" 2>/dev/null || :; return 1; }
  chmod 600 "$_set_tmp" 2>/dev/null || { rm -f "$_set_tmp" 2>/dev/null || :; return 1; }
  if ! mv "$_set_tmp" "$CONF" 2>/dev/null; then
    rm -f "$_set_tmp" 2>/dev/null || :
    return 1
  fi
  return 0
}

# pg_log MSG — 追加日志
pg_log() {
  (umask 077; echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$PG/apply.log") || return 1
  chmod 600 "$PG/apply.log" 2>/dev/null || :
  return 0
}

# ---------- 错误处理框架 ----------
# PG_ERRS: 累计错误数; PG_LOGF: 错误明细文件(重启/重跑前清空)
PG_ERRS=0
PG_LOGF="$PG/apply.errors"
pg_err_reset() {
  PG_ERRS=0
  (umask 077; : > "$PG_LOGF") 2>/dev/null || :
  chmod 600 "$PG_LOGF" 2>/dev/null || :
}

# pg_fail STAGE MESSAGE — 记录一处失败（不退出，继续后续步骤）
pg_fail() {
  PG_ERRS=$((PG_ERRS+1))
  (umask 077
   echo "[$(date '+%m-%d %H:%M:%S')] FAIL($1): $2" >> "$PG/apply.log"
   echo "$1: $2" >> "$PG_LOGF" 2>/dev/null) || :
  chmod 600 "$PG/apply.log" "$PG_LOGF" 2>/dev/null || :
}


# Return the ownership state of the /system/etc/hosts mount without parsing paths as regex.
# Android mount output for a bind typically prints: "$PG/hosts on /system/etc/hosts ...".
# Do not mistake any other mount at that target for ours; overwriting a third-party mount
# can silently disable another module's hosts rules.
pg_hosts_mount_state_from_text() {
  _phms_src="$1"; _phms_target="$2"; _phms_text="$3"
  printf '%s\n' "$_phms_text" | awk -v src="$_phms_src" -v tgt="$_phms_target" '
    index($0, " on " tgt " ") {
      if (index($0, src " on " tgt " ")) owned=1
      else foreign=1
    }
    END { if (owned) print "owned"; else if (foreign) print "foreign"; else print "none" }
  '
}

pg_hosts_mount_state() {
  _phms_text=$(mount 2>/dev/null)
  pg_hosts_mount_state_from_text "$PG/hosts" /system/etc/hosts "$_phms_text"
}

# pg_commit_hosts_candidate CANDIDATE — transactional replacement of $PG/hosts.
# The previous inode is renamed to a same-filesystem recovery file before commit;
# this avoids needing a second full-size copy and lets us roll back if the new file
# is truncated or a write fails after the original was moved out of the way.
# The caller's normal post-build flow re-binds the final $PG/hosts after this returns.
pg_commit_hosts_candidate() {
  _hc_candidate="$1"
  [ -f "$_hc_candidate" ] && [ -r "$_hc_candidate" ] || {
    pg_fail hosts "候选 hosts 文件不存在或不可读；保留上一份 hosts"
    return 1
  }
  _hc_want=$(wc -l < "$_hc_candidate" 2>/dev/null | tr -d ' ')
  case "$_hc_want" in ''|*[!0-9]*)
    pg_fail hosts "无法校验候选 hosts 行数；保留上一份 hosts"
    return 1 ;;
  esac

  _hc_was_mounted=0
  _hc_mount_state=$(pg_hosts_mount_state 2>/dev/null)
  case "$_hc_mount_state" in
    owned)
      _hc_was_mounted=1
      umount /system/etc/hosts 2>/dev/null || umount -l /system/etc/hosts 2>/dev/null || true
      if [ "$(pg_hosts_mount_state 2>/dev/null)" = owned ]; then
        pg_fail hosts "无法卸载 /system/etc/hosts bind mount；保留旧 hosts，跳过替换（本模块挂载）"
        return 1
      fi
      ;;
    foreign)
      pg_fail hosts " /system/etc/hosts 被其他模块挂载；拒绝替换并保留现有挂载"
      return 1
      ;;
  esac

  _hc_backup="$PG/cache/hosts.precommit.$$"
  if [ -e "$_hc_backup" ]; then
    pg_fail hosts "发现未清理的 hosts 恢复文件 $_hc_backup；为避免覆盖恢复证据，跳过替换"
    return 1
  fi
  _hc_had_old=0
  if [ -f "$PG/hosts" ]; then
    if mv "$PG/hosts" "$_hc_backup" 2>>"$PG/apply.log"; then
      _hc_had_old=1
    else
      pg_fail hosts "无法保存上一份 hosts 到恢复文件；跳过替换"
      return 1
    fi
  fi

  _hc_written=0
  if mv "$_hc_candidate" "$PG/hosts" 2>>"$PG/apply.log"; then
    _hc_written=1
  elif cat "$_hc_candidate" > "$PG/hosts" 2>>"$PG/apply.log"; then
    _hc_written=1
    rm -f "$_hc_candidate" 2>/dev/null || true
  fi

  if [ "$_hc_written" = 1 ]; then
    _hc_got=$(wc -l < "$PG/hosts" 2>/dev/null | tr -d ' ')
    case "$_hc_got" in ''|*[!0-9]*) _hc_got=-1 ;; esac
    [ "$_hc_got" -eq "$_hc_want" ] || _hc_written=0
  fi

  if [ "$_hc_written" != 1 ]; then
    # Remove any partial/corrupted candidate first, then put the original inode
    # back. If rename fails, copy as the last-resort recovery while retaining the
    # recovery file until the copy can be verified.
    rm -f "$PG/hosts" 2>/dev/null || true
    if [ "$_hc_had_old" = 1 ]; then
      if ! mv "$_hc_backup" "$PG/hosts" 2>>"$PG/apply.log"; then
        if cp -p "$_hc_backup" "$PG/hosts.rollback.$$" 2>>"$PG/apply.log" &&
           mv -f "$PG/hosts.rollback.$$" "$PG/hosts" 2>>"$PG/apply.log"; then
          _hc_restore_ok=1
        else
          rm -f "$PG/hosts.rollback.$$" 2>/dev/null || true
          _hc_restore_ok=0
        fi
      else
        _hc_restore_ok=1
      fi
      if [ "${_hc_restore_ok:-0}" = 1 ]; then
        # In the copy fallback, keep the recovery file if unlinking fails; it is
        # diagnostic evidence, not an active input.
        rm -f "$_hc_backup" 2>/dev/null || true
      else
        pg_fail hosts "严重：新 hosts 提交失败且无法自动恢复；旧文件证据保留在 $_hc_backup"
      fi
    fi
    pg_fail hosts "hosts 提交不完整（期望 $_hc_want 行）；已回滚到上一份 hosts（若存在）"
    return 1
  fi

  chmod 644 "$PG/hosts" 2>/dev/null || true
  if [ "$_hc_had_old" = 1 ]; then
    rm -f "$_hc_backup" 2>/dev/null || pg_log "hosts: 新文件已提交，但旧版本恢复文件清理失败：$_hc_backup"
  fi
  pg_log "hosts: transactional replacement committed lines=$_hc_want (previous mounted=$_hc_was_mounted)"
  return 0
}

# pg_step STAGE CMD... — 运行命令，失败记录（返回码透传给调用者）
#   用法: pg_step hosts "mkdir -p $PG/cache"
pg_step() {
  _stage="$1"; shift
  if "$@" >/dev/null 2>>"$PG/apply.log"; then
    return 0
  else
    _rc=$?
    pg_fail "$_stage" "命令失败(rc=$_rc): $*"
    return $_rc
  fi
}

# pg_summary EXIT_LABEL — 收尾：数 apply.errors 行数（子 shell 里的 pg_fail 写文件
#   但 PG_ERRS 变量不回传父进程，因此以文件为准），有错返回错误数
pg_rand() {
  # POSIX sh / busybox ash / mksh 都没有 $RANDOM。
  # 之前直接写 $RANDOM 会得到空串 → $(( )) 里按 0 计算，
  # 导致「随机偏移/随机延迟」实际恒为固定值（等于功能没生效）。
  # 用 eval 间接取：直接写 ${RANDOM:-} 会让 shellcheck 报 SC3028；
  # bash/dash(带RANDOM)/mksh 有该变量时正常使用，否则返回空串。
  _pr_r=$(eval 'printf "%s" "${RANDOM:-}"' 2>/dev/null)
  case "$_pr_r" in ''|*[!0-9]*) ;; *) printf '%s' "$_pr_r"; return 0 ;; esac
  if [ -r /dev/urandom ]; then
    _pr=$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d ' \n')
    case "$_pr" in ''|*[!0-9]*) ;; *) printf '%s' "$_pr"; return 0 ;; esac
  fi
  _pr=$(date +%S 2>/dev/null); case "$_pr" in ''|*[!0-9]*) _pr=0 ;; esac
  printf '%s' "$_pr"
}

pg_summary() {
  _n=0
  # 注意：grep -c 在「无匹配」时输出 0 但退出码为 1，
  # 不能用 `|| echo 0` 兜底（会得到两行 "0\n0" → Illegal number）。
  if [ -f "$PG_LOGF" ]; then
    _n=$(grep -c . "$PG_LOGF" 2>/dev/null)
    case "$_n" in ''|*[!0-9]*) _n=0 ;; esac
  fi
  if [ "$_n" -gt 0 ]; then
    pg_log "=== $1: 完成但有 $_n 处失败，详见 apply.log / apply.errors ==="
    return "$_n"
  fi
  pg_log "=== $1: 全部成功 ==="
  return 0
}

# pg_have CMD — 命令存在
pg_have() { command -v "$1" >/dev/null 2>&1; }

# 找可用的下载器：curl 或 wget（失败返回非0，调用方负责 pg_fail 记录）
pg_fetch() {
  # $1=URL $2=输出文件
  # --connect-timeout 必须设：只给 --max-time 时，DNS 卡住/黑洞路由会耗满整个时限，
  # WebUI 侧体感就是「点一下卡死十几秒」（实测 pgExec sync 形态会冻住主线程）。
  if pg_have curl; then
    curl -fsSL --connect-timeout 6 --max-time 15 -o "$2" "$1" 2>>"$PG/apply.log"
  elif pg_have wget; then
    wget -q -T 15 -O "$2" "$1" 2>>"$PG/apply.log"
  else
    return 1
  fi
}

# 带硬时限执行命令：Android toybox 有 timeout 就用它，没有就直接跑。
# 用途：拉起订阅/下载类子命令，保证调用方一定能在有限时间内拿到退出码。
pg_timeout_run() {
  _ptr_s=$1; shift
  if pg_have timeout; then
    timeout "$_ptr_s" "$@"
  else
    "$@"
  fi
}

# Normalize all FX source forms at one shared boundary so hosts, firewall and VPN
# consumers receive the same action semantics. Actionless deny-list rows default to
# REJECT; explicit DIRECT/PASS remain explicit and must never be turned into blocks.
pg_fx_normalize_stream() {
  awk '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    function deny_type(t) {
      return t=="DOMAIN" || t=="DOMAIN-SUFFIX" || t=="DOMAIN-KEYWORD" || t=="IP-CIDR" || t=="IP-CIDR6" || t=="PACKAGE-NAME" || t=="PROCESS-NAME"
    }
    function process_line(line, n,a,i,type,last,normalized,hosts,hn,j,d) {
      line=trim(line); sub(/\r$/, "", line)
      if (line=="" || line ~ /^[#;]/ || line ~ /^!/) return
      if (line ~ /^(0\.0\.0\.0|127\.0\.0\.1|::1)[[:space:]]+/) {
        sub(/^[^[:space:]]+[[:space:]]+/, "", line)
        hn=split(line,hosts,/[[:space:]]+/)
        for(j=1;j<=hn;j++) {
          d=tolower(hosts[j])
          if (d ~ /^#/ ) break
          if (d ~ /^[A-Za-z0-9.-]+\.[A-Za-z0-9.-]+$/ && d !~ /\.\.|^\.|\.$/) print "DOMAIN," d ",REJECT"
        }
        return
      }
      if (line ~ /^\|\|[A-Za-z0-9.-]+\^/) {
        d=line; sub(/^\|\|/, "", d); sub(/\^.*$/, "", d)
        if (d ~ /\./) print "DOMAIN-SUFFIX," tolower(d) ",REJECT"
        return
      }
      if (line ~ /^@@\|\|[A-Za-z0-9.-]+\^/) return
      n=split(line,a,",")
      if (n>=2) {
        for(i=1;i<=n;i++) a[i]=trim(a[i])
        type=toupper(a[1])
        if(type=="HOST") type="DOMAIN"
        if(type=="HOST-SUFFIX") type="DOMAIN-SUFFIX"
        a[1]=type
        if (deny_type(type)) {
          if (a[2]=="") return
          last=toupper(a[n])
          if (n==3 && (last=="NO-RESOLVE" || last=="SRC" || last=="EXTENDED" || last=="NO-DROP")) {
            a[4]=a[3]; a[3]="REJECT"; n=4
          } else if (n<3) { a[3]="REJECT"; n=3 }
          else if (a[3]=="") a[3]="REJECT"
          if (type ~ /^DOMAIN/) a[2]=tolower(a[2])
        }
        normalized=a[1]
        for(i=2;i<=n;i++) normalized=normalized "," a[i]
        print normalized
        return
      }
      if (line ~ /^[A-Za-z0-9.-]+\.[A-Za-z0-9.-]+$/ && line !~ /\.\.|^\.|\.$/) print "DOMAIN-SUFFIX," tolower(line) ",REJECT"
    }
    {
      line=$0
      # Old config stored multiple rules in a single literal \\n field; expand first,
      # then normalize each row independently to avoid leaking one row into another.
      gsub(/\\n/, "\n", line)
      rows=split(line,parts,"\n")
      for(i=1;i<=rows;i++) process_line(parts[i])
    }
  '
}

# pg_fx_expand — 展开 [list:fx] 的订阅、内置源和本地行。All source types pass through
# the same normalizer so DIRECT/PASS and `no-resolve` modifier semantics stay consistent.
pg_fx_expand() {
  mkdir -p "$PG/cache"
  pg_list_enabled fx | while IFS= read -r line; do
    case "$line" in
      http://*|https://*)
        _fx_url="$line"
        _fx_key=$(printf '%s' "$_fx_url" | cksum | awk '{print $1}')
        _fx_cache="$PG/cache/fx_$_fx_key"
        if pg_fetch "$_fx_url" "$_fx_cache.new" && [ -s "$_fx_cache.new" ]; then
          if mv -f "$_fx_cache.new" "$_fx_cache"; then :; else rm -f "$_fx_cache.new"; fi
        else
          rm -f "$_fx_cache.new"
          if [ -s "$_fx_cache" ]; then
            pg_log "fx: fetch failed, using cached content for [source URL redacted]"
          else
            pg_log "fx: fetch failed, no cache, skip [source URL redacted]"
            continue
          fi
        fi
        pg_fx_normalize_stream < "$_fx_cache"
        ;;
      fxfile://*)
        _fx_id=${line#fxfile://}
        # WebUI edits create a user-owned override; otherwise use the bundled source.
        case "$_fx_id" in ''|*[!A-Za-z0-9_.-]*) pg_log "fx: invalid bundled source id skipped"; continue ;; esac
        _fx_b="$PG/fxrules-user/$_fx_id.txt"
        [ -r "$_fx_b" ] || _fx_b="$MODDIR/fxrules/$_fx_id.txt"
        if [ -r "$_fx_b" ]; then
          pg_fx_normalize_stream < "$_fx_b"
        else
          pg_log "fx: builtin fx rule missing: fxrules/$_fx_id.txt"
        fi
        ;;
      *)
        printf '%s\n' "$line" | pg_fx_normalize_stream
        ;;
    esac
  done
}

# Restore the first-install OEM hosts snapshot when the live target is hidden by a
# module bind mount. Refuse snapshots bearing our generated markers to avoid recursing
# a generated list into the baseline. Writes are atomic so an interrupted boot cannot
# leave a truncated cache file.
pg_restore_system_hosts_base_from_backup() {
  _fx_base="$PG/cache/system-hosts.base"
  _fx_backup="$PG/backup/hosts.orig"
  [ -s "$_fx_backup" ] || return 1
  if grep -qE '^(# PrivacyGuard hosts|# FX-only hosts)' "$_fx_backup" 2>/dev/null; then return 1; fi
  mkdir -p "$PG/cache" 2>/dev/null || return 1
  _fx_base_tmp="$_fx_base.$$"
  if cp -p "$_fx_backup" "$_fx_base_tmp" 2>/dev/null && [ -s "$_fx_base_tmp" ] && mv -f "$_fx_base_tmp" "$_fx_base" 2>/dev/null; then
    chmod 600 "$_fx_base" 2>/dev/null || true
    pg_log 'fx: restored original system hosts baseline from first-install backup' 2>/dev/null || true
    return 0
  fi
  rm -f "$_fx_base_tmp" 2>/dev/null || true
  return 1
}

# Save the real pre-bind system hosts once when it is safely readable. When FX is
# enabled without the general hosts engine, the FX-only overlay still needs a stable
# localhost/system baseline. Never copy our own generated overlay as the baseline.
pg_capture_system_hosts_base() {
  _fx_base="$PG/cache/system-hosts.base"
  [ -s "$_fx_base" ] && return 0
  mkdir -p "$PG/cache" 2>/dev/null || return 1
  _fx_hmount=$(pg_hosts_mount_state 2>/dev/null)
  case "$_fx_hmount" in
    owned|foreign)
      # The live target is not safe to snapshot. Recover the known first-install copy
      # if available; if not, keep the caller's conservative template fallback.
      pg_restore_system_hosts_base_from_backup && return 0
      return 0
      ;;
  esac
  if [ -r /system/etc/hosts ] && ! grep -qE '^(# PrivacyGuard hosts|# FX-only hosts)' /system/etc/hosts 2>/dev/null; then
    _fx_base_tmp="$_fx_base.$$"
    if cp -p /system/etc/hosts "$_fx_base_tmp" 2>/dev/null && [ -s "$_fx_base_tmp" ] && mv -f "$_fx_base_tmp" "$_fx_base" 2>/dev/null; then
      chmod 600 "$_fx_base" 2>/dev/null || true
      pg_log 'fx: saved original system hosts baseline before overlay' 2>/dev/null || true
      return 0
    fi
    rm -f "$_fx_base_tmp" 2>/dev/null || true
  fi
  pg_restore_system_hosts_base_from_backup && return 0
  return 1
}

# Build an FX-only system hosts overlay when fx=1 but hosts_block=0. This prevents the
# UI from claiming FX is active while DOMAIN rules are discarded with the full hosts
# engine disabled. It deliberately excludes [list:rule], [list:block], telemetry and
# other privacy lists; local/hosts remains a separate user-owned file.
pg_build_fx_hosts() {
  mkdir -p "$PG/cache" "$PG/local" 2>/dev/null || return 1
  pg_capture_system_hosts_base 2>/dev/null || true
  _fx_host_tmp="$PG/cache/hosts.fx-candidate.$$"
  _fx_raw="$PG/cache/hosts.fx-rules.$$"
  : > "$_fx_host_tmp" || return 1
  {
    printf '# FX-only hosts overlay (generated %s)\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    if [ -s "$PG/cache/system-hosts.base" ]; then
      cat "$PG/cache/system-hosts.base"
    elif [ -r "$MODDIR/system/etc/hosts" ]; then
      # Safe fallback for upgrades where a previous module bind mount hides the
      # original OEM file; the shipped template contains only localhost defaults.
      awk '/^[[:space:]]*($|#)/ {next} {print}' "$MODDIR/system/etc/hosts"
    else
      printf '127.0.0.1 localhost\n::1 localhost ip6-localhost ip6-loopback\n'
    fi
  } >> "$_fx_host_tmp" || { rm -f "$_fx_host_tmp"; return 1; }

  # Keep local hosts independent from subscriptions. Use the same bounded parser as
  # the full hosts build: active host mappings stay explicit; bare domains map to 0.0.0.0.
  if [ -f "$PG/local/hosts" ]; then
    awk '{ sub(/\r$/, "") } NR==1 { sub(/^\357\273\277/, "") }
      /^[[:space:]]*#/ || /^[[:space:]]*$/ {next}
      {gsub(/[[:space:]]+/, " "); sub(/^ /, ""); sub(/ $/, "")
       if (NF >= 2 && $1 ~ /^[0-9.]+$/) {print; next}
       if (NF >= 2 && index($1, ":") > 0 && $1 ~ /^[0-9A-Fa-f:.]+$/) {print; next}
       if (NF==1 && $1 ~ /^[0-9.]+$/) next
       if (NF==1 && index($1, ":") > 0 && $1 ~ /^[0-9A-Fa-f:.]+$/) next
       d=$1; sub(/[\/:].*$/, "", d); if (d ~ /^[A-Za-z0-9.-]+$/) print "0.0.0.0 " d
      }' "$PG/local/hosts" >> "$_fx_host_tmp" 2>/dev/null || { rm -f "$_fx_host_tmp"; pg_fail fx 'FX-only hosts: local hosts parse failed'; return 1; }
  fi

  if ! pg_fx_expand > "$_fx_raw" 2>>"$PG/apply.log"; then
    rm -f "$_fx_host_tmp" "$_fx_raw" 2>/dev/null || true
    pg_fail fx 'FX-only hosts: rule expansion failed; previous hosts retained'
    return 1
  fi
  _fx_suffix_n=$(awk -F',' '$1=="DOMAIN-SUFFIX" {n++} END {print n+0}' "$_fx_raw" 2>/dev/null)
  _fx_keyword_n=$(awk -F',' '$1=="DOMAIN-KEYWORD" {n++} END {print n+0}' "$_fx_raw" 2>/dev/null)
  _fx_process_n=$(awk -F',' '$1=="PROCESS-NAME" {n++} END {print n+0}' "$_fx_raw" 2>/dev/null)
  _fx_domains=$(awk -F',' '
    function valid_domain(d,n,a,i){
      if (length(d)<1 || length(d)>253 || d !~ /^[A-Za-z0-9.-]+$/ || d ~ /[.][.]|^[.]|[.]$/) return 0
      n=split(d,a,".")
      for(i=1;i<=n;i++) if(length(a[i])<1 || length(a[i])>63 || a[i] !~ /^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$/) return 0
      return 1
    }
    $1=="DOMAIN" || $1=="DOMAIN-SUFFIX" {
      action=toupper($3); if (action!="" && action!="REJECT" && action!="BLOCK" && action!="DROP" && action!="DENY" && action!="REJECT-DROP") next
      d=tolower($2); sub(/^[[:space:]]+|[[:space:]]+$/, "", d)
      if(valid_domain(d) && !seen[d]++) print "0.0.0.0 " d
    }
  ' "$_fx_raw" 2>/dev/null)
  if [ -n "$_fx_domains" ]; then printf '%s\n' "$_fx_domains" >> "$_fx_host_tmp" || { rm -f "$_fx_host_tmp" "$_fx_raw"; return 1; }; fi
  _fx_out="$PG/cache/hosts.fx-dedup.$$"
  if ! awk '!seen[$0]++' "$_fx_host_tmp" > "$_fx_out" 2>/dev/null; then
    rm -f "$_fx_host_tmp" "$_fx_raw" "$_fx_out" 2>/dev/null || true
    pg_fail fx 'FX-only hosts: de-dup failed; previous hosts retained'
    return 1
  fi
  rm -f "$_fx_host_tmp" "$_fx_raw" 2>/dev/null || true
  _fx_lines=$(wc -l < "$_fx_out" 2>/dev/null | tr -d ' '); _fx_bytes=$(wc -c < "$_fx_out" 2>/dev/null | tr -d ' ')
  case "$_fx_lines:$_fx_bytes" in *[!0-9:]*|'':*) rm -f "$_fx_out"; return 1 ;; esac
  if [ "$_fx_lines" -gt 300000 ] || [ "$_fx_bytes" -gt 50331648 ]; then
    rm -f "$_fx_out" 2>/dev/null || true
    pg_fail fx 'FX-only hosts: candidate exceeds safe size limits; previous hosts retained'
    return 1
  fi
  if ! pg_commit_hosts_candidate "$_fx_out"; then rm -f "$_fx_out" 2>/dev/null || true; return 1; fi
  pg_log "fx: FX-only hosts committed; lines=$_fx_lines bytes=$_fx_bytes; full hosts_block remains disabled"
  if [ "${_fx_suffix_n:-0}" -gt 0 ] && [ "$(pg_get vpn_mode direct)" = "direct" ]; then
    pg_log "fx: DIRECT hosts mode maps suffix roots and explicitly listed hostnames only; wildcard descendant matching requires the VPN route engine"
  fi
  if [ "${_fx_keyword_n:-0}" -gt 0 ] && [ "$(pg_get vpn_mode direct)" = "direct" ]; then
    pg_log "fx: DIRECT hosts mode cannot enforce DOMAIN-KEYWORD rules; these require hostname-aware VPN routing"
  fi
  if [ "${_fx_process_n:-0}" -gt 0 ]; then
    pg_log "fx: PROCESS-NAME rules are parsed but are not reliable under the current REDIRECT ingress (process lookup cannot reliably match the original destination); do not count them as enforced"
  fi
  return 0
}

# pg_migrate_lists — v1.10.8 升级迁移（幂等）
# 老用户的 settings.conf 是 v1.10.7 及更早生成的：没有 [list:hosts_local] 段，
# 也没有 new builtin:// / fxfile:// 条目。直接升级会让「内置规则集 / 内置 FX」在
# WebUI 里完全不出现（列表读的是 settings.conf，不是 default.conf）。
# 这里只补缺失项：不动用户已有行、不覆盖用户改名/启停状态，重复执行无副作用。
# 调用点：customize.sh（安装时）、apply.sh（每次 apply / 开机 service.sh 触发）。
pg_migrate_lists() {
  [ -f "$CONF" ] || return 0
  mkdir -p "$PG/cache" 2>/dev/null || true

  # 1) [list:hosts_local]（本地 hosts 分区）缺失则追加到文件末尾
  if ! grep -q '^\[list:hosts_local\]' "$CONF" 2>/dev/null; then
    {
      printf '\n[list:hosts_local]\n'
      printf '# 本地 hosts（v1.10.8 新增）：本机手写、不经网络，改完「应用」立即生效\n'
      printf '# 行格式：内容|备注|1启用（支持 0.0.0.0 域名 / 127.0.0.1 域名 / 裸域名）\n'
      printf '# 注意：本分区不支持整段删除（只能逐条删改）\n'
    } >> "$CONF" 2>/dev/null
    pg_log "migrate: 已补 [list:hosts_local] 段" 2>/dev/null || true
  fi

  # Migrate legacy [list:hosts_local] entries into the canonical no-extension
  # $PG/local/hosts file exactly once. Active entries stay active; disabled entries
  # are preserved as comments so they cannot silently begin blocking traffic.
  _mh_marker="$PG/cache/hosts-local-list-migrated-v1"
  if [ ! -f "$_mh_marker" ]; then
    _mh_ok=1
    mkdir -p "$PG/local" "$PG/cache" 2>/dev/null || _mh_ok=0
    _mh_tmp="$PG/cache/hosts-local-migrate.$$.tmp"
    _mh_new="$PG/cache/hosts-local-merged.$$.tmp"
    if [ "$_mh_ok" = 1 ] && : > "$_mh_tmp" 2>/dev/null; then
      pg_list hosts_local 2>/dev/null | awk -F'|' '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        {
          value=$1; status=$3
          sub(/^[[:space:]]+/, "", value); sub(/[[:space:]]+$/, "", value)
          if (value == "") next
          if (status == "1") print value
          else print "# disabled legacy hosts entry: " value
        }
      ' > "$_mh_tmp" || _mh_ok=0
    else
      _mh_ok=0
    fi
    if [ "$_mh_ok" = 1 ] && [ -s "$_mh_tmp" ]; then
      [ -f "$PG/local/hosts" ] || : > "$PG/local/hosts" 2>/dev/null || _mh_ok=0
      # Keep the current local file first and append only lines not already present.
      if [ "$_mh_ok" = 1 ]; then
        cat "$PG/local/hosts" "$_mh_tmp" 2>/dev/null | awk '!seen[$0]++' > "$_mh_new" || _mh_ok=0
      fi
      # A failed backup is a failed migration: do not risk merging over the only
      # copy of the user's existing local hosts file.
      if [ "$_mh_ok" = 1 ] && [ -f "$PG/local/hosts" ]; then
        cp -p "$PG/local/hosts" "$PG/local/hosts.pre-list-migration.bak" 2>/dev/null || _mh_ok=0
      fi
      if [ "$_mh_ok" = 1 ]; then
        if cat "$_mh_new" > "$PG/local/hosts.migrate-write" 2>/dev/null &&
           mv -f "$PG/local/hosts.migrate-write" "$PG/local/hosts" 2>/dev/null; then
          chmod 600 "$PG/local/hosts" 2>/dev/null || true
        else
          rm -f "$PG/local/hosts.migrate-write" 2>/dev/null || true
          _mh_ok=0
        fi
      fi
    fi
    if [ "$_mh_ok" = 1 ]; then
      # The marker is the commit record. Publish it only after the merged file has
      # been committed (or after successfully proving there were no legacy entries).
      _mh_mark_tmp="$_mh_marker.tmp.$$"
      if printf 'completed
' > "$_mh_mark_tmp" 2>/dev/null && mv -f "$_mh_mark_tmp" "$_mh_marker" 2>/dev/null; then
        pg_log "migrate: legacy hosts_local migration committed; disabled entries preserved as comments" 2>/dev/null || true
      else
        rm -f "$_mh_mark_tmp" 2>/dev/null || true
        pg_log "migrate: ERROR unable to publish hosts_local migration marker; will retry next apply" 2>/dev/null || true
      fi
    else
      pg_log "migrate: ERROR hosts_local migration did not commit; marker withheld so next apply can retry" 2>/dev/null || true
    fi
    rm -f "$_mh_tmp" "$_mh_new" 2>/dev/null || true
  fi

    # User-requested clean blacklist: migrate any old active domain rows to a separate
  # built-in ruleset override, then leave [list:block] genuinely empty. One-time and
  # transactional; backups are kept before changing the persistent configuration.
  _mg_empty_mark="$PG/cache/migrate-block-empty-v1.done"
  if [ ! -f "$_mg_empty_mark" ]; then
    _mg_empty_ok=1
    _mg_backup="$PG/cache/settings.conf.pre-empty-block-v1.bak"
    [ -f "$_mg_backup" ] || cp -p "$CONF" "$_mg_backup" 2>/dev/null || _mg_empty_ok=0
    _mg_moved="$PG/cache/block-to-rule.$$.txt"
    _mg_conftmp="$PG/cache/settings-empty-block.$$.tmp"
    if [ "$_mg_empty_ok" = 1 ]; then
      awk -F'|' '
        /^\[list:block\][[:space:]]*$/ { section="block"; next }
        /^\[/ { section=""; next }
        section!="block" || /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        NF>=1 {
          d=tolower($1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", d); sub(/\.$/, "", d)
          status=$NF; gsub(/[[:space:]]/, "", status)
          if (status=="1" && d ~ /^([a-z0-9-]+\.)+[a-z][a-z]+$/) print "0.0.0.0 " d
          else if (status=="1" && d ~ /^(0\.0\.0\.0|127\.0\.0\.1)[[:space:]]+/) print d
        }
      ' "$CONF" | awk '!seen[$0]++' > "$_mg_moved" 2>/dev/null || _mg_empty_ok=0
    fi
    # Preserve domains from prior blacklist in an override of the NEW disabled ruleset.
    # Do not create an override on fresh installs with no legacy values.
    if [ "$_mg_empty_ok" = 1 ] && [ -s "$_mg_moved" ]; then
      mkdir -p "$PG/rulefiles-user" 2>/dev/null || _mg_empty_ok=0
      _mg_rule_override="$PG/rulefiles-user/privacy_ad_domains.txt"
      _mg_rule_tmp="$PG/cache/privacy-ad-domains.$$.tmp"
      if [ "$_mg_empty_ok" = 1 ]; then
        if [ -f "$_mg_rule_override" ]; then
          [ -f "$PG/cache/privacy_ad_domains.pre-migration.bak" ] || cp -p "$_mg_rule_override" "$PG/cache/privacy_ad_domains.pre-migration.bak" 2>/dev/null || _mg_empty_ok=0
          if [ "$_mg_empty_ok" = 1 ]; then cat "$_mg_rule_override" "$_mg_moved" 2>/dev/null | awk '!seen[$0]++' > "$_mg_rule_tmp" || _mg_empty_ok=0; fi
        else
          cat "$MODDIR/rulefiles/privacy_ad_domains.txt" "$_mg_moved" 2>/dev/null | awk '!seen[$0]++' > "$_mg_rule_tmp" || _mg_empty_ok=0
        fi
        if [ "$_mg_empty_ok" = 1 ]; then chmod 600 "$_mg_rule_tmp" 2>/dev/null || true; mv -f "$_mg_rule_tmp" "$_mg_rule_override" 2>/dev/null || _mg_empty_ok=0; fi
      fi
    fi
    if [ "$_mg_empty_ok" = 1 ]; then
      if awk '
        /^\[list:block\][[:space:]]*$/ { print; print "# 黑名单默认留空；旧黑名单域名已迁移到独立规则集（默认关闭）。"; section="block"; found=1; next }
        /^\[/ { section=""; print; next }
        section=="block" { next }
        { print }
        END { if (!found) { print ""; print "[list:block]"; print "# 黑名单默认留空；旧黑名单域名已迁移到独立规则集（默认关闭）。" } }
      ' "$CONF" > "$_mg_conftmp" 2>/dev/null && mv -f "$_mg_conftmp" "$CONF" 2>/dev/null; then
        chmod 600 "$CONF" 2>/dev/null || true
        printf 'completed\n' > "$_mg_empty_mark.tmp.$$" 2>/dev/null && mv -f "$_mg_empty_mark.tmp.$$" "$_mg_empty_mark" 2>/dev/null || _mg_empty_ok=0
      else
        _mg_empty_ok=0
      fi
    fi
    if [ "$_mg_empty_ok" != 1 ]; then
      pg_log 'migrate: ERROR empty-block migration failed; inspect backup and retry on next apply' 2>/dev/null || true
    else
      pg_log 'migrate: blacklist cleared; former active entries moved to disabled privacy_ad_domains ruleset' 2>/dev/null || true
    fi
    rm -f "$_mg_moved" "$_mg_conftmp" "$PG/cache/privacy-ad-domains.$$.tmp" 2>/dev/null || true
  fi

  # Ruleset catalog v3: repair the stale AWAvenue URL, then add verified upstream
  # catalogs to existing settings without overwriting user names or enabled states.
  # All remote lists stay disabled by default; the rules engine supports only a subset
  # of ABP/uBO syntax, so incompatible cosmetic/options are not silently broadened.
  _mg_rule_starters="$PG/cache/migrate-rule-starters-v3.done"
  if [ ! -f "$_mg_rule_starters" ]; then
    _mg_rule_old_awa='https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-Clash-classical.yaml'
    _mg_rule_new_awa='https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-Adblock.txt'
    _mg_rule_old_hagezi='https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/pro.txt'
    _mg_rule_new_hagezi='https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt'
    _mg_filter24='https://adguardteam.github.io/HostlistsRegistry/assets/filter_24.txt'
    _mg_rule_tmp="$PG/cache/migrate-rule-catalog.$$.tmp"
    # If both old and new URLs exist, drop only the obsolete URL. If only the old
    # one exists, replace its URL but preserve the original enabled bit.
    if grep -Fq "$_mg_rule_old_awa|" "$CONF" 2>/dev/null; then
      if grep -Fq "$_mg_rule_new_awa|" "$CONF" 2>/dev/null; then
        if awk -v old="$_mg_rule_old_awa" 'index($0,old "|")!=1 {print}' "$CONF" > "$_mg_rule_tmp" 2>/dev/null && mv -f "$_mg_rule_tmp" "$CONF" 2>/dev/null; then :; else pg_log 'migrate: warning: unable to drop stale AWAvenue YAML row; will retry' 2>/dev/null || true; fi
      else
        if awk -F'|' -v old="$_mg_rule_old_awa" -v new="$_mg_rule_new_awa" 'BEGIN{OFS="|"} index($1,old)==1 { $1=new; $2="秋风广告规则（官方 Adblock 格式；默认关闭）"; print; next } {print}' "$CONF" > "$_mg_rule_tmp" 2>/dev/null && mv -f "$_mg_rule_tmp" "$CONF" 2>/dev/null; then :; else pg_log 'migrate: warning: unable to migrate stale AWAvenue URL; will retry' 2>/dev/null || true; fi
      fi
    fi
    # HaGeZi moved the PRO list from domains/pro.txt to adblock/pro.txt. Migrate
    # only that stale row and preserve the user's enabled state; remove old row if
    # a new row is already present to avoid duplicate network downloads.
    if grep -Fq "$_mg_rule_old_hagezi|" "$CONF" 2>/dev/null; then
      if grep -Fq "$_mg_rule_new_hagezi|" "$CONF" 2>/dev/null; then
        if awk -v old="$_mg_rule_old_hagezi" 'index($0,old "|")!=1 {print}' "$CONF" > "$_mg_rule_tmp" 2>/dev/null && mv -f "$_mg_rule_tmp" "$CONF" 2>/dev/null; then :; else pg_log 'migrate: warning: unable to drop stale HaGeZi PRO row; will retry' 2>/dev/null || true; fi
      else
        if awk -F'|' -v old="$_mg_rule_old_hagezi" -v new="$_mg_rule_new_hagezi" 'BEGIN{OFS="|"} index($1,old)==1 { $1=new; $2="HaGeZi Multi PRO（Adblock 格式；默认关闭）"; print; next } {print}' "$CONF" > "$_mg_rule_tmp" 2>/dev/null && mv -f "$_mg_rule_tmp" "$CONF" 2>/dev/null; then :; else pg_log 'migrate: warning: unable to migrate stale HaGeZi PRO URL; will retry' 2>/dev/null || true; fi
      fi
    fi
    # Correct the display label of filter_24: it is the 1Hosts Lite list hosted
    # by AdGuard's registry, not an AdGuard-authored blocklist. Preserve its state.
    if grep -Fq "$_mg_filter24|" "$CONF" 2>/dev/null; then
      if awk -F'|' -v key="$_mg_filter24" 'BEGIN{OFS="|"} $1==key { $2="1Hosts Lite（AdGuard Hostlists Registry；默认关闭）"; print; next } {print}' "$CONF" > "$_mg_rule_tmp" 2>/dev/null && mv -f "$_mg_rule_tmp" "$CONF" 2>/dev/null; then :; else pg_log 'migrate: warning: unable to correct 1Hosts Lite label; will retry' 2>/dev/null || true; fi
    fi

    _mg_entries="$PG/cache/migrate-rule-starters.$$.txt"
    cat > "$_mg_entries" <<'__PG_RULE_STARTERS_V3__'
 builtin://privacy_ad_domains|广告与追踪域名集合（原黑名单迁入；默认关闭）|0
https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-Adblock.txt|秋风广告规则（官方 Adblock 格式；默认关闭）|0
https://raw.githubusercontent.com/AdguardTeam/AdGuardSDNSFilter/master/Filters/rules.txt|AdGuard DNS Filter（官方跟踪/广告规则；默认关闭）|0
https://raw.githubusercontent.com/AdAway/adaway.github.io/master/hosts.txt|AdAway Hosts（移动端广告与跟踪；默认关闭）|0
https://raw.githubusercontent.com/lingeringsound/10007_auto/master/all|10007 Hosts（对应仓库 10007/广告域名规则上游；默认关闭）|0
https://gitlab.com/andryou/block/raw/master/chibi|Chibi Hosts（社区 Hosts 规则；默认关闭）|0
https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/BaseFilter/sections/adservers.txt|AdGuard 广告服务器规则（兼容子集；默认关闭）|0
https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/SpywareFilter/sections/tracking_servers.txt|AdGuard 跟踪服务器规则（兼容子集；默认关闭）|0
https://easylist-downloads.adblockplus.org/easylist.txt|EasyList 通用网页广告规则（兼容子集；默认关闭）|0
https://easylist-downloads.adblockplus.org/easyprivacy.txt|EasyPrivacy 隐私跟踪规则（兼容子集；默认关闭）|0
https://easylist-downloads.adblockplus.org/easylistchina.txt|EasyList China 中文网站补充规则（兼容子集；默认关闭）|0
https://easylist-downloads.adblockplus.org/antiadblockfilters.txt|EasyList 反广告拦截提示规则（兼容子集；默认开启）|1
https://raw.githubusercontent.com/Noyllopa/NoAppDownload/master/NoAppDownload.txt|NoAppDownload 网页打开客户端/下载提示规则（网页元素子集；默认关闭）|0
https://adguardteam.github.io/HostlistsRegistry/assets/filter_24.txt|1Hosts Lite（AdGuard Hostlists Registry；默认关闭）|0
https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt|HaGeZi Multi PRO（Adblock 格式；默认关闭）|0
__PG_RULE_STARTERS_V3__
    _mg_starter_tmp="$PG/cache/migrate-rule-starters-out.$$.tmp"
    _mg_starter_ok=1
    while IFS= read -r _mg_entry; do
      # Ignore accidental leading whitespace in the here-doc catalog.
      _mg_entry=$(printf '%s' "$_mg_entry" | sed 's/^[[:space:]]*//')
      [ -n "$_mg_entry" ] || continue
      _mg_key=${_mg_entry%%|*}
      if ! awk -v sec='[list:rule]' -v key="$_mg_key" '
        /^\[list:rule\][[:space:]]*$/ { inrule=1; next }
        /^\[/ { inrule=0 }
        inrule && index($0,key "|")==1 { found=1 }
        END { exit !found }
      ' "$CONF"; then
        if awk -v entry="$_mg_entry" '
          /^\[list:rule\][[:space:]]*$/ && !added { print; print entry; added=1; inrule=1; next }
          /^\[/ { inrule=0 }
          { print }
          END { if (!added) { print ""; print "[list:rule]"; print entry } }
        ' "$CONF" > "$_mg_starter_tmp" 2>/dev/null && mv -f "$_mg_starter_tmp" "$CONF" 2>/dev/null; then :; else _mg_starter_ok=0; fi
      fi
    done < "$_mg_entries"
    if [ "$_mg_starter_ok" = 1 ]; then
      _mg_catalog_missing=0
      while IFS= read -r _mg_entry; do
        _mg_entry=$(printf '%s' "$_mg_entry" | sed 's/^[[:space:]]*//')
        [ -n "$_mg_entry" ] || continue
        _mg_key=${_mg_entry%%|*}
        grep -Fq "$_mg_key|" "$CONF" 2>/dev/null || _mg_catalog_missing=1
      done < "$_mg_entries"
      if [ "$_mg_catalog_missing" = 0 ]; then : > "$_mg_rule_starters" 2>/dev/null || true; else _mg_starter_ok=0; fi
    fi
    if [ "$_mg_starter_ok" != 1 ]; then pg_log 'migrate: rule catalog v3 incomplete; will retry next apply' 2>/dev/null || true; fi
    rm -f "$_mg_entries" "$_mg_starter_tmp" "$_mg_rule_tmp" 2>/dev/null || true
    chmod 600 "$CONF" 2>/dev/null || true
  fi

  # Ruleset catalog v4: add upstream sources that materially improve web cosmetic
  # coverage (mobile ads, Chinese sites, annoyance/pop-up filters and optional ad-host
  # domains). Existing rows and user-selected enable flags are preserved verbatim.
  _mg_rule_catalog_v4="$PG/cache/migrate-rule-catalog-v4.done"
  if [ ! -f "$_mg_rule_catalog_v4" ]; then
    _mg_v4_entries="$PG/cache/migrate-rule-v4.$$.txt"
    cat > "$_mg_v4_entries" <<'__PG_RULE_CATALOG_V4__'
https://filters.adtidy.org/extension/ublock/filters/14.txt|AdGuard Annoyances 弹窗/烦人元素规则（引擎兼容子集；默认开启）|1
https://filters.adtidy.org/extension/ublock/filters/224.txt|AdGuard 中文网站广告规则（引擎兼容子集；默认开启）|1
https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters-mobile.txt|uBlock 移动网页广告规则（标准 CSS/域名子集；默认开启）|1
https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/annoyances-others.txt|uBlock Other Annoyances（标准 CSS/域名子集；高级脚本规则不执行；默认开启）|1
https://easylist.to/easylist/fanboy-annoyance.txt|Fanboy Annoyance 综合弹窗/烦人元素规则（兼容子集；默认关闭）|0
https://easylist.to/easylist/fanboy-social.txt|Fanboy Social 社交组件规则（兼容子集；默认关闭）|0
https://raw.githubusercontent.com/Ultimate-Hosts-Blacklist/yoyo.org_domains/master/domains.list|Ultimate Hosts yoyo.org 广告服务器域名（不屏蔽成人内容站点；默认开启）|1
__PG_RULE_CATALOG_V4__
    _mg_v4_ok=1
    while IFS= read -r _mg_v4_entry; do
      [ -n "$_mg_v4_entry" ] || continue
      _mg_v4_key=${_mg_v4_entry%%|*}
      if ! awk -v key="$_mg_v4_key" '
        /^\[list:rule\][[:space:]]*$/ {inrule=1; next}
        /^\[/ {inrule=0}
        inrule && index($0,key "|")==1 {found=1}
        END {exit !found}
      ' "$CONF" 2>/dev/null; then
        _mg_v4_tmp="$PG/cache/migrate-rule-v4-out.$$.tmp"
        if awk -v entry="$_mg_v4_entry" '
          /^\[list:rule\][[:space:]]*$/ && !added {print; print entry; added=1; inrule=1; next}
          /^\[/ {inrule=0}
          {print}
          END {if (!added) {print ""; print "[list:rule]"; print entry}}
        ' "$CONF" > "$_mg_v4_tmp" 2>/dev/null && mv -f "$_mg_v4_tmp" "$CONF" 2>/dev/null; then :; else _mg_v4_ok=0; fi
      fi
    done < "$_mg_v4_entries"
    if [ "$_mg_v4_ok" = 1 ] && awk '
      /^\[list:rule\][[:space:]]*$/ {inrule=1; next}
      /^\[/ {inrule=0}
      inrule && /filters\.adtidy\.org\/extension\/ublock\/filters\/14\.txt\|/ {a++}
      inrule && /filters\.adtidy\.org\/extension\/ublock\/filters\/224\.txt\|/ {b++}
      inrule && /uBlockOrigin\/uAssets\/master\/filters\/filters-mobile\.txt\|/ {c++}
      inrule && /uBlockOrigin\/uAssets\/master\/filters\/annoyances-others\.txt\|/ {d++}
      inrule && /Ultimate-Hosts-Blacklist\/yoyo\.org_domains\/master\/domains\.list\|/ {e++}
      END {exit !(a==1 && b==1 && c==1 && d==1 && e==1)}
    ' "$CONF" 2>/dev/null; then
      : > "$_mg_rule_catalog_v4" 2>/dev/null || true
      pg_log 'migrate: rule catalog v4 upstream coverage sources registered' 2>/dev/null || true
    else
      _mg_v4_ok=0
      pg_log 'migrate: warning: rule catalog v4 incomplete; will retry' 2>/dev/null || true
    fi
    rm -f "$_mg_v4_entries" "$PG/cache/migrate-rule-v4-out.$$.tmp" 2>/dev/null || true
    chmod 600 "$CONF" 2>/dev/null || true
  fi


  # v1.0.0 cosmetic subset re-added by explicit product request: install once for
  # existing users, without overriding their current rule state or duplicating entries.
  _mg_cosmetic_mark='builtin_cosmetic_rules_v1'
  if ! grep -q "^# $_mg_cosmetic_mark$" "$CONF" 2>/dev/null; then
    _mg_cosmetic="$PG/cache/migrate-cosmetic.$$.tmp"
    cat > "$_mg_cosmetic" <<'__PG_COSMETIC_RULES__'
# builtin_cosmetic_rules_v1
builtin://NoAppDownload.txt|内置网页开屏/下载客户端提示元素规则（不覆盖原生 App 启动页）|1
builtin://Adblock_Watermark.txt|内置网页 DOM 水印隐藏规则（不移除视频/图片像素水印）|1
__PG_COSMETIC_RULES__
    # Avoid duplicate entries if the user already imported these rules manually.
    if grep -Fq 'builtin://NoAppDownload.txt|' "$CONF" 2>/dev/null && grep -Fq 'builtin://Adblock_Watermark.txt|' "$CONF" 2>/dev/null; then
      :
    else
      _mg_rl=$(grep -n '^\[list:rule\]' "$CONF" 2>/dev/null | head -1 | cut -d: -f1)
      if [ -n "$_mg_rl" ]; then
        _mg_nxr=$(awk -v s="$_mg_rl" 'NR>s && /^\[/ {print NR; exit}' "$CONF" 2>/dev/null)
        _mg_cosmetic_out="$PG/cache/migrate-cosmetic-out.$$.tmp"
        if [ -n "$_mg_nxr" ]; then
          if { head -n $((_mg_nxr - 1)) "$CONF"; cat "$_mg_cosmetic"; tail -n +"$_mg_nxr" "$CONF"; } > "$_mg_cosmetic_out" 2>/dev/null && mv -f "$_mg_cosmetic_out" "$CONF" 2>/dev/null; then
            pg_log 'migrate: bundled splash/watermark cosmetic rules registered' 2>/dev/null || true
          fi
        else
          if cat "$_mg_cosmetic" >> "$CONF" 2>/dev/null; then pg_log 'migrate: bundled splash/watermark cosmetic rules registered' 2>/dev/null || true; fi
        fi
      fi
    fi
    # Marker only after source entries are present; failed insertion retries next apply.
    if grep -Fq 'builtin://NoAppDownload.txt|' "$CONF" 2>/dev/null && grep -Fq 'builtin://Adblock_Watermark.txt|' "$CONF" 2>/dev/null; then
      printf '# %s\n' "$_mg_cosmetic_mark" >> "$CONF" 2>/dev/null || true
    fi
    rm -f "$_mg_cosmetic" "$PG/cache/migrate-cosmetic-out.$$.tmp" 2>/dev/null
    chmod 600 "$CONF" 2>/dev/null || true
  fi

  # v1.0.0: register broad upstream cosmetic lists once. This only adds sources that
  # did not previously exist; it does not change the state of any existing row.
  _mg_upstream_cosmetic_mark="$PG/cache/builtin_cosmetic_upstream_v1.done"
  if [ ! -f "$_mg_upstream_cosmetic_mark" ]; then
    _mg_upstream_cosmetic_entries="$PG/cache/migrate-cosmetic-upstreams.$$.txt"
    cat > "$_mg_upstream_cosmetic_entries" <<'__PG_COSMETIC_UPSTREAMS__'
https://raw.githubusercontent.com/runningcheese/RunningCheese-Firefox/master/Restore/Adblock_Watermark.txt|RunningCheese 网页水印规则（标准 CSS 与 :style 子集；默认开启）|1
https://raw.githubusercontent.com/runningcheese/RunningCheese-Firefox/master/Restore/Adblock_Popup.txt|RunningCheese 网页弹窗补充规则（标准 CSS 子集；默认开启）|1
https://cdn.jsdelivr.net/gh/Noyllopa/NoAppDownload@master/NoAppDownload.txt|NoAppDownload 全量网页打开客户端提示规则（标准 CSS 子集；默认开启）|1
https://raw.githubusercontent.com/fenglingback/cxfllist/main/rules/cxfl-ublock.txt|cxfl 网页元素补充规则（部分高级语法不支持；默认关闭）|0
__PG_COSMETIC_UPSTREAMS__
    _mg_upstream_ok=1
    while IFS= read -r _mg_upstream_entry; do
      [ -n "$_mg_upstream_entry" ] || continue
      _mg_upstream_key=${_mg_upstream_entry%%|*}
      if ! awk -v key="$_mg_upstream_key" '
        /^\[list:rule\][[:space:]]*$/ {inrule=1; next}
        /^\[/ {inrule=0}
        inrule && index($0,key "|")==1 {found=1}
        END {exit !found}
      ' "$CONF" 2>/dev/null; then
        _mg_upstream_tmp="$PG/cache/migrate-cosmetic-upstreams-out.$$.tmp"
        if awk -v entry="$_mg_upstream_entry" '
          /^\[list:rule\][[:space:]]*$/ && !added {print; print entry; added=1; inrule=1; next}
          /^\[/ {inrule=0}
          {print}
          END {if (!added) {print ""; print "[list:rule]"; print entry}}
        ' "$CONF" > "$_mg_upstream_tmp" 2>/dev/null && mv -f "$_mg_upstream_tmp" "$CONF" 2>/dev/null; then :; else _mg_upstream_ok=0; fi
      fi
    done < "$_mg_upstream_cosmetic_entries"
    if [ "$_mg_upstream_ok" = 1 ]; then
      : > "$_mg_upstream_cosmetic_mark" 2>/dev/null || true
      pg_log 'migrate: upstream watermark, popup, and app-download cosmetic sources registered' 2>/dev/null || true
    else
      pg_log 'migrate: cosmetic upstream registration incomplete; will retry next apply' 2>/dev/null || true
    fi
    rm -f "$_mg_upstream_cosmetic_entries" "$PG/cache/migrate-cosmetic-upstreams-out.$$.tmp" 2>/dev/null || true
    chmod 600 "$CONF" 2>/dev/null || true
  fi

  # Normalize known ad-source labels to Chinese while preserving the third-field toggle.
  _mg_zh_labels="$PG/cache/rule_catalog_chinese_labels_v1.done"
  if [ ! -f "$_mg_zh_labels" ]; then
    _mg_label_tmp="$PG/cache/rule-catalog-labels.$$.tmp"
    if awk -F'|' -v OFS='|' '
      BEGIN {
        label["https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-Adblock.txt"]="【通用网页广告】秋风 AWAvenue 广告过滤规则（默认关闭）"
        label["https://raw.githubusercontent.com/AdguardTeam/AdGuardSDNSFilter/master/Filters/rules.txt"]="【广告与追踪域名】AdGuard DNS 域名过滤清单（默认关闭）"
        label["https://raw.githubusercontent.com/AdAway/adaway.github.io/master/hosts.txt"]="【移动应用广告域名】AdAway Hosts 清单（默认关闭）"
        label["https://raw.githubusercontent.com/lingeringsound/10007_auto/master/all"]="【综合广告域名】10007 Hosts 大清单（默认关闭）"
        label["https://gitlab.com/andryou/block/raw/master/chibi"]="【综合广告域名】Chibi Hosts 社区清单（默认关闭）"
        label["https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/BaseFilter/sections/adservers.txt"]="【广告服务器域名】AdGuard 广告服务器清单（默认关闭）"
        label["https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/SpywareFilter/sections/tracking_servers.txt"]="【隐私追踪域名】AdGuard 跟踪服务器清单（默认关闭）"
        label["https://raw.githubusercontent.com/Noyllopa/NoAppDownload/master/NoAppDownload.txt"]="【网页保持浏览器打开】NoAppDownload 客户端跳转/下载提示（备用源，默认关闭）"
        label["https://raw.githubusercontent.com/fenglingback/cxfllist/main/rules/cxfl-ublock.txt"]="【网页广告与烦人元素】cxfl 补充规则（高级脚本语法不执行，默认关闭）"
        label["https://easylist.to/easylist/fanboy-annoyance.txt"]="【综合网页弹窗】Fanboy Annoyance 弹窗/烦人元素清单（默认关闭）"
        label["https://easylist.to/easylist/fanboy-social.txt"]="【社交组件过滤】Fanboy Social 社交组件清单（默认关闭）"
        label["https://adguardteam.github.io/HostlistsRegistry/assets/filter_24.txt"]="【综合广告域名】1Hosts Lite 域名清单（默认关闭）"
        label["https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt"]="【综合广告与追踪】HaGeZi Multi PRO 清单（默认关闭）"
      }
      /^\[list:rule\][[:space:]]*$/ {inrule=1; print; next}
      /^\[/ {inrule=0; print; next}
      inrule && NF {
        n=split($0,a,"|")
        if (n>=3 && (a[1] in label)) {a[2]=label[a[1]]; $0=a[1] OFS a[2] OFS a[3]}
      }
      {print}
    ' "$CONF" > "$_mg_label_tmp" 2>/dev/null && mv -f "$_mg_label_tmp" "$CONF" 2>/dev/null; then
      : > "$_mg_zh_labels" 2>/dev/null || true
    else
      pg_log 'migrate: Chinese label normalization failed; will retry' 2>/dev/null || true
    fi
    rm -f "$_mg_label_tmp" 2>/dev/null || true
    chmod 600 "$CONF" 2>/dev/null || true
  fi

  # Bundle source snapshots locally for core cosmetic/adult-popup rules. Upgrade migration
  # copies the user's enable flag from each formerly remote row to its local counterpart,
  # then disables duplicate remote rows. Other user rule flags remain untouched.
  _mg_local_rules="$PG/cache/rule_catalog_local_adult_sources_v1.done"
  if [ ! -f "$_mg_local_rules" ]; then
    _mg_local_tmp="$PG/cache/rule-catalog-local.$$.tmp"
    if awk -F'|' -v OFS='|' '
      BEGIN {
        local["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_specific_hide.txt"]="builtin://AdultSite_Elements_EasyList.txt|【成人网站广告元素】EasyList 成人站点元素规则（本地内置安全CSS子集）"
        local["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_adservers.txt"]="builtin://AdultSite_AdServers.txt|【成人广告服务器】EasyList 成人广告/追踪服务器（本地内置）"
        local["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_allowlist.txt"]="builtin://AdultSite_Allowlist.txt|【成人站点白名单】EasyList 成人站点资源例外（本地内置）"
        local["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_adservers_popup.txt"]="builtin://AdultSite_AdServersPopup.txt|【成人广告服务器弹窗】EasyList Popunder/弹窗域名规则（本地内置）"
        local["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_specific_block_popup.txt"]="builtin://AdultSite_SitePopup.txt|【成人站点专用弹窗】EasyList 成人网站跳转/弹窗规则（本地内置）"
        local["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_thirdparty_popup.txt"]="builtin://AdultSite_ThirdPartyPopup.txt|【成人第三方弹窗】EasyList 成人第三方弹窗规则（本地内置）"
        local["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_specific_block.txt"]="builtin://AdultSite_RequestRules.txt|【成人网站专用请求过滤】EasyList 站点路径、脚本与资源过滤（本地内置）"
        local["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_thirdparty.txt"]="builtin://AdultSite_ThirdParty.txt|【成人网站第三方资源】EasyList 成人第三方广告请求（本地内置）"
        local["https://raw.githubusercontent.com/runningcheese/RunningCheese-Firefox/master/Restore/Adblock_Watermark.txt"]="builtin://RunningCheese_Watermark.txt|【网页去水印补充】RunningCheese 网页 DOM/CSS 水印规则（本地内置）"
        local["https://raw.githubusercontent.com/runningcheese/RunningCheese-Firefox/master/Restore/Adblock_Popup.txt"]="builtin://RunningCheese_Popup.txt|【网页去弹窗补充】RunningCheese 网页浮层/弹窗规则（本地内置安全子集）"
        for (k in local) { split(local[k],b,"|"); localkey[k]=b[1] }
      }
      function emitmissing(    k,pair,b,n) {
        if (inserted) return
        for (k in local) {
          if (!(localkey[k] in added)) {
            split(local[k],b,"|")
            print b[1],b[2],"1"
            added[b[1]]=1
          }
        }
        inserted=1
      }
      /^\[list:rule\][[:space:]]*$/ {inrule=1; seenrule=1; print; next}
      /^\[/ {if (inrule) emitmissing(); inrule=0; print; next}
      inrule && NF {
        n=split($0,a,"|")
        # Keep the first row for each source key, preserving its existing state.
        if (n>=3 && a[1] in rowseen) next
        if (n>=3) rowseen[a[1]]=1
        # Existing local entries count as present so upgrades never duplicate them.
        if (n>=3 && a[1] ~ /^builtin:\/\//) added[a[1]]=1
        if (n>=3 && (a[1] in local)) {
          split(local[a[1]],b,"|")
          if (!(b[1] in added)) {print b[1],b[2],a[3]; added[b[1]]=1}
          a[2]="【在线更新备用】同类规则已随模块本地内置，默认关闭"
          a[3]="0"
          $0=a[1] OFS a[2] OFS a[3]
        }
        if (n>=3 && a[1]=="builtin://NoAppDownload.txt" && !(a[1] in added)) {print a[1],"【网页保持浏览器打开】NoAppDownload 全量网页提示（本地内置兼容子集）",a[3]; added[a[1]]=1}
      }
      # Critical safety invariant: retain every unrelated user subscription and
      # every transformed/normalized source row. Without this default print, this
      # migration would rewrite [list:rule] down to only the local adult/watermark
      # rows and silently delete arbitrary user rule sources on upgrade.
      {print}
      END {
        if (inrule) emitmissing()
        if (!seenrule) { print "[list:rule]"; inrule=1; emitmissing() }
      }
    ' "$CONF" > "$_mg_local_tmp" 2>/dev/null && mv -f "$_mg_local_tmp" "$CONF" 2>/dev/null; then
      : > "$_mg_local_rules" 2>/dev/null || true
      pg_log 'migrate: complete locally bundled cosmetic/adult popup source rows registered (existing enable flags preserved)' 2>/dev/null || true
    else
      pg_log 'migrate: local bundled rule migration failed; will retry next apply' 2>/dev/null || true
    fi
    rm -f "$_mg_local_tmp" 2>/dev/null || true
    chmod 600 "$CONF" 2>/dev/null || true
  fi

  # Chinese purpose labels v2: normalize older English adult/web rule labels while
  # preserving every existing third-field enable state. This is label-only migration.
  _mg_zh_labels_v2="$PG/cache/rule_catalog_chinese_labels_v2.done"
  if [ ! -f "$_mg_zh_labels_v2" ]; then
    _mg_label_v2_tmp="$PG/cache/rule-catalog-labels-v2.$$.tmp"
    if awk -F'|' -v OFS='|' '
      BEGIN {
        label["builtin://NoAppDownload.txt"]="【网页去开屏/跳转提示】内置手机网页打开App、扫码下载、客户端弹窗元素"
        label["builtin://Adblock_Watermark.txt"]="【网页去水印】内置DOM水印元素规则（不擦除已合成进图片/视频像素的水印）"
        label["builtin://AdultSite_AdPopup.txt"]="【成人网站去广告弹窗】内置广告层/弹窗选择器（保护正文、评论与播放器）"
        label["builtin://Adblock_Warning_Removal.txt"]="【去反广告拦截提示】内置网页反广告拦截提醒元素规则"
        label["builtin://AdultSite_AdHosts.txt"]="【成人广告网络域名】内置广告供应商/popunder域名（不屏蔽成人内容站点根域）"
        label["builtin://privacy_ad_domains"]="【通用广告与追踪域名】内置域名补充清单（默认关闭，可能影响个别服务）"
        label["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_specific_hide.txt"]="【成人网站广告元素】EasyList站点级广告元素隐藏（安全CSS子集）"
        label["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_adservers.txt"]="【成人广告服务器】EasyList成人广告网络/服务器规则"
        label["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_allowlist.txt"]="【成人网站规则例外】EasyList成人网站资源/脚本白名单，避免误拦正文功能"
        label["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_adservers_popup.txt"]="【成人广告弹窗域名】EasyList成人广告服务器弹窗规则"
        label["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_specific_block.txt"]="【成人网站广告请求】EasyList站点级广告资源拦截规则"
        label["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_specific_block_popup.txt"]="【成人网站站点弹窗】EasyList站点级弹窗/跳转拦截规则"
        label["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_thirdparty.txt"]="【成人第三方广告】EasyList成人网站第三方广告请求规则"
        label["builtin://AdultSite_RequestRules.txt"]="【成人网站专用请求过滤】EasyList站点路径、脚本与资源过滤（本地内置）"
        label["builtin://AdultSite_ThirdParty.txt"]="【成人网站第三方资源】EasyList成人第三方广告请求（本地内置）"
        label["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_thirdparty_popup.txt"]="【成人第三方弹窗】EasyList成人网站第三方弹窗规则"
        label["https://raw.githubusercontent.com/yokoffing/filterlists/main/adult_annoyance_list.txt"]="【成人网站烦人元素】Adult Annoyances弹窗/遮挡补充（安全选择器子集）"
        label["https://raw.githubusercontent.com/DandelionSprout/adfilt/master/stayingonbrowser/Staying%20On%20The%20Phone%20Browser"]="【网页保持浏览器打开】手机网页“打开App/下载客户端”提示补充规则"
        label["https://filters.adtidy.org/extension/ublock/filters/11.txt"]="【移动端广告网络】AdGuard Mobile Ads移动广告服务器规则"
        label["https://easylist-downloads.adblockplus.org/easylist_noadult.txt"]="【通用网页广告】EasyList非成人站点广告规则大清单（独立可选，默认关闭）"
        label["https://raw.githubusercontent.com/jk278/Ad-J/main/Ad-J.txt"]="【通用网页广告补充】Ad Filter J社区规则（独立可选；兼容子集）"
        label["https://raw.githubusercontent.com/AdguardTeam/AdGuardSDNSFilter/master/Filters/rules.txt"]="【广告与追踪域名】AdGuard DNS域名过滤清单（默认关闭）"
        label["https://raw.githubusercontent.com/AdAway/adaway.github.io/master/hosts.txt"]="【移动应用广告域名】AdAway Hosts清单（默认关闭）"
        label["https://raw.githubusercontent.com/lingeringsound/10007_auto/master/all"]="【综合广告域名】10007 Hosts大清单（默认关闭）"
        label["https://gitlab.com/andryou/block/raw/master/chibi"]="【综合广告域名】Chibi Hosts社区清单（默认关闭）"
        label["https://easylist-downloads.adblockplus.org/easylist.txt"]="【通用网页广告】EasyList国际站点广告规则（大清单，默认关闭）"
        label["https://easylist-downloads.adblockplus.org/easyprivacy.txt"]="【隐私跟踪拦截】EasyPrivacy请求/跟踪规则（独立可选，默认关闭）"
        label["https://easylist-downloads.adblockplus.org/easylistchina.txt"]="【中文网站广告】EasyList China中文网站广告补充（默认关闭）"
        label["https://easylist-downloads.adblockplus.org/antiadblockfilters.txt"]="【去反广告拦截提示】EasyList Anti-Adblock规则（兼容子集）"
        label["https://raw.githubusercontent.com/runningcheese/RunningCheese-Firefox/master/Restore/Adblock_Watermark.txt"]="【网页去水印】RunningCheese水印选择器补充（标准CSS/:style安全子集）"
        label["https://raw.githubusercontent.com/runningcheese/RunningCheese-Firefox/master/Restore/Adblock_Popup.txt"]="【网页去弹窗广告】RunningCheese弹窗/浮层补充（标准CSS子集）"
        label["https://cdn.jsdelivr.net/gh/Noyllopa/NoAppDownload@master/NoAppDownload.txt"]="【网页去开屏/下载提示】NoAppDownload全量网页客户端提示规则（标准CSS子集）"
        label["https://raw.githubusercontent.com/fenglingback/cxfllist/main/rules/cxfl-ublock.txt"]="【网页广告与烦人元素】cxfl补充规则（高级脚本语法不执行，默认关闭）"
        label["https://filters.adtidy.org/extension/ublock/filters/14.txt"]="【网页去弹窗/烦人元素】AdGuard Annoyances通用规则（安全兼容子集）"
        label["https://filters.adtidy.org/extension/ublock/filters/224.txt"]="【中文网站广告】AdGuard中文过滤规则（安全兼容子集）"
        label["https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters-mobile.txt"]="【移动网页广告】uBlock Origin移动端广告规则（CSS/域名兼容子集）"
        label["https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/annoyances-others.txt"]="【网页去烦人元素】uBlock Origin弹窗/遮挡补充（高级脚本不执行）"
      }
      /^\[list:rule\][[:space:]]*$/ {inrule=1; print; next}
      /^\[/ {inrule=0; print; next}
      inrule && NF {
        n=split($0,a,"|")
        if (n>=3 && (a[1] in label)) {a[2]=label[a[1]]; $0=a[1] OFS a[2] OFS a[3]}
      }
      {print}
    ' "$CONF" > "$_mg_label_v2_tmp" 2>/dev/null && mv -f "$_mg_label_v2_tmp" "$CONF" 2>/dev/null; then
      : > "$_mg_zh_labels_v2" 2>/dev/null || true
      pg_log 'migrate: rule-list labels normalized to Chinese purpose names v2; enable states preserved' 2>/dev/null || true
    else
      pg_log 'migrate: Chinese label normalization v2 failed; will retry' 2>/dev/null || true
    fi
    rm -f "$_mg_label_v2_tmp" 2>/dev/null || true
    chmod 600 "$CONF" 2>/dev/null || true
  fi

  # Keep labels in Chinese and register the EasyList adult exception source on
  # existing installs without changing the user's enabled/disabled state.
  _mg_cn_catalog_mark="$PG/cache/rule_catalog_chinese_adult_v1.done"
  if [ ! -f "$_mg_cn_catalog_mark" ]; then
    _mg_cn_entries="$PG/cache/migrate-rule-catalog.$$.txt"
    cat > "$_mg_cn_entries" <<'__PG_RULE_CATALOG_CN__'
https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_allowlist.txt|【成人网站规则例外】EasyList成人网站资源/脚本白名单，避免误拦正文功能|1
__PG_RULE_CATALOG_CN__
    _mg_cn_ok=1
    while IFS= read -r _mg_cn_entry; do
      [ -n "$_mg_cn_entry" ] || continue
      _mg_cn_key=${_mg_cn_entry%%|*}
      if ! awk -v key="$_mg_cn_key" '
        /^\[list:rule\][[:space:]]*$/ {inrule=1; next}
        /^\[/ {inrule=0}
        inrule && index($0,key "|")==1 {found=1}
        END {exit !found}
      ' "$CONF" 2>/dev/null; then
        _mg_cn_out="$PG/cache/migrate-rule-catalog-out.$$.tmp"
        if awk -v entry="$_mg_cn_entry" '
          /^\[list:rule\][[:space:]]*$/ && !added {print; print entry; added=1; inrule=1; next}
          /^\[/ {inrule=0}
          {print}
          END {if(!added){print ""; print "[list:rule]"; print entry}}
        ' "$CONF" > "$_mg_cn_out" 2>/dev/null && mv -f "$_mg_cn_out" "$CONF" 2>/dev/null; then :; else _mg_cn_ok=0; fi
      fi
    done < "$_mg_cn_entries"
    if [ "$_mg_cn_ok" = 1 ] && grep -Fq 'easylist_adult/adult_allowlist.txt|' "$CONF" 2>/dev/null; then
      : > "$_mg_cn_catalog_mark" 2>/dev/null || true
      pg_log 'migrate: Chinese ad-rule catalog includes adult-site request exceptions' 2>/dev/null || true
    else
      pg_log 'migrate: warning: adult exception source registration incomplete; will retry' 2>/dev/null || true
    fi
    rm -f "$_mg_cn_entries" "$PG/cache/migrate-rule-catalog-out.$$.tmp" 2>/dev/null || true
    chmod 600 "$CONF" 2>/dev/null || true
  fi

  # Coexistence is the default: the outer VPN remains the owner of Android's
  # VPNService; FX uses its root transparent-proxy path only when the tunnel and
  # owner can be identified. Unknown route/UID stays fail-safe rather than leaking.
  _mg_vpn_auto_mark="$PG/cache/vpn_external_compat_auto_v1.done"
  if [ ! -f "$_mg_vpn_auto_mark" ]; then
    _mg_vpn_auto_ok=1
    if grep -q '^vpn_external_compat=0$' "$CONF" 2>/dev/null; then
      _mg_vpn_auto_tmp="$PG/cache/migrate-vpn-auto.$$.tmp"
      if sed 's/^vpn_external_compat=0$/vpn_external_compat=1/' "$CONF" > "$_mg_vpn_auto_tmp" 2>/dev/null && mv -f "$_mg_vpn_auto_tmp" "$CONF" 2>/dev/null; then
        pg_log 'migrate: external VPN coexistence switched to automatic default' 2>/dev/null || true
      else
        _mg_vpn_auto_ok=0
      fi
      rm -f "$_mg_vpn_auto_tmp" 2>/dev/null || true
    fi
    if [ "$_mg_vpn_auto_ok" = 1 ]; then : > "$_mg_vpn_auto_mark" 2>/dev/null || true; fi
    chmod 600 "$CONF" 2>/dev/null || true
  fi

  # v1.0.0: add focused adult-site ad/pop-up and anti-adblock cosmetic rules to existing installs.
  # These are web DOM selectors only; the optional ad-host list is default-off to avoid content breakage.
  _mg_adult_cosmetic_mark="$PG/cache/builtin_adult_cosmetic_rules_v2.done"
  if [ ! -f "$_mg_adult_cosmetic_mark" ]; then
    _mg_extra_entries="$PG/cache/migrate-adult-cosmetic.$$.txt"
    cat > "$_mg_extra_entries" <<'__PG_ADULT_COSMETIC__'
builtin://AdultSite_AdPopup.txt|【成人网站去广告弹窗】内置广告层/弹窗选择器（保护正文、评论与播放器）|1
builtin://Adblock_Warning_Removal.txt|【去反广告拦截提示】内置网页反广告拦截提醒元素规则|1
builtin://AdultSite_AdHosts.txt|【成人广告网络域名】内置广告供应商/popunder域名（不屏蔽成人内容站点根域）|1
__PG_ADULT_COSMETIC__
    _mg_extra_ok=1
    while IFS= read -r _mg_extra_entry; do
      [ -n "$_mg_extra_entry" ] || continue
      _mg_extra_key=${_mg_extra_entry%%|*}
      if ! awk -v key="$_mg_extra_key" '
        /^\[list:rule\][[:space:]]*$/ {inrule=1; next}
        /^\[/ {inrule=0}
        inrule && index($0,key "|")==1 {found=1}
        END {exit !found}
      ' "$CONF" 2>/dev/null; then
        _mg_extra_out="$PG/cache/migrate-adult-cosmetic-out.$$.tmp"
        if awk -v entry="$_mg_extra_entry" '
          /^\[list:rule\][[:space:]]*$/ && !added {print; print entry; added=1; inrule=1; next}
          /^\[/ {inrule=0}
          {print}
          END {if(!added){print ""; print "[list:rule]"; print entry}}
        ' "$CONF" > "$_mg_extra_out" 2>/dev/null && mv -f "$_mg_extra_out" "$CONF" 2>/dev/null; then :; else _mg_extra_ok=0; fi
      fi
    done < "$_mg_extra_entries"
    if [ "$_mg_extra_ok" = 1 ] && awk '
      /^\[list:rule\][[:space:]]*$/ {inrule=1; next}
      /^\[/ {inrule=0}
      inrule && /builtin:\/\/AdultSite_AdPopup\.txt\|/ {a++}
      inrule && /builtin:\/\/Adblock_Warning_Removal\.txt\|/ {b++}
      inrule && /builtin:\/\/AdultSite_AdHosts\.txt\|/ {c++}
      END {exit !(a==1 && b==1 && c==1)}
    ' "$CONF" 2>/dev/null; then
      : > "$_mg_adult_cosmetic_mark" 2>/dev/null || true
      pg_log 'migrate: adult-site ad cosmetic and optional ad-host rules registered' 2>/dev/null || true
    else
      pg_log 'migrate: warning: adult-site cosmetic catalog incomplete; will retry' 2>/dev/null || true
    fi
    rm -f "$_mg_extra_entries" "$PG/cache/migrate-adult-cosmetic-out.$$.tmp" 2>/dev/null || true
    chmod 600 "$CONF" 2>/dev/null || true
  fi

  # Adult cosmetic upstream v3: add two GitHub-maintained adult-specific lists without
  # touching any existing subscription state. These lists are CSS/cosmetic inputs only;
  # apply.sh and vpnrule.sh intentionally skip them in hosts/network route compilation.
  _mg_adult_upstream_v3="$PG/cache/builtin_adult_upstreams_v3.done"
  if [ ! -f "$_mg_adult_upstream_v3" ]; then
    _mg_adult_upstream_entries="$PG/cache/migrate-adult-upstreams.$$.txt"
    cat > "$_mg_adult_upstream_entries" <<'__PG_ADULT_UPSTREAM_V3__'
https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_specific_hide.txt|【成人网站广告元素】EasyList站点级广告元素隐藏（安全CSS子集）|1
https://raw.githubusercontent.com/yokoffing/filterlists/main/adult_annoyance_list.txt|【成人网站烦人元素】Adult Annoyances弹窗/遮挡补充（安全选择器子集）|1
__PG_ADULT_UPSTREAM_V3__
    _mg_adult_upstream_ok=1
    while IFS= read -r _mg_adult_entry; do
      [ -n "$_mg_adult_entry" ] || continue
      _mg_adult_key=${_mg_adult_entry%%|*}
      if ! awk -v key="$_mg_adult_key" '
        /^\[list:rule\][[:space:]]*$/ {inrule=1; next}
        /^\[/ {inrule=0}
        inrule && index($0,key "|")==1 {found=1}
        END {exit !found}
      ' "$CONF" 2>/dev/null; then
        _mg_adult_out="$PG/cache/migrate-adult-upstreams-out.$$.tmp"
        if awk -v entry="$_mg_adult_entry" '
          /^\[list:rule\][[:space:]]*$/ && !added {print; print entry; added=1; inrule=1; next}
          /^\[/ {inrule=0}
          {print}
          END {if (!added) {print ""; print "[list:rule]"; print entry}}
        ' "$CONF" > "$_mg_adult_out" 2>/dev/null && mv -f "$_mg_adult_out" "$CONF" 2>/dev/null; then :; else _mg_adult_upstream_ok=0; fi
      fi
    done < "$_mg_adult_upstream_entries"
    if [ "$_mg_adult_upstream_ok" = 1 ] && grep -Fq 'easylist_adult/adult_specific_hide.txt|' "$CONF" && grep -Fq 'yokoffing/filterlists/main/adult_annoyance_list.txt|' "$CONF"; then
      : > "$_mg_adult_upstream_v3" 2>/dev/null || true
      pg_log 'migrate: EasyList adult-specific and Adult Annoyances cosmetic sources registered' 2>/dev/null || true
    else
      pg_log 'migrate: adult cosmetic upstream registration incomplete; will retry next apply' 2>/dev/null || true
    fi
    rm -f "$_mg_adult_upstream_entries" "$PG/cache/migrate-adult-upstreams-out.$$.tmp" 2>/dev/null || true
    chmod 600 "$CONF" 2>/dev/null || true
  fi

  # Adult ad-network hosts v5: user explicitly asked that the adult-site ad host list
  # be active by default. It contains ad/popunder vendors only, not adult content site
  # roots. Switch the old default row once while keeping the same row/path/version.
  _mg_adult_hosts_v5="$PG/cache/migrate-adult-ad-hosts-v5.done"
  if [ ! -f "$_mg_adult_hosts_v5" ]; then
    _mg_v5_tmp="$PG/cache/migrate-adult-hosts-v5.$$.tmp"
    if awk -F'|' -v OFS='|' '
      /^builtin:\/\/AdultSite_AdHosts\.txt\|/ {
        $2="成人网站广告网络域名（仅广告供应商；默认开启）"; $3="1"; changed++
      }
      {print}
      END {if (changed != 1) exit 1}
    ' "$CONF" > "$_mg_v5_tmp" 2>/dev/null && mv -f "$_mg_v5_tmp" "$CONF" 2>/dev/null; then
      : > "$_mg_adult_hosts_v5" 2>/dev/null || true
      pg_log 'migrate: adult ad-host rule enabled (ad networks only; content-site roots unchanged)' 2>/dev/null || true
    else
      rm -f "$_mg_v5_tmp" 2>/dev/null || true
      pg_log 'migrate: warning: adult ad-host default migration incomplete; will retry' 2>/dev/null || true
    fi
    chmod 600 "$CONF" 2>/dev/null || true
  fi

  # Rules catalog v7: extend categorized adult-site and mobile-browser prompt sources.
  # Every source receives a Chinese purpose label; only absent rows are inserted so
  # existing user-selected enable/disable states are never overwritten.
  _mg_catalog_v7="$PG/cache/migrate-rule-catalog-v7.done"
  if [ ! -f "$_mg_catalog_v7" ]; then
    _mg_v7_entries="$PG/cache/migrate-rule-v7.$$.txt"
    cat > "$_mg_v7_entries" <<'__PG_RULE_CATALOG_V7__'
https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_adservers.txt|【成人广告服务器】EasyList成人广告网络/服务器规则|1
https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_adservers_popup.txt|【成人广告弹窗域名】EasyList成人广告服务器弹窗规则|1
https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_specific_block.txt|【成人网站广告请求】EasyList站点级广告资源拦截规则|1
https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_specific_block_popup.txt|【成人网站站点弹窗】EasyList站点级弹窗/跳转拦截规则|1
https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_thirdparty.txt|【成人第三方广告】EasyList成人网站第三方广告请求规则|1
https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_thirdparty_popup.txt|【成人第三方弹窗】EasyList成人网站第三方弹窗规则|1
https://raw.githubusercontent.com/DandelionSprout/adfilt/master/stayingonbrowser/Staying%20On%20The%20Phone%20Browser|【网页保持浏览器打开】手机网页“打开App/下载客户端”提示补充规则|1
https://filters.adtidy.org/extension/ublock/filters/11.txt|【移动端广告网络】AdGuard Mobile Ads移动广告服务器规则|1
https://easylist-downloads.adblockplus.org/easylist_noadult.txt|【通用网页广告】EasyList非成人站点广告规则大清单（独立可选，默认关闭）|0
https://raw.githubusercontent.com/jk278/Ad-J/main/Ad-J.txt|【通用网页广告补充】Ad Filter J社区规则（独立可选；兼容子集）|0
__PG_RULE_CATALOG_V7__
    _mg_v7_ok=1
    while IFS= read -r _mg_v7_entry; do
      [ -n "$_mg_v7_entry" ] || continue
      _mg_v7_key=${_mg_v7_entry%%|*}
      if ! awk -v key="$_mg_v7_key" '
        /^\[list:rule\][[:space:]]*$/ {inrule=1; next}
        /^\[/ {inrule=0}
        inrule && index($0,key "|")==1 {found=1}
        END {exit !found}
      ' "$CONF" 2>/dev/null; then
        _mg_v7_tmp="$PG/cache/migrate-rule-v7-out.$$.tmp"
        if awk -v entry="$_mg_v7_entry" '
          /^\[list:rule\][[:space:]]*$/ && !added {print; print entry; added=1; inrule=1; next}
          /^\[/ {inrule=0}
          {print}
          END {if (!added) {print ""; print "[list:rule]"; print entry}}
        ' "$CONF" > "$_mg_v7_tmp" 2>/dev/null && mv -f "$_mg_v7_tmp" "$CONF" 2>/dev/null; then :; else _mg_v7_ok=0; fi
      fi
    done < "$_mg_v7_entries"
    if [ "${_mg_v7_ok:-1}" = 1 ] && grep -Fq 'adult_adservers.txt|' "$CONF" && grep -Fq 'adult_thirdparty_popup.txt|' "$CONF" && grep -Fq 'Staying%20On%20The%20Phone%20Browser|' "$CONF" && grep -Fq 'filters/11.txt|' "$CONF"; then
      : > "$_mg_catalog_v7" 2>/dev/null || true
      pg_log 'migrate: categorized EasyList adult adserver/site/popup lists and mobile-browser prompt sources registered' 2>/dev/null || true
    else
      pg_log 'migrate: rule catalog v7 incomplete; will retry next apply' 2>/dev/null || true
    fi
    rm -f "$_mg_v7_entries" "$PG/cache/migrate-rule-v7-out.$$.tmp" 2>/dev/null || true
    chmod 600 "$CONF" 2>/dev/null || true
  fi

  # Rules catalog v8: register the complete uBlock Origin filter source as an
  # independently named optional list. Keep it disabled by default because broad
  # lists can occasionally affect site-specific functionality; all existing states
  # are preserved on upgrade.
  _mg_catalog_v8="$PG/cache/migrate-rule-catalog-v8.done"
  if [ ! -f "$_mg_catalog_v8" ]; then
    _mg_v8_url='https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt'
    if ! awk -v key="$_mg_v8_url" '
      /^\[list:rule\][[:space:]]*$/ {inrule=1; next}
      /^\[/ {inrule=0}
      inrule && index($0,key "|")==1 {found=1}
      END {exit !found}
    ' "$CONF" 2>/dev/null; then
      _mg_v8_tmp="$PG/cache/migrate-rule-v8.$$.tmp"
      if awk -v entry="$_mg_v8_url|【通用网页广告】uBlock Origin完整网页过滤清单（大清单；默认关闭，可单独开启）|0" '
        /^\[list:rule\][[:space:]]*$/ && !added {print; print entry; added=1; inrule=1; next}
        /^\[/ {inrule=0}
        {print}
        END {if (!added) {print ""; print "[list:rule]"; print entry}}
      ' "$CONF" > "$_mg_v8_tmp" 2>/dev/null && mv -f "$_mg_v8_tmp" "$CONF" 2>/dev/null; then
        : > "$_mg_catalog_v8" 2>/dev/null || true
        pg_log 'migrate: optional full uBlock Origin catalog source registered with Chinese label' 2>/dev/null || true
      else
        rm -f "$_mg_v8_tmp" 2>/dev/null || true
        pg_log 'migrate: warning: uBlock catalog v8 incomplete; will retry' 2>/dev/null || true
      fi
    else
      : > "$_mg_catalog_v8" 2>/dev/null || true
    fi
    chmod 600 "$CONF" 2>/dev/null || true
  fi

  # Anti-adblock removal v6: explicitly requested, high-value annoyance source.
  # Only this focused filter is promoted; the broad Fanboy lists remain opt-in.
  _mg_antiadblock_v6="$PG/cache/migrate-antiadblock-upstream-v6.done"
  if [ ! -f "$_mg_antiadblock_v6" ]; then
    _mg_antiadblock_tmp="$PG/cache/migrate-antiadblock-v6.$$.tmp"
    if awk -F'|' -v OFS='|' '
      /^\[list:rule\][[:space:]]*$/ {inrule=1; print; next}
      /^\[/ {inrule=0}
      inrule && $1=="https://easylist-downloads.adblockplus.org/antiadblockfilters.txt" {
        $2="EasyList 反广告拦截提示规则（兼容子集；默认开启）"; $3="1"; changed++
      }
      {print}
      END {if (changed != 1) exit 1}
    ' "$CONF" > "$_mg_antiadblock_tmp" 2>/dev/null && mv -f "$_mg_antiadblock_tmp" "$CONF" 2>/dev/null; then
      : > "$_mg_antiadblock_v6" 2>/dev/null || true
      pg_log 'migrate: EasyList anti-adblock cosmetic source enabled for broader warning removal' 2>/dev/null || true
    else
      rm -f "$_mg_antiadblock_tmp" 2>/dev/null || true
      pg_log 'migrate: warning: anti-adblock source migration incomplete; will retry' 2>/dev/null || true
    fi
    chmod 600 "$CONF" 2>/dev/null || true
  fi

  # Local upstream rule expansion v1: bundle independently selectable upstream lists.
  # Preserve enable state for keys already present; new local sources are enabled by default.
  _mg_local_upstream_mark="$PG/cache/builtin_local_upstream_rules_v1.done"
  if [ ! -f "$_mg_local_upstream_mark" ]; then
    _mg_local_upstream_entries="$PG/cache/migrate-local-upstream-rules.$$.txt"
    cat > "$_mg_local_upstream_entries" <<'__PG_LOCAL_UPSTREAM_RULES__'
builtin://AdultSite_AdServers.txt|【成人广告服务器请求】EasyList本地354条成人广告服务器请求规则|1
builtin://AdultSite_Allowlist.txt|【成人站点资源白名单】EasyList本地例外规则，防止误拦必要API/脚本|1
builtin://AdultSite_AdServersPopup.txt|【成人广告服务器弹窗】EasyList本地广告服务器弹窗规则|1
builtin://AdultSite_SitePopup.txt|【成人网站站点弹窗】EasyList本地站点专用弹窗/跳转规则|1
builtin://AdultSite_ThirdPartyPopup.txt|【成人第三方弹窗】EasyList本地第三方弹窗规则|1
builtin://AdultSite_RequestRules.txt|【成人网站专用请求过滤】EasyList站点路径、脚本与资源规则（不支持语法安全跳过）|1
builtin://AdultSite_ThirdParty.txt|【成人网站第三方资源】EasyList第三方广告与资源规则（保留来源域/类型条件）|1
builtin://AdultSite_Elements_EasyList.txt|【成人网站广告元素】EasyList本地站点广告元素隐藏（安全CSS子集）|1
builtin://RunningCheese_Watermark.txt|【网页水印补充】奶酪上游水印规则本地兼容子集|1
builtin://RunningCheese_Popup.txt|【网页浮层弹窗补充】奶酪上游网页弹窗本地兼容子集|1
__PG_LOCAL_UPSTREAM_RULES__
    _mg_local_ok=1
    while IFS= read -r _mg_local_entry; do
      [ -n "$_mg_local_entry" ] || continue
      _mg_local_key=${_mg_local_entry%%|*}
      if ! awk -v key="$_mg_local_key" '
        /^\[list:rule\][[:space:]]*$/ {inrule=1; next}
        /^\[/ {inrule=0}
        inrule && index($0,key "|")==1 {found=1}
        END {exit !found}
      ' "$CONF" 2>/dev/null; then
        _mg_local_tmp="$PG/cache/migrate-local-upstream-out.$$.tmp"
        if awk -v entry="$_mg_local_entry" '
          /^\[list:rule\][[:space:]]*$/ && !added {print; print entry; added=1; inrule=1; next}
          /^\[/ {inrule=0}
          {print}
          END {if (!added) {print ""; print "[list:rule]"; print entry}}
        ' "$CONF" > "$_mg_local_tmp" 2>/dev/null && mv -f "$_mg_local_tmp" "$CONF" 2>/dev/null; then :; else _mg_local_ok=0; fi
      fi
    done < "$_mg_local_upstream_entries"
    if [ "$_mg_local_ok" = 1 ]; then
      : > "$_mg_local_upstream_mark" 2>/dev/null || true
      pg_log 'migrate: expanded upstream adult/watermark/popup rule sets are available offline' 2>/dev/null || true
    else
      pg_log 'migrate: local upstream rule registration incomplete; will retry' 2>/dev/null || true
    fi
    rm -f "$_mg_local_upstream_entries" "$PG/cache/migrate-local-upstream-out.$$.tmp" 2>/dev/null || true
    chmod 600 "$CONF" 2>/dev/null || true
  fi

  # Recovery/normalization after all legacy catalog migrations above. Earlier catalog
  # migrations (v3/v7) could append online adult/cosmetic lists *after* the first local
  # migration ran. This final pass restores locally bundled rows, disables redundant
  # online copies, and—critically—preserves every unrelated user subscription.
  _mg_local_sources_v2="$PG/cache/rule_catalog_local_adult_sources_v2.done"
  if [ ! -f "$_mg_local_sources_v2" ]; then
    # If a previous build ran the buggy v1 migration (which omitted its default print),
    # recover missing rule rows from the pre-migration backup if one exists. Do not
    # overwrite current rows/flags; skip only obsolete URLs already replaced upstream.
    _mg_recover_mark="$PG/cache/rule_catalog_user_rows_recovery_v1.done"
    if [ ! -f "$_mg_recover_mark" ]; then
      _mg_recover_backup="$PG/cache/settings.conf.pre-empty-block-v1.bak"
      _mg_recover_ok=1
      if [ -f "$PG/cache/rule_catalog_local_adult_sources_v1.done" ] && [ -s "$_mg_recover_backup" ]; then
        _mg_recover_tmp="$PG/cache/rule-catalog-recover.$$.tmp"
        if awk -F'|' -v backup="$_mg_recover_backup" '
          BEGIN {
            sec=0
            while ((getline line < backup) > 0) {
              if (line == "[list:rule]") { sec=1; continue }
              if (line ~ /^\[/) { sec=0; continue }
              if (!sec || line ~ /^[[:space:]]*#/ || line ~ /^[[:space:]]*$/) continue
              n=split(line,a,"|")
              if (n>=3 && a[1]!="" && !(a[1] in oldrow)) {
                oldrow[a[1]]=line
                order[++nold]=a[1]
              }
            }
            close(backup)
          }
          function emitmissing(    i,k,a) {
            if (emitted) return
            for (i=1;i<=nold;i++) {
              k=order[i]
              if (k in present) continue
              if (k=="https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-Clash-classical.yaml" && ("https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-Adblock.txt" in present)) continue
              if (k=="https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/pro.txt" && ("https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt" in present)) continue
              print oldrow[k]
              present[k]=1
            }
            emitted=1
          }
          /^\[list:rule\][[:space:]]*$/ { if (inrule) emitmissing(); inrule=1; seenrule=1; print; next }
          /^\[/ { if (inrule) emitmissing(); inrule=0; print; next }
          inrule && NF && $0 !~ /^[[:space:]]*#/ { n=split($0,a,"|"); if(n>=3) present[a[1]]=1 }
          { print }
          END {
            if (inrule) emitmissing()
            if (!seenrule && nold>0) { print "[list:rule]"; inrule=1; emitmissing() }
          }
        ' "$CONF" > "$_mg_recover_tmp" 2>/dev/null && mv -f "$_mg_recover_tmp" "$CONF" 2>/dev/null; then
          pg_log 'migrate: recovered missing user rule sources from pre-migration backup' 2>/dev/null || true
        else
          _mg_recover_ok=0
          pg_log 'migrate: warning: user rule-source recovery failed; active configuration left intact; will retry' 2>/dev/null || true
        fi
        rm -f "$_mg_recover_tmp" 2>/dev/null || true
      fi
      if [ "$_mg_recover_ok" = 1 ]; then : > "$_mg_recover_mark" 2>/dev/null || true; fi
    fi

    _mg_local_v2_tmp="$PG/cache/rule-catalog-local-v2.$$.tmp"
    if awk -F'|' -v OFS='|' '
      BEGIN {
        local["https://raw.githubusercontent.com/Noyllopa/NoAppDownload/master/NoAppDownload.txt"]="builtin://NoAppDownload.txt|【网页去开屏/跳转提示】NoAppDownload 本地网页打开App/下载提示规则"
        local["https://cdn.jsdelivr.net/gh/Noyllopa/NoAppDownload@master/NoAppDownload.txt"]="builtin://NoAppDownload.txt|【网页去开屏/跳转提示】NoAppDownload 本地网页打开App/下载提示规则"
        local["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_specific_hide.txt"]="builtin://AdultSite_Elements_EasyList.txt|【成人网站广告元素】EasyList 本地站点广告元素（安全CSS兼容子集）"
        local["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_adservers.txt"]="builtin://AdultSite_AdServers.txt|【成人广告服务器请求】EasyList 成人广告/追踪服务器（本地内置）"
        local["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_allowlist.txt"]="builtin://AdultSite_Allowlist.txt|【成人站点资源白名单】EasyList 成人资源例外规则（本地内置）"
        local["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_adservers_popup.txt"]="builtin://AdultSite_AdServersPopup.txt|【成人广告服务器弹窗】EasyList Popunder/弹窗域名规则（本地内置）"
        local["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_specific_block_popup.txt"]="builtin://AdultSite_SitePopup.txt|【成人网站站点弹窗】EasyList 站点专用弹窗/跳转规则（本地内置）"
        local["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_thirdparty_popup.txt"]="builtin://AdultSite_ThirdPartyPopup.txt|【成人第三方弹窗】EasyList 成人第三方弹窗规则（本地内置）"
        local["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_specific_block.txt"]="builtin://AdultSite_RequestRules.txt|【成人网站专用请求过滤】EasyList 站点路径/脚本/资源规则（本地内置）"
        local["https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_thirdparty.txt"]="builtin://AdultSite_ThirdParty.txt|【成人网站第三方资源】EasyList 成人第三方请求规则（本地内置）"
        local["https://raw.githubusercontent.com/runningcheese/RunningCheese-Firefox/master/Restore/Adblock_Watermark.txt"]="builtin://RunningCheese_Watermark.txt|【网页去水印补充】RunningCheese 网页DOM/CSS水印规则（本地内置）"
        local["https://raw.githubusercontent.com/runningcheese/RunningCheese-Firefox/master/Restore/Adblock_Popup.txt"]="builtin://RunningCheese_Popup.txt|【网页去弹窗补充】RunningCheese 网页浮层/弹窗规则（本地内置）"
        for (k in local) { split(local[k],b,"|"); localkey[k]=b[1] }
      }
      function emitmissing(    k,b) {
        if (inserted) return
        for (k in local) {
          if (!(localkey[k] in added)) {
            split(local[k],b,"|")
            print b[1],b[2],"1"
            added[b[1]]=1
          }
        }
        inserted=1
      }
      /^\[list:rule\][[:space:]]*$/ { if (inrule) emitmissing(); inrule=1; seenrule=1; print; next }
      /^\[/ { if (inrule) emitmissing(); inrule=0; print; next }
      inrule && NF {
        n=split($0,a,"|")
        if (n>=3 && a[1] in rowseen) next
        if (n>=3) rowseen[a[1]]=1
        if (n>=3 && a[1] ~ /^builtin:\/\//) added[a[1]]=1
        if (n>=3 && (a[1] in local)) {
          split(local[a[1]],b,"|")
          if (!(b[1] in added)) { print b[1],b[2],a[3]; added[b[1]]=1 }
          a[2]="【在线备用】同类规则已随模块本地内置，默认关闭"
          a[3]="0"
          $0=a[1] OFS a[2] OFS a[3]
        }
        # The upstream Adult Annoyances mix includes selectors that hide comments,
        # related content and other non-ad elements. It is not bundled as an active
        # rule set, so only its automatic migration default is turned off; custom
        # labels/states are respected.
        if (n>=3 && a[1]=="https://raw.githubusercontent.com/yokoffing/filterlists/main/adult_annoyance_list.txt" && a[2]=="【成人网站烦人元素】Adult Annoyances弹窗/遮挡补充（安全选择器子集）") {
          a[2]="【在线补充】Adult Annoyances含站点内容选择器，非本地快照，按需启用"
          a[3]="0"
          $0=a[1] OFS a[2] OFS a[3]
        }
      }
      { print }
      END {
        if (inrule) emitmissing()
        if (!seenrule) { print "[list:rule]"; inrule=1; emitmissing() }
      }
    ' "$CONF" > "$_mg_local_v2_tmp" 2>/dev/null && mv -f "$_mg_local_v2_tmp" "$CONF" 2>/dev/null; then
      : > "$_mg_local_sources_v2" 2>/dev/null || true
      pg_log 'migrate: final local rule normalization completed; redundant online copies disabled; user rows retained' 2>/dev/null || true
    else
      pg_log 'migrate: final local rule normalization failed; will retry next apply' 2>/dev/null || true
    fi
    rm -f "$_mg_local_v2_tmp" 2>/dev/null || true
    chmod 600 "$CONF" 2>/dev/null || true
  fi

  # Always repair legacy/misplaced cosmetic entries: these belong to [list:rule],
  # never [list:fx]. Preserve their enabled state if already in [list:rule].
  _mg_fx_move="$PG/cache/migrate-fx-cosmetic.$$.tmp"
  _mg_fx_clean="$PG/cache/migrate-fx-clean.$$.tmp"
  _mg_fx_final="$PG/cache/migrate-fx-final.$$.tmp"
  : > "$_mg_fx_move"
  if awk -v out="$_mg_fx_move" '
    /^\[list:fx\][[:space:]]*$/ { section="fx"; print; next }
    /^\[/ { section="" }
    section=="fx" && /builtin:\/\/(NoAppDownload\.txt|Adblock_Watermark\.txt|AdultSite_AdPopup\.txt|Adblock_Warning_Removal\.txt|AdultSite_Elements_EasyList\.txt|RunningCheese_Watermark\.txt|RunningCheese_Popup\.txt|AdultSite_AdServers\.txt|AdultSite_Allowlist\.txt|AdultSite_AdServersPopup\.txt|AdultSite_SitePopup\.txt|AdultSite_ThirdPartyPopup\.txt|AdultSite_RequestRules\.txt|AdultSite_ThirdParty\.txt)\|/ { print > out; next }
    { print }
  ' "$CONF" > "$_mg_fx_clean" 2>/dev/null && [ -s "$_mg_fx_clean" ]; then
    if [ -s "$_mg_fx_move" ]; then
      awk -v addfile="$_mg_fx_move" '
        BEGIN {
          while ((getline line < addfile) > 0) {
            if (line ~ /builtin:\/\/NoAppDownload\.txt\|/) addSplash=line
            if (line ~ /builtin:\/\/Adblock_Watermark\.txt\|/) addWater=line
            if (line ~ /builtin:\/\/AdultSite_AdPopup\.txt\|/) addAdult=line
            if (line ~ /builtin:\/\/Adblock_Warning_Removal\.txt\|/) addAnti=line
          }
          close(addfile)
        }
        /^\[list:rule\][[:space:]]*$/ { if (section=="rule") flush(); section="rule"; print; next }
        /^\[/ { if (section=="rule") flush(); section=""; print; next }
        section=="rule" && /builtin:\/\/NoAppDownload\.txt\|/ { haveSplash=1 }
        section=="rule" && /builtin:\/\/Adblock_Watermark\.txt\|/ { haveWater=1 }
        section=="rule" && /builtin:\/\/AdultSite_AdPopup\.txt\|/ { haveAdult=1 }
        section=="rule" && /builtin:\/\/Adblock_Warning_Removal\.txt\|/ { haveAnti=1 }
        { print }
        function flush() {
          if (addSplash!="" && !haveSplash) print addSplash
          if (addWater!="" && !haveWater) print addWater
          if (addAdult!="" && !haveAdult) print addAdult
          if (addAnti!="" && !haveAnti) print addAnti
          addSplash=""; addWater=""; addAdult=""; addAnti=""
          haveSplash=0; haveWater=0; haveAdult=0; haveAnti=0
        }
        END { if (section=="rule") flush() }
      ' "$_mg_fx_clean" > "$_mg_fx_final" 2>/dev/null && mv -f "$_mg_fx_final" "$CONF" 2>/dev/null && pg_log 'migrate: moved cosmetic entries out of [list:fx] into [list:rule]' 2>/dev/null || true
    else
      mv -f "$_mg_fx_clean" "$CONF" 2>/dev/null || true
    fi
  fi
  rm -f "$_mg_fx_move" "$_mg_fx_clean" "$_mg_fx_final" 2>/dev/null
  chmod 600 "$CONF" 2>/dev/null || true


  # 2.5) v1.10.7 及更早的 default.conf 默认开启了两个「在线订阅示例」（adguard
  #      filter_24 / hagezi pro）。v1.10.8 起要求所有规则默认关闭、独立启停；
  #      升级时只把这两条**模块内置示例 URL** 的启用位改成 0，用户自加的一律不动。
  #      好处：首次「应用」不再因为 GitHub raw 不可达而报 1 处失败（真机实测）。
  #      只做一次：迁移标记存在后不再动，否则用户之后在 WebUI 重新勾选会被反复改回 0。
  _mg_off_mark="$PG/cache/migrate-1108-off.done"
  if [ ! -f "$_mg_off_mark" ]; then
    _mg_old_a='https://adguardteam.github.io/HostlistsRegistry/assets/filter_24.txt'
    _mg_old_b='https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt'
    _mg_off="$PG/cache/migrate.off.$$.tmp"
    if awk -F'|' -v OFS='|' -v a="$_mg_old_a" -v b="$_mg_old_b" '
      /^[[:space:]]*#/ { print; next }
      (NF >= 3 && ($1 == a || $1 == b) && $NF == "1") { $NF = "0"; print; next }
      { print }
    ' "$CONF" > "$_mg_off" 2>/dev/null; then
      mv -f "$_mg_off" "$CONF" 2>/dev/null && pg_log "migrate: 模块示例在线订阅已默认关闭(如有)"
    fi
    rm -f "$_mg_off" 2>/dev/null
    chmod 600 "$CONF" 2>/dev/null || true
    : > "$_mg_off_mark" 2>/dev/null || true
  fi

  # 3) 升级时为旧 settings.conf 补入 FX 内置源。旧代码引用从未赋值的
  # $_mg_i1/$_mg_i2，导致该通用插入分支永远跳过，旧安装不会收到新内置条目。
  # 保留用户已存在/已停用的同 ID 项，不重复添加，也不改写用户启用状态。
  _mg_96110_candidate='fxfile://96110_candidate|96110 相关社区候选域名（来源动作冲突；精确域名，默认关闭）|0'
  if ! pg_list fx 2>/dev/null | grep -Fq 'fxfile://96110_candidate'; then
    _mg_96110_tmp="$PG/cache/migrate-fx-96110-candidate.$$.tmp"
    if grep -q '^\[list:fx\]' "$CONF" 2>/dev/null; then
      if awk -v entry="$_mg_96110_candidate" '
        /^\[list:fx\][[:space:]]*$/ && !added { print; print entry; added=1; inlist=1; next }
        /^\[/ { inlist=0 }
        { print }
        END { if (!added) { print ""; print "[list:fx]"; print entry } }
      ' "$CONF" > "$_mg_96110_tmp" 2>/dev/null && mv -f "$_mg_96110_tmp" "$CONF" 2>/dev/null; then
        chmod 600 "$CONF" 2>/dev/null || true
        pg_log 'migrate: 96110 community candidate registered as a separate optional FX source' 2>/dev/null || true
      else
        pg_log 'migrate: ERROR unable to register 96110 candidate; will retry next apply' 2>/dev/null || true
      fi
    fi
    rm -f "$_mg_96110_tmp" 2>/dev/null || true
  fi
  _mg_fx_entry='fxfile://anti_fraud_96110|FX 专用反诈中心域名/IP 规则（源自 FX.txt 的限定区段）|1'
  if ! pg_list fx 2>/dev/null | grep -Fq 'fxfile://anti_fraud_96110'; then
    _mg_fx_tmp="$PG/cache/migrate-fx-source.$$.tmp"
    if grep -q '^\[list:fx\]' "$CONF" 2>/dev/null; then
      if awk -v entry="$_mg_fx_entry" '
        /^\[list:fx\][[:space:]]*$/ && !added { print; print entry; added=1; inlist=1; next }
        /^\[/ { inlist=0 }
        { print }
        END { if (!added) { print ""; print "[list:fx]"; print entry } }
      ' "$CONF" > "$_mg_fx_tmp" 2>/dev/null && mv -f "$_mg_fx_tmp" "$CONF" 2>/dev/null; then
        chmod 600 "$CONF" 2>/dev/null || true
        pg_log 'migrate: bundled FX anti-fraud source registered in [list:fx]' 2>/dev/null || true
      else
        pg_log 'migrate: ERROR unable to register bundled FX source; will retry next apply' 2>/dev/null || true
      fi
    else
      if { cat "$CONF"; printf '\n[list:fx]\n%s\n' "$_mg_fx_entry"; } > "$_mg_fx_tmp" 2>/dev/null && mv -f "$_mg_fx_tmp" "$CONF" 2>/dev/null; then
        chmod 600 "$CONF" 2>/dev/null || true
        pg_log 'migrate: created [list:fx] and registered bundled FX source' 2>/dev/null || true
      else
        pg_log 'migrate: ERROR unable to create [list:fx]; will retry next apply' 2>/dev/null || true
      fi
    fi
    rm -f "$_mg_fx_tmp" 2>/dev/null || true
  fi

  # Final local-source catalog pass v3 runs AFTER all legacy list moves/additions.
  # This catches duplicates reintroduced from [list:fx] by the late legacy repair,
  # preserves the first row's enable flag, disables redundant online copies, and
  # leaves every unrelated/user-added source line untouched.
  _mg_local_final_mark="$PG/cache/rule_catalog_final_local_sources_v3.done"
  if [ ! -f "$_mg_local_final_mark" ]; then
    _mg_local_final_tmp="$PG/cache/rule-catalog-final-local.$$.tmp"
    if awk -F'|' -v OFS='|' '
      BEGIN {
        localKey[++localN]="builtin://NoAppDownload.txt"; localLabel[localKey[localN]]="【网页去开屏/跳转提示】NoAppDownload 本地网页打开App/下载提示规则"
        localKey[++localN]="builtin://Adblock_Watermark.txt"; localLabel[localKey[localN]]="【网页去水印】内置DOM/CSS水印元素（不擦除已合成进图片/视频像素的水印）"
        localKey[++localN]="builtin://RunningCheese_Watermark.txt"; localLabel[localKey[localN]]="【网页去水印补充】RunningCheese网页水印本地兼容规则"
        localKey[++localN]="builtin://RunningCheese_Popup.txt"; localLabel[localKey[localN]]="【网页去弹窗补充】RunningCheese网页浮层/弹窗本地兼容规则"
        localKey[++localN]="builtin://AdultSite_Elements_EasyList.txt"; localLabel[localKey[localN]]="【成人网站广告元素】EasyList本地站点广告元素（安全CSS兼容子集）"
        localKey[++localN]="builtin://AdultSite_AdPopup.txt"; localLabel[localKey[localN]]="【成人网站去广告弹窗】内置广告层/弹窗选择器（保护正文、评论与播放器）"
        localKey[++localN]="builtin://Adblock_Warning_Removal.txt"; localLabel[localKey[localN]]="【去反广告拦截提示】内置网页反广告拦截提醒元素规则"
        localKey[++localN]="builtin://AdultSite_AdHosts.txt"; localLabel[localKey[localN]]="【成人广告网络域名】内置成人广告供应商/弹窗域名（不屏蔽成人内容站根域）"
        localKey[++localN]="builtin://AdultSite_AdServers.txt"; localLabel[localKey[localN]]="【成人广告服务器请求】EasyList本地成人广告/追踪服务器"
        localKey[++localN]="builtin://AdultSite_Allowlist.txt"; localLabel[localKey[localN]]="【成人站点资源白名单】EasyList本地资源例外规则"
        localKey[++localN]="builtin://AdultSite_AdServersPopup.txt"; localLabel[localKey[localN]]="【成人广告服务器弹窗】EasyList本地弹窗/Popunder域名规则"
        localKey[++localN]="builtin://AdultSite_SitePopup.txt"; localLabel[localKey[localN]]="【成人网站站点弹窗】EasyList本地站点专用弹窗/跳转规则"
        localKey[++localN]="builtin://AdultSite_ThirdPartyPopup.txt"; localLabel[localKey[localN]]="【成人第三方弹窗】EasyList本地第三方弹窗规则"
        localKey[++localN]="builtin://AdultSite_RequestRules.txt"; localLabel[localKey[localN]]="【成人网站专用请求过滤】EasyList本地站点路径/脚本/资源规则"
        localKey[++localN]="builtin://AdultSite_ThirdParty.txt"; localLabel[localKey[localN]]="【成人网站第三方资源】EasyList本地第三方广告/资源规则"
        onlineKey[++onlineN]="https://raw.githubusercontent.com/Noyllopa/NoAppDownload/master/NoAppDownload.txt"
        onlineKey[++onlineN]="https://cdn.jsdelivr.net/gh/Noyllopa/NoAppDownload@master/NoAppDownload.txt"
        onlineKey[++onlineN]="https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_specific_hide.txt"
        onlineKey[++onlineN]="https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_adservers.txt"
        onlineKey[++onlineN]="https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_allowlist.txt"
        onlineKey[++onlineN]="https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_adservers_popup.txt"
        onlineKey[++onlineN]="https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_specific_block_popup.txt"
        onlineKey[++onlineN]="https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_thirdparty_popup.txt"
        onlineKey[++onlineN]="https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_specific_block.txt"
        onlineKey[++onlineN]="https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_thirdparty.txt"
        onlineKey[++onlineN]="https://raw.githubusercontent.com/runningcheese/RunningCheese-Firefox/master/Restore/Adblock_Watermark.txt"
        onlineKey[++onlineN]="https://raw.githubusercontent.com/runningcheese/RunningCheese-Firefox/master/Restore/Adblock_Popup.txt"
        for (i=1;i<=onlineN;i++) online[onlineKey[i]]=1
      }
      function emitmissing(    i,k) {
        if (didmissing) return
        for (i=1;i<=localN;i++) {
          k=localKey[i]
          if (!(k in seenLocal)) {
            print k,localLabel[k],"1"
            seenLocal[k]=1
          }
        }
        didmissing=1
      }
      /^\[list:rule\][[:space:]]*$/ { if (inrule) emitmissing(); inrule=1; seenRule=1; print; next }
      /^\[/ { if (inrule) emitmissing(); inrule=0; print; next }
      inrule && NF {
        n=split($0,a,"|")
        if (n>=3 && (a[1] in localLabel)) {
          if (a[1] in seenLocal) next
          seenLocal[a[1]]=1
          a[2]=localLabel[a[1]]
          $0=a[1] OFS a[2] OFS a[3]
        } else if (n>=3 && (a[1] in online)) {
          if (a[1] in seenOnline) next
          seenOnline[a[1]]=1
          a[2]="【在线备用】同类规则已随模块本地内置，默认关闭"
          a[3]="0"
          $0=a[1] OFS a[2] OFS a[3]
        }
      }
      { print }
      END { if (inrule) emitmissing(); if (!seenRule) { print "[list:rule]"; inrule=1; emitmissing() } }
    ' "$CONF" > "$_mg_local_final_tmp" 2>/dev/null && mv -f "$_mg_local_final_tmp" "$CONF" 2>/dev/null; then
      : > "$_mg_local_final_mark" 2>/dev/null || true
      pg_log 'migrate: final local-source normalization completed after all legacy additions; local IDs deduplicated and online copies disabled' 2>/dev/null || true
    else
      pg_log 'migrate: final local-source normalization failed; will retry next apply' 2>/dev/null || true
    fi
    rm -f "$_mg_local_final_tmp" 2>/dev/null || true
    chmod 600 "$CONF" 2>/dev/null || true
  fi

  # Retire the old MITM/WAF/IP category toggles. Any user-authored rows in the old
  # [conf:mitm_block]/[conf:waf_block] sections become ordinary [list:block] rows,
  # each with its own enabled flag. The old category flag is used only once to keep
  # previously-active rows active and previously-disabled rows disabled.
  _mrb_marker="$PG/cache/migrate-legacy-block-rows-v1.done"
  if [ ! -f "$_mrb_marker" ]; then
    _mrb_ok=1
    _mrb_candidates="$PG/cache/legacy-block-rows.$$.tmp"
    _mrb_existing="$PG/cache/legacy-block-existing.$$.tmp"
    _mrb_final="$PG/cache/legacy-block-filtered.$$.tmp"
    _mrb_conf_tmp="$PG/cache/settings-legacy-block.$$.tmp"
    _mrb_existing_seen="$PG/cache/legacy-block-seen.$$.tmp"
    : > "$_mrb_candidates" 2>/dev/null || _mrb_ok=0
    _mrb_mitm_on=$(pg_get mitm_block 0)
    [ "$_mrb_mitm_on" = "1" ] || _mrb_mitm_on=0
    _mrb_waf_on=$(pg_get waf_block 0)
    [ "$_mrb_waf_on" = "1" ] || _mrb_waf_on=0
    if [ "$_mrb_ok" = "1" ]; then
      pg_conf mitm_block 2>/dev/null | awk -v on="$_mrb_mitm_on" '
        {sub(/\r$/, ""); sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, "")}
        /^[[:space:]]*(#|$)/ {next}
        /^([0-9]+\.){3}[0-9]+(\/[0-9]+)?$/ || (index($0, ":") && $0 ~ /^[0-9A-Fa-f:.\/]+$/) {
          print $0 "|旧 MITM 网关 IP 规则|" on
        }
      ' >> "$_mrb_candidates" || _mrb_ok=0
      pg_conf waf_block 2>/dev/null | awk -v on="$_mrb_waf_on" '
        {sub(/\r$/, ""); sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, "")}
        /^[[:space:]]*(#|$)/ {next}
        /^([0-9]+\.){3}[0-9]+(\/[0-9]+)?$/ || (index($0, ":") && $0 ~ /^[0-9A-Fa-f:.\/]+$/) || ($0 ~ /^[A-Za-z0-9.-]+$/ && $0 ~ /\./ && $0 !~ /[.][.]|^[.]|[.]$/) {
          print $0 "|旧 IP/网段黑名单规则|" on
        }
      ' >> "$_mrb_candidates" || _mrb_ok=0
    fi
    if [ "$_mrb_ok" = "1" ]; then
      awk -F'|' '!seen[$1]++' "$_mrb_candidates" > "$_mrb_final" || _mrb_ok=0
    fi
    if [ "$_mrb_ok" = "1" ] && [ -s "$_mrb_final" ]; then
      # Existing per-rule items win over legacy duplicates. A backup is required before
      # the first rewrite; the completion marker is only published after atomic commit.
      pg_list block 2>/dev/null | awk -F'|' 'NF && $1!="" {print $1}' > "$_mrb_existing" || _mrb_ok=0
      [ -s "$_mrb_existing" ] || printf '
' > "$_mrb_existing"
      if [ "$_mrb_ok" = "1" ]; then
        awk -F'|' 'NR==FNR {seen[$1]=1; next} !seen[$1]++ {print}' "$_mrb_existing" "$_mrb_final" > "$_mrb_candidates" || _mrb_ok=0
      fi
      if [ "$_mrb_ok" = "1" ] && [ -s "$_mrb_candidates" ]; then
        _mrb_backup="$PG/cache/settings.conf.pre-per-rule-block-v1.bak"
        [ -f "$_mrb_backup" ] || cp -p "$CONF" "$_mrb_backup" 2>/dev/null || _mrb_ok=0
        if [ "$_mrb_ok" = "1" ]; then
          awk -F'|' '
            FNR==NR { n=split($0,a,"|"); if(n>=3 && a[1]!="" && !(a[1] in candidate)) {candidate[a[1]]=$0; order[++cn]=a[1]} next }
            function emit( i,k) { if(done) return; for(i=1;i<=cn;i++){k=order[i]; if(!(k in seen)) print candidate[k]} done=1 }
            /^\[list:block\][[:space:]]*$/ { if(inblock && !done) emit(); inblock=1; found=1; print; next }
            /^\[/ { if(inblock && !done) emit(); inblock=0; print; next }
            inblock && !/^[[:space:]]*#/ && NF { split($0,a,"|"); if(a[1]!="") seen[a[1]]=1 }
            { print }
            END { if(inblock && !done) emit(); if(!found){ print ""; print "[list:block]"; emit() } }
          ' "$_mrb_candidates" "$CONF" > "$_mrb_conf_tmp" 2>/dev/null && mv -f "$_mrb_conf_tmp" "$CONF" 2>/dev/null || _mrb_ok=0
          if [ "$_mrb_ok" = "1" ]; then chmod 600 "$CONF" 2>/dev/null || true; fi
        fi
      fi
    fi
    if [ "$_mrb_ok" = "1" ]; then
      : > "$_mrb_marker" 2>/dev/null || _mrb_ok=0
      pg_log "migrate: legacy MITM/WAF IP/domain rows migrated to individually enabled [list:block] entries" 2>/dev/null || true
    else
      pg_log "migrate: legacy per-rule block migration failed; backup/marker withheld so next apply can retry" 2>/dev/null || true
    fi
    rm -f "$_mrb_candidates" "$_mrb_existing" "$_mrb_final" "$_mrb_conf_tmp" "$_mrb_existing_seen" 2>/dev/null || true
  fi

}

