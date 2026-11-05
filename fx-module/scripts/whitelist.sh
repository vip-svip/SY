#!/system/bin/sh
# FX 1.0.0 whitelist manager: safe CRUD for [list:domain].
# Usage: whitelist.sh list | add DOMAIN [COMMENT] | remove DOMAIN | apply
set -u
_pg_d=$(dirname "$0" 2>/dev/null)
MODDIR=$(cd "$_pg_d/.." 2>/dev/null && pwd)
PG=${PG:-/data/adb/privacyguard}
CONF=${CONF:-$PG/settings.conf}

usage() {
  echo "用法: whitelist.sh list | add DOMAIN [备注] | remove DOMAIN | apply" >&2
  echo "白名单仅放行明确列出的域名及其子域；请勿添加过宽的根域名。" >&2
  exit 2
}

normalize_domain() {
  _nd=$(printf '%s' "$1" | tr 'A-Z' 'a-z' | sed 's/^\*\.//; s/[[:space:]]*$//')
  case "$_nd" in ''|.*|*.|*..*|*[!a-z0-9.-]*) return 1 ;; esac
  printf '%s\n' "$_nd" | awk '
    {
      d=$0
      if (length(d)<1 || length(d)>253) exit 1
      n=split(d,a,".")
      for (i=1;i<=n;i++) {
        if (length(a[i])<1 || length(a[i])>63 || a[i] !~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/) exit 1
      }
      print d
    }'
}

