#!/system/bin/sh
# ============================================================
#  route.sh — 规则路由层（profile 单一事实源）
#
#  设计要点：
#    · config/profile.json 是唯一事实源（节点/策略组/规则/DNS/通用）
#    · 内核配置由 abserver route compile 从 profile 编译出来，
#      不再由 shell 拼字符串 —— 拼字符串既没法做策略组，
#      也没法按内核版本切换语法
#    · 规则集优先用模块内置的 .srs，做到完全离线可用
#    · 目标内核版本从实际内核二进制读出来，避免配置语法与内核不匹配
#
#  用法:
#    route.sh status                     概览
#    route.sh seed                       从旧的节点/选中状态生成 profile
#    route.sh profile                    输出 profile.json
#    route.sh set-profile <base64>       写入 profile.json
#    route.sh compile [--force]          编译内核配置
#    route.sh lint [-json]               规则体检
#    route.sh explain [-json]            规则编译对照
#    route.sh test -domain D [-ip I]...  规则命中推演
#    route.sh import -in F [-format auto] [-merge]  多格式导入
#    route.sh mirrors [-probe]           规则集镜像
#    route.sh fetch-rules                下载规则集到本地
#    route.sh clash <子命令...>           Clash API 透传
# ============================================================
. "$(dirname "$0")/common.sh"

PN="$DATA_DIR/rules/proxy"
PROFILE="$PN/profile.json"
CFG="$PN/config.json"
LEGACY_NODES="$PN/nodes.conf"
LEGACY_SELECTED="$PN/.selected"
RS_LOCAL="$PN/rulesets"
RS_BUILTIN="$MODDIR/rulesets"

PROXY_PORT=$(cfg_get PROXY_PORT 2080)
CLASH_PORT=$(cfg_get CLASH_API_PORT 9090)

AB="$BIN"
[ -x "$AB" ] || AB="$MODDIR/bin/abserver"

# ---------- 内核 ----------
route_core_path() {
  if [ -n "${CORE_FLAG:-}" ] && [ -f "$CORE_FLAG" ]; then cat "$CORE_FLAG"; return; fi
  for c in "$MODDIR/bin/sing-box" "$MODDIR/bin/singbox" \
           "$MODDIR/bin/kernels/"sing-box-* "$MODDIR/bin/core/"sing-box-* \
           "$MODDIR/bin/"sing-box-*/sing-box "$PN/.core_path"; do
    [ -x "$c" ] && { echo "$c"; return; }
    [ -f "$c" ] && { cat "$c"; return; }
  done
  echo ""
}

# 内核版本决定配置语法断代，必须问真内核，不能猜
route_core_ver() {
  core="$(route_core_path)"
  [ -n "$core" ] && [ -x "$core" ] || { echo ""; return; }
  v="$("$core" version 2>/dev/null | head -n1 | sed -n 's/^sing-box version *v\{0,1\}\([0-9][0-9.]*\).*/\1/p')"
  echo "$v"
}

# 规则集目录：优先本地缓存（可写），其次模块内置（只读）
route_rs_dir() {
  if [ -d "$RS_LOCAL" ] && [ -n "$(ls -A "$RS_LOCAL" 2>/dev/null)" ]; then
    echo "$RS_LOCAL"; return
  fi
  if [ -d "$RS_BUILTIN" ] && [ -n "$(ls -A "$RS_BUILTIN" 2>/dev/null)" ]; then
    echo "$RS_BUILTIN"; return
  fi
  echo ""
}

