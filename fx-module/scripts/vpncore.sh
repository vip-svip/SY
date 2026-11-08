#!/system/bin/sh
# ============================================================
# PrivacyGuard vpncore.sh — 本地代理核心（sing-box）自动管理
#   让「导入节点即可用」：端口无监听时自动下载 sing-box、
#   依据 [list:vpn_node] 生成配置并启动，无需用户自建核心。
#
# 被 apply.sh source，也可独立执行：
#   sh vpncore.sh ensure    确保本地端口已监听（缺失则下载/启动）
#   sh vpncore.sh stop      停止核心
#   sh vpncore.sh status    输出 JSON {"ok":1,"running":0|1,"ver":"...","arch":"..."}
#   sh vpncore.sh genconf   仅重新生成 $PG/singbox.json
#
# 依赖 util.sh（pg_log/pg_conf/pg_list_enabled/pg_fetch/pg_have/pg_get）
# 配置来源：顶层 vpn_core / [conf:vpn] 的 core_* 键 + [list:vpn_node]
# ============================================================
SINGBOX_VER_DEFAULT=1.14.3
SINGBOX_BASE_URL="${SINGBOX_BASE_URL:-https://github.com/SagerNet/sing-box/releases/download}"

# ---- [conf:vpn] 段取值（pg_get 只读顶层键，段内键必须走 pg_conf）----
vpncore_conf() {
  pg_conf vpn 2>/dev/null | grep -m1 "^$1=" | cut -d= -f2- | tr -d ' '
}

# ---- 架构映射：Android ABI → sing-box release 资产名 ----
vpncore_arch() {
  _a=$(getprop ro.product.cpu.abi 2>/dev/null)
  [ -z "$_a" ] && _a=$(uname -m 2>/dev/null)
  case "$_a" in
      --emit-rulesets) set -- emit-rulesets ;;
    arm64*|aarch64) echo "arm64" ;;
    armv7*|armeabi*) echo "arm" ;;
    x86_64|amd64) echo "amd64" ;;
    i?86|*86*) echo "386" ;;
    *) echo "arm64" ;;
  esac
}

vpncore_ver() {
  _v=$(vpncore_conf core_ver)
  [ -z "$_v" ] && _v="$SINGBOX_VER_DEFAULT"
  echo "$_v"
}

# ---- 内核版本探测（用于版本自适应生成配置）----
# 真实 sing-box 的 `version` 首行形如 "sing-box version 1.14.3"；
# 测试桩/非 sing-box 可执行文件不输出该行 → 返回空，调用方回退 core_ver。
vpncore_bin_version() {
  _bv_b="$1"
  if [ -n "$_bv_b" ] && [ -x "$_bv_b" ]; then
    "$_bv_b" version 2>/dev/null | sed -n 's/^[[:space:]]*sing-box version[[:space:]]\{1,\}v\{0,1\}\([0-9][0-9.]*\).*/\1/p' | head -n1
  fi
}

# 生成配置实际使用的版本：二进制可识别优先，否则 [conf:vpn] core_ver / 内置默认
vpncore_core_version() {
  _cv_bv=$(vpncore_bin_version "${1:-$(vpncore_bin)}")
  case "$_cv_bv" in
    [0-9]*) printf '%s' "$_cv_bv" ;;
    *) vpncore_ver ;;
  esac
}

# 版本比较：A >= B 返回 0（只比 major.minor，够用且不依赖 sort -V）
vpncore_ver_ge() {
  _vg_a="$1"; _vg_b="$2"
  _vg_a1=${_vg_a%%.*}; _vg_ar=${_vg_a#*.}; _vg_a2=${_vg_ar%%.*}
  _vg_b1=${_vg_b%%.*}; _vg_br=${_vg_b#*.}; _vg_b2=${_vg_br%%.*}
  case "$_vg_a1" in ''|*[!0-9]*) _vg_a1=0 ;; esac
  case "$_vg_a2" in ''|*[!0-9]*) _vg_a2=0 ;; esac
  case "$_vg_b1" in ''|*[!0-9]*) _vg_b1=0 ;; esac
  case "$_vg_b2" in ''|*[!0-9]*) _vg_b2=0 ;; esac
  [ "$_vg_a1" -gt "$_vg_b1" ] && return 0
  [ "$_vg_a1" -lt "$_vg_b1" ] && return 1
  [ "$_vg_a2" -ge "$_vg_b2" ]
}

# ---- 定位模块目录（内置 bin/ 所在处）----
vpncore_moddir() {
  if [ -n "$PG_MODDIR" ] && [ -f "$PG_MODDIR/module.prop" ]; then echo "$PG_MODDIR"; return 0; fi
  if [ -n "$MODDIR" ] && [ -f "$MODDIR/module.prop" ]; then echo "$MODDIR"; return 0; fi
  _vd=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
  case "$_vd" in */scripts) _vd=${_vd%/scripts} ;; esac
  if [ -n "$_vd" ] && [ -f "$_vd/module.prop" ]; then echo "$_vd"; return 0; fi
  for _vd in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do
    [ -f "$_vd/module.prop" ] && { echo "$_vd"; return 0; }
  done
  return 1
}

# SHA-256 helper shared by builtin-core copy/verification. Android Toybox usually
# provides sha256sum; fail over to the applet explicitly when PATH is minimal.
vpncore_sha256() {
  _vsh_file="$1"
  [ -f "$_vsh_file" ] || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$_vsh_file" 2>/dev/null | awk 'NR==1 {print $1}'
  elif command -v toybox >/dev/null 2>&1; then
    toybox sha256sum "$_vsh_file" 2>/dev/null | awk 'NR==1 {print $1}'
  else
    return 1
  fi
}

# ---- 释放内置内核：<mod>/bin/<arch>/sing-box -> $PG/bin/sing-box ----
# 返回 0=就绪 1=无内置/校验失败 2=复制失败但模块内可直接执行。
# Never trust only byte length: a same-size but corrupted/stale executable can
# otherwise survive upgrades and fail at run time. Verify sidecar and copied bytes.
vpncore_install_builtin() {
  _arch=$(vpncore_arch)
  _md=$(vpncore_moddir) || return 1
  _src="$_md/bin/$_arch/sing-box"
  if [ ! -f "$_src" ]; then
    _avail=$(ls "$_md/bin" 2>/dev/null | grep -v '^[[:space:]]*$' | tr '\n' '/' | sed 's:/$::')
    pg_log "vpn_core: 本机架构 $(vpncore_arch) 无内置内核（模块内置：${_avail:-无}）—— 将尝试在线下载"
    return 1
  fi

  _src_expected=""
  if [ -s "$_src.sha256" ]; then
    _src_expected=$(awk 'NR==1 {print $1}' "$_src.sha256" 2>/dev/null)
    case "$_src_expected" in
      [0-9a-fA-F][0-9a-fA-F]*)
        case "$_src_expected" in *[!0-9a-fA-F]* ) _src_expected="" ;; esac
        [ "${#_src_expected}" -eq 64 ] || _src_expected="" ;;
      *) _src_expected="" ;;
    esac
  fi
  _src_actual=$(vpncore_sha256 "$_src" 2>/dev/null)
  if [ -n "$_src_expected" ]; then
    [ "$(printf '%s' "$_src_expected" | tr 'A-F' 'a-f')" = "$_src_actual" ] || {
      pg_fail vpncore "内置 sing-box SHA-256 校验失败，拒绝执行或复制：$_src"
      return 1
    }
  elif [ -n "$_src_actual" ]; then
    _src_expected=$_src_actual
    pg_log "vpn_core: 内置 sing-box 没有 SHA-256 sidecar，已在本次启动时计算基准摘要"
  else
    pg_log "vpn_core: SHA-256 工具不可用，退回旧式长度校验；无法识别同长度损坏文件"
  fi

  _dst=$(vpncore_bin)
  if [ -f "$_dst" ]; then
    _dst_sha=$(vpncore_sha256 "$_dst" 2>/dev/null)
    if [ -n "$_src_expected" ] && [ -n "$_dst_sha" ] && [ "$_dst_sha" = "$_src_expected" ]; then
      chmod 755 "$_dst" 2>/dev/null
      return 0
    fi
    if [ -z "$_src_expected" ] && [ "$(wc -c < "$_dst" 2>/dev/null)" = "$(wc -c < "$_src" 2>/dev/null)" ]; then
      chmod 755 "$_dst" 2>/dev/null
      pg_log "vpn_core: SHA-256 不可用，同长度内核沿用兼容回退"
      return 0
    fi
    pg_log "vpn_core: 已释放的 sing-box 与内置摘要不一致，执行原子修复"
  fi

  mkdir -p "$(dirname "$_dst")" 2>/dev/null || return 1
  if cp -f "$_src" "$_dst.tmp" 2>/dev/null; then
    chmod 755 "$_dst.tmp" 2>/dev/null || { rm -f "$_dst.tmp"; return 1; }
    if [ -n "$_src_expected" ]; then
      _tmp_sha=$(vpncore_sha256 "$_dst.tmp" 2>/dev/null)
      if [ -z "$_tmp_sha" ] || [ "$_tmp_sha" != "$_src_expected" ]; then
        rm -f "$_dst.tmp" 2>/dev/null
        pg_fail vpncore "内置 sing-box 复制后摘要不匹配，保留原文件：$_src"
        return 1
      fi
    fi
    if mv -f "$_dst.tmp" "$_dst" 2>/dev/null; then
      chcon u:object_r:system_file:s0 "$_dst" 2>/dev/null
      pg_log "vpn_core: 内置内核已释放并校验 ($_arch -> $_dst)"
      return 0
    fi
  fi
  rm -f "$_dst.tmp" 2>/dev/null
  if [ -x "$_src" ]; then
    pg_log "vpn_core: 复制失败，改为直接使用模块内内核 $_src"
    return 2
  fi
  pg_fail vpncore "内置内核释放失败（空间不足？）：$_src"
  return 1
}

# ---- 核心二进制路径：用户指定优先，否则 $PG/bin/sing-box ----
# 测试台可设 PGVPN_CORE_BIN 指向假 sing-box 桩（见 test-env/fakesingbox/sing-box）。
# 注意：仅当桩文件存在且可执行时才用——桩不存在则回落到正常下载流程。
# 测试台另可设 SINGBOX_SKIP_DL=1 跳过真实下载（沙盒无外网时避免挂住）。
vpncore_bin() {
  if [ -n "$PGVPN_CORE_BIN" ] && [ -x "$PGVPN_CORE_BIN" ]; then echo "$PGVPN_CORE_BIN"; return 0; fi
  _b=$(vpncore_conf core_bin)
  if [ -n "$_b" ] && [ -x "$_b" ]; then echo "$_b"; return 0; fi
  echo "$PG/bin/sing-box"
}

vpncore_cfg() { echo "$PG/singbox.json"; }
vpncore_pid() { echo "$PG/singbox.pid"; }
vpncore_log() { echo "$PG/singbox.log"; }

# Query Android's active VpnInfo instead of guessing that the first tun*/wg* link
# is the app VPN. Android can have unrelated WireGuard/Tailscale/leftover devices;
# only a unique VpnInfo row with ownerUid and vpnIface is safe for app-VPN chaining.
# Output is a single "interface|ownerUid" row. Ambiguous/missing state fails closed.
vpncore_android_active_vpn_info() {
  command -v dumpsys >/dev/null 2>&1 || return 1
  command -v ip >/dev/null 2>&1 || return 1
  _vavi_dump=$(dumpsys connectivity 2>/dev/null) || return 1
  [ -n "$_vavi_dump" ] || return 1
  _vavi_rows=$(printf '%s\n' "$_vavi_dump" | awk '
    /VpnInfo\{/ {
      if (inside && rec != "") print rec
      rec=$0; inside=1
      if (index($0, "}")) { print rec; rec=""; inside=0 }
      next
    }
    inside {
      rec=rec " " $0
      if (index($0, "}")) { print rec; rec=""; inside=0 }
    }
    END { if (inside && rec != "") print rec }
  ')
  [ -n "$_vavi_rows" ] || return 1
  _vavi_count=0
  _vavi_info=""
  while IFS= read -r _vavi_row; do
    _vavi_if=$(printf '%s\n' "$_vavi_row" | sed -n 's/.*vpnIface[[:space:]]*=[[:space:]]*\([^, }]*\).*/\1/p' | head -1)
    _vavi_uid=$(printf '%s\n' "$_vavi_row" | sed -n 's/.*ownerUid[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)
    case "$_vavi_if" in ''|*[!A-Za-z0-9_.:-]*) continue ;; esac
    case "$_vavi_uid" in ''|*[!0-9]*|0) continue ;; esac
    _vavi_count=$((_vavi_count+1))
    _vavi_info="$_vavi_if|$_vavi_uid"
  done <<__PG_VPNINFO__
$_vavi_rows
__PG_VPNINFO__
  [ "$_vavi_count" -eq 1 ] || return 1
  _vavi_if=${_vavi_info%%|*}
  _vavi_link=$(ip -o link show dev "$_vavi_if" 2>/dev/null) || return 1
  [ -n "$_vavi_link" ] || return 1
  # A stale VpnInfo row can outlive a disconnected/down tunnel during handover.
  # Binding to a present-but-DOWN device can black-hole FX node and DNS sockets;
  # treat it as unknown so apply.sh takes its safe non-interception path and the
  # external-VPN watcher retries when the interface becomes UP again.
  _vavi_flags=$(printf '%s\n' "$_vavi_link" | sed -n 's/.*<\([^>]*\)>.*/\1/p' | tr ',' '\n' | grep -x 'UP' | head -1)
  [ "$_vavi_flags" = "UP" ] || return 1
  printf '%s' "$_vavi_info"
}

# Detect the one external Android VPN interface that FX will use as its outer
# transport. Production apply.sh sets _PG_EXT_VPN_IF only from the validated VpnInfo
# above. Standalone checks may call this function without an override, in which case
# it performs the same authoritative query. Never select the first generic tunnel.
vpncore_outer_tunnel_interface() {
  [ "$(pg_get vpn_external_compat 1 2>/dev/null)" = "1" ] || return 1
  [ "$(pg_get vpn_mode direct 2>/dev/null)" != "direct" ] || return 1
  _vcoi_if="${_PG_EXT_VPN_IF:-}"
  if [ -z "$_vcoi_if" ]; then
    _vcoi_info=$(vpncore_android_active_vpn_info 2>/dev/null) || return 1
    _vcoi_if=${_vcoi_info%%|*}
  fi
  case "$_vcoi_if" in ''|*[!A-Za-z0-9_.:-]*) return 1 ;; esac
  command -v ip >/dev/null 2>&1 || return 1
  # The caller may have discovered this interface moments earlier. Revalidate
  # its live UP flag at the point of binding too: VPN handovers can leave a
  # stale VpnInfo row or bring the tunnel down between detection and config
  # generation. Existence alone is not proof that SO_BINDTODEVICE will route.
  _vcoi_link=$(ip -o link show dev "$_vcoi_if" 2>/dev/null) || return 1
  [ -n "$_vcoi_link" ] || return 1
  _vcoi_up=$(printf '%s\n' "$_vcoi_link" | sed -n 's/.*<\([^>]*\)>.*/\1/p' | tr ',' '\n' | grep -x 'UP' | head -1)
  [ "$_vcoi_up" = "UP" ] || return 1
  printf '%s' "$_vcoi_if"
}

vpncore_add_bind_interface() {
  _vobi_json="$1"; _vobi_if="$2"
  case "$_vobi_if" in ''|*[!A-Za-z0-9_.:-]*) return 1 ;; esac
  case "$_vobi_json" in *\}) ;; *) return 1 ;; esac
  # The URI converter emits a single JSON object without trailing whitespace.
  # Overriding an existing bind_interface, if any, is intentionally not attempted:
  # an unexpected format is rejected rather than risk malformed/ambiguous JSON.
  case "$_vobi_json" in *'"bind_interface"'*) return 1 ;; esac
  _vobi_prefix=${_vobi_json%?}
  printf '%s,"bind_interface":"%s"}' "$_vobi_prefix" "$_vobi_if"
}

