#!/system/bin/sh
# ============================================================
# PrivacyGuard vpnsub.sh — VPN 订阅/分流表辅助（被 apply.sh source）
#   vpn_chn_download     下载大陆分流表 → $PG/chnroute
#   vpn_update_subs      拉取全部启用订阅 → 重写 [list:vpn_node] → 自动选优
#   vpn_repair_conf      修复被历史 bug 截断的 settings.conf（从 default.conf 补骨架 + 保留节点）
#   vpn_auto_pick        测速全部候选节点 → 把 vpn_node 切到最快者
#   vpn_node_hostport    从节点 URI 提取 host:port（免 jq）
#   vpn_node_name        从节点 URI 提取名称
# ============================================================

# ---- settings.conf 骨架修复（稳健性兜底，幂等）----
# 背景：v1.10.4 的 vpnsub.sh 在 toybox awk 下可能写出「只剩节点段」的文件并把原文件
# 覆盖掉（vpn_mode/[conf:vpn]/dns_block 等骨架全丢）。用户的模块是从旧版升级上来的，
# 需要能自动把骨架补回来、同时保住用户节点。
# 策略（保守）：
#   - 缺关键骨架（vpn_mode= 或 [conf:vpn] 段头）才判定需要修复，否则完全不动
#   - 以 scripts/default.conf 为骨架补全缺失的顶层键
#   - 原文件里仍然存在的段（尤其 [list:vpn_node]）整体保留：default.conf 有的段用
#     default 的骨架，原文件有的段把原文件内容追加回去
#   - 写前备份；结果必须含 vpn_mode 且节点段存在 → 否则放弃并保留原文件
# 返回 0=无需修复或修复成功，1=修复失败（原文件保留）
vpn_repair_conf() {
  [ -f "$CONF" ] || return 0
  _rp_need=0
  grep -q '^vpn_mode=' "$CONF" 2>/dev/null || _rp_need=1
  grep -q '^\[conf:vpn\]' "$CONF" 2>/dev/null || _rp_need=1
  [ "$_rp_need" = "1" ] || return 0
  _rp_def="$MODDIR/scripts/default.conf"
  [ -s "$_rp_def" ] || _rp_def="/data/adb/modules/privacyguard/scripts/default.conf"
  if [ ! -s "$_rp_def" ]; then
    pg_log "vpnsub: settings.conf 骨架缺失，但找不到 default.conf，无法修复"
    return 1
  fi
  pg_log "vpnsub: settings.conf 骨架缺失，按 default.conf 修复（保节点段）"
  mkdir -p "$PG/backup" 2>/dev/null
  _rp_bk="$PG/backup/settings.conf.damaged.$(date +%s)"
  cp -f "$CONF" "$_rp_bk" 2>/dev/null
  _rp_out="$CONF.repair"
  rm -f "$_rp_out" 2>/dev/null
  # 第一趟：default.conf 为骨架，顶层键的值优先取原文件
  awk -v oldf="$CONF" '
    NR == FNR {
      if ($0 ~ /^\[/) { insec = 1; next }
      if (insec) next
      if ($0 ~ /^[a-z0-9_]+=/) { split($0, kv, "="); key[kv[1]] = $0 }
      next
    }
    {
      if ($0 ~ /^\[/) { print; insec2 = 1; next }
      if (insec2) { print; next }
      if ($0 ~ /^[a-z0-9_]+=/) { split($0, kv2, "="); if (kv2[1] in key) { print key[kv2[1]]; next } }
      print
    }
  ' "$CONF" "$_rp_def" > "$_rp_out" 2>/dev/null
  # 第二趟：以 default.conf 的段头为白名单，再从原 CONF 中收集
  # 不存在于默认骨架的自定义段。旧代码把文件顺序和 key 类型都写错，
  # 会把 default.conf 的标准段再次追加，产生重复 [conf:*]/[list:*] 段，
  # 而真正的用户自定义段反而可能丢失。
  _rp_add=$(awk '
    NR == FNR {
      if ($0 ~ /^\[/) known[$0] = 1
      next
    }
    /^\[/ {
      if (sec != "" && !(sec in known)) print buf
      sec = $0
      buf = $0
      next
    }
    sec != "" { buf = buf "\n" $0 }
    END { if (sec != "" && !(sec in known)) print buf }
  ' "$_rp_def" "$CONF" 2>/dev/null)
  if [ -n "$_rp_add" ]; then
    printf '\n%s\n' "$_rp_add" >> "$_rp_out"
  fi
  # 校验：必须有骨架 + 节点段，且行数不比原文件少太多
  if [ -s "$_rp_out" ] \
     && grep -q '^vpn_mode=' "$_rp_out" 2>/dev/null \
     && grep -q '^\[list:vpn_node\]' "$_rp_out" 2>/dev/null; then
    mv "$_rp_out" "$CONF"
    pg_log "vpnsub: settings.conf 已修复（损坏原件备份 $_rp_bk）"
    return 0
  fi
  rm -f "$_rp_out" 2>/dev/null
  pg_log "vpnsub: settings.conf 修复失败，保留原文件（备份 $_rp_bk）"
  return 1
}

# ---- 大陆分流表 ----
vpn_chn_download() {
  _vc_url=$(pg_conf vpn | grep -m1 '^chnroute_url=' | cut -d= -f2- | tr -d ' ')
  if [ -z "$_vc_url" ]; then
    pg_fail chn "chnroute_url 未配置"
    return 1
  fi
  if pg_fetch "$_vc_url" "$PG/chnroute.tmp" && [ -s "$PG/chnroute.tmp" ]; then
    grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' "$PG/chnroute.tmp" > "$PG/chnroute"
    rm -f "$PG/chnroute.tmp"
    _vc_n=$(wc -l < "$PG/chnroute")
    if [ "$_vc_n" -lt 100 ]; then
      pg_fail chn "分流表行数异常($_vc_n), 已丢弃"
      rm -f "$PG/chnroute"
      return 1
    fi
    pg_log "vpn: chnroute updated ($_vc_n cidrs)"
    return 0
  fi
  rm -f "$PG/chnroute.tmp"
  pg_fail chn "chnroute 下载失败"
  return 1
}

# ---- 节点 URI → host:port ----
vpn_node_hostport() {
  _u="$1"
  case "$_u" in
    vmess://*)
      _pj=$(echo "${_u#vmess://}" | base64 -d 2>/dev/null)
      [ -n "$_pj" ] || return 1
      _h=$(echo "$_pj" | tr -d ' "{}' | grep -o 'add:[^,]*' | head -1 | sed 's/^add://')
      _p=$(echo "$_pj" | tr -d ' "{}[]' | grep -o 'port:[0-9]*' | head -1 | sed 's/^port://')
      # VMess JSON 中 IPv6 地址可能带 []，也可能是不带括号的裸 IPv6；
      # host:port 在后续拆分前必须保持无歧义。
      case "$_h" in
        *:*) case "$_h" in \[*\]) : ;; *) _h="[$_h]" ;; esac ;;
      esac
      [ -n "$_h" ] && [ -n "$_p" ] && echo "$_h:$_p"
      ;;
    vless://*|trojan://*|ss://*|ssr://*|hysteria://*|hysteria2://*|tuic://*|anytls://*|socks5://*|socks5h://*)
      _r=${_u#*://}
      _r=${_r#*@}
      _r=${_r%%[/?#]*}
      echo "$_r"
      ;;
  esac
}

# ---- 节点 URI → 名称 ----
vpn_node_name() {
  _u="$1"; _i="$2"
  case "$_u" in
    vmess://*)
      _pj=$(echo "${_u#vmess://}" | base64 -d 2>/dev/null)
      if [ -n "$_pj" ]; then
        _nm=$(echo "$_pj" | sed -n 's/.*"ps"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        [ -n "$_nm" ] && { echo "$_nm"; return 0; }
      fi
      ;;
    *'#'*)
      _nm=${_u##*'#'}
      _nm=$(echo "$_nm" | sed 's/%[0-9A-Fa-f][0-9A-Fa-f]/_/g')
      [ -n "$_nm" ] && { echo "$_nm"; return 0; }
      ;;
  esac
  echo "节点 $_i"
}

# ---- Clash / Clash Meta YAML → 节点 URI ----
# Shadowrocket / ClashX / Clash Verge / Surge 等客户端导出的订阅多为 YAML（proxies: 数组），
# 不含 vmess:// 这类 URI，原来的 URI 正则 + base64 解码完全抓不到 → 导入 0 节点。
# 这里用 awk 把 proxies 段解析成制表符分隔的记录，再由 shell 拼回标准 URI，
# 复用 vpn_node_hostport / singbox_node_outbound 的既有能力，不引入新依赖。
vpn_yaml_records() {
  awk '
function trim(v){ gsub(/^[ \t]+/, "", v); gsub(/[ \t]+$/, "", v); return v }
function strip_yaml_comment(v,    i,c,q,esc,sq){
  q = ""; esc = 0; sq = sprintf("%c", 39)
  for (i = 1; i <= length(v); i++) {
    c = substr(v, i, 1)
    if (q == "\"") {
      if (esc) esc = 0
      else if (c == "\\") esc = 1
      else if (c == "\"") q = ""
    } else if (q == sq) {
      if (c == sq) q = ""
    } else if (c == "\"" || c == sq) q = c
    else if (c == "#" && (i == 1 || substr(v, i - 1, 1) ~ /[ \t]/)) return substr(v, 1, i - 1)
  }
  return v
}
function unq(v){ v = trim(v); if (v ~ /^".*"$/) v = substr(v, 2, length(v) - 2); else if (v ~ /^'"'"'.*'"'"'$/) v = substr(v, 2, length(v) - 2); return v }
function reset(){ typ = ""; name = ""; host = ""; port = ""; id = ""; pw = ""; sni = ""; net = ""; path = ""; tls = ""; cipher = ""; flow = ""; fp = ""; pbk = ""; sid = ""; alpn = ""; reality = ""; ws_host = ""; service = ""; username = "" }
function flush(){
  if (typ == "" || host == "" || port == "") return
  if (typ == "hy2") typ = "hysteria2"
  if (typ == "ssr") return
  if (typ != "vmess" && typ != "vless" && typ != "trojan" && typ != "ss" && typ != "hysteria2" && typ != "tuic" && typ != "anytls" && typ != "socks5") return
  printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n", typ, name, host, port, id, pw, sni, net, path, tls, cipher, flow, fp, pbk, sid, alpn, reality, ws_host, service, username
}
function setkv(part,   idx, k, v){
  idx = index(part, ":")
  if (idx < 2) return
  k = tolower(trim(substr(part, 1, idx - 1)))
  v = unq(substr(part, idx + 1))
  if (k == "name") name = v
  else if (k == "type") typ = tolower(v)
  else if (k == "server") host = v
  else if (k == "port") port = v
  else if (k == "uuid") id = v
  else if (k == "password" || k == "auth") pw = v
  else if (k == "cipher") cipher = v
  else if (k == "servername" || k == "sni" || k == "peer") { if (sni == "") sni = v }
  else if (k == "network") net = tolower(v)
  else if (k == "path") { if (path == "") path = v }
  else if (k == "tls") { tls = tolower(v); if (v ~ /enabled:[ \t]*true/) tls = "true" }
  else if (k == "enabled" && tolower(v) == "true") tls = "true"
  else if (k == "server_name" || k == "server-name") { if (sni == "") sni = v }
  else if (k == "flow") flow = v
  else if (k == "fingerprint" || k == "client-fingerprint") fp = v
  else if (k == "public-key" || k == "public_key") pbk = v
  else if (k == "short-id" || k == "short_id") sid = v
  else if (k == "alpn") { gsub(/[\[\]\" ]/, "", v); alpn = v }
  else if (k == "host") ws_host = v
  else if (k == "service-name" || k == "service_name" || k == "grpc-service-name" || k == "grpc_service_name") service = v
  else if (k == "username" || k == "user") username = v
  else if (k == "reality" || k == "reality-opts") reality = "1"
}
BEGIN{ inP = 0; reset() }
{
  line = strip_yaml_comment($0)
  sub(/\r$/, "", line)
  if (line ~ /^[ \t]*#/) next
  if (line ~ /^proxies[ \t]*:/) { inP = 1; next }
  if (!inP) next
  if (line ~ /^[A-Za-z][A-Za-z0-9_-]*[ \t]*:/) { flush(); inP = 0; next }
  t = line
  sub(/^[ \t]+/, "", t)
  if (t ~ /^-[ \t]+name[ \t]*:/ || t ~ /^-[ \t]*\{[ \t]*name[ \t]*:/) { flush(); reset() }
  sub(/^-[ \t]*/, "", t)
  if (t ~ /^\{/) {
    sub(/^\{/, "", t); sub(/\}$/, "", t); gsub(/,/, "\n", t)
    n = split(t, parts, "\n")
    for (i = 1; i <= n; i++) setkv(parts[i])
  } else {
    setkv(t)
  }
}
END{ flush() }
' "$1"
}

# FX_CLASH_REALITY_FIELDS_V1
# FX_CLASH_TRANSPORT_FIELDS_V1
# FX_CLASH_SOCKS_AUTH_V1
# FX_CLASH_VMESS_WS_SNI_V1
# Escape a single-line shell value for a JSON string. YAML scalar parsing here
# is line-oriented, so raw multiline scalars are not supported by this converter.
vpn_json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g'
}

vpn_yaml_to_uri() {
  _yu_f="$1"
  [ -s "$_yu_f" ] || return 0
  # Providers frequently serve UTF-8 BOM + CRLF YAML, or base64-encoded YAML.
  # Normalize a private temporary copy so the first `proxies:` key is never missed.
  mkdir -p "$PG/cache" 2>/dev/null
  _yu_norm="$PG/cache/vpn-yaml.norm.$$"
  awk 'NR==1{sub(/^\357\273\277/, "")} {sub(/\r$/, ""); print}' "$_yu_f" > "$_yu_norm" 2>/dev/null || { rm -f "$_yu_norm"; return 0; }
  grep -Eq '^[[:space:]]*proxies[[:space:]]*:' "$_yu_norm" 2>/dev/null || { rm -f "$_yu_norm"; return 0; }
  _yu_sep=$(printf '\037')
  vpn_yaml_records "$_yu_norm" 2>/dev/null | while IFS="$_yu_sep" read -r _yt _yn _yh _yp _yid _ypw _ysni _ynet _ypath _ytls _yci _yflow _yfp _ypbk _ysid _yalpn _yreality _yws_host _yservice _yusername; do
    [ -n "$_yt" ] || continue
    case "$_yp" in ''|*[!0-9]*) continue ;; esac
    [ -n "$_yh" ] || continue
    [ -n "$_yn" ] || _yn="${_yt}-${_yh}-${_yp}"
    _ysni=${_ysni:-$_yh}
    # Keep raw scalar values for VMess JSON; percent-encode only URI components.
    _yn_raw=$_yn; _ysni_raw=$_ysni; _ypath_raw=$_ypath
    _yn_uri=$(printf '%s' "$_yn" | sed 's/%/%25/g; s/#/%23/g; s/?/%3F/g; s/ /%20/g; s/\&/%26/g')
    _ysni_uri=$(printf '%s' "$_ysni" | sed 's/%/%25/g; s/#/%23/g; s/?/%3F/g; s/ /%20/g; s/\&/%26/g; s/+/%2B/g; s/=/\%3D/g; s/;/%3B/g')
    _ypath_uri=$(printf '%s' "$_ypath" | sed 's/%/%25/g; s/#/%23/g; s/?/%3F/g; s/ /%20/g; s/\&/%26/g; s/+/%2B/g; s/=/\%3D/g; s/;/%3B/g')
    _yid_uri=$(printf '%s' "$_yid" | sed 's/%/%25/g; s/@/%40/g; s/:/%3A/g; s/#/%23/g; s/ /%20/g; s/?/%3F/g; s/\&/%26/g; s/+/%2B/g; s/=/\%3D/g; s/;/%3B/g; s|/|%2F|g')
    _ypw_uri=$(printf '%s' "$_ypw" | sed 's/%/%25/g; s/@/%40/g; s/:/%3A/g; s/#/%23/g; s/ /%20/g; s/?/%3F/g; s/\&/%26/g; s/+/%2B/g; s/=/\%3D/g; s/;/%3B/g; s|/|%2F|g')
    # URI authority needs brackets around IPv6 literals.
    case "$_yh" in
      *:*) case "$_yh" in \[*\]) ;; *) _yh="[$_yh]" ;; esac ;;
    esac
    case "$_yt" in
      vmess)
        _jps=$(vpn_json_escape "$_yn")
        _jhost=$(vpn_json_escape "$_yh")
        _jport=$(vpn_json_escape "$_yp")
        _jid=$(vpn_json_escape "$_yid")
        _jscy=$(vpn_json_escape "${_yci:-auto}")
        _jnet=$(vpn_json_escape "${_ynet:-tcp}")
        _jpath=$(vpn_json_escape "${_ypath:-/}")
        _jsni=$(vpn_json_escape "$_ysni_raw")
        _jws_host=$(vpn_json_escape "${_yws_host:-$_ysni_raw}")
        _jtls=
        case "$_ytls" in true|yes|1|tls) _jtls=tls ;; esac
        _yj=$(printf '{"v":"2","ps":"%s","add":"%s","port":"%s","id":"%s","scy":"%s","net":"%s","path":"%s","host":"%s","sni":"%s","tls":"%s"}' \
          "$_jps" "$_jhost" "$_jport" "$_jid" "$_jscy" "$_jnet" "$_jpath" "$_jws_host" "$_jsni" "$_jtls")
        _yb=$(printf '%s' "$_yj" | base64 2>/dev/null | tr -d '\n')
        [ -n "$_yb" ] && echo "vmess://$_yb"
        ;;
      vless)
        _yv_security=none
        case "$_ytls" in true|yes|1|tls|enabled) _yv_security=tls ;; esac
        if [ "$_yreality" = "1" ] || [ -n "$_ypbk" ]; then
          # Never silently downgrade a Reality profile to ordinary TLS.
          [ -n "$_ypbk" ] || continue
          _yv_security=reality
        fi
        _yv_extra=
        [ -n "$_ypbk" ] && _yv_extra="$_yv_extra&pbk=$(printf '%s' "$_ypbk" | sed 's/%/%25/g; s/&/%26/g; s/#/%23/g')"
        [ -n "$_ysid" ] && _yv_extra="$_yv_extra&sid=$(printf '%s' "$_ysid" | sed 's/%/%25/g; s/&/%26/g; s/#/%23/g')"
        [ -n "$_yfp" ] && _yv_extra="$_yv_extra&fp=$(printf '%s' "$_yfp" | sed 's/%/%25/g; s/&/%26/g; s/#/%23/g')"
        [ -n "$_yflow" ] && _yv_extra="$_yv_extra&flow=$(printf '%s' "$_yflow" | sed 's/%/%25/g; s/&/%26/g; s/#/%23/g')"
        [ -n "$_yalpn" ] && _yv_extra="$_yv_extra&alpn=$(printf '%s' "$_yalpn" | sed 's/%/%25/g; s/&/%26/g; s/#/%23/g')"
        [ -n "$_yws_host" ] && _yv_extra="$_yv_extra&host=$(printf '%s' "$_yws_host" | sed 's/%/%25/g; s/&/%26/g; s/#/%23/g')"
        [ -n "$_yservice" ] && _yv_extra="$_yv_extra&serviceName=$(printf '%s' "$_yservice" | sed 's/%/%25/g; s/&/%26/g; s/#/%23/g')"
        echo "vless://${_yid_uri}@${_yh}:${_yp}?encryption=none&security=${_yv_security}&sni=${_ysni_uri}&type=${_ynet:-tcp}&path=${_ypath_uri:-/}${_yv_extra}#${_yn_uri}"
        ;;
      trojan)
        _yt_extra=
        _yt_transport=
        case "$_ynet" in
          ws|grpc) _yt_transport="&type=$_ynet&path=${_ypath_uri:-/}" ;;
          ""|tcp) [ -n "$_ypath" ] && _yt_transport="&path=$_ypath_uri" ;;
          *) _yt_transport="&type=$_ynet" ;;
        esac
        [ -n "$_yws_host" ] && _yt_extra="&host=$(printf '%s' "$_yws_host" | sed 's/%/%25/g; s/&/%26/g; s/#/%23/g')"
        [ -n "$_yservice" ] && _yt_extra="$_yt_extra&serviceName=$(printf '%s' "$_yservice" | sed 's/%/%25/g; s/&/%26/g; s/#/%23/g')"
        echo "trojan://${_ypw_uri}@${_yh}:${_yp}?sni=${_ysni_uri}${_yt_transport}${_yt_extra}#${_yn_uri}"
        ;;
      ss)
        _yb=$(printf '%s:%s' "${_yci:-aes-256-gcm}" "$_ypw" | base64 2>/dev/null | tr -d '\n')
        [ -n "$_yb" ] && echo "ss://${_yb}@${_yh}:${_yp}#${_yn}"
        ;;
      hysteria2)
        echo "hysteria2://${_ypw_uri}@${_yh}:${_yp}?sni=${_ysni_uri}#${_yn_uri}"
        ;;
      tuic)
        echo "tuic://${_yid_uri}:${_ypw_uri}@${_yh}:${_yp}?sni=${_ysni_uri}#${_yn_uri}"
        ;;
      anytls)
        echo "anytls://${_ypw_uri}@${_yh}:${_yp}?sni=${_ysni_uri}#${_yn_uri}"
        ;;
      socks5)
        if [ -n "$_yusername" ] || [ -n "$_ypw" ]; then
          # Do not silently turn an authenticated SOCKS profile into anonymous access.
          [ -n "$_yusername" ] && [ -n "$_ypw" ] || continue
          _ysocks_user=$(printf "%s" "$_yusername" | sed "s/%/%25/g; s/@/%40/g; s/:/%3A/g; s/#/%23/g; s/ /%20/g; s/&/%26/g; s/+/%2B/g; s/=/\%3D/g; s/;/%3B/g")
          echo "socks5://${_ysocks_user}:${_ypw_uri}@${_yh}:${_yp}#${_yn_uri}"
        else
          echo "socks5://${_yh}:${_yp}#${_yn_uri}"
        fi
        ;;
    esac
  done
  rm -f "$_yu_norm" 2>/dev/null
}