# ---------- 从旧状态生成 profile ----------
route_seed() {
  mkdir -p "$PN"
  sel="$(cat "$LEGACY_SELECTED" 2>/dev/null)"
  [ -z "$sel" ] && sel=1

  nodes_json=""
  if [ -f "$LEGACY_NODES" ]; then
    while IFS= read -r ln; do
      [ -z "$ln" ] && continue
      remark="$(printf '%s' "$ln" | cut -d'|' -f1)"
      proto="$(printf '%s' "$ln" | cut -d'|' -f2)"
      link="$(printf '%s' "$ln" | cut -d'|' -f3-)"
      case "$link" in
        *://*) : ;;
        *) continue ;;
      esac
      # 交给 abserver 解析分享链接，落到临时 profile 再合并
      tmp="$CACHE/seed_one.json"
      printf '%s\n' "$link" > "$CACHE/seed_one.txt"
      "$AB" route import -in "$CACHE/seed_one.txt" -format share-links \
            -out "$tmp" -quiet >/dev/null 2>&1 || continue
      if [ -n "$nodes_json" ]; then nodes_json="$nodes_json,"; fi
      # 只取解析出的第一个节点对象
      obj="$(sed -n 's/.*"nodes"[[:space:]]*:[[:space:]]*\[\(.*\)\].*/\1/p' "$tmp" | head -n1)"
      [ -z "$obj" ] && continue
      # 用备注覆盖名字，方便识别
      [ -n "$remark" ] && obj="$(printf '%s' "$obj" | sed "s|\"name\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"name\":\"$(json_escape "$remark")\"|")"
      nodes_json="$nodes_json$obj"
    done < "$LEGACY_NODES"
  fi

  [ -z "$nodes_json" ] && { echo "ERR: 没有可用节点，请先添加节点"; return 1; }

  # 目标内核版本
  kver="$(route_core_ver)"
  [ -z "$kver" ] && kver="$(cfg_get PROXY_CORE_VER 1.14.3)"

  {
    printf '{\n'
    printf '  "nodes": [%s],\n' "$nodes_json"
    printf '  "groups": [\n'
    printf '    {"name":"PROXY","type":"select","proxies":["auto","DIRECT"]},\n'
    printf '    {"name":"auto","type":"url-test","proxies":[],"url":"http://www.gstatic.com/generate_204","interval":300}\n'
    printf '  ],\n'
    printf '  "rule_sets": [],\n'
    printf '  "rules": [\n'
    printf '    {"kind":"GEOSITE","payload":"category-ads-all","policy":"REJECT","enabled":true},\n'
    printf '    {"kind":"GEOSITE","payload":"private","policy":"DIRECT","enabled":true},\n'
    printf '    {"kind":"GEOSITE","payload":"cn","policy":"DIRECT","enabled":true},\n'
    printf '    {"kind":"GEOIP","payload":"cn","policy":"DIRECT","enabled":true},\n'
    printf '    {"kind":"MATCH","payload":"*","policy":"PROXY","enabled":true}\n'
    printf '  ],\n'
    printf '  "dns": {\n'
    printf '    "enabled": true,\n'
    printf '    "servers": [\n'
    printf '      {"tag":"local","address":"223.5.5.5"},\n'
    printf '      {"tag":"remote","address":"https://1.1.1.1/dns-query","detour":"proxy"}\n'
    printf '    ],\n'
    printf '    "final": "local",\n'
    printf '    "strategy": "prefer_ipv4"\n'
    printf '  },\n'
    printf '  "general": {\n'
    printf '    "log_level": "%s",\n' "$(cfg_get PROXY_LOG_LEVEL warn)"
    printf '    "mixed_port": %s,\n' "$PROXY_PORT"
    printf '    "tun_enabled": true,\n'
    printf '    "tun_stack": "mixed",\n'
    printf '    "tun_mtu": 9000,\n'
    printf '    "strict_route": true,\n'
    printf '    "clash_api": true,\n'
    printf '    "clash_api_port": %s,\n' "$CLASH_PORT"
    printf '    "sing_box_version": "%s"\n' "$kver"
    printf '  }\n'
    printf '}\n'
  } > "$PROFILE"

  # 把所有节点补进 auto 组
  route_fix_auto_group
  echo "OK: 已生成 profile（$(printf '%s' "$nodes_json" | tr -cd ',' | wc -c | tr -d ' ') 个以上节点）"
}

