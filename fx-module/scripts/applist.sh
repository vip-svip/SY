#!/bin/sh
# PrivacyGuard applist.sh — 列出设备已安装应用（分应用代理选择器数据源）
# 用法: sh applist.sh [--refresh]
# 输出: 每行一个 JSON {"pkg":"包名","name":"应用名","sys":0|1}（sys=1 系统应用）
#
# 实现要点：
#   1) 系统应用判定用 `pm list packages -s`（真实系统分区应用），
#      不再靠 com.android.* 前缀猜——厂商应用(com.miui./com.oplus./com.samsung.)也能判对；
#   2) 应用名(dumpsys package)是逐包调用，很慢 → 落盘缓存到 cache/applabel.conf，
#      无 --refresh 时只补缺失项，重复调用秒回；
#   3) 名称做 JSON 转义（应用名可能含 " 或 \）；
#   4) 无 pm 时退回 packages.xml / packages.list。
PG_HOME=${PG_HOME:-/data/adb/privacyguard}
. "$(dirname "$0")/util.sh" 2>/dev/null || true

# 缓存目录：优先模块私有目录，不可写则退回 /tmp（避免只读/受限环境报错）
pg_cache_dir() {
  for _d in "$PG_HOME/cache" /tmp/pg-cache; do
    mkdir -p "$_d" 2>/dev/null && [ -w "$_d" ] && { echo "$_d"; return 0; }
  done
  echo /tmp
}

emit() { printf '%s\n' "$1"; }

# ---- JSON 字符串转义：反斜杠、双引号、制表符、换行 ----
json_esc() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/ /g' | tr -d '\r\n'
}

# ---- 系统应用包名集合（一次性，落盘供判定）----
SYS_LIST=""
build_sys_list() {
  _cd=$(pg_cache_dir)
  _f="$_cd/appsys.list"
  if [ -s "$_f" ] && [ "$REFRESH" != "1" ]; then SYS_LIST="$_f"; return 0; fi
  if pg_have pm && pm list packages -s 2>/dev/null | sed -n 's/^package://p' > "$_f.tmp" 2>/dev/null && [ -s "$_f.tmp" ]; then
    mv -f "$_f.tmp" "$_f" 2>/dev/null
    SYS_LIST="$_f"
    return 0
  fi
  rm -f "$_f.tmp" 2>/dev/null
  return 1
}

is_sys() {
  [ -n "$SYS_LIST" ] || return 1
  grep -qxF "$1" "$SYS_LIST" 2>/dev/null
}

# ---- 应用名缓存 ----
LABEL_CACHE=""
load_label_cache() {
  LABEL_CACHE="$(pg_cache_dir)/applabel.conf"
  [ "$REFRESH" = "1" ] && : > "$LABEL_CACHE" 2>/dev/null
}

cache_get() {
  [ -s "$LABEL_CACHE" ] || return 1
  _v=$(grep -m1 "^$1\t" "$LABEL_CACHE" 2>/dev/null | cut -f2-)
  [ -n "$_v" ] || return 1
  printf '%s' "$_v"
}

cache_put() {
  [ -n "$2" ] || return 0
  printf '%s\t%s\n' "$1" "$2" >> "$LABEL_CACHE" 2>/dev/null
}

# 包名 → APK 路径（一次 pm list packages -f 建表，避免逐包 pm path）
APK_MAP=""
build_apk_map() {
  _cd=$(pg_cache_dir)
  _f="$_cd/apkpath.map"
  if [ -s "$_f" ] && [ "$REFRESH" != "1" ]; then APK_MAP="$_f"; return 0; fi
  if pg_have pm && pm list packages -f 2>/dev/null | sed 's/^package://' > "$_f.tmp" 2>/dev/null && [ -s "$_f.tmp" ]; then
    # 格式: /data/app/xx/base.apk=com.pkg  →  包名<TAB>路径
    awk -F= 'NF>=2 {a=$1; sub(/.*=/,"",a); print $NF "\t" a}' "$_f.tmp" > "$_f" 2>/dev/null
    # 上面取字段有歧义，改用更稳的切分：
    awk '{ i = index($0, "="); if (i>0) { path=substr($0,1,i-1); pkg=substr($0,i+1); print pkg "\t" path } }' "$_f.tmp" > "$_f" 2>/dev/null
    rm -f "$_f.tmp"
    APK_MAP="$_f"
    return 0
  fi
  rm -f "$_f.tmp" 2>/dev/null
  return 1
}