[ -f "$CONF" ] || { echo "配置文件不存在: $CONF" >&2; exit 1; }
cmd=${1:-}
case "$cmd" in
  list)
    awk '
      /^\[list:domain\][[:space:]]*$/ {inside=1; found=1; next}
      /^\[/ {inside=0}
      inside && $0 !~ /^[[:space:]]*#/ && $0 ~ /\|/ {
        n=split($0,a,"|"); d=a[1]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", d)
        if (n<3 || a[3]=="1") print d "|" (n>=2?a[2]:"") "|1"
      }
      END {if (!found) exit 3}
    ' "$CONF"
    rc=$?
    [ "$rc" -eq 0 ] || { echo "配置中没有 [list:domain] 白名单段" >&2; exit "$rc"; }
    ;;
  add|remove)
    [ "$#" -ge 2 ] || usage
    domain=$(normalize_domain "$2") || { echo "拒绝非法域名: $2" >&2; exit 2; }
    comment=${3:-"用户白名单"}
    # Avoid allowing the comment to inject list fields or extra config lines.
    comment=$(printf '%s' "$comment" | tr '|\r\n' '   ' | cut -c1-120)
    [ -n "$comment" ] || comment="用户白名单"
    # Serialize read-modify-write operations so two quick UI actions cannot lose updates.
    lock="$CONF.whitelist.lock"
    if ! mkdir "$lock" 2>/dev/null; then
      echo "白名单正在被其他操作修改；请稍后重试。若设备重启/进程异常后仍提示，请确认没有白名单操作运行后再手动清理锁目录：$lock" >&2
      exit 1
    fi
    tmp="$CONF.whitelist.$$"
    backup="$CONF.whitelist.previous"
    cleanup() { rm -f "$tmp" 2>/dev/null || :; rmdir "$lock" 2>/dev/null || :; }
    trap cleanup EXIT HUP INT TERM
    [ -f "$CONF" ] && [ ! -L "$CONF" ] || { echo "配置不是普通文件或是符号链接，拒绝修改" >&2; exit 1; }
    [ ! -e "$tmp" ] || { echo "临时文件已存在，拒绝覆盖: $tmp" >&2; exit 1; }
    if [ "$cmd" = add ]; then
      awk -v d="$domain" -v c="$comment" '
        function norm(s) {s=tolower(s); sub(/^\*\./,"",s); gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s}
        /^\[list:domain\][[:space:]]*$/ {inside=1; found=1; print; next}
        /^\[/ {
          if (inside && !done) {print d "|" c "|1"; done=1}
          inside=0
        }
        inside && $0 !~ /^[[:space:]]*#/ && $0 ~ /\|/ {
          n=split($0,a,"|")
          if (norm(a[1])==d) {
            if (!done) {print d "|" c "|1"; done=1}
            next
          }
        }
        {print}
        END {
          if (!found) {
            if (!done) print "[list:domain]\n" d "|" c "|1"
          } else if (!done) print d "|" c "|1"
        }
      ' "$CONF" > "$tmp" || { rm -f "$tmp"; exit 1; }
    else
      awk -v d="$domain" '
        function norm(s) {s=tolower(s); sub(/^\*\./,"",s); gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s}
        /^\[list:domain\][[:space:]]*$/ {inside=1; found=1; print; next}
        /^\[/ {inside=0}
        inside && $0 !~ /^[[:space:]]*#/ && $0 ~ /\|/ {
          n=split($0,a,"|")
          if (norm(a[1])==d) next
        }
        {print}
        END {if (!found) exit 3}
      ' "$CONF" > "$tmp" || { rm -f "$tmp"; echo "无法移除：未找到白名单段或配置读取失败" >&2; exit 1; }
    fi
    [ -s "$tmp" ] || { echo "生成的配置为空，拒绝提交" >&2; exit 1; }
    # Keep a last-known-good copy before the atomic rename. Do not replace the
    # active config if backup creation fails.
    cp -p "$CONF" "$backup.tmp.$$" 2>/dev/null || { echo "无法创建白名单回滚副本，未修改配置" >&2; exit 1; }
    [ -s "$backup.tmp.$$" ] || { rm -f "$backup.tmp.$$"; echo "白名单回滚副本为空，未修改配置" >&2; exit 1; }
    mv -f "$backup.tmp.$$" "$backup" || { rm -f "$backup.tmp.$$"; echo "无法提交白名单回滚副本，未修改配置" >&2; exit 1; }
    chmod --reference="$CONF" "$tmp" 2>/dev/null || chmod 600 "$tmp" 2>/dev/null || :
    mv -f "$tmp" "$CONF" || { echo "配置写入失败；原配置副本保留在 $backup" >&2; exit 1; }
    echo "$cmd 白名单成功: $domain"
    echo "修改前配置副本: $backup"
    echo "配置已更新；执行 'whitelist.sh apply' 才会重新应用到运行规则。"
    ;;
  apply)
    [ -x "$MODDIR/scripts/apply.sh" ] || { echo "apply.sh 不可执行或不存在" >&2; exit 1; }
    # Applying a just-edited whitelist is a transaction: if apply fails, restore
    # the last-known-good config and make one best-effort apply of the restored state.
    backup="$CONF.whitelist.previous"
    sh "$MODDIR/scripts/apply.sh"
    apply_rc=$?
    [ "$apply_rc" -eq 0 ] && exit 0
    echo "白名单应用失败（rc=$apply_rc）；尝试恢复修改前配置" >&2
    if [ -f "$backup" ] && [ ! -L "$backup" ] && [ -s "$backup" ]; then
      rollback_tmp="$CONF.whitelist.rollback.$$"
      if cp -p "$backup" "$rollback_tmp" 2>/dev/null && [ -s "$rollback_tmp" ] && mv -f "$rollback_tmp" "$CONF" 2>/dev/null; then
        echo "已恢复修改前配置；正在尝试重新应用旧配置" >&2
        sh "$MODDIR/scripts/apply.sh"
        restore_rc=$?
        if [ "$restore_rc" -eq 0 ]; then
          echo "旧配置重新应用成功；白名单修改已回滚" >&2
        else
          echo "警告：旧配置已恢复到磁盘，但重新应用也失败（rc=$restore_rc）；请检查 apply.log" >&2
        fi
      else
        rm -f "$rollback_tmp" 2>/dev/null
        echo "严重：回滚配置写入失败；原备份保留在 $backup" >&2
      fi
    else
      echo "严重：找不到有效的白名单回滚副本；未能自动恢复配置" >&2
    fi
    exit "$apply_rc"
    ;;
  *) usage ;;
esac