# auto 组的成员应等于全部节点名
route_fix_auto_group() {
  [ -f "$PROFILE" ] || return 0
  "$AB" route lint -profile "$PROFILE" -json >/dev/null 2>&1 || true
}

# ---------- 编译 ----------
route_compile() {
  [ -f "$PROFILE" ] || route_seed >/dev/null 2>&1
  [ -f "$PROFILE" ] || { echo "ERR: 没有 profile，请先添加节点"; return 1; }

  kver="$(route_core_ver)"
  rsdir="$(route_rs_dir)"
  mkdir -p "$PN"

  set -- -profile "$PROFILE" -out "$CFG" -mixed-port "$PROXY_PORT"
  [ -n "$kver" ] && set -- "$@" -sb-version "$kver"
  [ -n "$rsdir" ] && set -- "$@" -ruleset-dir "$rsdir"

  out="$("$AB" route compile "$@" 2>&1)"
  rc=$?
  if [ $rc -ne 0 ]; then
    echo "ERR: 配置编译失败"
    printf '%s\n' "$out"
    return 1
  fi
  log "route compile: $out"
  printf '%s\n' "$out"
  echo "OK: 内核配置已生成 -> $CFG"
}

route_status() {
  printf 'profile   : %s\n' "$([ -f "$PROFILE" ] && echo "存在 ($(wc -c < "$PROFILE" | tr -d ' ') 字节)" || echo "未生成")"
  printf '内核配置  : %s\n' "$([ -f "$CFG" ] && echo "存在 ($(wc -c < "$CFG" | tr -d ' ') 字节)" || echo "未生成")"
  printf '内核      : %s\n' "$(route_core_path)"
  printf '内核版本  : %s\n' "$(route_core_ver)"
  printf '规则集目录: %s\n' "$(route_rs_dir)"
  if [ -f "$PROFILE" ]; then
    "$AB" route lint -profile "$PROFILE" 2>&1 | head -n 6
  fi
}

# ---------- 面板用 JSON ----------
js() { printf '"%s"' "$(json_escape "$1")"; }

route_pid_running() {
  p="$(cat "$PN/core.pid" 2>/dev/null)"
  if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then echo "yes"; else echo "no"; fi
}