# ---- sing-box JSON -> canonical URI (QuickJS-NG is bundled for ARM64) ----
vpn_singbox_json_to_uri() {
  _sj_file="$1"
  _sj_qjs="$MODDIR/bin/arm64/qjs"
  _sj_script="$MODDIR/scripts/vpn-singbox-json.js"
  if [ ! -s "$_sj_file" ] || [ ! -x "$_sj_qjs" ] || [ ! -s "$_sj_script" ]; then
    pg_log "vpnsub: sing-box JSON parser unavailable or input empty (file=$_sj_file)"
    return 1
  fi
  "$_sj_qjs" --std "$_sj_script" "$_sj_file" 2>>"$PG/apply.log"
  _sj_rc=$?
  if [ "$_sj_rc" -ne 0 ]; then
    pg_log "vpnsub: sing-box JSON parser exited $_sj_rc for $_sj_file"
    return "$_sj_rc"
  fi
  return 0
}

# Logs only the subscription host; never write credential paths/query strings to apply.log.
vpn_sub_host_label() {
  _vsh="${1#*://}"
  _vsh="${_vsh%%/*}"; _vsh="${_vsh%%\?*}"; _vsh="${_vsh%%\#*}"
  _vsh="${_vsh##*@}"
  [ -n "$_vsh" ] && printf '%s' "$_vsh" || printf 'subscription'
}

