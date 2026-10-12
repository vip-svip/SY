#!/system/bin/sh
# ============================================================
#  lists.sh — 多规则表管理 (参照 AdGuard Home「过滤器列表」/ uBlock 自定义列表)
#  配置文件: config/lists.conf   每行: 名称|URL|启用(1/0)|分类
#  下载缓存: cache/dns/list_<名称>.txt
#  用法: lists.sh {list|add <name> <url> [category]|del <name>|
#                  enable <name>|disable <name>|update [name]|clear}
#  作者: vip-svip
# ============================================================
. "$(dirname "$0")/common.sh"

LISTS_CONF="$DATA_DIR/config/lists.conf"
RAW_DIR="$CACHE/dns"
mkdir -p "$RAW_DIR" "$DATA_DIR/config"
touch "$LISTS_CONF"

_ck() { printf '%s' "$1" | tr -d '[:space:]'; }
_safe() { printf '%s' "$1" | sed 's/[^a-zA-Z0-9._-]/_/g'; }  # 名称消毒(避免路径穿越)

list_json() {
  printf '['
  first=1
  while IFS= read -r l; do
    case "$l" in ""|\#*) continue ;; esac
    nm=$(printf '%s' "$l" | cut -d'|' -f1)
    url=$(printf '%s' "$l" | cut -d'|' -f2)
    en=$(printf '%s' "$l" | cut -d'|' -f3)
    cat=$(printf '%s' "$l" | cut -d'|' -f4)
    [ -z "$en" ] && en=1
    f="$RAW_DIR/list_$(_safe "$nm").txt"
    cnt=0; [ -f "$f" ] && cnt=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
    [ "$first" = 1 ] || printf ','
    first=0
    printf '{"name":"%s","url":"%s","enabled":%s,"category":"%s","count":%s}' \
      "$(json_escape "$nm")" "$(json_escape "$url")" "$en" "$(json_escape "$cat")" "${cnt:-0}"
  done < "$LISTS_CONF"
  printf ']\n'
}

exists() {
  awk -F'|' -v k="$(_ck "$1")" '{m=$1; gsub(/[[:space:]]/,"",m); if(m==k || $1==k) f=1} END{exit !f}' "$LISTS_CONF"
}

add() { # $1 name  $2 url  $3 category
  nm="$1"; url="$2"; cat="$3"
  if [ -z "$nm" ] || [ -z "$url" ]; then echo "ERR: 需要 名称 与 URL"; return 1; fi
  if exists "$nm"; then echo "OK: 规则表 $nm 已存在"; return 0; fi
  printf '%s|%s|1|%s\n' "$nm" "$url" "$cat" >> "$LISTS_CONF"
  echo "OK: 已添加规则表 $nm"
}

del() { # $1 name
  nm="$1"; if [ -z "$nm" ]; then echo "ERR: 缺少名称"; return 1; fi
  tmp="$LISTS_CONF.tmp.$$"
  awk -F'|' -v n="$(_ck "$nm")" '{m=$1; gsub(/[[:space:]]/,"",m); if(m!=n && $1!="'"$nm"'") print}' "$LISTS_CONF" > "$tmp" && mv "$tmp" "$LISTS_CONF"
  rm -f "$RAW_DIR/list_$(_safe "$nm").txt"
  echo "OK: 已删除规则表 $nm"
}

set_en() { # $1 name  $2 value
  nm="$1"; v="$2"; if [ -z "$nm" ]; then echo "ERR: 缺少名称"; return 1; fi
  case "$v" in 0|1) ;; *) echo "ERR: 状态须为 0/1"; return 1 ;; esac
  tmp="$LISTS_CONF.tmp.$$"
  awk -F'|' -v OFS='|' -v n="$(_ck "$nm")" -v v="$v" '{m=$1; gsub(/[[:space:]]/,"",m); if(m==n || $1=="'"$nm"'") $3=v; print}' "$LISTS_CONF" > "$tmp" && mv "$tmp" "$LISTS_CONF"
  if [ "$v" = 1 ]; then echo "OK: 规则表 $nm 已启用"; else echo "OK: 规则表 $nm 已停用"; fi
}

update() { # $1 可选 name
  target="$1"; n=0; ok=0
  while IFS= read -r l; do
    case "$l" in ""|\#*) continue ;; esac
    nm=$(printf '%s' "$l" | cut -d'|' -f1)
    url=$(printf '%s' "$l" | cut -d'|' -f2)
    [ -n "$target" ] && [ "$nm" != "$target" ] && continue
    n=$((n+1))
    f="$RAW_DIR/list_$(_safe "$nm").txt"
    if http_get "$url" "$f.tmp.$$" 45 && [ -s "$f.tmp.$$" ]; then mv "$f.tmp.$$" "$f"; ok=$((ok+1)); else rm -f "$f.tmp.$$"; fi
  done < "$LISTS_CONF"
  echo "OK: 更新 $ok/$n 个规则表"
}

case "$1" in
  list)    list_json ;;
  add)     add "$2" "$3" "$4" ;;
  del)     del "$2" ;;
  enable)  set_en "$2" 1 ;;
  disable) set_en "$2" 0 ;;
  update)  update "$2" ;;
  clear)   : > "$LISTS_CONF"; echo "OK: 已清空规则表" ;;
  *) echo "usage: lists.sh {list|add <name> <url> [category]|del <name>|enable <name>|disable <name>|update [name]|clear}" ;;
esac