# ---- DNS 配置段：按内核版本选择 schema ----
# sing-box 1.12 起 DNS server 改为新格式（type + server）；1.14 起旧格式
# {"tag":"remote","address":"..."} 已从内核移除，配置解析阶段直接报错退出
# （legacyDNS...RemovedMessage: "legacy DNS server formats are ... removed in
#  sing-box 1.14.0"）。因此 >=1.12 的内核生成新格式，更老的自定义核心保持旧格式。
#
# ★ 真机 1.14.3 关键结论（check 通过、run 必崩）：
#   绝不能给 local server 写 `"detour":"direct"`。1.14 运行期判定
#   「detour to an empty direct outbound makes no sense」→ run 阶段 FATAL：
#     start service: start dns-transport: start dns/udp[local]:
#     detour to an empty direct outbound makes no sense
#   `sing-box check` 只做配置解码，不校验这类运行期语义 → 漏过（这就是
#   「check 通过但代理不工作」的根因）。去掉 detour 后 run 正常。
#   同时 dns 段存在就**必须**有 route.default_domain_resolver（否则另一个 FATAL，
#   见 vpncore_resolver_json），两者是不同的问题、都要满足。
#
# 旧版（<1.12）的 address 形式同样不能带 detour：老内核里 detour 指向 direct
# 出站同样是空 direct，行为未验证过，统一去掉更安全（local DNS 本来就走直连）。
# DNS deny rules from individually enabled [list:block] entries.
# Keep exact DOMAIN and DOMAIN-SUFFIX semantics distinct; unsupported syntax is skipped.
vpncore_dns_block_rules() {
  _dbr_ver="$1"
  vpncore_ver_ge "$_dbr_ver" "1.11" || return 0
  pg_list_enabled block 2>/dev/null | while IFS= read -r _dbr_line; do
    _dbr_kind="suffix"; _dbr_domain=""
    _dbr_type=$(printf '%s\n' "$_dbr_line" | cut -d',' -f1 | tr '[:lower:]' '[:upper:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$_dbr_type" in
      DOMAIN) _dbr_domain=$(printf '%s\n' "$_dbr_line" | awk -F',' '{a=toupper($1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", a); act=toupper($3); gsub(/^[[:space:]]+|[[:space:]]+$/, "", act); d=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", d); if(a=="DOMAIN" && (act=="" || act=="REJECT" || act=="REJECT-DROP" || act=="BLOCK" || act=="DROP" || act=="DENY")) print d}'); _dbr_kind="exact" ;;
      DOMAIN-SUFFIX) _dbr_domain=$(printf '%s\n' "$_dbr_line" | awk -F',' '{a=toupper($1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", a); act=toupper($3); gsub(/^[[:space:]]+|[[:space:]]+$/, "", act); d=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", d); if(a=="DOMAIN-SUFFIX" && (act=="" || act=="REJECT" || act=="REJECT-DROP" || act=="BLOCK" || act=="DROP" || act=="DENY")) print d}'); _dbr_kind="suffix" ;;
      DOMAIN-REGEX)
        # Preserve commas inside the regex: only the first and final CSV fields are structural.
        _dbr_regex_line=$(printf '%s' "$_dbr_line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        _dbr_regex_body=${_dbr_regex_line#*,}
        [ "$_dbr_regex_body" != "$_dbr_regex_line" ] || continue
        _dbr_regex_action=${_dbr_regex_body##*,}
        _dbr_regex_action=$(printf '%s' "$_dbr_regex_action" | tr '[:lower:]' '[:upper:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        case "$_dbr_regex_action" in
          REJECT|REJECT-DROP|BLOCK|DROP|DENY) _dbr_domain=${_dbr_regex_body%,*} ;;
          *) _dbr_domain="$_dbr_regex_body" ;;
        esac
        _dbr_domain=$(printf '%s' "$_dbr_domain" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -n "$_dbr_domain" ] && [ "${#_dbr_domain}" -le 512 ] || continue
        case "$_dbr_domain" in *[!\ -~]*) continue ;; esac
        _dbr_json=$(printf '%s' "$_dbr_domain" | sed 's/\\/\\\\/g; s/"/\\"/g')
        printf '{"domain_regex":["%s"],"action":"reject"},' "$_dbr_json"
        continue ;;
      '||'*)
        # Only the unmodified hostname rule has a safe suffix equivalent here.
        # AdGuard modifiers (notably $important, $badfilter, $denyallow and
        # $match-case) alter priority or matching semantics; keep them in the
        # request-aware filter engine instead of silently flattening them.
        case "$_dbr_line" in *'^') ;; *) continue ;; esac
        _dbr_domain=${_dbr_line#||}
        _dbr_domain=${_dbr_domain%\^}
        _dbr_kind="suffix"
        ;;
      /*/)
        # AdGuard DNS regex form: /pattern/. Do not interpret exception rules as blocks.
        _dbr_domain=${_dbr_line#*/}
        _dbr_domain=${_dbr_domain%/*}
        [ -n "$_dbr_domain" ] && [ "${#_dbr_domain}" -le 512 ] || continue
        case "$_dbr_domain" in *[!\ -~]*) continue ;; esac
        _dbr_json=$(printf '%s' "$_dbr_domain" | sed 's/\\/\\\\/g; s/"/\\"/g')
        printf '{"domain_regex":["%s"],"action":"reject"},' "$_dbr_json"
        continue
        ;;
      SRC-IP-CIDR)
        # sing-box route rule field: source_ip_cidr. Clash writes SRC-IP-CIDR.
        _dbr_domain=$(printf '%s\n' "$_dbr_line" | awk -F',' '{a=toupper($1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", a); d=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", d); if(a=="SRC-IP-CIDR" \|\| a=="SRC-IP-CIDR6") print d}')
        case "$_dbr_domain" in
          *:*|*.*) ;;
          *) continue ;;
        esac
        _dbr_json=$(printf '%s' "$_dbr_domain" | sed 's/\\/\\\\/g; s/"/\\"/g')
        printf '{"source_ip_cidr":["%s"],"action":"reject"},' "$_dbr_json"
        continue
        ;;
      DST-PORT)
        # sing-box route rule field: port / port_range.
        _dbr_domain=$(printf '%s\n' "$_dbr_line" | awk -F',' '{a=toupper($1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", a); d=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", d); if(a=="DST-PORT") print d}')
        case "$_dbr_domain" in ''|*[!0-9,-]*) continue ;; esac
        case "$_dbr_domain" in
          *-*) printf '{"port_range":["%s"],"action":"reject"},' "$_dbr_domain" ;;
          *)   printf '{"port":["%s"],"action":"reject"},' "$_dbr_domain" ;;
        esac
        continue
        ;;
      DOMAIN-KEYWORD)
        _dbr_domain=$(printf '%s\n' "$_dbr_line" | awk -F',' '{a=toupper($1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", a); act=toupper($3); gsub(/^[[:space:]]+|[[:space:]]+$/, "", act); d=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", d); if(a=="DOMAIN-KEYWORD" && (act=="" || act=="REJECT" || act=="REJECT-DROP" || act=="BLOCK" || act=="DROP" || act=="DENY")) print d}')
        _dbr_domain=$(printf '%s' "$_dbr_domain" | tr 'A-Z' 'a-z' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        case "$_dbr_domain" in ''|*[!a-z0-9._-]*) continue ;; esac
        printf '{"domain_keyword":["%s"],"action":"reject"},' "$_dbr_domain"
        continue
        ;;
      0.0.0.0\ *|127.0.0.1\ *|::1\ *) _dbr_domain=$(printf '%s\n' "$_dbr_line" | awk '{$1=""; sub(/^ /,""); print}'); _dbr_kind="exact" ;;
      IP-CIDR,*|IP-CIDR6,*|MIXED-IP-CIDR,*|DOMAIN-KEYWORD,*|DOMAIN-REGEX,*|RULE-SET,*|PROCESS-NAME,*|USER-AGENT,*|URL-REGEX,*) continue ;;
      *) _dbr_domain="$_dbr_line"; _dbr_kind="exact" ;;
    esac
    _dbr_domain=$(printf '%s' "$_dbr_domain" | tr 'A-Z' 'a-z' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^\*\.//')
    case "$_dbr_domain" in *.*) ;; *) continue ;; esac
    case "$_dbr_domain" in *[!a-z0-9.-]*|*.|.*|*..*|-*|*.-*|*-.*) continue ;; esac
    _dbr_valid=$(printf '%s\n' "$_dbr_domain" | awk -F. 'length($0)>253 {exit 1} {for(i=1;i<=NF;i++) if(length($i)<1 || length($i)>63 || $i !~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/) exit 1; print "ok"}') || continue
    [ "$_dbr_valid" = ok ] || continue
    _dbr_allowed=0
    while IFS= read -r _dbr_wl; do
      _dbr_wl=$(printf '%s' "$_dbr_wl" | tr 'A-Z' 'a-z' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^\*\.//')
      case "$_dbr_wl" in *.*) ;; *) continue ;; esac
      case "$_dbr_domain" in "$_dbr_wl"|*."$_dbr_wl") _dbr_allowed=1; break ;; esac
    done <<EOF_WL
$(pg_list_enabled domain 2>/dev/null)
EOF_WL
    [ "$_dbr_allowed" = 0 ] || continue
    if [ "$_dbr_kind" = exact ]; then printf '{"domain":["%s"],"action":"reject"},' "$_dbr_domain"
    else printf '{"domain_suffix":["%s"],"action":"reject"},' "$_dbr_domain"; fi
  done
}

# Emit optional DNS cache policy for all subsequent route actions.
# The controls are scoped to [conf:vpn]; unsupported version-specific fields are omitted.
vpncore_dns_cache_options() {
  _dco_ver="$1"
  vpncore_ver_ge "$_dco_ver" "1.11" || return 0
  _dco_disable=$(vpncore_conf dns_disable_cache)
  _dco_optimistic=$(vpncore_conf dns_disable_optimistic_cache)
  _dco_ttl=$(vpncore_conf dns_rewrite_ttl)
  _dco_fields=""
  case "$_dco_disable" in 1|true|yes) _dco_fields='"disable_cache":true' ;; esac
  if vpncore_ver_ge "$_dco_ver" "1.14"; then
    case "$_dco_optimistic" in 1|true|yes)
      [ -n "$_dco_fields" ] && _dco_fields="$_dco_fields,"
      _dco_fields="${_dco_fields}\"disable_optimistic_cache\":true"
      ;;
    esac
  fi
  case "$_dco_ttl" in ''|*[!0-9]*) _dco_ttl=0 ;; esac
  if [ "$_dco_ttl" -gt 0 ] 2>/dev/null && [ "$_dco_ttl" -le 86400 ] 2>/dev/null; then
    [ -n "$_dco_fields" ] && _dco_fields="$_dco_fields,"
    _dco_fields="${_dco_fields}\"rewrite_ttl\":$_dco_ttl"
  fi
  [ -n "$_dco_fields" ] && printf '{"action":"route-options",%s},' "$_dco_fields"
}

# Emit whitelist routing exceptions before deny rules. sing-box DNS rules are first-match:
# a whitelist domain_suffix must precede a broader blocked suffix to actually override it.
vpncore_dns_whitelist_rules() {
  _dwr_ver="$1"
  _dwr_modern=0
  vpncore_ver_ge "$_dwr_ver" "1.11" && _dwr_modern=1
  # DNS route action remains supported in sing-box 1.14+; server is its required target.
  {
    pg_list_enabled domain 2>/dev/null
    # The hosts parser persists only validated @@||domain^ exceptions here.
    # Reuse that generated cache so subscription exceptions also apply to VPN DNS.
    [ -s "$PG/cache/wlexc.tmp" ] && cat "$PG/cache/wlexc.tmp"
  } | while IFS= read -r _dwr_domain; do
    # wlexc.tmp stores Adblock-style exceptions (for example @@||example.com^),
    # while pg_list_enabled emits plain domain names. Normalize only the exact
    # wrapper markers; malformed exception syntax remains invalid and is rejected below.
    _dwr_domain=$(printf '%s' "$_dwr_domain" | tr 'A-Z' 'a-z' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^@@||//;s/\^$//;s/^\*\.//')
    case "$_dwr_domain" in *.*) ;; *) continue ;; esac
    case "$_dwr_domain" in *[!a-z0-9.-]*|*.|.*|*..*|-*|*.-*|*-.*) continue ;; esac
    _dwr_valid=$(printf '%s\n' "$_dwr_domain" | awk -F. 'length($0)>253 {exit 1} {for(i=1;i<=NF;i++) if(length($i)<1 || length($i)>63 || $i !~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/) exit 1; print "ok"}') || continue
    [ "$_dwr_valid" = ok ] || continue
    if [ "$_dwr_modern" = 1 ]; then
      printf '{"domain_suffix":["%s"],"action":"route","server":"remote-1"},' "$_dwr_domain"
    else
      printf '{"domain_suffix":["%s"],"server":"remote-1"},' "$_dwr_domain"
    fi
  done
}

# DNS endpoint grammar follows the useful Shadowrocket forms:
#   IP[:port], udp://, tcp://, tls://, quic://, https://, h3://
# Append #proxy (or #proxy=selected) to send that resolver's own socket through
# the currently selected FX proxy node. Resolver-host bootstrap always uses
# the direct local-1 server to avoid a DNS -> proxy -> DNS dependency loop.
vpncore_dns_ipv6_valid() {
  printf '%s\n' "$1" | awk '
    /:::/ {exit 1}
    {
      value=$0
      position=index(value,"::")
      count=0
      if(position) {
        left=substr(value,1,position-1)
        right=substr(value,position+2)
        if(index(right,"::")) exit 1
        if(left!="") {
          n=split(left,a,":")
          for(i=1;i<=n;i++) if(length(a[i])<1 || length(a[i])>4 || a[i]!~/^[0-9A-Fa-f]+$/) exit 1
          count+=n
        }
        if(right!="") {
          n=split(right,b,":")
          for(i=1;i<=n;i++) if(length(b[i])<1 || length(b[i])>4 || b[i]!~/^[0-9A-Fa-f]+$/) exit 1
          count+=n
        }
        if(count>=8) exit 1
      } else {
        n=split(value,a,":")
        if(n!=8) exit 1
        for(i=1;i<=n;i++) if(length(a[i])<1 || length(a[i])>4 || a[i]!~/^[0-9A-Fa-f]+$/) exit 1
      }
    }
  '
}
vpncore_dns_host_kind() {
  _host=$1
  case "$_host" in
    *:*)
      vpncore_dns_ipv6_valid "$_host" || return 1
      printf ip
      ;;
    *[!0-9.]*)
      printf '%s\n' "$_host" | awk '
        BEGIN { FS="."; ok=1 }
        length($0)>253 || $0=="" {ok=0}
        {
          for(i=1;i<=NF;i++)
            if(length($i)<1 || length($i)>63 ||
               $i !~ /^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$/) ok=0
        }
        END {if(!ok)exit 1; print "domain"}
      ' || return 1
      ;;
    *)
      printf '%s\n' "$_host" | awk -F. '
        NF!=4 {exit 1}
        {
          for(i=1;i<=4;i++)
            if($i!~/^[0-9]+$/ || length($i)>3 || $i+0>255 ||
               ($i!="0" && $i~/^0/)) exit 1
          print "ip"
        }
      ' || return 1
      ;;
  esac
}
vpncore_dns_parse_endpoint() {
  _endpoint=$1
  _detour=
  case "$_endpoint" in
    *'#proxy'|*'#proxy=selected') _detour=proxy; _endpoint=${_endpoint%%#proxy*} ;;
    *'#direct') _detour=direct; _endpoint=${_endpoint%#direct} ;;
    *'#'*) return 1 ;;
  esac
  [ -n "$_endpoint" ] || return 1
  _endpoint_check=$(printf '%s' "$_endpoint" | sed 's/\[[0-9A-Fa-f:]*\]//g')
  printf '%s' "$_endpoint_check" | grep -Eq '^[A-Za-z0-9._:/?%&=+#-]+$' || return 1
  _scheme=udp
  _default_port=53
  _path=
  case "$_endpoint" in
    https://*) _scheme=https; _default_port=443; _rest=${_endpoint#https://} ;;
    h3://*) _scheme=h3; _default_port=443; _rest=${_endpoint#h3://} ;;
    quic://*) _scheme=quic; _default_port=853; _rest=${_endpoint#quic://} ;;
    tls://*) _scheme=tls; _default_port=853; _rest=${_endpoint#tls://} ;;
    tcp://*) _scheme=tcp; _default_port=53; _rest=${_endpoint#tcp://} ;;
    udp://*) _scheme=udp; _default_port=53; _rest=${_endpoint#udp://} ;;
    *://*) return 1 ;;
    *) _rest=$_endpoint ;;
  esac
  case "$_scheme" in
    https|h3)
      case "$_rest" in
        */*) _authority=${_rest%%/*}; _path=/${_rest#*/} ;;
        *) _authority=$_rest; _path=/dns-query ;;
      esac
      [ -n "$_path" ] || _path=/dns-query
      case "$_path" in /*) ;; *) return 1 ;; esac
      printf '%s' "$_path" | grep -Eq '^/[A-Za-z0-9._~%/?=&:+-]*$' || return 1
      ;;
    *) _authority=$_rest ;;
  esac
  [ -n "$_authority" ] || return 1
  _port=$_default_port
  case "$_authority" in
    \[*\]:*)
      _host=$(printf '%s' "$_authority" | sed 's/^\[\([^]]*\)\]:[0-9][0-9]*$/\1/')
      _port=$(printf '%s' "$_authority" | sed -n 's/^\[[^]]*\]:\([0-9][0-9]*\)$/\1/p')
      [ -n "$_port" ] || return 1
      ;;
    \[*\])
      _host=$(printf '%s' "$_authority" | sed 's/^\[\([^]]*\)\]$/\1/')
      ;;
    *:*)
      case "$_authority" in *:*:*) return 1 ;; esac
      _host=${_authority%%:*}
      _port=${_authority##*:}
      [ -n "$_port" ] || return 1
      ;;
    *) _host=$_authority ;;
  esac
  case "$_host" in ''|*[!A-Za-z0-9_.:-]*) return 1 ;; esac
  case "$_port" in ''|*[!0-9]*) return 1 ;; esac
  [ "$_port" -ge 1 ] && [ "$_port" -le 65535 ] || return 1
  _host_kind=$(vpncore_dns_host_kind "$_host") || return 1
  printf '%s|%s|%s|%s|%s|%s\n' "$_scheme" "$_host" "$_port" "$_path" "$_detour" "$_host_kind"
}
vpncore_dns_endpoint_object() {
  _endpoint=$1; _tag=$2; _bind_if=$3; _bootstrap_tag=$4; _group=$5; _auto_detour=${6:-}
  _parsed=$(vpncore_dns_parse_endpoint "$_endpoint") || return 1
  IFS='|' read -r _scheme _host _port _path _detour _host_kind <<EOF_DNS_ENDPOINT
$_parsed
EOF_DNS_ENDPOINT
  case "$_detour" in
    direct) _detour= ;;
    '') [ -n "$_auto_detour" ] && _detour=$_auto_detour ;;
  esac
  # A domain-name resolver cannot bootstrap itself. The direct local DNS
  # group is required to use IP literals; remote DoH/DoT/DoQ hostnames use
  # that group solely to resolve the resolver hostname.
  if [ "$_group" = local ] && [ "$_host_kind" != ip ]; then return 1; fi
  _json='{"type":"'"$_scheme"'","tag":"'"$_tag"'","server":"'"$_host"'","server_port":'"$_port"
  case "$_scheme" in https|h3) _json="$_json,\"path\":\"$_path\"" ;; esac
  case "$_scheme" in tls|quic|https|h3)
    if [ "$_host_kind" = domain ]; then
      _json="$_json,\"tls\":{\"enabled\":true,\"server_name\":\"$_host\"}"
    else
      _json="$_json,\"tls\":{\"enabled\":true}"
    fi
    ;;
  esac
  if [ "$_host_kind" = domain ]; then
    [ -n "$_bootstrap_tag" ] || return 1
    _json="$_json,\"domain_resolver\":\"$_bootstrap_tag\""
  fi
  [ "$_detour" != proxy ] || _json="$_json,\"detour\":\"proxy\""
  [ -z "$_bind_if" ] || _json="$_json,\"bind_interface\":\"$_bind_if\""
  printf '%s}' "$_json"
}
vpncore_dns_list_count() {
  _list=$1
  case "$_list" in ''|,*|*,|*,,*) return 1 ;; esac
  printf '%s\n' "$_list" | awk -F, 'NF>0 {print NF}'
}
vpncore_dns_server_objects() {
  _list=$1; _prefix=$2; _bind_if=$3; _bootstrap_tag=$4; _group=$5; _auto_detour=${6:-}
  _count=$(vpncore_dns_list_count "$_list") || return 1
  _i=0; _objects=
  while IFS= read -r _endpoint; do
    [ -n "$_endpoint" ] || return 1
    _i=$((_i+1))
    _tag="$_prefix-$_i"
    _object=$(vpncore_dns_endpoint_object "$_endpoint" "$_tag" "$_bind_if" "$_bootstrap_tag" "$_group" "$_auto_detour") || return 1
    [ -z "$_objects" ] || _objects="$_objects,"
    _objects="$_objects$_object"
  done <<EOF_DNS_ENDPOINTS
$(printf '%s\n' "$_list" | tr ',' '\n')
EOF_DNS_ENDPOINTS
  [ "$_i" -eq "$_count" ] || return 1
  printf '%s' "$_objects"
}
vpncore_dns_race_rules() {
  _list=$1; _prefix=$2; _scope=$3; _force=${4:-0}; _response_prefix=${5:-$_prefix}; _defer=${6:-0}
  _count=$(vpncore_dns_list_count "$_list") || return 1
  [ "$_count" -gt 1 ] || [ "$_force" = 1 ] || return 0
  _i=0; _rules=
  while IFS= read -r _endpoint; do
    [ -n "$_endpoint" ] || return 1
    _i=$((_i+1)); _tag="$_prefix-$_i"; _response_tag="fx-$_response_prefix-$_i"
    if [ "$_scope" = local ]; then
      _scope_json='"domain_suffix":[".cn"],'
    else
      _scope_json='"invert":true,"domain_suffix":[".cn"],'
    fi
    if [ "$_i" -eq 1 ]; then
      _evaluate='{'$_scope_json'"action":"evaluate","server":"'$_tag'","tag":"'$_response_tag'"}'
    else
      _evaluate='{'$_scope_json'"action":"evaluate","server":"'$_tag'","tag":"'$_response_tag'","speculative":true}'
    fi
    # response_rcode is a scalar in sing-box's DNS rule schema. Emit two
    # independent race matchers for each evaluated response so both successful
    # NOERROR answers and authoritative NXDOMAIN answers can win a resolver race.
    _race_noerror='{"match_response":"'$_response_tag'","response_rcode":"NOERROR","action":"respond","race":true}'
    _race_nxdomain='{"match_response":"'$_response_tag'","response_rcode":"NXDOMAIN","action":"respond","race":true}'
    [ -z "$_rules" ] || _rules="$_rules,"
    _rules="$_rules$_evaluate,$_race_noerror,$_race_nxdomain"
  done <<EOF_DNS_RACE
$(printf '%s\n' "$_list" | tr ',' '\n')
EOF_DNS_RACE
  # Preserve the first primary answer only after an optional fallback group
  # has had the opportunity to return a successful response.
  if [ "$_defer" != 1 ]; then
    _rules="$_rules,{\"match_response\":\"fx-$_response_prefix-1\",\"action\":\"respond\"}"
  fi
  printf '%s' "$_rules"
}
vpncore_dns_json() {
  _dns_rd=$1; _dns_cd=$2; _dns_bin=$3; _dns_bind_if=$4
  [ -n "$_dns_bin" ] || _dns_bin=$(vpncore_bin)
  _fx_dns_schema_version=$(vpncore_core_version "$_dns_bin")
  _dns_cache_rule=$(vpncore_dns_cache_options "$_fx_dns_schema_version" 2>/dev/null || true)
  _dns_wl_rules=$(vpncore_dns_whitelist_rules "$_fx_dns_schema_version" 2>/dev/null || true)
  _dns_block_rules=
  _fx_dns_modern=0; _fx_dns_race=0
  vpncore_ver_ge "$_fx_dns_schema_version" 1.11 && _dns_block_rules=$(vpncore_dns_block_rules "$_fx_dns_schema_version" 2>/dev/null || true)
  vpncore_ver_ge "$_fx_dns_schema_version" 1.12 && _fx_dns_modern=1
  vpncore_ver_ge "$_fx_dns_schema_version" 1.14 && _fx_dns_race=1

  # Shadowrocket-style groups: normal DNS remains separate from the optional
  # proxy DNS group so allowlisted domains never point at a missing tag.
  _dns_proxy_list=$(vpncore_conf proxy_dns_server)
  _dns_fallback_list=$(vpncore_conf fallback_dns_server)
  _dns_direct_system=$(vpncore_conf dns_direct_system)
  _dns_fallback_system=$(vpncore_conf dns_fallback_system)
  _dns_direct_fallback_proxy=$(vpncore_conf dns_direct_fallback_proxy)
  case "$_dns_direct_system" in 1) : ;; *) _dns_direct_system=0 ;; esac
  case "$_dns_fallback_system" in 1) : ;; *) _dns_fallback_system=0 ;; esac
  case "$_dns_direct_fallback_proxy" in 1) : ;; *) _dns_direct_fallback_proxy=0 ;; esac

  _remote_count=$(vpncore_dns_list_count "$_dns_rd") || {
    pg_log "vpn_core: remote DNS list is empty or malformed"; return 1;
  }
  _query_list=$_dns_rd
  _query_prefix=remote
  _query_auto_detour=
  _proxy_count=0
  if [ -n "$_dns_proxy_list" ]; then
    _proxy_count=$(vpncore_dns_list_count "$_dns_proxy_list") || {
      pg_log "vpn_core: proxy DNS list is malformed"; return 1;
    }
    _query_list=$_dns_proxy_list
    _query_prefix=proxy
    _query_auto_detour=proxy
  fi
  _query_count=$(vpncore_dns_list_count "$_query_list") || return 1
  _local_count=$(vpncore_dns_list_count "$_dns_cd") || {
    pg_log "vpn_core: direct DNS list is empty or malformed"; return 1;
  }
  _fallback_count=0
  if [ -n "$_dns_fallback_list" ]; then
    _fallback_count=$(vpncore_dns_list_count "$_dns_fallback_list") || {
      pg_log "vpn_core: fallback DNS list is malformed"; return 1;
    }
  fi

  if [ "$_fx_dns_modern" = 0 ]; then
    [ "$_remote_count" -eq 1 ] && [ "$_local_count" -eq 1 ] &&
      [ "$_fallback_count" -eq 0 ] && [ "$_proxy_count" -eq 0 ] &&
      [ "$_dns_direct_system" = 0 ] && [ "$_dns_fallback_system" = 0 ] &&
      [ "$_dns_direct_fallback_proxy" = 0 ] || {
        pg_log "vpn_core: Shadowrocket private DNS features require sing-box >=1.14"
        return 1
      }
    _remote_parsed=$(vpncore_dns_parse_endpoint "$_dns_rd") || return 1
    _local_parsed=$(vpncore_dns_parse_endpoint "$_dns_cd") || return 1
    IFS='|' read -r _rs _rh _rp _rpath _rdetour _rkind <<EOF_REMOTE_OLD
$_remote_parsed
EOF_REMOTE_OLD
    IFS='|' read -r _ls _lh _lp _lpath _ldetour _lkind <<EOF_LOCAL_OLD
$_local_parsed
EOF_LOCAL_OLD
    [ "$_rs" = udp ] && [ "$_ls" = udp ] && [ "$_rp" = 53 ] && [ "$_lp" = 53 ] &&
      [ "$_rkind" = ip ] && [ "$_lkind" = ip ] &&
      [ -z "$_rdetour" ] && [ -z "$_ldetour" ] || return 1
    if [ -n "$_dns_bind_if" ]; then
      pg_log "vpn_core: external VPN overlay requires sing-box >=1.12 for pinned DNS"
      return 1
    fi
    printf '"dns":{"servers":[{"tag":"remote-1","address":"%s"},{"tag":"local-1","address":"%s"}],"rules":[%s%s{"domain_suffix":[".cn"],"server":"local-1"}],"final":"remote-1"}' \
      "$_rh" "$_lh" "$_dns_wl_rules" "$_dns_block_rules"
    return 0
  fi
  if [ "$_fx_dns_race" = 0 ] &&
     { [ "$_remote_count" -gt 1 ] || [ "$_query_count" -gt 1 ] ||
       [ "$_local_count" -gt 1 ] || [ "$_fallback_count" -gt 0 ] ||
       [ "$_proxy_count" -gt 0 ] || [ "$_dns_direct_system" = 1 ] ||
       [ "$_dns_fallback_system" = 1 ] || [ "$_dns_direct_fallback_proxy" = 1 ]; }; then
    pg_log "vpn_core: multi-resolver/fallback DNS policy requires sing-box >=1.14"
    return 1
  fi

  _remote_objects=$(vpncore_dns_server_objects "$_dns_rd" remote "$_dns_bind_if" local-1 remote) || {
    pg_log "vpn_core: invalid normal DNS endpoint list"; return 1;
  }
  _proxy_objects=
  if [ -n "$_dns_proxy_list" ]; then
    _proxy_objects=$(vpncore_dns_server_objects "$_dns_proxy_list" proxy "$_dns_bind_if" local-1 remote proxy) || {
      pg_log "vpn_core: invalid proxy DNS endpoint list"; return 1;
    }
  fi
  _local_objects=$(vpncore_dns_server_objects "$_dns_cd" local "$_dns_bind_if" "" local) || {
    pg_log "vpn_core: invalid direct DNS endpoint list (direct resolvers must be IP literals)"; return 1;
  }
  _fallback_objects=
  if [ -n "$_dns_fallback_list" ]; then
    _fallback_objects=$(vpncore_dns_server_objects "$_dns_fallback_list" fallback "$_dns_bind_if" local-1 fallback) || {
      pg_log "vpn_core: invalid fallback DNS endpoint list"; return 1;
    }
  fi
  _direct_proxy_objects=
  if [ "$_dns_direct_fallback_proxy" = 1 ] && [ "$_proxy_count" -eq 0 ]; then
    _direct_proxy_objects=$(vpncore_dns_server_objects "$_dns_rd" direct-proxy "$_dns_bind_if" local-1 remote proxy) || {
      pg_log "vpn_core: unable to create proxy-detoured direct DNS fallback"; return 1;
    }
  fi
  _system_server='{"type":"local","tag":"system"}'

  _dns_rules=$_dns_cache_rule$_dns_wl_rules$_dns_block_rules
  [ -z "$_dns_rules" ] || _dns_rules="$_dns_rules,"
  _local_rules=

  # Direct/China DNS: configured direct resolvers first; optional fallback
  # servers follow, then optional proxy or Android/system fallback.
  if [ "$_dns_direct_system" = 1 ]; then
    _local_rules="$_local_rules{\"domain_suffix\":[\".cn\"],\"action\":\"route\",\"server\":\"system\"},"
  else
    _local_force=0
    [ "$_fallback_count" -gt 0 ] && _local_force=1
    [ "$_dns_fallback_system" = 1 ] && _local_force=1
    [ "$_dns_direct_fallback_proxy" = 1 ] && _local_force=1
    _local_primary_rules=$(vpncore_dns_race_rules "$_dns_cd" local local "$_local_force" direct-primary "$_local_force") || return 1
    [ -z "$_local_primary_rules" ] || _local_rules="$_local_rules$_local_primary_rules,"
    if [ "$_fallback_count" -gt 0 ]; then
      _local_fallback_defer=0
      { [ "$_dns_fallback_system" = 1 ] || [ "$_dns_direct_fallback_proxy" = 1 ]; } && _local_fallback_defer=1
      _local_fallback_rules=$(vpncore_dns_race_rules "$_dns_fallback_list" fallback local 1 direct-fallback "$_local_fallback_defer") || return 1
      [ -z "$_local_fallback_rules" ] || _local_rules="$_local_rules$_local_fallback_rules,"
    fi
    if [ "$_dns_direct_fallback_proxy" = 1 ]; then
      if [ "$_proxy_count" -gt 0 ]; then
        _local_proxy_list=$_dns_proxy_list
        _local_proxy_prefix=proxy
      else
        _local_proxy_list=$_dns_rd
        _local_proxy_prefix=direct-proxy
      fi
      _local_proxy_defer=0
      [ "$_dns_fallback_system" = 1 ] && _local_proxy_defer=1
      _local_proxy_rules=$(vpncore_dns_race_rules "$_local_proxy_list" "$_local_proxy_prefix" local 1 direct-proxy-fallback "$_local_proxy_defer") || return 1
      [ -z "$_local_proxy_rules" ] || _local_rules="$_local_rules$_local_proxy_rules,"
    fi
    if [ "$_local_force" = 1 ] &&
       [ "$_dns_fallback_system" != 1 ] &&
       [ "$_dns_direct_fallback_proxy" != 1 ]; then
      _local_rules="$_local_rules{\"match_response\":\"fx-direct-primary-1\",\"action\":\"respond\"},"
    fi
    if [ "$_dns_fallback_system" = 1 ]; then
      _local_final=system
    elif [ "$_dns_direct_fallback_proxy" = 1 ]; then
      if [ "$_proxy_count" -gt 0 ]; then _local_final=proxy-1
      else _local_final=direct-proxy-1; fi
    elif [ "$_fallback_count" -gt 0 ]; then
      _local_final=fallback-1
    else
      _local_final=local-1
    fi
    _local_rules="$_local_rules{\"domain_suffix\":[\".cn\"],\"action\":\"route\",\"server\":\"$_local_final\"},"
  fi

  # Non-CN/proxy DNS uses proxy_dns_server when present; normal remote DNS
  # remains available for whitelisted domains and as an independently tagged group.
  _remote_force=0
  [ "$_fallback_count" -gt 0 ] && _remote_force=1
  [ "$_dns_fallback_system" = 1 ] && _remote_force=1
  _remote_primary_rules=$(vpncore_dns_race_rules "$_query_list" "$_query_prefix" remote "$_remote_force" remote-primary "$_remote_force") || return 1
  [ -z "$_remote_primary_rules" ] || _dns_rules="$_dns_rules$_remote_primary_rules,"
  if [ "$_fallback_count" -gt 0 ]; then
    _remote_fallback_defer=0
    [ "$_dns_fallback_system" = 1 ] && _remote_fallback_defer=1
    _remote_fallback_rules=$(vpncore_dns_race_rules "$_dns_fallback_list" fallback remote 1 remote-fallback "$_remote_fallback_defer") || return 1
    [ -z "$_remote_fallback_rules" ] || _dns_rules="$_dns_rules$_remote_fallback_rules,"
  fi
  if [ "$_remote_force" = 1 ] && [ "$_dns_fallback_system" != 1 ]; then
    _dns_rules="$_dns_rules{\"match_response\":\"fx-remote-primary-1\",\"action\":\"respond\"},"
  fi
  if [ "$_dns_fallback_system" = 1 ]; then
    _remote_final=system
  elif [ "$_fallback_count" -gt 0 ]; then
    _remote_final=fallback-1
  else
    _remote_final="$_query_prefix-1"
  fi
  [ -z "$_local_rules" ] || _dns_rules="$_dns_rules$_local_rules"

  _dns_servers=$_remote_objects,$_local_objects
  [ -z "$_proxy_objects" ] || _dns_servers="$_dns_servers,$_proxy_objects"
  [ -z "$_fallback_objects" ] || _dns_servers="$_dns_servers,$_fallback_objects"
  [ -z "$_direct_proxy_objects" ] || _dns_servers="$_dns_servers,$_direct_proxy_objects"
  if [ "$_dns_fallback_system" = 1 ] || [ "$_dns_direct_system" = 1 ]; then
    _dns_servers="$_system_server,$_dns_servers"
  fi
  printf '"dns":{"servers":[%s],"rules":[%s],"final":"%s"}' "$_dns_servers" "$_dns_rules" "$_remote_final"
}
vpncore_resolver_json() {
  _rs_bin="$1"
  [ -n "$_rs_bin" ] || _rs_bin=$(vpncore_bin)
  _rs_ver=$(vpncore_core_version "$_rs_bin")
  if vpncore_ver_ge "$_rs_ver" "1.12"; then
    printf '"default_domain_resolver":{"server":"local-1"}'
  fi
}

# ---- 启动前配置预检：把 sing-box 的真实解析错误带回日志 / apply.errors ----
# 平台差异：真实 sing-box 支持 `check`；测试桩/老内核不支持时跳过，不误判为配置错误。
# 返回 0=通过/跳过，1=配置校验失败（stdout 输出一行精简原因）。
vpncore_check_conf() {
  _ck_bin="$1"; _ck_cfg="$2"
  _ck_log=$(vpncore_log)
  [ -x "$_ck_bin" ] && [ -s "$_ck_cfg" ] || return 0
  # 只有能报出版本号的才算真实 sing-box；测试桩（无 version 输出）直接跳过，
  # 避免对桩执行 check 时进入其 run 分支（桩会监听端口挂住）。
  [ -n "$(vpncore_bin_version "$_ck_bin")" ] || return 0
  if command -v pg_timeout_run >/dev/null 2>&1; then
    _ck_out=$(pg_timeout_run 15 "$_ck_bin" check -c "$_ck_cfg" 2>&1)
  else
    _ck_out=$("$_ck_bin" check -c "$_ck_cfg" 2>&1)
  fi
  _ck_rc=$?
  if [ "$_ck_rc" -eq 0 ]; then
    pg_log "vpn_core: sing-box check 通过 ($_ck_cfg)"
    return 0
  fi
  # 无输出 / unknown command 类输出 → 老内核没有 check 子命令，交给 run 阶段报错
  if [ -z "$_ck_out" ]; then
    pg_log "vpn_core: 内核不支持 check 子命令，跳过预检"
    return 0
  fi
  case "$_ck_out" in
    *"unknown command"*|*"unrecognized"*|*"available commands"*|*"flag provided but not defined"*)
      pg_log "vpn_core: 内核不支持 check 子命令，跳过预检"
      return 0 ;;
  esac
  printf '%s\n' "$_ck_out" >> "$_ck_log" 2>/dev/null
  pg_log "vpn_core: sing-box check 失败 (rc=$_ck_rc)"
  printf '%s' "$(printf '%s\n' "$_ck_out" | tr -d '\r' | grep -v '^[[:space:]]*$' | tail -n 1 | cut -c1-220)"
  return 1
}

# ---- 运行期预检：check 通过 ≠ 能跑 ----
# 真机 1.14.3 教训：`check` 只做配置解码，**不校验运行期语义**。
# 实例：dns local server 带 `"detour":"direct"` → check rc=0，但 run 立刻 FATAL
#   "start service: start dns-transport: start dns/udp[local]:
#    detour to an empty direct outbound makes no sense"
# 结果就是用户看到「配置校验通过」却永远起不来。因此这里额外做一次「短跑」：
# 用临时端口起一次 run，1.5s 内看进程是否已死，死了就把它的 FATAL 行作为原因。
# 返回 0=能跑/跳过，1=run 阶段失败（stdout 输出一行原因）
vpncore_probe_run() {
  _pr_bin="$1"; _pr_cfg="$2"
  [ -x "$_pr_bin" ] && [ -s "$_pr_cfg" ] || return 0
  [ -n "$(vpncore_bin_version "$_pr_bin")" ] || return 0   # 测试桩不短跑
  _pr_log="$PG/singbox.probe.log"
  : > "$_pr_log" 2>/dev/null
  "$_pr_bin" run -c "$_pr_cfg" < /dev/null >> "$_pr_log" 2>&1 &
  _pr_p=$!
  _pr_w=0
  while [ "$_pr_w" -lt 15 ]; do
    if ! kill -0 "$_pr_p" 2>/dev/null; then
      # 进程已退出 → 运行期失败。但如果是因为端口被占（已有核心在跑）则属正常，
      # 不该判失败——用「启动即要求监听」的语义区分：日志里出现 bind/adress in use 就跳过。
      if grep -qiE 'address already in use|bind:' "$_pr_log" 2>/dev/null; then
        rm -f "$_pr_log" 2>/dev/null
        return 0
      fi
      _pr_why=$(grep -aE 'FATAL|ERROR' "$_pr_log" 2>/dev/null | tail -n 1 | tr -d '\r' | cut -c1-220)
      pg_log "vpn_core: run 预检失败 — ${_pr_why:-进程启动即退出}"
      printf '%s' "${_pr_why:-进程启动即退出（详见 $_pr_log）}"
      rm -f "$_pr_log" 2>/dev/null
      return 1
    fi
    sleep 0.1 2>/dev/null || sleep 1
    _pr_w=$((_pr_w+1))
  done
  kill "$_pr_p" 2>/dev/null
  wait "$_pr_p" 2>/dev/null
  rm -f "$_pr_log" 2>/dev/null
  pg_log "vpn_core: run 预检通过（进程存活 1.5s）"
  return 0
}

# ---- 核心日志尾巴：失败原因回显（单行、去噪、截断，便于放进 apply.errors）----
vpncore_log_tail() {
  _lt_log=$(vpncore_log)
  [ -s "$_lt_log" ] || return 0
  tail -n 8 "$_lt_log" 2>/dev/null | tr -d '\r' | grep -v '^[[:space:]]*$' | tail -n 2 \
    | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g;s/[[:space:]]*$//' | cut -c1-240
}

# TUN readiness is independent from the legacy redirect listener. A live TCP
# port alone is not proof that sing-box created its managed interface.
vpncore_tun_interface_ready() {
  [ "$(pg_get vpn_mode direct 2>/dev/null)" = "tun" ] || return 0
  command -v ip >/dev/null 2>&1 || return 1
  _vtr_link=$(ip -o link show dev fx0 2>/dev/null) || return 1
  [ -n "$_vtr_link" ] || return 1
  _vtr_flags=$(printf '%s\n' "$_vtr_link" | sed -n 's/.*<\([^>]*\)>.*/\1/p' | tr ',' '\n' | grep -x 'UP' | head -1)
  [ "$_vtr_flags" = "UP" ]
}

