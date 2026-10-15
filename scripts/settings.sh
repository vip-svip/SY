#!/system/bin/sh
# ============================================================
#  settings.sh — 模块设置持久化 (重启不还原)
#  统一网关: 所有面板开关/选项落到 $DATA_DIR/config/module_settings.conf,
#  该目录位于 /data/adb/SY (持久分区), 重启/重刷面板均保留。
#  用法: settings.sh {get|set|all|dump|reset} [key] [value]
# ============================================================
. "$(dirname "$0")/common.sh"

SET_FILE="$DATA_DIR/config/module_settings.conf"
mkdir -p "$(dirname "$SET_FILE")"
[ -f "$SET_FILE" ] || touch "$SET_FILE"

set_kv() { # key value
  k="$1"; v="$2"
  [ -z "$k" ] && return 1
  if grep -qE "^[[:space:]]*${k}=" "$SET_FILE" 2>/dev/null; then
    tmp="$SET_FILE.tmp.$$"
    sed "s|^[[:space:]]*${k}=.*|${k}=${v}|" "$SET_FILE" > "$tmp" && mv "$tmp" "$SET_FILE"
  else
    echo "${k}=${v}" >> "$SET_FILE"
  fi
}
get_kv() { # key [default]
  k="$1"; def="$2"
  v=$(grep -E "^[[:space:]]*${k}=" "$SET_FILE" 2>/dev/null | tail -n1 | sed "s/^[[:space:]]*${k}=//")
  [ -n "$v" ] && echo "$v" || echo "$def"
}

case "$1" in
  get)  get_kv "$2" "$3" ;;
  set)  set_kv "$2" "$3"; echo "OK: $2=$3" ;;
  all)  cat "$SET_FILE" 2>/dev/null ;;
  dump) # 输出为 JSON 对象
    { printf '{'; first=1
      while IFS= read -r line; do
        case "$line" in ""|\#*) continue ;; esac
        k=${line%%=*}; v=${line#*=}
        [ "$first" = "0" ] && printf ','
        printf '"%s":"%s"' "$k" "$(printf '%s' "$v" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
        first=0
      done < "$SET_FILE"
      printf '}\n'; } 2>/dev/null
    ;;
  save-b64) # 批量写入 key=value 文本
    [ -z "$2" ] && { echo "ERR: 空内容"; exit 1; }
    echo "$2" | base64 -d 2>/dev/null | sed -e 's/\r$//' -e '/^[[:space:]]*$/d' > "$SET_FILE"
    _n=$(grep -c "=" "$SET_FILE" 2>/dev/null | head -n1); [ -z "$_n" ] && _n=0
  echo "OK: 设置已保存（$_n 项）"
    ;;
  reset) : > "$SET_FILE"; echo "OK: 设置已重置为默认" ;;
  *) echo "usage: settings.sh {get|set|all|dump|reset} [key] [value]" ;;
esac