apk_of() {
  [ -n "$APK_MAP" ] || return 1
  _v=$(grep -m1 "^$1\t" "$APK_MAP" 2>/dev/null | cut -f2-)
  [ -n "$_v" ] || return 1
  printf '%s' "$_v"
}

# 带超时的命令包装：toybox 有 timeout；没有则直接执行
run_t() {
  _to="$1"; shift
  if pg_have timeout; then timeout "$_to" "$@" 2>/dev/null; else "$@" 2>/dev/null; fi
}

name_of() {
  _p="$1"
  # 1) 缓存命中（绝大多数情况走这里，秒回）
  if _c=$(cache_get "$_p"); then printf '%s' "$_c"; return 0; fi
  _l=""
  # 2) aapt/aapt2 直读 APK（最快，约 10ms/包；多数 ROM 无此命令）
  if [ -n "$AAPT" ]; then
    _apk=$(apk_of "$_p")
    if [ -n "$_apk" ] && [ -f "$_apk" ]; then
      _l=$("$AAPT" dump badging "$_apk" 2>/dev/null | sed -n "s/^application-label:'\\(.*\\)'/\\1/p" | head -n1)
      case "$_l" in *application-label*) _l="" ;; esac
    fi
  fi
  # 3) dumpsys package（逐包，慢；加 3s 超时防个别坏包卡死整个列表）
  if [ -z "$_l" ] && pg_have dumpsys; then
    _l=$(run_t 3 dumpsys package "$_p" | sed -n 's/^[[:space:]]*application-label[-a-zA-Z]*:[[:space:]]*//p' | head -n1)
    if [ -z "$_l" ]; then
      _l=$(run_t 3 dumpsys package "$_p" | sed -n 's/^[[:space:]]*label=[[:space:]]*//p' | head -n1)
    fi
  fi
  # 4) cmd package 兜底
  if [ -z "$_l" ] && pg_have cmd; then
    _l=$(run_t 3 cmd package resolve-activity --brief "$_p" | tail -n1 | sed 's#.*/##')
    case "$_l" in "$_p"|"") _l="" ;; esac
  fi
  [ -z "$_l" ] && _l="$_p"
  cache_put "$_p" "$_l"
  printf '%s' "$_l"
}

list_via_pm() {
  pm list packages 2>/dev/null | sed -n 's/^package://p'
}

list_via_xml() {
  for f in /data/system/packages.xml /data/system/packages.list; do
    [ -r "$f" ] || continue
    if [ "${f##*.}" = "xml" ]; then
      sed -n 's/.*name="\([a-zA-Z0-9_.]*\)".*/\1/p' "$f" 2>/dev/null
    else
      awk '{print $1}' "$f" 2>/dev/null
    fi
    return 0
  done
}

main() {
  case "$1" in
    --refresh|-f) REFRESH=1 ;;
    *) REFRESH=0 ;;
  esac
  load_label_cache
  build_sys_list
  # aapt 快路径（存在则用，能大幅降低逐包 dumpsys 的耗时）
  AAPT=""
  for _a in aapt2 aapt; do
    if command -v "$_a" >/dev/null 2>&1; then AAPT="$_a"; break; fi
  done
  build_apk_map || true

  _pkgs=""
  pg_have pm && _pkgs=$(list_via_pm)
  [ -n "$_pkgs" ] || _pkgs=$(list_via_xml)

  if [ -z "$_pkgs" ]; then
    # Never fabricate the module package as a target: an unverified app list must
    # fail closed so the UI keeps its stored target list and blocks saving.
    echo "applist: cannot enumerate installed packages via pm or system package database" >&2
    return 1
  fi

  _plist="$(pg_cache_dir)/pkgs.$$"
  printf '%s\n' "$_pkgs" | sort -u > "$_plist" 2>/dev/null
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    # The FX hook module and LSPosed managers are infrastructure, not ordinary
    # targets; the module also fails closed for these packages at runtime.
    case "$p" in
      de.privacyguard.hook|de.privacyguard.adhook|org.lsposed.manager|org.lsposed.lspd|org.meowcat.edxposed.manager) continue ;;
    esac
    _sys=0
    if is_sys "$p"; then _sys=1; fi
    _n=$(name_of "$p")
    printf '{"pkg":"%s","name":"%s","sys":%s}\n' "$(json_esc "$p")" "$(json_esc "$_n")" "$_sys"
  done < "$_plist"
  rm -f "$_plist" 2>/dev/null
}

main "$@"