vpncore_listening() {
  # 本地端口是否已 LISTEN。探测优先级：netstat、ss、/proc/net/tcp*、curl。
  # 不得仅凭 PID 存活就宣称端口就绪：iptables 已重定向而本地端口未监听时会断网。
  _lp=$(vpncore_conf local_port)
  _lp=${_lp:-7890}
  case "$_lp" in ''|*[!0-9]*) _lp=7890 ;; esac
  if pg_have netstat && netstat -tln 2>/dev/null | grep -q 'LISTEN'; then
    netstat -tln 2>/dev/null | grep -q ":${_lp}[[:space:]].*LISTEN" && return 0
    return 1
  fi
  # Android 12+ toybox 已移除 netstat，ss 是官方替代实现
  if pg_have ss && ss -tln 2>/dev/null | grep -q "LISTEN"; then
    ss -tln 2>/dev/null | grep -q ":${_lp}[[:space:]]" && return 0
    return 1
  fi
  # Android/toybox 环境可能没有 netstat/ss。直接读取内核 TCP 表，
  # 0A = LISTEN，端口使用十六进制；同时检查 IPv4 与 IPv6。
  _lp_hex=$(printf '%04X' "$_lp" 2>/dev/null)
  if [ -n "$_lp_hex" ] && [ -r /proc/net/tcp ]; then
    if awk -v p="$_lp_hex" 'NR>1 {split($2,a,":"); if (toupper(a[2])==p && $4=="0A") found=1} END {exit !found}' /proc/net/tcp 2>/dev/null; then return 0; fi
    if [ -r /proc/net/tcp6 ] && awk -v p="$_lp_hex" 'NR>1 {split($2,a,":"); if (toupper(a[2])==p && $4=="0A") found=1} END {exit !found}' /proc/net/tcp6 2>/dev/null; then return 0; fi
    return 1
  fi
  if pg_have curl; then
    curl -s --max-time 2 -o /dev/null "http://127.0.0.1:$_lp" 2>/dev/null
    case $? in 7|28) return 1 ;; esac
    return 0
  fi
  # 无可用探测器且 /proc TCP 表不可读：保持“未知”，不能把它当成就绪。
  pg_log "vpn_core: listener probe unavailable; refusing to infer readiness from PID alone"
  return 1
}