# Recover an interrupted multi-file subscription commit before any new update begins.
# The journal is written only after a verified backup exists and before settings.conf
# can be replaced. If the process is killed at any point before the transaction clears
# the journal, restore that exact pre-transaction snapshot (including vpn_node).
vpn_recover_subs_transaction() {
  _vtr_journal="$PG/cache/vpn-update.transaction"
  [ -e "$_vtr_journal" ] || return 0
  _vtr_backup=$(sed -n '1p' "$_vtr_journal" 2>/dev/null)
  # Validate the backup as a direct child by basename, not only by a glob prefix:
  # shell '*' also matches '/', so a prefix-only check permits path traversal.
  _vtr_backup_name=${_vtr_backup##*/}
  case "$_vtr_backup" in
    "$PG"/backup/"$_vtr_backup_name") ;;
    *)
      pg_fail vpnsub "订阅事务恢复日志路径无效；为避免覆盖未知配置，已停止更新"
      return 1
      ;;
  esac
  case "$_vtr_backup_name" in
    settings.conf.*) ;;
    *)
      pg_fail vpnsub "订阅事务恢复日志备份名无效；为避免覆盖未知配置，已停止更新"
      return 1
      ;;
  esac
  # A journal is exactly one pathname line. Reject appended/ambiguous records.
  if [ "$(wc -l < "$_vtr_journal" 2>/dev/null)" -ne 1 ]; then
    pg_fail vpnsub "订阅事务恢复日志格式无效；为避免误恢复，已停止更新"
    return 1
  fi
  if [ ! -s "$_vtr_backup" ]; then
    pg_fail vpnsub "订阅事务恢复所需备份缺失；恢复日志已保留，已停止更新"
    return 1
  fi
  _vtr_tmp="$CONF.recover.$$"
  if ! cp -p "$_vtr_backup" "$_vtr_tmp" 2>/dev/null || [ ! -s "$_vtr_tmp" ] ||
     ! mv "$_vtr_tmp" "$CONF" 2>/dev/null; then
    rm -f "$_vtr_tmp" 2>/dev/null
    pg_fail vpnsub "订阅事务崩溃恢复失败；原备份和恢复日志均已保留"
    return 1
  fi
  if ! rm -f "$_vtr_journal" 2>/dev/null; then
    pg_fail vpnsub "订阅事务配置已恢复，但无法清除恢复日志；为避免重复提交已停止更新"
    return 1
  fi
  pg_log "vpnsub: detected interrupted subscription transaction; restored settings.conf from $_vtr_backup"
  return 0
}

