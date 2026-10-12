#!/system/bin/sh
# ============================================================
#  netblock.sh — 网络拦截模块（多规则类型）
#  支持 6 种规则类型，统一管理并落地生效：
#    domain  域名   -> 写入 hosts(0.0.0.0)，全设备拦截
#    ip      单IP   -> iptables DROP
#    cidr    网段   -> iptables DROP
#    port    端口   -> iptables REJECT
#    keyword 关键词 -> 记录到 MITM 规则(内容层关键字)
#    app     应用   -> 按 uid owner 拦截该应用全部流量
#  用法: netblock.sh {status|list|add|del|clear|apply|
#                    import-b64|import-net|del-multi|add-batch-b64|
#                    apps-list|apps-add|apps-del-multi|preview}
# ============================================================
. "$(dirname "$0")/common.sh"

NB="$DATA_DIR/rules/netblock"
CHAIN="SY_BLOCK"
mkdir -p "$NB" 2>/dev/null
T_DOMAIN="$NB/domains.txt"; T_IP="$NB/ips.txt"; T_CIDR="$NB/cidrs.txt"
T_PORT="$NB/ports.txt"; T_KW="$NB/keywords.txt"; T_APP="$NB/apps.txt"
for f in "$T_DOMAIN" "$T_IP" "$T_CIDR" "$T_PORT" "$T_KW" "$T_APP"; do [ -f "$f" ] || : > "$f"; done

file_of() {
  case "$1" in
    domain) echo "$T_DOMAIN" ;; ip) echo "$T_IP" ;; cidr) echo "$T_CIDR" ;;
    port) echo "$T_PORT" ;; keyword) echo "$T_KW" ;; app) echo "$T_APP" ;; *) echo "" ;;
  esac
}
valid_type() { case "$1" in domain|ip|cidr|port|keyword|app) return 0 ;; *) return 1 ;; esac; }

ensure_chain() {
  have iptables || return 1
  iptables -N "$CHAIN" 2>/dev/null
  iptables -C OUTPUT -j "$CHAIN" 2>/dev/null || iptables -I OUTPUT -j "$CHAIN" 2>/dev/null
}
flush_chain() { have iptables && iptables -F "$CHAIN" 2>/dev/null; }

uid_of_pkg() { # pkg -> uid
  id=$(dumpsys package "$1" 2>/dev/null | grep -m1 -E "userId=" | sed 's/[^0-9]//g')
  [ -n "$id" ] && echo "$id"
}

apply() {
  if [ -f "$MODDIR/scripts/dns.sh" ]; then
    sh "$MODDIR/scripts/dns.sh" apply >/dev/null 2>&1
  fi
  have iptables || { echo "ERR: 缺少 iptables"; return 1; }
  ensure_chain; flush_chain
  n=0
  if [ -s "$T_IP" ]; then
    while read -r x; do [ -z "$x" ] && continue; iptables -A "$CHAIN" -d "$x" -j DROP 2>/dev/null && n=$((n+1)); done < "$T_IP"
  fi
  if [ -s "$T_CIDR" ]; then
    while read -r x; do [ -z "$x" ] && continue; iptables -A "$CHAIN" -d "$x" -j DROP 2>/dev/null && n=$((n+1)); done < "$T_CIDR"
  fi
  if [ -s "$T_PORT" ]; then
    while read -r x; do [ -z "$x" ] && continue; iptables -A "$CHAIN" -p tcp --dport "$x" -j REJECT 2>/dev/null && n=$((n+1)); done < "$T_PORT"
  fi
  if [ -s "$T_APP" ]; then
    while read -r x; do
      [ -z "$x" ] && continue
      pkg=$(echo "$x" | awk -F'|' '{print $1}')
      uid=$(uid_of_pkg "$pkg")
      [ -z "$uid" ] && continue
      iptables -A "$CHAIN" -m owner --uid-owner "$uid" -j DROP 2>/dev/null && n=$((n+1))
    done < "$T_APP"
  fi
  log "netblock: apply domains=$(count_lines "$T_DOMAIN") rules=$n apps=$(count_lines "$T_APP")"
  echo "OK: 网络拦截已生效（域名 $(count_lines "$T_DOMAIN") 条，IP/网段/端口/应用规则 $n 条）"
}