# ---- 下载 sing-box（GitHub release tar.gz）----
vpncore_download() {
  _ver=$(vpncore_ver)
  _arch=$(vpncore_arch)
  _bin=$(vpncore_bin)
  _url="$SINGBOX_BASE_URL/v$_ver/sing-box-$_ver-android-$_arch.tar.gz"
  mkdir -p "$PG/bin" "$PG/cache" 2>/dev/null
  pg_log "vpn_core: sing-box v$_ver (android-$_arch) downloading"
  _tgz="$PG/cache/sing-box-$$.tar.gz"
  if pg_fetch "$_url" "$_tgz" && [ -s "$_tgz" ]; then
    # tar.gz 解包（busybox/toybox tar 均支持 -xz）
    if tar -xzf "$_tgz" -C "$PG/bin" 2>/dev/null || busybox tar -xzf "$_tgz" -C "$PG/bin" 2>/dev/null; then
      mv -f "$PG/bin/sing-box-$_ver-android-$_arch/sing-box" "$_bin" 2>/dev/null
      rm -rf "$PG/bin/sing-box-$_ver-android-$_arch" "$_tgz" 2>/dev/null
      chmod 755 "$_bin" 2>/dev/null
      if [ -x "$_bin" ]; then
        pg_log "vpn_core: sing-box installed at $_bin"
        return 0
      fi
    fi
    _vpn_hint=$(pg_url_hint "$_url")
    pg_log "vpn_core: tar extract failed ($_vpn_hint)"
  else
    _vpn_hint=$(pg_url_hint "$_url")
    pg_log "vpn_core: download failed ($_vpn_hint) — 网络不可用或版本不存在"
  fi
  rm -f "$_tgz" 2>/dev/null
  return 1
}

# ---- PID 身份校验：按 argv 边界精确匹配本模块配置路径 ----
# 不能用命令行子串匹配：恶意/无关参数可能包含相同路径的后缀或前缀。
# 本管理器启动参数固定为 `sing-box run -c "$PG/singbox.json"`，所以
# 要求 argv[0] 的程序名确为 sing-box，且 -c/--config 的下一个独立参数
# 与本模块配置路径完全相等。无法读取或解析 cmdline 时按“不属于本模块”处理。
vpncore_pid_matches() {
  _pm_pid="$1"
  case "$_pm_pid" in ''|*[!0-9]*) return 1 ;; esac
  [ -n "$PG" ] || return 1
  [ -r "/proc/$_pm_pid/cmdline" ] || return 1
  tr '\000' '\n' < "/proc/$_pm_pid/cmdline" 2>/dev/null | awk -v cfg="$PG/singbox.json" '
    NR == 1 {
      exe = $0
      sub(/^.*\//, "", exe)
      if (exe != "sing-box") { bad = 1; exit 1 }
      next
    }
    (prev == "-c" || prev == "--config") && $0 == cfg { found = 1 }
    { prev = $0 }
    END { if (!bad && found) exit 0; exit 1 }
  '
}