# ---- 订阅更新（apply.sh vpn-sub）----
_vpn_update_subs_unlocked() {
  # Normally called under vpn-update.lock; recovery is repeated here defensively so
  # direct/internal callers cannot proceed on top of an unfinished prior commit.
  vpn_recover_subs_transaction || return 1
  _vs_subs=$(pg_list_enabled vpn_sub)
  [ -n "$_vs_subs" ] || { pg_fail vpnsub "没有启用的订阅"; return 1; }
  # 创建缓存目录必须先于重定向初始化文件；否则首次运行/缓存目录被清理时，
  # `: > file` 会失败，而后续管道仍可能继续执行并把失败伪装成普通空订阅。
  if ! mkdir -p "$PG/cache" 2>/dev/null; then
    pg_fail vpnsub "无法创建订阅缓存目录"
    return 1
  fi
  _vs_all="$PG/cache/vpn-nodes.all"
  if ! : > "$_vs_all"; then
    pg_fail vpnsub "无法初始化订阅节点缓存文件"
    return 1
  fi
  _vs_count=0
  _vs_total=0
  _vs_fetch_fail=0
  # 逐行读取：订阅 URL 可能含 & / ? 等字符，for 会按 IFS 拆词导致 URL 被截断。
  # 必须用 `done < 文件` 而非 `printf | while`：管道会在子 shell 执行，
  # _vs_count 的自增不会回传父 shell，导致成功也判成「全部订阅拉取失败」。
  _vs_urls="$PG/cache/vpnsub.urls.$$"
  printf '%s\n' "$_vs_subs" > "$_vs_urls" 2>/dev/null
  while IFS= read -r _vs_url; do
    case "$_vs_url" in
      http://*|https://*) ;;
      *) continue ;;
    esac
    _vs_total=$((_vs_total + 1))
    _vs_f="$PG/cache/vpnsub.$$"
    if pg_fetch "$_vs_url" "$_vs_f" && [ -s "$_vs_f" ]; then
      {
        grep -aoE '(vmess|vless|trojan|ss|ssr|hysteria2?|tuic|anytls|socks5?)://[A-Za-z0-9+/=:@._~?&=%#-]+' "$_vs_f" 2>/dev/null
        base64 -d "$_vs_f" 2>/dev/null | grep -aoE '(vmess|vless|trojan|ss|ssr|hysteria2?|tuic|anytls|socks5?)://[A-Za-z0-9+/=:@._~?&=%#-]+' 2>/dev/null
        # Clash YAML and sing-box JSON may themselves be base64-wrapped by providers.
        vpn_yaml_to_uri "$_vs_f" 2>/dev/null
        vpn_singbox_json_to_uri "$_vs_f" 2>/dev/null
        _vs_dec="$PG/cache/vpnsub.dec.$$"
        if base64 -d "$_vs_f" > "$_vs_dec" 2>/dev/null && [ -s "$_vs_dec" ]; then
          vpn_yaml_to_uri "$_vs_dec" 2>/dev/null
          vpn_singbox_json_to_uri "$_vs_dec" 2>/dev/null
        fi
        rm -f "$_vs_dec" 2>/dev/null
      } | head -200 >> "$_vs_all"
      _vs_count=$((_vs_count + 1))
      pg_log "vpn: fetched subscription host $(vpn_sub_host_label "$_vs_url")"
    else
      _vs_fetch_fail=$((_vs_fetch_fail + 1))
      pg_fail fetch "订阅拉取失败（服务器：$(vpn_sub_host_label "$_vs_url")；鉴权参数已隐藏）"
    fi
    rm -f "$_vs_f"
  done < "$_vs_urls"
  rm -f "$_vs_urls" 2>/dev/null
  [ "$_vs_count" -ge 1 ] || { pg_fail vpnsub "全部订阅拉取失败"; return 1; }

  # 去重 + 校验可解析
  _vs_new="$PG/cache/vpn-node.new"
  : > "$_vs_new"
  sort -u "$_vs_all" 2>/dev/null > "$_vs_all.sorted"
  while IFS= read -r _uri; do
    [ -n "$(vpn_node_hostport "$_uri")" ] && echo "$_uri" >> "$_vs_new"
  done < "$_vs_all.sorted"
  rm -f "$_vs_all.sorted" 2>/dev/null
  [ -s "$_vs_new" ] || { pg_fail vpnsub "订阅里没有识别到节点 URI"; return 1; }

  # 保留当前选中节点（顶层 vpn_node=proto:host:port）
  # 语义澄清（真机数据语义修复）：
  #   [list:vpn_node] 的第 3 字段 = 「启用」（与其它 list 段一致，pg_list_enabled 按 $3=="1"
  #   取节点、WebUI loadNodes 也按它过滤）。它**不是**「选中」——选中态由顶层
  #   vpn_node= 键表达（WebUI renderNodes 用它比对画选中态）。
  #   历史 bug：旧版 vpnsub 在这里按「是否当前节点」写 0/1，导致订阅导入后除选中项外
  #   全为 0 → genconf 只拿到 1 个节点、WebUI 列表显示为空。订阅导入即应全部启用。
  # 注意 pg_get 的默认值语义坑：`pg_get vpn_node ""` 在 util.sh 里是
  # `[ -n "$_v" ] && echo "$_v" || echo "${2:-0}"` —— 第二个参数是空串时 `:-` 会
  # 回退成 "0"，于是空配置下返回字面量 "0"。这里显式过滤掉非节点形态的返回值，
  # 否则 "0" 会被当成"已选中节点"而阻止下面的首个节点兜底（真机实测：vpn_node 一直为空）。
  _vs_sel=$(pg_get vpn_node "")
  case "$_vs_sel" in
    0|''|direct) _vs_sel="" ;;
    *://*|*:*.*) : ;;
    *) _vs_sel="" ;;
  esac
  _vs_selhp=""
  [ -n "$_vs_sel" ] && _vs_selhp=${_vs_sel#*:}

  # 生成新 [list:vpn_node] 段内容（含段头，便于直接整段替换）
  _vs_sec="$PG/cache/vpn-node.sec"
  _vs_first=""
  {
    echo "[list:vpn_node]"
    echo "# 节点列表(原始URI|节点名|1=启用) — 由订阅更新自动生成"
    _i=0
    while IFS= read -r _uri; do
      _i=$((_i + 1))
      _nm=$(vpn_node_name "$_uri" "$_i")
      _hp=$(vpn_node_hostport "$_uri")
      [ -n "$_vs_first" ] || _vs_first="${_uri%%://*}:$_hp"
      echo "$_uri|$_nm|1"
    done < "$_vs_new"
  } > "$_vs_sec"

  # 选中节点的变更延后到 settings.conf 成功提交之后。否则节点段写入失败时，
  # 顶层 vpn_node= 会先指向新节点，而原列表仍是旧列表，造成“配置半提交”。

  # 重写 settings.conf 的 [list:vpn_node] 段（其余内容原样保留）。
  #
  # ★★★ 数据安全（真机事故后加固）★★★
  # 旧实现只有一个守卫：「新文件里含任意一条节点 URI」→ 直接 `mv "$1" "$CONF"`。
  # 这在真机上造成过**用户配置全毁**：toybox awk 的 `getline < secf` 失败时不报错、
  # 只产出「含新节点段、但其余内容为空」的文件 → 守卫通过 → mv 覆盖 →
  # 用户 settings.conf 从 16KB 变成 366B（vpn_mode/[conf:vpn]/dns_block/伪装键全丢），
  # 而且 rc=0 报成功。这类「静默数据销毁」比功能不可用严重得多，必须结构性防御：
  #   1) 写前备份（保留最近 2 份，可回滚）
  #   2) 新文件必须同时满足：非空 + 含节点段头 + 含节点 URI + **段数不少于原文件** +
  #      行数不少于原文件的 80% —— 任一不满足即拒绝写入、保留原文件
  #   3) awk 输出 rc / 空文件检测；失败走「原文件不动 + pg_fail」而不是追加兜底覆盖
  _vs_backup() {
    if ! mkdir -p "$PG/backup" 2>/dev/null; then
      pg_log "vpnsub: 无法创建配置备份目录；拒绝覆盖 settings.conf"
      return 1
    fi
    _bk="$PG/backup/settings.conf.$(date +%s).$$"
    if ! cp -p "$CONF" "$_bk" 2>/dev/null || [ ! -s "$_bk" ]; then
      rm -f "$_bk" 2>/dev/null
      pg_log "vpnsub: settings.conf 备份失败；拒绝覆盖原配置"
      return 1
    fi
    # Atomic intent record: a SIGKILL after settings.conf replacement (or after
    # pg_set vpn_node) must not leave the list and selected-node key from different
    # transaction generations. If the journal cannot be published, abort before commit.
    _vs_journal="$PG/cache/vpn-update.transaction"
    _vs_journal_tmp="$_vs_journal.tmp.$$"
    if ! printf '%s\n' "$_bk" > "$_vs_journal_tmp" 2>/dev/null ||
       ! chmod 600 "$_vs_journal_tmp" 2>/dev/null ||
       ! mv "$_vs_journal_tmp" "$_vs_journal" 2>/dev/null; then
      rm -f "$_vs_journal_tmp" 2>/dev/null
      pg_log "vpnsub: cannot publish transaction recovery journal; refusing settings.conf commit"
      return 1
    fi
    if ! printf '%s\n' "$_bk" > "$PG/backup/settings.conf.latest.tmp.$$" 2>/dev/null ||
       ! mv "$PG/backup/settings.conf.latest.tmp.$$" "$PG/backup/settings.conf.latest" 2>/dev/null; then
      rm -f "$PG/backup/settings.conf.latest.tmp.$$" 2>/dev/null
      # 备份文件本身已存在；latest 指针失败不应导致丢失这份可恢复副本。
      pg_log "vpnsub: latest 备份指针更新失败，但备份副本已保留：$_bk"
    fi
    # 只保留最近 2 份（避免无限增长）；保留当前刚创建的备份。
    _keep=$(ls -1t "$PG/backup"/settings.conf.* 2>/dev/null | grep -v '\.latest$' | grep -v '\.tmp\.' | tail -n +3)
    for _f in $_keep; do [ "$_f" = "$_bk" ] || rm -f "$_f" 2>/dev/null; done
    return 0
  }

  # 结构完整性校验：$1=候选文件。返回 0=可以覆盖 CONF
  _vs_validate() {
    _v_new="$1"
    [ -s "$_v_new" ] || { pg_log "vpnsub: 拒绝写入——候选文件为空"; return 1; }
    grep -q '^\[list:vpn_node\]' "$_v_new" 2>/dev/null \
      || { pg_log "vpnsub: 拒绝写入——候选缺少 [list:vpn_node] 段头"; return 1; }
    grep -qE '^(vmess|vless|trojan|ss|ssr|hysteria2|tuic|anytls|socks5)://' "$_v_new" 2>/dev/null \
      || { pg_log "vpnsub: 拒绝写入——候选不含任何节点 URI"; return 1; }
    # 段数不得减少（丢了 [conf:vpn] 之类的骨架段就是被截断）
    _v_osec=$(grep -c '^\[' "$CONF" 2>/dev/null)
    _v_nsec=$(grep -c '^\[' "$_v_new" 2>/dev/null)
    case "$_v_osec" in ''|*[!0-9]*) _v_osec=0 ;; esac
    case "$_v_nsec" in ''|*[!0-9]*) _v_nsec=0 ;; esac
    if [ "$_v_nsec" -lt "$_v_osec" ]; then
      pg_log "vpnsub: 拒绝写入——段数 $_v_nsec < 原 $_v_osec（疑似截断，保留原配置）"
      return 1
    fi
    # 不可直接比较整份文件行数：节点列表本身允许合法缩减（例如旧订阅 1000 个节点，
    # 新订阅只有 10 个），按原文件 80% 阈值会把正常更新误判为配置截断。
    # 改为剔除可变的 [list:vpn_node] 段后比较其余非空行；这样节点数量可以变化，
    # 但 vpn_mode、[conf:vpn]、DNS、hosts 等非节点配置不得丢失或被改写。
    _v_old_rest="$PG/cache/settings.nonnode.old.$$"
    _v_new_rest="$PG/cache/settings.nonnode.new.$$"
    if ! awk '
      /^\[list:vpn_node\]/ { inlist = 1; next }
      inlist && /^\[/ { inlist = 0 }
      inlist { next }
      NF == 0 { next }
      { print }
    ' "$CONF" > "$_v_old_rest" 2>/dev/null ||
       ! awk '
      /^\[list:vpn_node\]/ { inlist = 1; next }
      inlist && /^\[/ { inlist = 0 }
      inlist { next }
      NF == 0 { next }
      { print }
    ' "$_v_new" > "$_v_new_rest" 2>/dev/null; then
      rm -f "$_v_old_rest" "$_v_new_rest" 2>/dev/null
      pg_log "vpnsub: 拒绝写入——无法校验非节点配置是否完整"
      return 1
    fi
    if ! cmp -s "$_v_old_rest" "$_v_new_rest"; then
      rm -f "$_v_old_rest" "$_v_new_rest" 2>/dev/null
      pg_log "vpnsub: 拒绝写入——非节点配置发生变化或疑似截断，保留原配置"
      return 1
    fi
    rm -f "$_v_old_rest" "$_v_new_rest" 2>/dev/null
    return 0
  }

  _vs_write() {
    if ! _vs_validate "$1"; then
      rm -f "$1" 2>/dev/null
      return 1
    fi
    if ! _vs_backup; then
      rm -f "$1" 2>/dev/null
      return 1
    fi
    if mv "$1" "$CONF" 2>/dev/null; then
      pg_log "vpnsub: settings.conf 已更新（备份见 $PG/backup/）"
      return 0
    fi
    rm -f "$1" 2>/dev/null
    return 1
  }
  _vs_ok=0
  _vs_awked=0
  _vs_had_node_section=0
  if grep -q '^\[list:vpn_node\]' "$CONF" 2>/dev/null; then
    _vs_had_node_section=1
    rm -f "$CONF.new" 2>/dev/null
    awk -v secf="$_vs_sec" '
      BEGIN { state = 0 }
      state == 0 && /^\[list:vpn_node\]/ {
        while ((getline l < secf) > 0) print l
        close(secf)
        state = 1
        next
      }
      state == 1 && /^\[/ { state = 0 }
      state == 1 { next }
      { print }
      END { exit 0 }
    ' "$CONF" > "$CONF.new" 2>>"$PG/apply.log"
    _vs_arc=$?
    # awk rc≠0 或产物为空 → 视为重写失败，绝不覆盖原文件
    if [ "$_vs_arc" -ne 0 ] || [ ! -s "$CONF.new" ]; then
      pg_log "vpnsub: awk 重写段失败(rc=$_vs_arc)，保留原配置，走插入路径"
      rm -f "$CONF.new" 2>/dev/null
    else
      _vs_awked=1
      _vs_write "$CONF.new" && _vs_ok=1
    fi
  fi
  if [ "$_vs_ok" != 1 ]; then
    # 如果原配置已经有 [list:vpn_node]，重写失败后绝不能走“插入”兜底：
    # 这会留下两个同名段，解析器可能读取旧段/新段之一，造成 UI 与核心看到不同节点。
    # 只有首次导入（原来没有节点段）才允许插入新段；已有段的改写失败必须中止并保留原文件。
    if [ "$_vs_had_node_section" = 1 ]; then
      rm -f "$CONF.new" 2>/dev/null
      pg_fail vpnsub "现有节点段重写或安全校验失败；为避免重复 [list:vpn_node] 段，已保留原配置并中止更新"
      return 1
    fi
    # 段不存在（首次导入）：改成**插入**新段（不删原有内容）
    if grep -q '^\[list:vpn_direct\]' "$CONF" 2>/dev/null; then
      rm -f "$CONF.new" 2>/dev/null
      awk -v blkf="$_vs_sec" '
        BEGIN { done_ins = 0 }
        !done_ins && /^\[list:vpn_direct\]/ {
          while ((getline l < blkf) > 0) print l
          close(blkf)
          print ""
          done_ins = 1
          print
          next
        }
        { print }
      ' "$CONF" > "$CONF.new" 2>>"$PG/apply.log"
      if ! _vs_write "$CONF.new"; then
        # 插入也失败：原文件保持不动，明确报错（不再用 cat >> 覆盖，避免二次损坏）
        pg_fail vpnsub "节点段写入被安全校验拒绝（原配置已保留，未做任何覆盖）"
        return 1
      fi
    else
      # 没有 [list:vpn_direct] 锚点：把新段追加到候选文件，再统一执行结构校验和原子替换。
      # 不直接改写 CONF，避免追加/磁盘写入失败时留下半截配置。
      rm -f "$CONF.new" 2>/dev/null
      if ! { cat "$CONF" && printf '\n' && cat "$_vs_sec"; } > "$CONF.new"; then
        rm -f "$CONF.new" 2>/dev/null
        pg_fail vpnsub "无法生成节点配置候选文件（原配置已保留）"
        return 1
      fi
      if ! _vs_write "$CONF.new"; then
        pg_fail vpnsub "节点段追加未通过安全校验（原配置已保留）"
        return 1
      fi
    fi
    grep -qE '^(vmess|vless|trojan|ss|ssr|hysteria2|tuic|anytls|socks5)://' "$CONF" 2>/dev/null || {
      pg_fail vpnsub "节点写入 settings.conf 失败"
      return 1
    }
  fi

  # 只有节点段成功提交后才同步顶层选择值，避免订阅失败留下新旧配置不一致。
  if [ -n "$_vs_selhp" ] && grep -qF "$_vs_selhp" "$_vs_new" 2>/dev/null; then
    pg_log "vpn: keep selected node $_vs_sel"
  elif [ -n "$_vs_first" ]; then
    if pg_set vpn_node "$_vs_first"; then
      pg_log "vpn: selected node -> $_vs_first"
    else
      # 节点列表已提交，但顶层选择值写入失败时，不能把新列表留在磁盘上，
      # 否则 settings.conf 会处于“新节点列表 + 旧选择值”的半提交状态。
      # 只回滚本次刚创建并验证过的备份；恢复先写临时文件，再同目录 mv，
      # 避免 cp 直接覆盖时进程中断留下半份 settings.conf。
      _vs_restore_ok=0
      _vs_restore_tmp="$CONF.rollback.$$"
      if [ -n "$_bk" ] && [ -s "$_bk" ] &&
         cp -p "$_bk" "$_vs_restore_tmp" 2>/dev/null &&
         [ -s "$_vs_restore_tmp" ] &&
         mv "$_vs_restore_tmp" "$CONF" 2>/dev/null; then
        _vs_restore_ok=1
        pg_log "vpnsub: 默认节点选择保存失败，已恢复原 settings.conf（备份 $_bk）"
      else
        rm -f "$_vs_restore_tmp" 2>/dev/null
        pg_log "vpnsub: 默认节点选择保存失败，且自动恢复未完成；原始备份保留：$_bk"
      fi
      if [ "$_vs_restore_ok" = 1 ]; then
        pg_fail vpnsub "默认节点选择保存失败；已回滚本次订阅配置，请检查权限或磁盘空间"
      else
        pg_fail vpnsub "默认节点选择保存失败，自动回滚未完成；请从备份恢复 settings.conf"
      fi
      return 1
    fi
  fi

  _vs_n=$(grep -vc '^#' "$_vs_new")
  if [ "$_vs_fetch_fail" -gt 0 ]; then
    pg_fail vpnsub "订阅部分更新：成功拉取 $_vs_count/$_vs_total 个，失败 $_vs_fetch_fail 个；本次写入 $_vs_n 个节点，请检查失败订阅 URL 和网络"
    pg_log "vpn: subscriptions partially updated ($_vs_count/$_vs_total subs fetched, $_vs_fetch_fail fetch failures, $_vs_n nodes)"
  else
    pg_log "vpn: subscriptions updated ($_vs_count subs, $_vs_n nodes)"
  fi

  # 旧数据规整：历史上 vpnsub 把第 3 字段当"选中"写 0/1，产物是「有节点但全 0」。
  # 这种段会让 pg_list_enabled 取到 0 个节点（genconf 直接失败）、WebUI 列表空白。
  #
  # 实现要点（踩过的坑）：**必须先判断再改，不能先缓冲整份文件**。
  # 之前写成「把全部行塞进 lines[] 再在 END 里按分支输出」，结果非 vpn_node 段的
  # 内容只在 else 分支输出——一旦触发规整分支，整份 settings.conf 被削成只剩
  # [list:vpn_node]，hosts_block/vpn_mode 等顶层开关全部丢失（真机实测：apply 里
  # "hosts: disabled"、"fw: all off"）。这里改成两趟：先数一遍，再只对该段 sed。
  _vs_legacy_fix() {
    [ -f "$CONF" ] || return 0
    _lf_stat=$(awk '
      /^\[list:vpn_node\]/ { inlist = 1; next }
      inlist && /^\[/        { inlist = 0 }
      inlist && $0 !~ /^[[:space:]]*#/ && index($0, "|") > 0 {
        n = split($0, f, "|")
        if (n >= 3 && f[1] != "") { nodes++; if (f[3] == "1") ones++ }
      }
      END { printf "%d %d", nodes + 0, ones + 0 }
    ' "$CONF" 2>/dev/null)
    _lf_nodes=${_lf_stat%% *}
    _lf_ones=${_lf_stat##* }
    case "$_lf_nodes" in ''|*[!0-9]*) return 0 ;; esac
    case "$_lf_ones"  in ''|*[!0-9]*) return 0 ;; esac
    [ "$_lf_nodes" -gt 0 ] || return 0
    [ "$_lf_ones" -eq 0 ] || return 0
    # 仅重写 [list:vpn_node] 段内的节点行（第 3 字段置 1），其余行原样输出
    awk '
      /^\[list:vpn_node\]/ { inlist = 1; print; next }
      inlist && /^\[/        { inlist = 0 }
      {
        if (inlist && $0 !~ /^[[:space:]]*#/ && index($0, "|") > 0) {
          n = split($0, f, "|")
          if (n >= 3 && f[1] != "") {
            o = f[1]
            for (j = 2; j < n; j++) o = o "|" f[j]
            print o "|1"
            next
          }
        }
        print
      }
    ' "$CONF" > "$CONF.tmp3" 2>/dev/null
    # 校验：新文件必须仍含段头、且不只是节点段（防止再次把整份配置削掉）
    if [ -s "$CONF.tmp3" ] && grep -q '^\[list:vpn_node\]' "$CONF.tmp3" 2>/dev/null \
       && [ "$(grep -c '^\[' "$CONF.tmp3")" -ge "$(grep -c '^\[' "$CONF")" ]; then
      mv "$CONF.tmp3" "$CONF"
      pg_log "vpn: normalized legacy [list:vpn_node] (3rd field all 0 -> 1, $_lf_nodes nodes)"
    else
      rm -f "$CONF.tmp3" 2>/dev/null
      pg_log "vpn: legacy normalize skipped (safety check failed)"
    fi
    return 0
  }
  _vs_legacy_fix

  # 自动选优：vpn_auto_pick=1 时测速全部节点，切到延迟最低者
  if [ "$(pg_get vpn_auto_pick 0)" = "1" ]; then
    vpn_auto_pick "$_vs_new" || pg_log "vpn: autopick 未切换（无可用更快节点）"
  fi
  # The transaction is complete only after list commit and selected-node persistence.
  # Failure to remove the journal is safe: the next invocation rolls back to backup.
  if ! rm -f "$PG/cache/vpn-update.transaction" 2>/dev/null; then
    pg_fail vpnsub "订阅配置已写入，但无法清除事务日志；下次更新将先恢复旧配置"
    return 1
  fi
  return 0
}

# Serialize the entire VPN subscription transaction. This function is sourced by
# apply.sh and can be entered by manual refresh, boot updater, or watchdog paths
# in separate processes. The transaction uses shared cache names and settings.conf.new;
# without a lock concurrent updates can truncate each other's candidates or roll back
# over a newer successful commit.
vpn_update_subs() {
  _vul_lock="$PG/cache/vpn-update.lock"
  if ! mkdir -p "$PG/cache" 2>/dev/null; then
    pg_fail vpnsub "无法创建订阅事务锁目录"
    return 1
  fi
  _vul_tries=0
  while ! mkdir "$_vul_lock" 2>/dev/null; do
    _vul_owner=$(cat "$_vul_lock/pid" 2>/dev/null || true)
    case "$_vul_owner" in
      ''|*[!0-9]*)
        # PID 尚未发布时无法安全地区分「刚 mkdir、正准备写 PID 的活进程」
        # 和「崩溃遗留的空锁」。按时间强制 mv 会有极小但真实的双持锁窗口，
        # 因此只等待有限时间后 fail-closed；不自动删除所有者未知的锁。
        if [ "$_vul_tries" -ge 30 ]; then
          pg_fail vpnsub "订阅事务锁没有有效 PID；为避免并发覆盖，已停止更新。确认无更新进程后可手动清理 $_vul_lock"
          return 75
        fi
        _vul_tries=$((_vul_tries + 1)); sleep 0.1
        ;;
      *)
        if kill -0 "$_vul_owner" 2>/dev/null; then
          [ "$_vul_tries" -lt 600 ] || { pg_fail vpnsub "订阅更新正在执行，请稍后重试"; return 75; }
          _vul_tries=$((_vul_tries + 1)); sleep 0.1
        else
          # Serialize stale-lock reclamation with a sibling guard directory.
          # A marker inside the lock itself is unsafe: after the old lock is
          # renamed, a delayed waiter can create that marker inside a replacement
          # lock before its PID is published. The sibling guard remains separate
          # from every lock generation. Always re-read the owner while holding it.
          _vul_stale_owner="$_vul_owner"
          _vul_reap_lock="$_vul_lock.reaper"
          if mkdir "$_vul_reap_lock" 2>/dev/null; then
            if ! printf '%s\n' "$$" > "$_vul_reap_lock/pid" 2>/dev/null; then
              rm -rf "$_vul_reap_lock" 2>/dev/null || :
              pg_fail vpnsub "无法登记失效锁回收所有者；为避免并发覆盖，已停止更新"
              return 75
            fi
            _vul_recheck=$(cat "$_vul_lock/pid" 2>/dev/null || true)
            if [ "$_vul_recheck" = "$_vul_stale_owner" ] &&
               ! kill -0 "$_vul_recheck" 2>/dev/null; then
              _vul_stale="$_vul_lock.stale.$$.$_vul_tries"
              if mv "$_vul_lock" "$_vul_stale" 2>/dev/null; then
                rm -rf "$_vul_stale" 2>/dev/null || :
              fi
            fi
            _vul_reap_owner=$(cat "$_vul_reap_lock/pid" 2>/dev/null || true)
            if [ "$_vul_reap_owner" = "$$" ]; then rm -rf "$_vul_reap_lock" 2>/dev/null || :; fi
          else
            # Another reaper owns the guard. Do not infer that either the guard
            # or target lock is stale from a missing/partial PID; fail closed.
            _vul_tries=$((_vul_tries + 1))
            [ "$_vul_tries" -lt 30 ] || { pg_fail vpnsub "订阅锁正在回收或回收状态未知；为避免并发覆盖，已停止更新"; return 75; }
            sleep 0.1
            continue
          fi
          _vul_tries=$((_vul_tries + 1))
          [ "$_vul_tries" -lt 600 ] || { pg_fail vpnsub "订阅锁回收未能安全完成，请稍后重试"; return 75; }
          sleep 0.1
        fi
        ;;
    esac
  done
  if ! printf '%s\n' "$$" > "$_vul_lock/pid"; then
    rmdir "$_vul_lock" 2>/dev/null || :
    pg_fail vpnsub "无法登记订阅事务锁所有者"
    return 1
  fi
  if vpn_recover_subs_transaction; then
    if _vpn_update_subs_unlocked; then _vul_rc=0; else _vul_rc=$?; fi
  else
    _vul_rc=1
  fi
  _vul_owner=$(cat "$_vul_lock/pid" 2>/dev/null || true)
  if [ "$_vul_owner" = "$$" ]; then
    rm -f "$_vul_lock/pid" 2>/dev/null || :
    rmdir "$_vul_lock" 2>/dev/null || :
  fi
  return "$_vul_rc"
}

