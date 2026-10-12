#!/system/bin/sh
# ============================================================
#  backup.sh — 全配置备份/恢复
#  用法: backup.sh {export|import <file|-> |list|delete <name>}
# ============================================================
. "$(dirname "$0")/common.sh"

do_export() {
  ts=$(date '+%Y%m%d_%H%M%S')
  out="$BACKUP_DIR/SY_backup_$ts.tar.gz"
  tar -czf "$out" -C "$DATA_DIR" \
      config rules scripts 2>/dev/null
  echo "OK: 备份已生成 $out ($(du -h "$out" 2>/dev/null | awk '{print $1}'))"
}

do_import() {
  src="$1"
  [ -z "$src" ] && { echo "ERR: 缺少备份文件"; exit 1; }
  if [ "$src" = "-" ]; then
    src="$CACHE/restore.tar.gz"; cat > "$src"
  fi
  [ -f "$src" ] || { echo "ERR: 文件不存在"; exit 1; }
  tar -xzf "$src" -C "$DATA_DIR" 2>/dev/null && \
    { sh "$(dirname "$0")/dns.sh" apply >/dev/null 2>&1; sh "$(dirname "$0")/mitm.sh" rules-reload >/dev/null 2>&1; \
      echo "OK: 已恢复所有配置"; } || echo "ERR: 恢复失败"
}

do_import_b64() {
  b="$2"
  [ -z "$b" ] && { echo "ERR: 缺少备份数据"; exit 1; }
  src="$CACHE/restore_upload.tar.gz"
  echo "$b" | base64 -d > "$src" 2>/dev/null
  [ -s "$src" ] || { echo "ERR: 备份数据解码失败"; exit 1; }
  tar -xzf "$src" -C "$DATA_DIR" 2>/dev/null && \
    { sh "$(dirname "$0")/dns.sh" apply >/dev/null 2>&1; sh "$(dirname "$0")/mitm.sh" rules-reload >/dev/null 2>&1; \
      echo "OK: 已从备份文件恢复所有配置"; } || echo "ERR: 恢复失败，可能不是有效的备份包"
}

case "$1" in
  export) do_export ;;
  import) do_import "$2" ;;
  import-b64) do_import_b64 "$@" ;;
  list)   ls -1 "$BACKUP_DIR" 2>/dev/null ;;
  delete) rm -f "$BACKUP_DIR/$2"; echo "OK: 已删除 $2" ;;
  *) echo "usage: backup.sh {export|import <file|->|import-b64 <b64>|list|delete <name>}" ;;
esac