# ---- 停止核心 ----
vpncore_stop() {
  _pidf=$(vpncore_pid)
  [ -f "$_pidf" ] || return 0
  _p=$(cat "$_pidf" 2>/dev/null)
  case "$_p" in ''|*[!0-9]*)
    rm -f "$_pidf"
    pg_log "vpn_core: removed malformed PID file"
    return 0
    ;;
  esac
  if ! kill -0 "$_p" 2>/dev/null || ! vpncore_pid_matches "$_p"; then
    # PID 已退出、被复用，或身份无法确认：绝不向该 PID 发送信号。
    rm -f "$_pidf"
    pg_log "vpn_core: stale PID file removed without signaling pid $_p"
    return 0
  fi
  kill "$_p" 2>/dev/null
  _sw=0
  while [ "$_sw" -lt 10 ]; do
    if ! kill -0 "$_p" 2>/dev/null || ! vpncore_pid_matches "$_p"; then break; fi
    sleep 0.2 2>/dev/null || sleep 1
    _sw=$((_sw+1))
  done
  # 仅在进程仍存活且 /proc 身份仍匹配时强制结束。
  if kill -0 "$_p" 2>/dev/null && vpncore_pid_matches "$_p"; then
    kill -9 "$_p" 2>/dev/null
    _sw2=0
    while [ "$_sw2" -lt 10 ]; do
      if ! kill -0 "$_p" 2>/dev/null || ! vpncore_pid_matches "$_p"; then break; fi
      sleep 0.1 2>/dev/null || sleep 1
      _sw2=$((_sw2+1))
    done
  fi
  # 不要在仍存活的核心上删 PID 句柄，否则下一轮会误判“核心已停止”，
  # 并在旧监听仍占端口时跳过新配置生成/启动。
  if kill -0 "$_p" 2>/dev/null && vpncore_pid_matches "$_p"; then
    pg_log "vpn_core: stop failed; process $_p still alive, preserving PID file"
    return 1
  fi
  rm -f "$_pidf"
  pg_log "vpn_core: stopped (pid $_p)"
  return 0
}

# ---- 生成 sing-box 配置（$PG/singbox.json）----
# 入站（1.14.3 真机实测结论）：
#   redirect  : 监听 [conf:vpn] local_ip:local_port —— 供 iptables -t nat REDIRECT 送入。
#               mixed 不认 SO_ORIGINAL_DST，用它做透明代理必然 400（已实测），
#               redirect 才能把原始目的地址还原（日志 "inbound connection to x.x.x.x:80"）。
#   mixed     : 监听 local_port+1 —— 供用户把浏览器/客户端显式指向该端口（客户端模式）。
# 出站 = 全部勾选节点 + selector 组 proxy（默认选中的 vpn_node）

# ---- rule_set emission ------------------------------------------------------
# The module ships its own block lists, so a set is a local file reference rather than a
# download. Sing-box reads `file://` sources as plain domain lists when the format says so.
#
# A list is only emitted when the file exists and is non-empty: an empty or missing file
# would make sing-box fail config validation with `rule-set not found`.
_vcr_ruleset_names=""

_vcr_emit_one() {
  # $1 = rule set tag, $2 = absolute path, $3 = separator (leading comma when chained)
  _vcr_eo_tag=$1
  _vcr_eo_path=$2
  _vcr_eo_sep=$3
  [ -s "$_vcr_eo_path" ] || return 0
  printf '%s{"tag":"%s","type":"local","format":"source","path":"%s"}' \
    "$_vcr_eo_sep" "$_vcr_eo_tag" "$_vcr_eo_path"
  case " $_vcr_ruleset_names " in
    *" $_vcr_eo_tag "*) : ;;
    *) _vcr_ruleset_names="$_vcr_ruleset_names $_vcr_eo_tag" ;;
  esac
}

_vcr_emit_rulesets() {
  _vcr_mod=${MODDIR:-${PG_MODDIR:-}}
  if [ -z "$_vcr_mod" ] || [ ! -d "$_vcr_mod/rulesets" ]; then
    return 0
  fi
  _vcr_out=""
  _vcr_first=1

  # Ad lists: the two categories that matter for kernel-proxy filtering. Including the
  # per-vendor privacy lists here would reject legitimate vendor domains, which is a
  # different decision than "drop ads".
  for _vcr_list in adblock_merged privacy_ad_domains privacy_splash_ad_domains privacy_antifraud_domains; do
    # vpnrule only accepts a local .json rule set (or .srs), so the sets live in
    # rulesets/, not in rulefiles/ whose format is a hosts list.
    _vcr_file="$_vcr_mod/rulesets/$_vcr_list.json"
    [ -s "$_vcr_file" ] || continue
    if [ "$_vcr_first" = 1 ]; then
      _vcr_sep=""
      _vcr_first=0
    else
      _vcr_sep=","
    fi
    _vcr_piece=$(_vcr_emit_one "$_vcr_list" "$_vcr_file" "$_vcr_sep")
    if [ -n "$_vcr_piece" ]; then
      _vcr_out="$_vcr_out$_vcr_piece"
    fi
  done

  printf '%s' "$_vcr_out"
}

# One reject rule per emitted set. Without these the sets exist but nothing consults them.
_vcr_emit_reject_rules() {
  _vcr_rr_first=1
  for _vcr_rr_name in $_vcr_ruleset_names; do
    if [ "$_vcr_rr_first" = 1 ]; then
      _vcr_rr_sep=""
      _vcr_rr_first=0
    else
      _vcr_rr_sep=","
    fi
    printf '%s{"rule_set":["%s"],"action":"reject","method":"drop"}' \
      "$_vcr_rr_sep" "$_vcr_rr_name"
  done
}

vpncore_genconf() {
  # $1 可选：实际使用的核心二进制（用于按真实版本选择 DNS schema）；
  # 独立调用（sh vpncore.sh genconf / 测试）时自动探测 vpncore_bin。
  _gc_bin="$1"
  [ -n "$_gc_bin" ] || _gc_bin=$(vpncore_bin)
  _cfg=$(vpncore_cfg)
  _gc_mode=$(pg_get vpn_mode direct 2>/dev/null)
  # Generate the complete config in a private, collision-free file in the
  # destination directory. mktemp creates it mode 0600; node credentials must
  # never be exposed through a predictable/world-readable staging path.
  _lip=$(vpncore_conf local_ip); _lip=${_lip:-127.0.0.1}
  _lport=$(vpncore_conf local_port); _lport=${_lport:-7890}
  case "$_lport" in ''|*[!0-9]*) _lport=7890 ;; esac
  # mixed 端口：可在 [conf:vpn] 用 mixed_port 覆盖；默认 local_port+1（避开 REDIRECT 目标端口）
  _mport=$(vpncore_conf mixed_port)
  case "$_mport" in ''|*[!0-9]*) _mport=$((_lport+1)) ;; esac
  _rdns=$(vpncore_conf remote_dns); _rdns=${_rdns:-1.1.1.1}
  _cdns=$(vpncore_conf cn_dns); _cdns=${_cdns:-223.5.5.5}
  _sel=$(pg_get vpn_node 2>/dev/null)
  # redirect 入站监听地址必须可被 REDIRECT 命中：仅支持 127.0.0.1 / 0.0.0.0 等本地地址，
  # 用户误填节点 IP 时回落到 127.0.0.1，避免「配置能过但流量进不来」。
  case "$_lip" in
    127.*|0.0.0.0|::1|\[::1\]) ;;
    *) _lip=127.0.0.1 ;;
  esac

  # ---- 外部 VPN 协作：不尝试启动第二个 Android VPN/TUN；把 FX 的代理节点、
  # direct outbound 与 DNS sockets 全部绑定到已有外层隧道接口。SO_BINDTODEVICE
  # 失败时只会连接失败，不允许 silently fall back 到物理 Wi-Fi/蜂窝接口。----
  _gc_bind_iface=""
  if [ "$(pg_get vpn_external_compat 1 2>/dev/null)" = "1" ] && [ "$_gc_mode" != "direct" ] && [ "$_gc_mode" != "tun" ]; then
    # External-VPN compatibility is an explicit routing contract. If the
    # tunnel vanished during handover, never silently generate unbound
    # outbounds/DNS that can escape over Wi-Fi or cellular.
    _gc_bind_iface=$(vpncore_outer_tunnel_interface 2>/dev/null) || {
      pg_fail vpncore "外部 VPN 接口不可用，拒绝生成未绑定接口的配置"
      return 1
    }
    [ -n "$_gc_bind_iface" ] || {
      pg_fail vpncore "外部 VPN 接口为空，拒绝生成未绑定接口的配置"
      return 1
    }
  fi

  # ---- 节点来源：见 vpncore_nodes（启用项优先，全停用/旧数据回退全量）----
  [ -n "$(vpncore_nodes)" ] || { pg_fail vpncore "无可用节点，未生成核心配置"; return 1; }

  _ob=$(vpncore_outbounds "$_gc_bind_iface") || { pg_fail vpncore "节点出站无法安全绑定外层 VPN 接口"; return 1; }
  [ -n "$_ob" ] || { pg_fail vpncore "没有可用的节点出站（URI 解析失败）"; return 1; }

  # 日志级别：默认 warn（省空间/省 IO）；排障时可用 [conf:vpn] log_level=info 打开，
  # info 下才会打印 "inbound/redirect[x]: inbound connection to host:port" 这类证据。
  _lvl=$(vpncore_conf log_level)
  case "$_lvl" in trace|debug|info|warn|error|fatal|panic) ;; *) _lvl=warn ;; esac

  # Resolve fallible DNS/outbound bindings before opening the staging file.
  # Returning from inside the output group would otherwise leave a partial file.
  _gc_dns_json=$(vpncore_dns_json "$_rdns" "$_cdns" "$_gc_bin" "$_gc_bind_iface") || {
    pg_fail vpncore "外层 VPN 的 DNS 无法安全绑定；拒绝生成未绑定配置"
    return 1
  }
  if [ -n "$_gc_bind_iface" ]; then
    _gc_direct_out=$(vpncore_add_bind_interface '{"type":"direct","tag":"direct"}' "$_gc_bind_iface") || {
      pg_fail vpncore "direct outbound 外层 VPN 接口绑定失败"
      return 1
    }
    pg_log "vpn_core: external VPN overlay pins node/direct/DNS outbound sockets to $_gc_bind_iface"
  else
    _gc_direct_out='{"type":"direct","tag":"direct"}'
  fi
  _cfg_tmp=$(umask 077; mktemp "${_cfg}.tmp.XXXXXX" 2>/dev/null) || {
    pg_fail vpncore "无法创建私有核心配置临时文件"
    return 1
  }

  {
    printf '{\n'
    printf '  "log": {"level": "%s", "timestamp": true},\n' "$_lvl"
    printf '  %s,\n' "$_gc_dns_json"
    # REDIRECT + mixed remain for legacy transparent/client paths. TUN mode owns routing.
    if [ "$_gc_mode" = "tun" ]; then
      printf '  "inbounds": [{"type":"tun","tag":"tun-in","interface_name":"fx0","address":["172.19.0.1/30","fdfe:dcba:9876::1/126"],"mtu":1400,"auto_route":true,"strict_route":true,"udp_timeout":"5m","exclude_uid":[0],"route_exclude_address":["192.168.0.0/16","10.0.0.0/8","172.16.0.0/12","100.64.0.0/10","127.0.0.0/8","169.254.0.0/16","224.0.0.0/4","::1/128","fc00::/7","fe80::/10","ff00::/8"],"stack":"system"},\n'
      printf '               {"type":"redirect","tag":"redirect-in","listen":"%s","listen_port":%s},\n' "$_lip" "$_lport"
      printf '               {"type":"mixed","tag":"mixed-in","listen":"%s","listen_port":%s}],\n' "$_lip" "$_mport"
    else
      printf '  "inbounds": [{"type":"redirect","tag":"redirect-in","listen":"%s","listen_port":%s},\n' "$_lip" "$_lport"
      printf '               {"type":"mixed","tag":"mixed-in","listen":"%s","listen_port":%s}],\n' "$_lip" "$_mport"
    fi
    printf '  "outbounds": [%s,\n    {"type":"selector","tag":"proxy","outbounds":[%s],"default":"%s"},\n    %s],\n' "$_ob" "$(vpncore_node_tags)" "$(vpncore_default_tag)" "$_gc_direct_out"
    # route：sniff 是 1.13+ 的「规则动作」形式；旧式 inbound.sniff 已在 1.13 移除
    # （1.14.3 实测：inbounds[].sniff → "legacy inbound fields are ... removed"）。
    # redirect 入站拿到的是 IP，必须靠 sniff 还原域名，否则 domain 规则/分流全部失效。
    # 有 dns 段时必须同时给 route.default_domain_resolver（1.14.3 实测否则 FATAL）：
    # 节点 server 为域名时，内核要先用本地直连 DNS 解析节点地址，不能走 remote（死循环）。
    _route_pre=$(vpncore_resolver_json "$_gc_bin")
    [ -n "$_route_pre" ] && _route_pre="$_route_pre,"
    # ---- 用户规则编译（vpnrule.sh）：把 [list:rule]/[list:fx] 里 sing-box 可表达的
    # Clash 语法（DOMAIN*/IP-CIDR/PROCESS-NAME/PORT/PROTOCOL/NETWORK/RULE-SET/
    # AND·OR·NOT/REJECT/MATCH）编译成 route.rules 片段；不可表达的（URL-REGEX/
    # USER-AGENT/IP-ASN/GEOIP/GEOSITE/MITM）由编译器 SKIP 计数，绝不写入 JSON
    # （写入 unknown field 会让 run 直接 FATAL）。
    # 规则顺序：sniff（必须最先，否则拿不到域名/协议）→ 用户规则 → 内网直连兜底。
    _vr_rules=""; _vr_final=""
    # 定位 vpnrule.sh：apply.sh 是 source 本文件，$0 指向 apply.sh 甚至是调用方，
    # 所以必须优先用 vpncore_moddir()（它会按 module.prop 逐级定位），回落到 $MODDIR。
    _vr_dir=$(vpncore_moddir 2>/dev/null)
    [ -n "$_vr_dir" ] || _vr_dir="$MODDIR"
    _vr_sh="$_vr_dir/scripts/vpnrule.sh"
    if [ -f "$_vr_sh" ]; then
      # 用 --emit 拿纯 rules 数组片段（比从 --json 里 sed 抠更可靠：
      # 规则本身可能含 "final" 之类字样，贪婪匹配会截错），
      # 再用 --json 只取统计数字。
      _vr_rules=$(PG="$PG" sh "$_vr_sh" --emit "$_gc_bin" 2>/dev/null)
      # Rule sets are declared below; without a rule that references them sing-box loads
      # the sets and never consults them, so the ad lists would filter nothing.
      _vcr_reject_rules=$(_vcr_emit_reject_rules)
      if [ -n "$_vcr_reject_rules" ]; then
        if [ -n "$_vr_rules" ]; then
          _vr_rules="$_vr_rules,$_vcr_reject_rules"
        else
          _vr_rules=$_vcr_reject_rules
        fi
      fi
      # 规则集定义（v1.10.7）：rule_set 引用必须同时有 route.rule_set 定义，
      # 否则 run 阶段 FATAL `rule-set not found`（check 抓不到这个错）。
      # Populates _vcr_ruleset_names as a side effect, which the reject emitter needs.
      _vr_rulesets=$(PG="$PG" sh "$_vr_sh" --emit-rulesets "$_gc_bin" 2>/dev/null)
      # The tags just emitted are the ones a reject rule may reference. Deriving them from
      # the emitted JSON avoids a second read of the files and cannot drift.
      _vcr_ruleset_names=$(printf '%s' "$_vr_rulesets" \
        | grep -o '"tag":"[^"]*"' 2>/dev/null \
        | sed 's/"tag":"//; s/"$//' | tr '\n' ' ')
      _vcr_reject_rules=$(_vcr_emit_reject_rules)
      if [ -n "$_vcr_reject_rules" ]; then
        if [ -n "$_vr_rules" ]; then
          _vr_rules="$_vr_rules,$_vcr_reject_rules"
        else
          _vr_rules=$_vcr_reject_rules
        fi
      fi
      _vr_out=$(PG="$PG" sh "$_vr_sh" --json "$_gc_bin" 2>/dev/null)
      _vr_n=$(printf '%s' "$_vr_out" | sed -n 's/.*"compiled":\([0-9]*\).*/\1/p')
      _vr_skip=$(printf '%s' "$_vr_out" | sed -n 's/.*"skipped":\([0-9]*\).*/\1/p')
      _vr_final=$(printf '%s' "$_vr_out" | sed -n 's/.*"final":"\([^"]*\)".*/\1/p')
      case "$_vr_n" in ''|*[!0-9]*) _vr_n=0 ;; esac
      case "$_vr_skip" in ''|*[!0-9]*) _vr_skip=0 ;; esac
      if [ "$_vr_n" -gt 0 ]; then
        pg_log "vpn_core: 用户规则已编译 $_vr_n 条（跳过 $_vr_skip 条不可表达语法）"
      fi
    fi
    # 组装 rules 数组
    _rules='{"action":"sniff","sniffer":["http","tls"],"timeout":"300ms"}'
    [ -n "$_vr_rules" ] && _rules="$_rules,$_vr_rules"
    _global_reject=0
    [ "$_vr_final" = 'reject' ] && _global_reject=1
    # route.final 只接受 outbound tag；全局拒绝必须使用 catch-all reject action。
    # MATCH/FINAL REJECT 拒绝所有未被前序用户规则匹配的流量；catch-all 必须在私网例外之前，
    # 否则私网直连规则会绕过全局拒绝。
    if [ "$_global_reject" = 1 ]; then
      _rules="$_rules,{\"action\":\"reject\",\"method\":\"drop\"}"
    else
      _rules="$_rules,{\"ip_is_private\":true,\"outbound\":\"direct\"}"
    fi
    # route.rule_set 定义块（v1.10.7）：有 rule_set 引用就必须有定义，
    # 否则 run FATAL `rule-set not found`。
    _routeset_pre=""
    if [ -n "$_vr_rulesets" ]; then
      _routeset_pre="\"rule_set\":[$_vr_rulesets],"
      pg_log "vpn_core: 规则集定义 $_vr_rulesets"
    fi
    # route.final：用户写了 MATCH/FINAL 就用它映射的 outbound，否则默认 proxy
    _final='proxy'
    case "$_vr_final" in
      direct|DIRECT|Direct) _final='direct' ;;
      reject|REJECT|Reject) _final='proxy' ;;  # catch-all reject rule handles unmatched traffic; keep a valid outbound tag
      proxy|PROXY|Proxy) _final='proxy' ;;
      '') : ;;
      *) _final='proxy' ;;
    esac
    _route_auto_iface=""
    [ "$_gc_mode" = "tun" ] && _route_auto_iface='"auto_detect_interface":true,'
    printf '  "route": {%s%s%s"rules":[%s],"final":"%s"}\n' "$_route_pre" "$_routeset_pre" "$_route_auto_iface" "$_rules" "$_final"
    printf '}\n'
  } > "$_cfg_tmp"
  if [ ! -s "$_cfg_tmp" ]; then
    rm -f "$_cfg_tmp" 2>/dev/null
    pg_fail vpncore "核心配置生成失败；保留原有配置"
    return 1
  fi
  # 真实 sing-box 可用时，先对临时文件执行 check；失败不得覆盖旧配置。
  _gc_check_err=$(vpncore_check_conf "$_gc_bin" "$_cfg_tmp")
  if [ $? -ne 0 ]; then
    rm -f "$_cfg_tmp" 2>/dev/null
    pg_fail vpncore "新核心配置预检失败，保留旧配置：${_gc_check_err:-详见核心日志}"
    return 1
  fi
  # ---- user profile script -------------------------------------------------
  # A script may rewrite the generated config (same contract as FlClash / Shadowrocket:
  # `function main(config)` returns the new config). It runs after the config check, and
  # the result is checked again because a script can emit an invalid profile.
  #
  # A script failure does NOT abort the apply: the unmodified config is used instead and
  # the reason is logged, so a bad script cannot leave the device without a tunnel.
  _pt_script=$(pg_get vpn_profile_script 2>/dev/null)
  if [ -n "${_pt_script:-}" ] && [ -f "$_pt_script" ] && [ ! -L "$_pt_script" ]; then
    _pt_sh="$(vpncore_moddir 2>/dev/null)/scripts/jsruntime/profile-transform.sh"
    if [ -x "$_pt_sh" ]; then
      _pt_out=${_cfg_tmp}.scripted
      if sh "$_pt_sh" "$_pt_script" "$_cfg_tmp" "$_pt_out" >> "$PG/boot.log" 2>&1 \
          && [ -s "$_pt_out" ]; then
        _pt_err=$(vpncore_check_conf "$_gc_bin" "$_pt_out")
        if [ $? -eq 0 ]; then
          mv -f "$_pt_out" "$_cfg_tmp" 2>/dev/null
          pg_log "vpn_core: profile script applied ($_pt_script)"
        else
          rm -f "$_pt_out" 2>/dev/null
          pg_log "vpn_core: profile script produced an invalid config; using the unscripted profile"
        fi
      else
        rm -f "$_pt_out" 2>/dev/null
        pg_log "vpn_core: profile script failed; using the unscripted profile"
      fi
    else
      pg_log "vpn_core: profile script set but profile-transform.sh is unavailable"
    fi
  fi

  if ! mv -f "$_cfg_tmp" "$_cfg" 2>/dev/null; then
    rm -f "$_cfg_tmp" 2>/dev/null
    pg_fail vpncore "无法原子提交新核心配置；保留原有配置"
    return 1
  fi
  pg_log "vpn_core: config generated ($_cfg, mode=$_gc_mode, nodes=$(vpncore_node_count), default=$(vpncore_default_tag), redirect=$_lip:$_lport, mixed=$_lip:$_mport)"
  return 0
}