# ---- 单节点测速：输出毫秒数（失败/无 curl 输出空） ----
# 与 vpntest.sh 同一方法（curl time_connect），此处内联以便批量循环少起进程
vpn_ping_ms() {
  _pp_h="$1"; _pp_p="$2"; _pp_to="${3:-5}"
  case "$_pp_p" in ''|*[!0-9]*) echo ""; return 1 ;; esac
  if ! pg_have curl; then echo ""; return 1; fi
  _pp_t=$(curl -o /dev/null -sS -m "$_pp_to" -w '%{time_connect}' "telnet://$_pp_h:$_pp_p" 2>/dev/null)
  case "$_pp_t" in ''|0.00*|0) echo ""; return 1 ;; esac
  _pp_ms=$(awk -v t="$_pp_t" 'BEGIN{printf "%d", t*1000}')
  case "$_pp_ms" in ''|*[!0-9]*) echo ""; return 1 ;; esac
  echo "$_pp_ms"
  return 0
}

# ---- 自动选优：测速全部候选节点，把 vpn_node 切到最快者 ----
# 参数 $1 = 候选 URI 清单文件（每行一个节点 URI）
# 说明：只按「延迟」选优（TCP time_connect），不含带宽测速；阈值与超时见
#       [conf:vpn] pick_min_ms / pick_test_timeout / pick_max_nodes。
# 注意：本函数在 vpn_update_subs 里调用，_vs_* 变量仍可见，勿用同名局部变量。
vpn_auto_pick() {
  _ap_file="$1"
  [ -s "$_ap_file" ] || { pg_log "vpn: autopick skip (no candidates)"; return 1; }
  _ap_min=$(pg_conf vpn | grep -m1 '^pick_min_ms=' | cut -d= -f2- | tr -d ' ')
  _ap_min=${_ap_min:-80}
  _ap_to=$(pg_conf vpn | grep -m1 '^pick_test_timeout=' | cut -d= -f2- | tr -d ' ')
  _ap_to=${_ap_to:-5}
  _ap_max=$(pg_conf vpn | grep -m1 '^pick_max_nodes=' | cut -d= -f2- | tr -d ' ')
  _ap_max=${_ap_max:-60}
  case "$_ap_min" in ''|*[!0-9]*) _ap_min=80 ;; esac
  case "$_ap_to"  in ''|*[!0-9]*) _ap_to=5 ;; esac
  case "$_ap_max" in ''|*[!0-9]*) _ap_max=60 ;; esac
  # 参数边界：先限制数字串长度，避免超大整数触发 toybox test 的数值溢出。
  # 再做数值范围校验，防止损坏/手工写入的极端配置造成超长阻塞。
  [ "${#_ap_min}" -gt 5 ] && _ap_min=60000
  [ "${#_ap_to}" -gt 2 ] && _ap_to=30
  [ "${#_ap_max}" -gt 3 ] && _ap_max=300
  [ "$_ap_min" -lt 1 ] 2>/dev/null && _ap_min=80
  [ "$_ap_min" -gt 60000 ] 2>/dev/null && _ap_min=60000
  [ "$_ap_to" -lt 1 ] 2>/dev/null && _ap_to=5
  [ "$_ap_to" -gt 30 ] 2>/dev/null && _ap_to=30
  [ "$_ap_max" -lt 1 ] 2>/dev/null && _ap_max=60
  [ "$_ap_max" -gt 300 ] 2>/dev/null && _ap_max=300
  # 无 curl 时无测速手段：明确记录并保留当前节点（不能盲切）
  if ! pg_have curl; then
    pg_log "vpn: autopick: 无 curl，无法测速，保留当前节点"
    return 1
  fi
  _ap_i=0
  _ap_best_uri=""
  _ap_best_ms=999999
  _ap_tried=0
  _ap_fail=0
  while IFS= read -r _uri; do
    [ -n "$_uri" ] || continue
    _hp=$(vpn_node_hostport "$_uri")
    [ -n "$_hp" ] || continue
    _ap_h=${_hp%:*}
    _ap_p=${_hp##*:}
    case "$_ap_p" in ''|*[!0-9]*) continue ;; esac
    [ "$_ap_p" -ge 1 ] 2>/dev/null && [ "$_ap_p" -le 65535 ] 2>/dev/null || continue
    [ -n "$_ap_h" ] || continue
    _ap_i=$((_ap_i + 1))
    [ "$_ap_i" -gt "$_ap_max" ] && break
    _proto=${_uri%%://*}
    _ap_ms=$(vpn_ping_ms "$_ap_h" "$_ap_p" "$_ap_to")
    if [ -z "$_ap_ms" ]; then
      _ap_fail=$((_ap_fail + 1))
      continue
    fi
    _ap_tried=$((_ap_tried + 1))
    if [ "$_ap_ms" -lt "$_ap_best_ms" ]; then
      _ap_best_ms=$_ap_ms
      _ap_best_uri=$_uri
    fi
  done < "$_ap_file"
  if [ -z "$_ap_best_uri" ] || [ "$_ap_best_ms" -ge "$_ap_min" ]; then
    if [ -z "$_ap_best_uri" ]; then
      pg_log "vpn: autopick: no reachable node (reachable=0, unreachable=$_ap_fail)"
    else
      pg_log "vpn: autopick: best ${_ap_best_ms}ms >= min ${_ap_min}ms, keep current node"
    fi
    return 1
  fi
  _ap_hp=$(vpn_node_hostport "$_ap_best_uri")
  _ap_nm=$(vpn_node_name "$_ap_best_uri" 0)
  _ap_proto=${_ap_best_uri%%://*}
  _ap_new="${_ap_proto}:${_ap_hp}"
  # 「选中」唯一来源是顶层 vpn_node=；不再改写 [list:vpn_node] 第 3 字段
  # （该字段是「启用」，WebUI loadNodes 与 pg_list_enabled 都按 $3=="1" 解释）。
  pg_set vpn_node "$_ap_new"
  pg_log "vpn: autopick -> $_ap_new (${_ap_nm}, ${_ap_best_ms}ms, tried $_ap_tried)"
  return 0
}