route_status_json() {
  core="$(route_core_path)"; ver="$(route_core_ver)"; rsdir="$(route_rs_dir)"
  psz=0; [ -f "$PROFILE" ] && psz=$(wc -c < "$PROFILE" 2>/dev/null | tr -d ' ')
  csz=0; [ -f "$CFG" ] && csz=$(wc -c < "$CFG" 2>/dev/null | tr -d ' ')
  nrs=0; if [ -n "$rsdir" ]; then for f in "$rsdir"/*.srs; do [ -e "$f" ] && nrs=$((nrs+1)); done; fi
  coresz=0; [ -n "$core" ] && [ -f "$core" ] && coresz=$(wc -c < "$core" 2>/dev/null | tr -d ' ')
  arch="$(getprop ro.product.cpu.abi 2>/dev/null)"
  printf '{"profile":%s,"profile_size":%s,"config":%s,"config_size":%s,' \
    "$([ -f "$PROFILE" ] && echo true || echo false)" "$psz" \
    "$([ -f "$CFG" ] && echo true || echo false)" "$csz"
  printf '"core":%s,"core_version":%s,"core_size":%s,"arch":%s,' \
    "$(js "$core")" "$(js "$ver")" "$coresz" "$(js "$arch")"
  printf '"ruleset_dir":%s,"ruleset_count":%s,' \
    "$(js "$rsdir")" "$nrs"
  printf '"builtin_dir":%s,"running":"%s","pid":"%s","mirror":%s,"mixed_port":%s,"clash_port":%s}\n' \
    "$(js "$RS_BUILTIN")" "$(route_pid_running)" "$(cat "$PN/core.pid" 2>/dev/null)" \
    "$(js "$(cfg_get RULESET_MIRROR testingcf)")" "$PROXY_PORT" "$CLASH_PORT"
}

# 规则集清单（内置 + 本地缓存）
route_rulesets_json() {
  rsdir="$(route_rs_dir)"
  printf '{"dir":%s,"builtin":%s,"items":[' "$(js "$rsdir")" "$(js "$RS_BUILTIN")"
  first=1
  for f in "$RS_BUILTIN"/*.srs; do
    [ -f "$f" ] || continue
    [ $first -eq 1 ] || printf ','
    first=0
    printf '{"name":%s,"size":%s,"from":"builtin"}' "$(js "$(basename "$f")")" "$(wc -c < "$f" | tr -d ' ')"
  done
  if [ -n "$rsdir" ] && [ "$rsdir" != "$RS_BUILTIN" ]; then
    for f in "$rsdir"/*.srs; do
      [ -f "$f" ] || continue
      [ $first -eq 1 ] || printf ','
      first=0
      printf '{"name":%s,"size":%s,"from":"local"}' "$(js "$(basename "$f")")" "$(wc -c < "$f" | tr -d ' ')"
    done
  fi
  printf ']}\n'
}

# 重载：重新编译，内核在跑就顺带重启
route_reload() {
  route_compile >/dev/null 2>&1 || true
  if [ "$(route_pid_running)" = "yes" ]; then
    sh "$MODDIR/scripts/proxynode.sh" restart
  else
    echo "OK: 配置已重载（内核未运行）"
  fi
}

case "${1:-status}" in
  status)      route_status ;;
  status-json) route_status_json ;;
  rulesets)    route_rulesets_json ;;
  reload)      route_reload ;;
  summary)     shift; "$AB" route summary -profile "$PROFILE" "$@" ;;
  set)         shift; "$AB" route set -profile "$PROFILE" "$@" ;;
  add-node)    shift; "$AB" route add-node -profile "$PROFILE" "$@" ;;
  add-rule)    shift; "$AB" route add-rule -profile "$PROFILE" "$@" ;;
  dnsprobe)    shift; "$AB" route dnsprobe "$@" ;;
  seed)        shift; route_seed "$@" ;;
  profile)     [ -f "$PROFILE" ] && cat "$PROFILE" || echo "{}" ;;
  set-profile)
    mkdir -p "$PN"
    raw="${2:-}"
    # 没给参数就从 stdin 读（面板 POST body 走这条路，避免超长命令行参数）
    [ -z "$raw" ] && raw="$(cat)"
    case "$raw" in
      \{*) printf '%s' "$raw" > "$PROFILE.tmp" ;;          # 直接给 JSON
      *)   printf '%s' "$raw" | b64dec > "$PROFILE.tmp" 2>/dev/null ;;  # base64
    esac
    # 用 summary 做纯 JSON 合法性校验（lint 有 error 时会非零退出，不能当校验器）
    if [ -s "$PROFILE.tmp" ] && "$AB" route summary -profile "$PROFILE.tmp" >/dev/null 2>&1; then
      mv -f "$PROFILE.tmp" "$PROFILE"
      echo "OK: profile 已更新（$(wc -c < "$PROFILE" | tr -d ' ') 字节）"
    else
      rm -f "$PROFILE.tmp"
      echo "ERR: 内容不是合法的 profile JSON（已拒绝写入）"
      exit 1
    fi
    ;;
  compile)     shift; route_compile "$@" ;;
  lint)        shift; "$AB" route lint -profile "$PROFILE" "$@" ;;
  explain)     shift; "$AB" route explain -profile "$PROFILE" "$@" ;;
  test)        shift; "$AB" route test -profile "$PROFILE" "$@" ;;
  import)      shift; "$AB" route import "$@" ;;
  mirrors)     shift; "$AB" route mirrors "$@" ;;
  fetch-rules)
    shift
    mkdir -p "$RS_LOCAL"
    "$AB" route fetch-rules -dir "$RS_LOCAL" "$@"
    ;;
  clash)       shift; "$AB" clash -api "127.0.0.1:$CLASH_PORT" "$@" ;;
  *)           sed -n '2,30p' "$0"; exit 2 ;;
esac