# 节点列表（[list:vpn_node] 行格式 URI|名称|1=启用）
# 注意：必须 while read 逐行迭代——for 会按 IFS 把 URI 里的 :/?/& 拆成多个词
# （曾致 selector 的 outbounds 变成 ["-6"]）
#
# 节点集合的**唯一解析入口**（outbounds / tags / default_tag / genconf 都走它）：
#   - 优先取启用项（pg_list_enabled 按 $3=="1"）
#   - 一个都没启用时回退全部节点行——两个目的：
#       (1) 保留「全停用时回退全量」兜底，避免 outbounds 为空导致核心起不来；
#       (2) 兼容旧版 vpnsub 写出的「第 3 字段全 0」旧数据（旧语义把该字段当"选中"），
#           否则真机上表现为「导入 5 个节点，核心却一个都没有」。
#   注：vpnsub.sh 现在会把这种旧段规整为全 1；这里是第二道防线。
vpncore_nodes() {
  _vn_enabled=$(pg_list_enabled vpn_node)
  if [ -n "$_vn_enabled" ]; then
    printf '%s\n' "$_vn_enabled"
    return 0
  fi
  pg_list vpn_node 2>/dev/null | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | \
    awk -F'|' '$1 != "" {print $1 "|" $2 "|1"}'
}

# 取列表行的第 1 字段（URI），即 "URI|名称|1" 里第一个 | 之前的内容。
# 关键（真机实测 1.14.3 / Android 13 mksh）：**不能写 "${line%%|*}"**——
# mksh 把未转义的 | 当「模式或」(pattern alternation)，`%%|*` 变成「最短匹配
# 空模式或任意串」，实测一律返回空串：表现为「节点全被当成解析失败」→
# outbounds 为空 → genconf fail → 核心起不来（用户看到 VPN 完全不可用）。
# busybox ash 下未转义写法才碰巧正确，所以这个 bug 只在真机上暴露。
# 用 sed 单进程取字段，对 mksh/ash/busybox 行为一致。
vpncore_line_uri() { printf '%s' "${1%%\|*}"; }

vpncore_node_count() { printf '%s\n' "$(vpncore_nodes)" | grep -c . ; }

# 生成全部 outbound JSON（逗号连接）
# 解析失败的节点跳过（_j 为空），保证 outbounds 与 selector 引用一一对应
vpncore_outbounds() {
  _out=""; _i=0; _out_bind_if="$1"
  while IFS= read -r _line; do
    _i=$((_i+1))
    _j=$(singbox_node_outbound "$(vpncore_line_uri "$_line")" "node-$_i")
    [ -n "$_j" ] || continue
    if [ -n "$_out_bind_if" ]; then
      _j=$(vpncore_add_bind_interface "$_j" "$_out_bind_if") || { pg_log "vpn_core: refusing unbound node outbound node-$_i in external VPN overlay"; return 1; }
    fi
    if [ -n "$_out" ]; then _out="$_out",; fi
    _out="${_out}${_j}"
  done <<__PGNODES__
$(vpncore_nodes)
__PGNODES__
  printf '%s' "$_out"
}

# 全部 tag（带引号逗号连接，供 selector 组使用）
# 与 outbounds 同一套跳过逻辑：解析失败的节点不出现在 selector 里
# 注意：`_out="$_outnode-$_i"` 在部分 busybox ash 下变量名被误拼（实测输出 "-6"），
# 必须写成 ${_out}node-${_i} 显式分隔。
vpncore_node_tags() {
  _out=""; _i=0
  while IFS= read -r _line; do
    _i=$((_i+1))
    _j=$(singbox_node_outbound "$(vpncore_line_uri "$_line")" "node-$_i")
    [ -n "$_j" ] || continue
    if [ -n "$_out" ]; then _out="$_out",; fi
    _out="${_out}\"node-${_i}\""
  done <<__PGNODES__
$(vpncore_nodes)
__PGNODES__
  printf '%s' "$_out"
}

# 当前选中 vpn_node 对应的 tag（找不到回落 node-1）
vpncore_default_tag() {
  _sel=$(pg_get vpn_node 2>/dev/null)
  _i=0
  while IFS= read -r _line; do
    _uri=$(vpncore_line_uri "$_line")
    _i=$((_i+1))
    [ -n "$(singbox_node_outbound "$_uri" "node-$_i")" ] || continue
    if [ "$_uri" = "$_sel" ]; then echo "node-$_i"; return 0; fi
  done <<__PGNODES__
$(vpncore_nodes)
__PGNODES__
  echo "node-1"
}

# ---- 启动核心 ----
vpncore_start() {
  # Direct mode is intentionally node-free and core-free. Do not attempt to
  # generate a proxy configuration, download sing-box, or fail because no node
  # is selected when the user explicitly chose direct mode.
  if [ "$(pg_get vpn_mode direct)" = "direct" ]; then
    pg_log "vpn_core: vpn_mode=direct; skip core start (direct mode needs no node or local proxy core)"
    return 0
  fi
  _bin=$(vpncore_bin)
  _cfg=$(vpncore_cfg)
  _pidf=$(vpncore_pid)
  _lport=$(vpncore_conf local_port); _lport=${_lport:-7890}
  case "$_lport" in ''|*[!0-9]*) _lport=7890 ;; esac
  if [ ! -x "$_bin" ]; then
    vpncore_install_builtin
    _ir=$?
    if [ $_ir -eq 2 ]; then _bin="$(vpncore_moddir)/bin/$(vpncore_arch)/sing-box"; fi
    if [ ! -x "$_bin" ]; then
      if [ "$(vpncore_conf core_auto)" = "0" ]; then
        pg_log "vpn_core: core_auto=0，跳过自动下载（请放一个可执行 sing-box 到 $_bin）"
        return 1
      fi
      if [ "$SINGBOX_SKIP_DL" = "1" ]; then
        pg_log "vpn_core: SINGBOX_SKIP_DL=1（沙盒测试台），跳过下载"
        return 1
      fi
      vpncore_download || {
        pg_fail vpncore "本机架构 $(vpncore_arch) 无内置内核且在线下载失败：请检查网络（GitHub 可达性）或手动放置 sing-box 到 $(vpncore_bin)"
        return 1
      }
    fi
  fi
  # 保留启动前配置快照：配置语法 check 通过但运行期 probe 失败时，也必须恢复旧配置。
  _cfg_backup="${_cfg}.previous.$$"
  _cfg_had_old=0
  if [ -s "$_cfg" ]; then
    # A valid old config exists: if its rollback copy cannot be made, do not
    # generate/commit a replacement. Otherwise a later run-probe failure could
    # delete the only known-good config after the backup attempt silently failed.
    if ! cp -p "$_cfg" "$_cfg_backup" 2>/dev/null || [ ! -s "$_cfg_backup" ]; then
      rm -f "$_cfg_backup" 2>/dev/null
      pg_fail vpncore "无法备份现有核心配置，拒绝启动并保留原配置"
      return 1
    fi
    _cfg_had_old=1
  else
    rm -f "$_cfg_backup" 2>/dev/null
  fi
  # 启动阶段耗时诊断只写日志，不参与控制流或削弱启动校验。
  _vcs_t0=$(date +%s 2>/dev/null); case "$_vcs_t0" in ''|*[!0-9]*) _vcs_t0=0 ;; esac
  vpncore_genconf "$_bin" || { rm -f "$_cfg_backup" 2>/dev/null; return 1; }
  _vcs_t1=$(date +%s 2>/dev/null); case "$_vcs_t1" in ''|*[!0-9]*) _vcs_t1=$_vcs_t0 ;; esac
  [ "$_vcs_t0" -eq 0 ] || pg_log "vpn_core_timing: config_generate=$((_vcs_t1-_vcs_t0))s"
  # 清空上一轮核心日志，确保下面的预检/启动错误只来自本轮
  : > "$(vpncore_log)" 2>/dev/null
  # 启动前预检：真实 sing-box 会在此阶段给出确切的配置解析错误（旧版 DNS 格式、
  # 非法 JSON、未知字段等），避免用户只看到「启动即退出」而无原因。
  _vcs_t0=$(date +%s 2>/dev/null); case "$_vcs_t0" in ''|*[!0-9]*) _vcs_t0=0 ;; esac
  _cerr=$(vpncore_check_conf "$_bin" "$_cfg")
  _vcs_rc=$?
  _vcs_t1=$(date +%s 2>/dev/null); case "$_vcs_t1" in ''|*[!0-9]*) _vcs_t1=$_vcs_t0 ;; esac
  [ "$_vcs_t0" -eq 0 ] || pg_log "vpn_core_timing: config_check=$((_vcs_t1-_vcs_t0))s"
  if [ "$_vcs_rc" -ne 0 ]; then
    pg_fail vpncore "sing-box 配置校验失败：${_cerr:-详见 $(vpncore_log)}"
    if [ "$_cfg_had_old" = 1 ] && mv -f "$_cfg_backup" "$_cfg" 2>/dev/null; then
      pg_log "vpn_core: 配置校验失败，已恢复上一份核心配置"
    else
      if [ "$_cfg_had_old" != 1 ]; then rm -f "$_cfg" 2>/dev/null; fi
      [ "$_cfg_had_old" = 1 ] || rm -f "$_cfg_backup" 2>/dev/null
      pg_log "vpn_core: 配置校验失败；没有可恢复的旧配置或恢复失败"
    fi
    rm -f "$_pidf" 2>/dev/null
    return 1
  fi
  # 第二道预检：check 通过 ≠ 能跑（1.14 的 dns detour / resolver 类问题只在 run 阶段报错）。
  # 这里先短跑一次，把运行期 FATAL 提前纳入失败原因，避免用户看到「校验通过却一直连不上」。
  _vcs_t0=$(date +%s 2>/dev/null); case "$_vcs_t0" in ''|*[!0-9]*) _vcs_t0=0 ;; esac
  _rerr=$(vpncore_probe_run "$_bin" "$_cfg")
  _vcs_rc=$?
  _vcs_t1=$(date +%s 2>/dev/null); case "$_vcs_t1" in ''|*[!0-9]*) _vcs_t1=$_vcs_t0 ;; esac
  [ "$_vcs_t0" -eq 0 ] || pg_log "vpn_core_timing: runtime_probe=$((_vcs_t1-_vcs_t0))s"
  if [ "$_vcs_rc" -ne 0 ]; then
    pg_fail vpncore "sing-box 运行预检失败：${_rerr}"
    if [ "$_cfg_had_old" = 1 ] && mv -f "$_cfg_backup" "$_cfg" 2>/dev/null; then
      pg_log "vpn_core: 运行预检失败，已恢复上一份核心配置"
    else
      if [ "$_cfg_had_old" != 1 ]; then rm -f "$_cfg" 2>/dev/null; fi
      [ "$_cfg_had_old" = 1 ] || rm -f "$_cfg_backup" 2>/dev/null
      pg_log "vpn_core: 运行预检失败；没有可恢复的旧配置或恢复失败"
    fi
    rm -f "$_pidf" 2>/dev/null
    return 1
  fi
  # stdin 必须重定向到 /dev/null：否则后台核心进程继承父 shell 的管道，
  # 父 shell 退出后管道不关闭 → 调用方（run-tc16.sh / WebUI 桥接）永远等不到 EOF
  "$_bin" run -c "$_cfg" < /dev/null >> "$(vpncore_log)" 2>&1 &
  _p=$!
  echo "$_p" > "$_pidf"
  _vcs_wait_t0=$(date +%s 2>/dev/null); case "$_vcs_wait_t0" in ''|*[!0-9]*) _vcs_wait_t0=0 ;; esac
  # 等待端口就绪（最长 5 秒）。仅进程存活不足以证明可接收重定向流量；
  # 只有实际监听可验证时才报告启动成功，避免 NAT 已接管但代理端口无人服务。
  _w=0
  while [ "$_w" -lt 10 ]; do
    if vpncore_listening; then
      if ! vpncore_tun_interface_ready; then
        pg_log "vpn_core: listener is ready but TUN interface fx0 is absent/down; waiting for route setup"
      else
        rm -f "$_cfg_backup" 2>/dev/null
        _vcs_wait_t1=$(date +%s 2>/dev/null); case "$_vcs_wait_t1" in ''|*[!0-9]*) _vcs_wait_t1=$_vcs_wait_t0 ;; esac
        [ "$_vcs_wait_t0" -eq 0 ] || pg_log "vpn_core_timing: listener_wait=$((_vcs_wait_t1-_vcs_wait_t0))s"
        pg_log "vpn_core: sing-box running (pid $_p, port $_lport; TUN interface checked when requested)"
        return 0
      fi
    fi
    if ! kill -0 "$_p" 2>/dev/null; then
      _why=$(vpncore_log_tail)
      pg_fail vpncore "sing-box 启动即退出${_why:+：$_why}（详见 $(vpncore_log)）"
      if [ "$_cfg_had_old" = 1 ] && mv -f "$_cfg_backup" "$_cfg" 2>/dev/null; then
        pg_log "vpn_core: 核心启动即退出，已恢复上一份核心配置"
      else
        [ "$_cfg_had_old" = 1 ] || rm -f "$_cfg" 2>/dev/null
        rm -f "$_cfg_backup" 2>/dev/null
        pg_log "vpn_core: 核心启动即退出，未能恢复旧配置"
      fi
      rm -f "$_pidf"
      return 1
    fi
    sleep 0.5 2>/dev/null || sleep 1
    _w=$((_w+1))
  done
  # Never roll back the config or erase ownership metadata while the new core may
  # still own fx0/routes. vpncore_stop deliberately preserves its PID file on failure.
  if kill -0 "$_p" 2>/dev/null; then
    pg_log "vpn_core: readiness timeout; attempting to stop core before config rollback"
    if ! vpncore_stop; then
      _why=$(vpncore_log_tail)
      pg_fail vpncore "sing-box 就绪超时且停止失败；保留 PID/当前配置以避免丢失 TUN 所有权记录${_why:+：$_why}"
      return 1
    fi
  fi
  _why=$(vpncore_log_tail)
  if [ "$(pg_get vpn_mode direct 2>/dev/null)" = "tun" ]; then
    pg_fail vpncore "sing-box 端口或 TUN 接口 fx0 在 5s 内未确认就绪${_why:+：$_why}"
  else
    pg_fail vpncore "sing-box 端口 $_lport 5s 内未确认就绪${_why:+：$_why}"
  fi
  if [ "$_cfg_had_old" = 1 ] && mv -f "$_cfg_backup" "$_cfg" 2>/dev/null; then
    pg_log "vpn_core: 核心未就绪，已恢复上一份核心配置"
  else
    [ "$_cfg_had_old" = 1 ] || rm -f "$_cfg" 2>/dev/null
    rm -f "$_cfg_backup" 2>/dev/null
    pg_log "vpn_core: 核心未就绪，未能恢复旧配置"
  fi
  rm -f "$_pidf"
  return 1
}