case "$1" in
  status)
    d=$(count_lines "$T_DOMAIN"); i=$(count_lines "$T_IP"); c=$(count_lines "$T_CIDR")
    p=$(count_lines "$T_PORT"); k=$(count_lines "$T_KW"); a=$(count_lines "$T_APP")
    applied="no"; have iptables && iptables -C OUTPUT -j "$CHAIN" 2>/dev/null && applied="yes"
    printf '{"domain":%s,"ip":%s,"cidr":%s,"port":%s,"keyword":%s,"app":%s,"applied":"%s"}\n' "$d" "$i" "$c" "$p" "$k" "$a" "$applied"
    ;;
  list)
    t="$2"; f=$(file_of "$t")
    if [ -n "$f" ]; then
      n=0; while IFS= read -r x; do [ -z "$x" ] && continue; n=$((n+1)); printf '%s|%s\n' "$n" "$x"; done < "$f" 2>/dev/null
    else
      for tt in domain ip cidr port keyword app; do
        ff=$(file_of "$tt"); [ -s "$ff" ] || continue
        while IFS= read -r x; do [ -z "$x" ] && continue; printf '%s|%s|%s\n' "$tt" "0" "$x"; done < "$ff"
      done
    fi
    ;;
  add)
    t="$2"; v="$3"; valid_type "$t" || { echo "ERR: 类型需为 domain|ip|cidr|port|keyword|app"; exit 1; }
    [ -z "$v" ] && { echo "ERR: 缺少规则值"; exit 1; }
    f=$(file_of "$t")
    if [ "$t" = "app" ]; then
      pkg=$(echo "$v" | awk -F'|' '{print $1}')
      lbl=$(echo "$v" | awk -F'|' '{print $2}')
      [ -z "$lbl" ] && lbl="$pkg"
      if grep -q "^${pkg}|" "$f" 2>/dev/null; then echo "OK: 应用已在列表 $pkg"; else echo "${pkg}|${lbl}" >> "$f"; echo "OK: 已添加应用 $lbl"; fi
    else
      v=$(echo "$v" | tr -d '[:space:]')
      grep -qxF "$v" "$f" 2>/dev/null || echo "$v" >> "$f"
      echo "OK: 已添加 [$t] $v"
    fi
    ;;
  del)
    t="$2"; v="$3"; f=$(file_of "$t")
    if [ -n "$f" ] && [ -f "$f" ]; then tmp="$f.tmp.$$"; grep -vxF "$v" "$f" > "$tmp" 2>/dev/null; mv "$tmp" "$f"; fi
    echo "OK: 已删除 [$t] $v"
    ;;
  del-multi)  # 批量删除: <type> <comma>
    t="$2"; f=$(file_of "$2")
    [ -z "$f" ] && { echo "ERR: 类型无效"; exit 1; }
    n=$(batch_del_values "$f" "$3")
    echo "OK: 已批量删除, 剩余 $n 条"
    ;;
  apps-del-multi)  # 应用批量删除: <comma_pkgs>
    n=$(batch_del_field "$T_APP" "$2" "|")
    echo "OK: 已删除所选应用, 剩余 $n 个"
    ;;
  clear)
    t="$2"; f=$(file_of "$t")
    if [ -n "$f" ]; then : > "$f"; echo "OK: 已清空 [$t]"; else for tt in domain ip cidr port keyword app; do : > "$(file_of "$tt")"; done; echo "OK: 已清空全部网络拦截规则"; fi
    ;;
  import-b64)  # 本地导入(批量) <type> <b64>
    t="$2"; b="$3"; f=$(file_of "$t")
    [ -z "$f" ] && { echo "ERR: 类型无效"; exit 1; }
    n=$(import_append_local "$f" "$b")
    echo "OK: 本地导入完成, 共 $n 条"
    ;;
  import-net)  # 网络导入 <type> <url>
    t="$2"; f=$(file_of "$2")
    [ -z "$f" ] && { echo "ERR: 类型无效"; exit 1; }
    res=$(import_append_net "$f" "$3" 40)
    case "$res" in ERR*) echo "$res" ;; *) echo "OK: 网络导入完成, 共 $res 条" ;; esac
    ;;
  add-batch-b64)  # 与 import-b64 同义(向后兼容)
    t="$2"; f=$(file_of "$2"); n=$(import_append_local "$f" "$3"); echo "OK: 已导入, 共 $n 条"
    ;;
  apps-list)  # 列出已安装应用(可选过滤词) -> "pkg|label"
    filter="$2"
    pm list packages -3 2>/dev/null | sed 's/^package://' | sort | while IFS= read -r pkg; do
      [ -z "$pkg" ] && continue
      case "$pkg" in *"$filter"*) : ;; *) continue ;; esac
      lbl=$(dumpsys package "$pkg" 2>/dev/null | grep -m1 -E "labelRes" >/dev/null 2>&1; echo "$pkg")
      printf '%s|%s\n' "$pkg" "$pkg"
    done
    ;;
  apps-add)  # 单个应用加入拦截 <pkg> [label]
    pkg="$2"; lbl="${3:-$2}"
    [ -z "$pkg" ] && { echo "ERR: 缺少包名"; exit 1; }
    if grep -q "^${pkg}|" "$T_APP" 2>/dev/null; then echo "OK: 应用已在列表 $pkg"; else echo "${pkg}|${lbl}" >> "$T_APP"; echo "OK: 已添加应用 $lbl"; fi
    ;;
  apply) apply ;;
  preview)
    echo "域名: $(count_lines "$T_DOMAIN") | IP: $(count_lines "$T_IP") | 网段: $(count_lines "$T_CIDR") | 端口: $(count_lines "$T_PORT") | 关键词: $(count_lines "$T_KW") | 应用: $(count_lines "$T_APP")"
    ;;
  *) echo "usage: netblock.sh {status|list|add|del|del-multi|clear|apply|import-b64|import-net|apps-list|apps-add|apps-del-multi|preview}" ;;
esac
