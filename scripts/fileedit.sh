#!/system/bin/sh
# ============================================================
#  fileedit.sh — 面板「文件编辑器」后端
#  ------------------------------------------------------------
#  为什么需要它：订阅源/规则清单/隐私目标这类配置此前只能靠按钮单条增删，
#  用户没法直接改整份文件（换订阅地址、批量粘贴、调整格式都做不到）。
#
#  安全边界（三件事都做）:
#   ① 路径白名单：只允许 config/ 与 rules/ 下的文件；
#   ② 拒绝 .. 穿越：用 case 匹配显式拦截，再做前缀复核；
#   ③ 大小上限 4MB，避免把内存/终端打满。
#
#  用法: fileedit.sh {list|read <rel>|write <rel>|append <rel>|info <rel>}
#        write/append 从 **stdin** 读取内容（避免命令行长度与转义问题）
# ============================================================
. "$(dirname "$0")/common.sh"

FE_MAX=4194304   # 4MB

# 校验相对路径；通过则回显绝对路径，否则 exit 1
fe_resolve() {
  rel="$1"
  [ -z "$rel" ] && { echo "ERR: 缺少路径"; return 1; }
  # 去掉开头的斜杠，拒绝任何 .. 段
  rel=$(printf '%s' "$rel" | sed 's|^/||; s|//*|/|g')
  case "$rel" in
    *..*) echo "ERR: 路径不允许包含 .."; return 1 ;;
    /*)   echo "ERR: 只接受相对路径"; return 1 ;;
  esac
  top=$(printf '%s' "$rel" | cut -d/ -f1)
  case "$top" in
    config|rules) ;;
    *) echo "ERR: 只允许编辑 config/ 与 rules/ 下的文件"; return 1 ;;
  esac
  full="$DATA_DIR/$rel"
  echo "$full"
  return 0
}

fe_list() {
  # 列出可编辑文件（带大小与行数），供面板做下拉选择
  printf '['
  first=1
  for d in config rules; do
    [ -d "$DATA_DIR/$d" ] || continue
    for f in "$DATA_DIR/$d"/*; do
      [ -f "$f" ] || continue
      rel="${f#$DATA_DIR/}"
      sz=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
      ln=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
      [ "$first" = "1" ] || printf ','
      first=0
      printf '{"path":"%s","size":%s,"lines":%s}' "$(json_escape "$rel")" "${sz:-0}" "${ln:-0}"
    done
  done
  printf ']\n'
}

fe_read() {
  full=$(fe_resolve "$1") || { echo "$full"; exit 1; }
  if [ ! -f "$full" ]; then
    echo "ERR: 文件不存在: $1"; exit 1
  fi
  sz=$(wc -c < "$full" 2>/dev/null | tr -d ' ')
  [ "${sz:-0}" -gt "$FE_MAX" ] && { echo "ERR: 文件过大（${sz}B > ${FE_MAX}B），编辑器不支持"; exit 1; }
  cat "$full"
}

fe_write() {
  full=$(fe_resolve "$1") || { echo "$full"; exit 1; }
  # 内容从 stdin 读；先落临时文件再改名（写入中断不会把原文件截成半个）
  tmp="$full.tmp.$$"
  cat > "$tmp" 2>/dev/null
  sz=$(wc -c < "$tmp" 2>/dev/null | tr -d ' ')
  if [ "${sz:-0}" -gt "$FE_MAX" ]; then rm -f "$tmp"; echo "ERR: 内容过大（${sz}B）"; exit 1; fi
  # 备份原文件（可回滚）
  [ -f "$full" ] && cp -f "$full" "$full.bak" 2>/dev/null
  mkdir -p "$(dirname "$full")" 2>/dev/null
  if mv -f "$tmp" "$full" 2>/dev/null; then
    echo "OK: 已写入 $1（${sz:-0} 字节）"
  else
    rm -f "$tmp"; echo "ERR: 写入失败（权限或磁盘问题）"; exit 1
  fi
}

fe_append() {
  full=$(fe_resolve "$1") || { echo "$full"; exit 1; }
  mkdir -p "$(dirname "$full")" 2>/dev/null
  cat >> "$full" 2>/dev/null
  sz=$(wc -c < "$full" 2>/dev/null | tr -d ' ')
  echo "OK: 已追加到 $1（现 ${sz:-0} 字节）"
}

fe_info() {
  full=$(fe_resolve "$1") || { echo "$full"; exit 1; }
  if [ -f "$full" ]; then
    sz=$(wc -c < "$full" 2>/dev/null | tr -d ' ')
    ln=$(wc -l < "$full" 2>/dev/null | tr -d ' ')
    printf '{"exists":true,"size":%s,"lines":%s,"path":"%s"}\n' "${sz:-0}" "${ln:-0}" "$(json_escape "$1")"
  else
    printf '{"exists":false,"size":0,"lines":0,"path":"%s"}\n' "$(json_escape "$1")"
  fi
}

case "$1" in
  list)   fe_list ;;
  read)   fe_read "$2" ;;
  write)  fe_write "$2" ;;
  append) fe_append "$2" ;;
  info)   fe_info "$2" ;;
  hashes)
    # 列出全部可编辑文件的 sha256，供面板做完整性核对
    for d in config rules; do
      [ -d "$DATA_DIR/$d" ] || continue
      for f in "$DATA_DIR/$d"/*; do
        [ -f "$f" ] || continue
        h=$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1)
        [ -n "$h" ] && printf '%s %s\n' "$h" "${f#$DATA_DIR/}"
      done
    done
    ;;
  *) echo "usage: fileedit.sh {list|read <rel>|write <rel>|append <rel>|info <rel>|hashes}"; exit 2 ;;
esac