# ---- 对外主入口：确保本地端口可用 ----
vpn_core_ensure() {
  if [ "$(pg_get vpn_mode direct)" = "direct" ]; then
    pg_log "vpn_core: vpn_mode=direct; ensure skipped (direct mode needs no node or local proxy core)"
    return 0
  fi
  if [ "$(pg_get vpn_core 0)" != "1" ]; then
    pg_log "vpn_core: vpn_core=0，沿用用户自建核心（不自动下载/启动）"
    return 0
  fi
  # 核心进程已存活 → 直接复用（最可靠的就绪信号，不依赖端口探测）
  _pf=$(vpncore_pid)
  if [ -f "$_pf" ]; then
    _p=$(cat "$_pf" 2>/dev/null)
    case "$_p" in
      ''|*[!0-9]*) ;;
      *)
        if kill -0 "$_p" 2>/dev/null && vpncore_pid_matches "$_p"; then
          # PID 身份正确也不等于服务已就绪：核心可能卡死、端口绑定失败，
          # 或启动后监听已消失。不能让调用方在本地端口不可用时误以为成功。
          if vpncore_listening && vpncore_tun_interface_ready; then
            pg_log "vpn_core: 核心进程与监听已验证，且 TUN 模式所需接口（如适用）已就绪 (pid $_p)，跳过启动"
            return 0
          fi
          pg_log "vpn_core: 已验证的核心进程仍存活但本地端口未监听，尝试安全停止后重启"
          if ! vpncore_stop; then
            pg_fail vpncore "核心进程 $_p 仍存活但端口未监听，安全停止失败；拒绝重复启动"
            return 1
          fi
        fi
        # kill -0 只证明 PID 存在，不证明它属于 sing-box。PID 复用时旧逻辑
        # 会把无关进程误判成代理核心，继而跳过启动，造成 DNS/NAT 已接管但本地端口无人服务。
        # 身份不匹配时只清理本模块的陈旧 PID 记录，绝不向该 PID 发信号。
        rm -f "$_pf" 2>/dev/null
        pg_log "vpn_core: stale/unverified PID record removed; will verify listener or start core"
        ;;
    esac
  fi
  if vpncore_listening && vpncore_tun_interface_ready; then
    _lport=$(vpncore_conf local_port); _lport=${_lport:-7890}
    pg_log "vpn_core: 沿用已验证监听且 TUN 接口状态符合当前模式的代理核心 (port $_lport)"
    return 0
  fi
  vpncore_start
}

# ---- 工具：URL 解码 + query 取值 + 去协议前缀 ----
# 注意：busybox sh 对 `${var#proto://}`（模式中含 //）不生效，必须用 sed 去前缀
# 另：URI 的 #fragment（#节点名）在传给 shell 前已被 pg_list 剥掉，但单测/直接调用时
# 可能仍带 #，这里统一去掉，避免污染 server_name/path。
urldec() { printf '%b' "$(echo "$1" | sed 's/%/\\x/g')"; }
qs() { echo "$1" | tr '&' '\n' | sed -n "s/^$2=//p" | head -n1 | sed 's/#.*$//'; }
qsdec() { urldec "$(qs "$1" "$2")"; }
vmess_field() { echo "$1" | tr -d ' "{}[]' | grep -o "$2:[^,]*" | head -n1 | sed "s/^$2://"; }
# 去协议前缀 + 去 #fragment + 去 query（保留 host:port/userinfo）
# 注意：busybox ash 的 `${var#proto://}`（模式含 //）不生效，必须用 sed
strip_proto() { echo "$1" | sed 's#^[a-z0-9]*://##; s/#.*$//; s/?.*$//'; }
# 去协议前缀 + 去 #fragment（保留 query）
strip_proto_q() { echo "$1" | sed 's#^[a-z0-9]*://##; s/#.*$//'; }
# 仅去 #fragment
strip_frag() { echo "$1" | sed 's/#.*$//'; }

# Parse host:port without splitting inside bracketed IPv6 literals. Emits an
# unbracketed IPv6 address for sing-box JSON and validates the numeric port.
split_host_port() {
  _shp="$1"
  case "$_shp" in
    \[*\]:*)
      NODE_HOST=${_shp#\[}; NODE_HOST=${NODE_HOST%%\]*}
      NODE_PORT=${_shp##*\]:}
      case "$NODE_HOST" in *:*) ;; *) return 1 ;; esac
      ;;
    *:*) NODE_HOST=${_shp%:*}; NODE_PORT=${_shp##*:} ;;
    *) return 1 ;;
  esac
  [ -n "$NODE_HOST" ] || return 1
  case "$NODE_PORT" in ''|*[!0-9]*) return 1 ;; esac
  [ "$NODE_PORT" -ge 1 ] 2>/dev/null && [ "$NODE_PORT" -le 65535 ] 2>/dev/null || return 1
  return 0
}

# ---- 节点 URI → sing-box outbound JSON ----
# 支持 vmess / vless / trojan / ss（SIP002 与旧格式）/ hysteria2 / tuic / anytls /
#       socks5 / ssh / snell / shadowtls / naive / openvpn / openconnect / masque
singbox_node_outbound() {
  _u="$1"; _t="$2"
  case "$_u" in
    vmess://*)
      _b64=$(strip_proto "$_u")
      _b64=$(echo "$_b64" | tr -- '-_' '+/')
      _pad=$(( (4 - ${#_b64} % 4) % 4 ))
      _i=0
      while [ $_i -lt $_pad ]; do _b64="$_b64="; _i=$((_i+1)); done
      _j=$(echo "$_b64" | base64 -d 2>/dev/null)
      _h=$(vmess_field "$_j" add); _p=$(vmess_field "$_j" port); _id=$(vmess_field "$_j" id)
      _net=$(vmess_field "$_j" net); _path=$(vmess_field "$_j" path); _host=$(vmess_field "$_j" host)
      _tls=$(vmess_field "$_j" tls); _sni=$(vmess_field "$_j" sni); _sec=$(vmess_field "$_j" scy)
      _sec=${_sec:-auto}
      [ -n "$_h" ] && [ -n "$_p" ] && [ -n "$_id" ] || return 1
      case "$_p" in ''|*[!0-9]*) return 1 ;; esac
      [ "$_p" -ge 1 ] 2>/dev/null && [ "$_p" -le 65535 ] 2>/dev/null || return 1
      # Strip brackets from bracketed IPv6 literal for JSON server field.
      case "$_h" in \[*\]) _h=${_h#\[}; _h=${_h%\]} ;; esac
      printf '{"type":"vmess","tag":"%s","server":"%s","server_port":%s,"uuid":"%s","security":"%s"' "$_t" "$_h" "$_p" "$_id" "$_sec"
      if [ "$_tls" = "tls" ]; then printf ',"tls":{"enabled":true,"server_name":"%s"}' "${_sni:-$_host}"; fi
      case "$_net" in
        ws) printf ',"transport":{"type":"ws","path":"%s","headers":{"Host":"%s"}}' "${_path:-/}" "$_host" ;;
        grpc) printf ',"transport":{"type":"grpc","service_name":"%s"}' "${_path:-}" ;;
      esac
      printf '}'
      return 0
      ;;
    vless://*|reality://*)
      # 支持 security=none/tls/reality：reality:// 或 security=reality 时输出
      # tls.reality（public_key/short_id）+ utls（fingerprint）。旧实现无条件输出
      # 普通 TLS，reality 节点会「能解析但连错目标」，等于功能不可用。
      _is_reality=0
      case "$_u" in reality://*) _is_reality=1 ;; esac
      _r=$(strip_proto_q "$_u")
      _id=${_r%%@*}; _r=${_r#*@}
      _hp=${_r%%\?*}; _q=${_r#*\?}
      split_host_port "$_hp" || return 1; _h=$NODE_HOST; _p=$NODE_PORT
      [ -n "$_h" ] || return 1
      case "$_h" in *[/%]*) return 1 ;; esac
      case "$_p" in ''|*[!0-9]*) return 1 ;; esac
      [ -n "$_id" ] || return 1
      _sni=$(qsdec "$_q" sni); _flow=$(qs "$_q" flow); _type=$(qs "$_q" type)
      _path=$(qsdec "$_q" path); _host=$(qsdec "$_q" host); _svc=$(qsdec "$_q" serviceName)
      [ -n "$_svc" ] || _svc=$(qsdec "$_q" service_name)
      _sec=$(qs "$_q" security); _alpn=$(qsdec "$_q" alpn)
      [ "$_is_reality" = "1" ] && [ -z "$_sec" ] && _sec=reality
      # alpn 可能是逗号分隔（h2,http/1.1），转成 JSON 数组
      _alpn_json=""
      if [ -n "$_alpn" ]; then
        _alpn_json=$(printf '%s' "$_alpn" | tr ',' '\n' | sed 's/^/"/;s/$/"/' | tr '\n' ',' | sed 's/,$//')
      fi
      printf '{"type":"vless","tag":"%s","server":"%s","server_port":%s,"uuid":"%s"' "$_t" "$_h" "$_p" "$_id"
      if [ "$_flow" = "xtls-rprx-vision" ]; then printf ',"flow":"xtls-rprx-vision"'; fi
      if [ "$_sec" = "reality" ]; then
        _pbk=$(qsdec "$_q" pbk); _sid=$(qsdec "$_q" sid); _fp=$(qsdec "$_q" fp)
        case "$_fp" in
          chrome|firefox|edge|safari|360|qq|ios|android|random|randomized) ;;
          *) _fp=chrome ;;
        esac
        if [ -z "$_pbk" ]; then
          echo "vpn_core: 跳过 reality 节点（缺少 pbk 公钥，无法建立 REALITY 连接）: ${_h}" >&2
          return 1
        fi
        printf ',"tls":{"enabled":true,"server_name":"%s","reality":{"enabled":true,"public_key":"%s","short_id":"%s"},"utls":{"enabled":true,"fingerprint":"%s"}' "${_sni:-$_h}" "$_pbk" "$_sid" "$_fp"
        [ -n "$_alpn_json" ] && printf ',"alpn":[%s]' "$_alpn_json"
        printf '}'
      elif [ "$_sec" = "tls" ]; then
        printf ',"tls":{"enabled":true,"server_name":"%s"' "${_sni:-$_h}"
        [ -n "$_alpn_json" ] && printf ',"alpn":[%s]' "$_alpn_json"
        printf '}'
      fi
      case "$_type" in
        ws)
          if [ -n "$_host" ]; then
            printf ',"transport":{"type":"ws","path":"%s","headers":{"Host":"%s"}}' "${_path:-/}" "$_host"
          else
            printf ',"transport":{"type":"ws","path":"%s"}' "${_path:-/}"
          fi
          ;;
        grpc) printf ',"transport":{"type":"grpc","service_name":"%s"}' "${_svc:-}" ;;
      esac
      printf '}'
      return 0
      ;;
    trojan://*|trojan-go://*)
      _r=$(strip_proto_q "$_u")
      # 去协议前缀时可能因模式未命中（如 trojan-go）而残留，这里兜底剥一次
      _r=$(echo "$_r" | sed 's#^[a-z0-9-]*://##')
      _pw=${_r%%@*}; _r=${_r#*@}
      _hp=${_r%%\?*}; _q=${_r#*\?}
      split_host_port "$_hp" || return 1; _h=$NODE_HOST; _p=$NODE_PORT
      [ -n "$_h" ] || return 1
      case "$_h" in *[/%]*) return 1 ;; esac
      case "$_p" in ''|*[!0-9]*) return 1 ;; esac
      [ -n "$_pw" ] || return 1
      _sni=$(qsdec "$_q" sni); _type=$(qs "$_q" type)
      _path=$(qsdec "$_q" path); _host=$(qsdec "$_q" host); _svc=$(qsdec "$_q" serviceName)
      [ -n "$_svc" ] || _svc=$(qsdec "$_q" service_name)
      # 注意：第一个 printf 只关闭 tls 对象，transport 仍属于 outbound 对象内部；
      # 旧代码在此多输出一个 }（先关掉 outbound，再追加 transport，结尾又补一个 }），
      # 任何含 trojan/trojan-go 节点的配置都会变成非法 JSON，内核启动即退出。
      printf '{"type":"trojan","tag":"%s","server":"%s","server_port":%s,"password":"%s","tls":{"enabled":true,"server_name":"%s"}' "$_t" "$_h" "$_p" "$_pw" "${_sni:-$_h}"
      case "$_type" in
        ws)
          if [ -n "$_host" ]; then
            printf ',"transport":{"type":"ws","path":"%s","headers":{"Host":"%s"}}' "${_path:-/}" "$_host"
          else
            printf ',"transport":{"type":"ws","path":"%s"}' "${_path:-/}"
          fi
          ;;
        grpc) printf ',"transport":{"type":"grpc","service_name":"%s"}' "${_svc:-}" ;;
      esac
      printf '}'
      return 0
      ;;
    ss://*)
      _r=$(strip_proto_q "$_u")
      _body=${_r%%\?*}
      # SIP002（含 @）与旧格式（整体 base64）两种：credentials 均需 base64 解码
      if echo "$_body" | grep -q '@'; then
        _creds=$(echo "${_body%%@*}" | tr -- '-_' '+/' | base64 -d 2>/dev/null)
        _hp=${_body#*@}
      else
        _d=$(echo "$_body" | tr -- '-_' '+/' | base64 -d 2>/dev/null)
        _creds=${_d%%@*}; _hp=${_d#*@}
      fi
      _m=${_creds%%:*}; _pw=${_creds#*:}
      split_host_port "$_hp" || return 1; _h=$NODE_HOST; _p=$NODE_PORT
      [ -n "$_h" ] || return 1
      case "$_h" in *[/%]*) return 1 ;; esac
      case "$_p" in ''|*[!0-9]*) return 1 ;; esac
      [ -n "$_m" ] && [ -n "$_pw" ] || return 1
      # method 必须可打印 ASCII（base64 解码失败会给出垃圾 → 直接判失败）
      case "$_m" in *[!A-Za-z0-9._-]*) return 1 ;; esac
      printf '{"type":"shadowsocks","tag":"%s","server":"%s","server_port":%s,"method":"%s","password":"%s"}' "$_t" "$_h" "$_p" "$_m" "$_pw"
      return 0
      ;;
    hysteria2://*|hysteria://*)
      _r=$(strip_proto_q "$_u")
      _pw=${_r%%@*}; _r=${_r#*@}
      _hp=${_r%%\?*}; _q=${_r#*\?}
      split_host_port "$_hp" || return 1; _h=$NODE_HOST; _p=$NODE_PORT
      _sni=$(qsdec "$_q" sni)
      [ -n "$_h" ] && [ -n "$_p" ] && [ -n "$_pw" ] || return 1
      printf '{"type":"hysteria2","tag":"%s","server":"%s","server_port":%s,"password":"%s","tls":{"enabled":true,"server_name":"%s"}}' "$_t" "$_h" "$_p" "$_pw" "${_sni:-$_h}"
      return 0
      ;;
    ssh://*)
      # ssh://user:password@host:port  — SSHOutboundOptions: user, password, private_key
      _r=$(strip_proto_q "$_u")
      _ui=${_r%%@*}; _r=${_r#*@}
      _hp=${_r%%\?*}; _q=${_r#*\?}
      split_host_port "$_hp" || return 1; _h=$NODE_HOST; _p=$NODE_PORT
      _user=${_ui%%:*}; _pw=${_ui#*:}
      [ "$_pw" = "$_ui" ] && _pw=
      [ -n "$_h" ] && [ -n "$_p" ] && [ -n "$_user" ] || return 1
      case "$_p" in ''|*[!0-9]*) return 1 ;; esac
      printf '{"type":"ssh","tag":"%s","server":"%s","server_port":%s,"user":"%s"' \
        "$_t" "$_h" "$_p" "$_user"
      [ -n "$_pw" ] && printf ',"password":"%s"' "$_pw"
      printf '}'
      return 0
      ;;
    snell://*)
      # snell://psk@host:port?version=5  — AbstractSnellInboundOptions: psk, version 5|6
      _r=$(strip_proto_q "$_u")
      _psk=${_r%%@*}; _r=${_r#*@}
      _hp=${_r%%\?*}; _q=${_r#*\?}
      split_host_port "$_hp" || return 1; _h=$NODE_HOST; _p=$NODE_PORT
      [ -n "$_h" ] && [ -n "$_p" ] && [ -n "$_psk" ] || return 1
      case "$_p" in ''|*[!0-9]*) return 1 ;; esac
      _ver=$(qsdec "$_q" version)
      case "$_ver" in 5|6) ;; *) _ver=5 ;; esac
      printf '{"type":"snell","tag":"%s","server":"%s","server_port":%s,"psk":"%s","version":%s}' \
        "$_t" "$_h" "$_p" "$_psk" "$_ver"
      return 0
      ;;
    shadowtls://*)
      # shadowtls://password@host:port?sni=..&version=3  — ShadowTLSInboundOptions
      _r=$(strip_proto_q "$_u")
      _pw=${_r%%@*}; _r=${_r#*@}
      _hp=${_r%%\?*}; _q=${_r#*\?}
      split_host_port "$_hp" || return 1; _h=$NODE_HOST; _p=$NODE_PORT
      [ -n "$_h" ] && [ -n "$_p" ] && [ -n "$_pw" ] || return 1
      case "$_p" in ''|*[!0-9]*) return 1 ;; esac
      _ver=$(qsdec "$_q" version); case "$_ver" in 1|2|3) ;; *) _ver=3 ;; esac
      _sni=$(qsdec "$_q" sni)
      printf '{"type":"shadowtls","tag":"%s","server":"%s","server_port":%s,"version":%s,"password":"%s","tls":{"enabled":true,"server_name":"%s"}}' \
        "$_t" "$_h" "$_p" "$_ver" "$_pw" "${_sni:-$_h}"
      return 0
      ;;
    naive+https://*|naive+quic://*)
      # naive+https://user:pass@host:port  — NaiveOutboundOptions: username, password
      case "$_u" in naive+quic://*) _nv=quic ;; *) _nv=https ;; esac
      _r=${_u#naive+}
      _r=$(strip_proto_q "https://$_r")
      _ui=${_r%%@*}; _r=${_r#*@}
      _hp=${_r%%\?*}; _q=${_r#*\?}
      split_host_port "$_hp" || return 1; _h=$NODE_HOST; _p=$NODE_PORT
      _user=${_ui%%:*}; _pw=${_ui#*:}
      [ "$_pw" = "$_ui" ] && _pw=
      [ -n "$_h" ] && [ -n "$_p" ] && [ -n "$_user" ] || return 1
      case "$_p" in ''|*[!0-9]*) return 1 ;; esac
      _sni=$(qsdec "$_q" sni)
      printf '{"type":"naive","tag":"%s","server":"%s","server_port":%s,"username":"%s"' \
        "$_t" "$_h" "$_p" "$_user"
      [ -n "$_pw" ] && printf ',"password":"%s"' "$_pw"
      printf ',"network":"%s"' "$_nv"
      printf ',"tls":{"enabled":true,"server_name":"%s"}' "${_sni:-$_h}"
      printf '}'
      return 0
      ;;
    openvpn://*)
      # openvpn://base64(config)  — OpenVPNEndpointOptions; the endpoint is a tun-like
      # device, so it is emitted as an endpoint rather than an outbound.
      _b64=$(strip_proto "$_u")
      _b64=$(echo "$_b64" | tr -- '-_' '+/')
      _cfg=$(echo "$_b64" | base64 -d 2>/dev/null)
      [ -n "$_cfg" ] || return 1
      _cfg=$(printf '%s' "$_cfg" | tr -d '\000-\037')
      [ -n "$_cfg" ] || return 1
      printf '{"type":"openvpn","tag":"%s","config":"%s"}' "$_t" "$_cfg"
      return 0
      ;;
    openconnect://*)
      # openconnect://user:pass@host:port?server=..  — OpenConnectEndpointOptions
      _r=$(strip_proto_q "$_u")
      _ui=${_r%%@*}; _r=${_r#*@}
      _hp=${_r%%\?*}; _q=${_r#*\?}
      split_host_port "$_hp" || return 1; _h=$NODE_HOST; _p=$NODE_PORT
      _user=${_ui%%:*}; _pw=${_ui#*:}
      [ "$_pw" = "$_ui" ] && _pw=
      [ -n "$_h" ] && [ -n "$_p" ] || return 1
      case "$_p" in ''|*[!0-9]*) return 1 ;; esac
      printf '{"type":"openconnect","tag":"%s","server":"%s:%s"' "$_t" "$_h" "$_p"
      [ -n "$_user" ] && printf ',"username":"%s"' "$_user"
      [ -n "$_pw" ] && printf ',"password":"%s"' "$_pw"
      printf '}'
      return 0
      ;;
    masque://*)
      # masque://user:pass@host:port?path=..  — MASQUEEndpointOptions
      _r=$(strip_proto_q "$_u")
      _ui=${_r%%@*}; _r=${_r#*@}
      _hp=${_r%%\?*}; _q=${_r#*\?}
      split_host_port "$_hp" || return 1; _h=$NODE_HOST; _p=$NODE_PORT
      _user=${_ui%%:*}; _pw=${_ui#*:}
      [ "$_pw" = "$_ui" ] && _pw=
      [ -n "$_h" ] && [ -n "$_p" ] || return 1
      case "$_p" in ''|*[!0-9]*) return 1 ;; esac
      printf '{"type":"masque","tag":"%s","server":"%s","server_port":%s' "$_t" "$_h" "$_p"
      [ -n "$_user" ] && printf ',"username":"%s"' "$_user"
      [ -n "$_pw" ] && printf ',"password":"%s"' "$_pw"
      printf '}'
      return 0
      ;;
    tuic://*)
      # tuic://uuid:password@host:port?sni=..&alpn=h3&congestion_control=bbr
      _r=$(strip_proto_q "$_u")
      _ui=${_r%%@*}; _r=${_r#*@}
      _hp=${_r%%\?*}; _q=${_r#*\?}
      split_host_port "$_hp" || return 1; _h=$NODE_HOST; _p=$NODE_PORT
      _id=${_ui%%:*}; _pw=${_ui#*:}
      [ -n "$_h" ] && [ -n "$_p" ] && [ -n "$_id" ] && [ -n "$_pw" ] || return 1
      [ "$_id" = "$_pw" ] && return 1
      case "$_p" in ''|*[!0-9]*) return 1 ;; esac
      _sni=$(qsdec "$_q" sni)
      _alpn=$(qsdec "$_q" alpn)
      _cc=$(qsdec "$_q" congestion_control)
      [ -n "$_cc" ] || _cc=$(qsdec "$_q" congestion-controller)
      printf '{"type":"tuic","tag":"%s","server":"%s","server_port":%s,"uuid":"%s","password":"%s"' \
        "$_t" "$_h" "$_p" "$_id" "$_pw"
      printf ',"tls":{"enabled":true,"server_name":"%s"' "${_sni:-$_h}"
      [ -n "$_alpn" ] && printf ',"alpn":["%s"]' "$_alpn"
      printf '}'
      [ -n "$_cc" ] && printf ',"congestion_control":"%s"' "$_cc"
      printf '}'
      return 0
      ;;
    anytls://*)
      # anytls://password@host:port?sni=..&insecure=1
      _r=$(strip_proto_q "$_u")
      _pw=${_r%%@*}; _r=${_r#*@}
      _hp=${_r%%\?*}; _q=${_r#*\?}
      split_host_port "$_hp" || return 1; _h=$NODE_HOST; _p=$NODE_PORT
      [ -n "$_h" ] && [ -n "$_p" ] && [ -n "$_pw" ] || return 1
      case "$_p" in ''|*[!0-9]*) return 1 ;; esac
      _sni=$(qsdec "$_q" sni)
      _ins=$(qs "$_q" insecure)
      _iv=false
      case "$_ins" in 1|true|yes) _iv=true ;; esac
      printf '{"type":"anytls","tag":"%s","server":"%s","server_port":%s,"password":"%s","tls":{"enabled":true,"server_name":"%s","insecure":%s}}' \
        "$_t" "$_h" "$_p" "$_pw" "${_sni:-$_h}" "$_iv"
      return 0
      ;;
    ssr://*)
      # sing-box 内核已移除 ShadowsocksR 支持（上游不再维护 SSR 协议）。
      # 这里显式判失败，让上层把它计入「已识别但不支持」，而不是静默丢节点、
      # 也不是伪造一个内核不认的 outbound 让整份配置起不来。
      return 2
      ;;
    socks5://*|socks://*|socks5h://*)
      _r=$(strip_proto "$_u")
      # 拆掉 userinfo（user:pw@host:port → host:port）；带认证的 socks5 必须把
      # 用户名/密码写进 outbound，否则内核会以匿名身份连接，认证节点必失败。
      _ui=""
      if echo "$_r" | grep -q '@'; then _ui=${_r%%@*}; _hp=${_r#*@}; else _hp=$_r; fi
      _hp=${_hp%%[?#]*}
      split_host_port "$_hp" || return 1; _h=$NODE_HOST; _p=$NODE_PORT
      case "$_p" in ''|*[!0-9]*) return 1 ;; esac
      [ -n "$_h" ] || return 1
      printf '{"type":"socks","tag":"%s","server":"%s","server_port":%s,"version":"5"' "$_t" "$_h" "$_p"
      if [ -n "$_ui" ]; then
        _user=$(urldec "${_ui%%:*}")
        case "$_ui" in *:*) _pass=$(urldec "${_ui#*:}") ;; *) _pass="" ;; esac
        if [ -n "$_user" ]; then printf ',"username":"%s","password":"%s"' "$_user" "$_pass"; fi
      fi
      printf '}'
      return 0
      ;;
    *) return 1 ;;
  esac
}

# ---- 独立执行入口（apply.sh source 时不触发）----
case "${0##*/}" in
  vpncore.sh)
    . "$(dirname "$0")/util.sh"
    case "$1" in
      ensure) vpn_core_ensure ;;
      stop) vpncore_stop ;;
      status)
        _bi=false
        [ -f "$(vpncore_moddir 2>/dev/null)/bin/$(vpncore_arch)/sing-box" ] && _bi=true
        _run=false
        [ -f "$(vpncore_pid)" ] && _run=true
        printf '{"ok":1,"running":%s,"ver":"%s","arch":"%s","bin":"%s","builtin":%s}\n' "$_run" "$(vpncore_ver)" "$(vpncore_arch)" "$(vpncore_bin)" "$_bi"
        ;;
      genconf) vpncore_genconf ;;
      install)
        vpncore_install_builtin
        _ir=$?
        printf '{"ok":%s,"rc":%s,"arch":"%s","src":"%s"}\n' \
          "$([ $_ir -ne 1 ] && echo 1 || echo 0)" "$_ir" "$(vpncore_arch)" \
          "$(vpncore_moddir 2>/dev/null)/bin/$(vpncore_arch)/sing-box"
        ;;
      update) vpncore_download ;;
      emit-rulesets)
        # Print the rule_set definitions this module can provide, comma separated.
        # Emitting nothing is valid: a device with no lists simply gets no sets.
        _vcr_emit_rulesets
        printf '\n'
        ;;
      *) echo "usage: vpncore.sh ensure|stop|status|genconf|install|update" ;;
    esac
    ;;
esac