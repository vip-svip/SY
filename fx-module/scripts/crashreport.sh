#!/system/bin/sh
# PrivacyGuard crashreport.sh — 崩溃归因工具（判断闪退是不是本模块造成的）
#
#   crashreport.sh list               读 /data/tombstones/tombstone_*，列一张表
#   crashreport.sh show N             看第 N 个 tombstone 的详情（时间/进程/线程/信号/Cause/栈顶3帧）
#   crashreport.sh classify           自动归因 + 输出 JSON（WebUI『日志』页用）+ 写 $PG/crashreport.txt
#   crashreport.sh classify --quiet   只写文件，不打印 JSON
#
# 分类口径（保守：只有证据指向模块时才报 module_related）：
#   miui_browser_native : 进程 com.android.browser 且栈顶在 libmiui_chromium.so / libchrome*.so
#   lsposed             : 进程或栈出现 lspd / lsposed / zygisk_lsposed（Xposed 框架自身问题，非本模块）
#   module_related      : 进程或栈出现 privacyguard 痕迹，或 Java 崩溃（Abort message 里 java.*）
#   other               : 其它（系统服务自身断言、第三方 App 等）
#
# 依赖: /system/bin/sh + toybox（awk/grep/sed/date），无 bashism，无 bash 数组。
# >>> pg-moddir (auto)
_pg_d=$(dirname "$0" 2>/dev/null)
MODDIR=$(cd "$_pg_d" 2>/dev/null && pwd)
case "$MODDIR" in */scripts) MODDIR=${MODDIR%/scripts} ;; esac
if [ ! -f "$MODDIR/module.prop" ]; then
  _pg_d2=$MODDIR
  _pg_n=0
  while [ -n "$_pg_d2" ] && [ "$_pg_d2" != "/" ] && [ $_pg_n -lt 4 ]; do
    if [ -f "$_pg_d2/module.prop" ]; then MODDIR=$_pg_d2; break; fi
    _pg_d2=$(dirname "$_pg_d2")
    _pg_n=$((_pg_n+1))
  done
fi
# <<< pg-moddir
# 兜底: 从 /data/local/tmp 或 WebUI 里直接调用时，$0 推导不到模块根目录
if [ ! -f "$MODDIR/module.prop" ]; then
  for _pg_c in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard; do
    [ -f "$_pg_c/module.prop" ] && { MODDIR=$_pg_c; break; }
  done
fi
PG=${PG:-/data/adb/privacyguard}
TDIR=${PG_TOMBSTONE_DIR:-/data/tombstones}
OUT="$PG/crashreport.txt"
TABLE=/data/local/tmp/pg_crashreport.tbl

# ---------- 单文件字段提取（显式匹配，避免 awk 变量注入） ----------
tb_ts()      { awk '/^Timestamp: /{ sub(/^Timestamp: */, ""); print; exit }' "$1" 2>/dev/null; }
tb_cmd()     { awk '/^Cmdline: /{ sub(/^Cmdline: */, ""); print; exit }' "$1" 2>/dev/null; }
tb_cause()   { awk '/^Cause: /{ sub(/^Cause: */, ""); print; exit }' "$1" 2>/dev/null; }
tb_abort()   { awk '/^Abort message: /{ sub(/^Abort message: */, ""); print; exit }' "$1" 2>/dev/null; }
tb_pidline() { awk '/^pid: /{ print; exit }' "$1" 2>/dev/null; }
tb_thread()  { tb_pidline "$1" | sed -n 's/.*name: \([^ ]*\).*/\1/p'; }
tb_signal()  { awk '/^signal [0-9]+/{ if (match($0, /\([A-Z_]+\)/)) print substr($0, RSTART+1, RLENGTH-2); else print $2; exit }' "$1" 2>/dev/null; }

tb_top() { # $1=N 帧数  $2=文件
  awk -v n="${1:-3}" '
    /^backtrace:/ { inbt = 1; next }
    inbt && /^ +#[0-9]+ pc/ { print; c++; if (c >= n) exit }
  ' "$2" 2>/dev/null
}

tb_frames8() { # 前 8 帧（证据面）
  awk '
    /^backtrace:/ { inbt = 1; next }
    inbt && /^ +#[0-9]+ pc/ { print; c++; if (c >= 8) exit }
  ' "$1" 2>/dev/null
}

tb_sym() { # 从一帧里取 (symbol)；没有符号(so 已 strip)就取 so 文件名
  # 帧格式: "      #00 pc 000000000477caa0  /path/libx.so (BuildId: abc) (sym+off)"
  #       或 "      #10 pc 000000000008d774  /apex/.../libc.so (abort+168) (BuildId: ...)"
  line=$(echo "$1" | sed 's/ *(BuildId: [0-9a-f]*)[[:space:]]*$//')
  s=$(echo "$line" | sed -n 's/.*(\([^()]*\))$/\1/p')
  case "$s" in
    *BuildId*) s="" ;;
  esac
  if [ -n "$s" ]; then echo "$s"; return; fi
  echo "$line" | sed -n 's#.*/\([^/ ]*\) *$#\1#p'
}

tb_ep() { # Timestamp → epoch 秒；解析失败输出 0
  ts=$(tb_ts "$1")
  [ -z "$ts" ] && { echo 0; return; }
  e=$(date -d "$ts" +%s 2>/dev/null)
  case "$e" in ''|*[!0-9]*) e=0 ;; esac
  echo "$e"
}

# ---------- 枚举（数字序） ----------
tb_files() {
  for f in "$TDIR"/tombstone_[0-9][0-9] "$TDIR"/tombstone_[0-9][0-9][0-9]; do
    [ -f "$f" ] && echo "$f"
  done
}

tb_index_of() { b=$(basename "$1"); echo "${b#tombstone_}"; }

# ---------- 分类核心：输出一个词 ----------
tb_classify_file() {
  f="$1"
  cmd=$(tb_cmd "$f")
  top=$(tb_top 1 "$f" | head -1)
  topline=$(echo "$top" | sed 's/^ *//')
  ev=$(tb_frames8 "$f")

  # 1) MIUI 浏览器自身 native 崩溃（最常见，且与模块无关）
  case "$cmd" in
    com.android.browser)
      case "$ev" in
        *libmiui_chromium.so*|*libchrome*.so*|*libmonochrome*.so*)
          echo miui_browser_native; return ;;
      esac
      ;;
    *browser*|*Browser*)
      case "$top" in
        *libmiui_chromium.so*|*lib*.so*) echo miui_browser_native; return ;;
      esac
      ;;
  esac

  # 2) LSPosed / zygisk 框架自身
  case "$cmd" in
    *lspd*|*lsposed*|*LSPosed*) echo lsposed; return ;;
  esac
  case "$ev" in
    *zygisk_lsposed*|*liblspd*|*lspd*) echo lsposed; return ;;
  esac

  # 3) 模块痕迹（privacyguard 出现在栈或映射里）
  case "$ev" in
    *privacyguard*|*de.privacyguard.hook*) echo module_related; return ;;
  esac
  maps=$(grep -m6 -E 'lspd|lsposed|privacyguard|zygisk' "$f" 2>/dev/null | head -6)
  case "$maps" in
    *privacyguard*) echo module_related; return ;;
  esac

  # 4) Java 异常崩溃：模块 hook 抛异常会在 Abort message 里留 java.* 痕迹
  ab=$(tb_abort "$f")
  case "$ab" in
    *java.*|*priv.*guard*) echo module_related; return ;;
  esac

  # 5) 内存类错误（SIGSEGV/SIGABRT）且栈顶是模块常改的 Java 接口 —— 保守归 other，
  #    因为 hook 层的破坏会表现为 Java FATAL 而不是 native segv。
  echo other
}

tb_reason() {
  case "$1" in
    miui_browser_native) echo "MIUI 浏览器自身 native 崩溃（libmiui_chromium.so），与本模块无关" ;;
    lsposed)             echo "LSPosed/zygisk 框架进程崩溃，属于框架自身问题" ;;
    module_related)      echo "崩溃现场出现 privacyguard 模块痕迹，需人工复核" ;;
    *)                   echo "无模块关联证据（系统服务/第三方 App 自身崩溃）" ;;
  esac
}

json_esc() { # stdin → 单行 JSON 安全字符串（转义 \ " 以及控制字符）
  awk '{
    gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/," ");
    gsub(/\r/,""); printf "%s", $0
  }'
}

# ---------- list ----------
do_list() {
  printf '%-3s %-19s %-22s %-16s %-9s %-18s %s\n' "IDX" "TIME" "PROC" "THREAD" "SIGNAL" "TOP" "CLASS"
  n=0
  for f in $(tb_files); do
    idx=$(tb_index_of "$f")
    ts=$(tb_ts "$f" | cut -c1-19)
    cmd=$(tb_cmd "$f")
    thr=$(tb_thread "$f")
    sig=$(tb_signal "$f")
    sym=$(tb_sym "$(tb_top 1 "$f" | head -1)")
    cls=$(tb_classify_file "$f")
    printf '%-3s %-19s %-22s %-16s %-9s %-18s %s\n' "$idx" "$ts" "$cmd" "$thr" "$sig" "$sym" "$cls"
    n=$((n+1))
  done
  [ "$n" -eq 0 ] && echo "(无 tombstone：$TDIR 为空 —— 没有 native 崩溃记录)"
  echo "共 $n 条；详细归因: crashreport.sh classify"
}

# ---------- show ----------
do_show() {
  want=$1
  [ -z "$want" ] && { echo "用法: crashreport.sh show N （N 见 list）" >&2; return 2; }
  case "$want" in
    ''|*[!0-9]*) echo "show 需要数字序号（见 list）" >&2; return 2 ;;
  esac
  if [ "${#want}" -eq 1 ]; then want="0$want"; fi
  f="$TDIR/tombstone_$want"
  [ -f "$f" ] || { echo "没有 $f" >&2; return 1; }
  cls=$(tb_classify_file "$f")
  echo "===== $f ====="
  echo "时间   : $(tb_ts "$f")"
  echo "进程   : $(tb_cmd "$f")"
  echo "线程   : $(tb_pidline "$f")"
  echo "信号   : $(tb_signal "$f")"
  ab=$(tb_abort "$f"); [ -n "$ab" ] && echo "Abort  : $ab"
  echo "Cause  : $(tb_cause "$f")"
  echo "分类   : $cls — $(tb_reason "$cls")"
  echo "--- 栈顶 3 帧 ---"
  tb_top 3 "$f"
  echo "--- 模块痕迹（lspd/zygisk/privacyguard 映射行）---"
  grep -m6 -E 'lspd|lsposed|privacyguard|zygisk' "$f" 2>/dev/null | sed 's/^ *//'
}

# ---------- classify ----------
do_classify() {
  quiet=$1
  : > "$TABLE"
  n=0; c_browser=0; c_lsp=0; c_mod=0; c_other=0; latest=0; after_mod=0
  mod_ep=0
  if [ -f "$MODDIR/module.prop" ]; then
    mod_ep=$(date -r "$MODDIR/module.prop" +%s 2>/dev/null)
    case "$mod_ep" in ''|*[!0-9]*) mod_ep=0 ;; esac
  fi
  for f in $(tb_files); do
    idx=$(tb_index_of "$f")
    ts=$(tb_ts "$f" | cut -c1-19)
    cmd=$(tb_cmd "$f")
    thr=$(tb_thread "$f")
    sig=$(tb_signal "$f")
    sym=$(tb_sym "$(tb_top 1 "$f" | head -1)")
    [ -z "$sym" ] && sym="?"
    cls=$(tb_classify_file "$f")
    case "$cls" in
      miui_browser_native) c_browser=$((c_browser+1)) ;;
      lsposed)             c_lsp=$((c_lsp+1)) ;;
      module_related)      c_mod=$((c_mod+1)) ;;
      *)                   c_other=$((c_other+1)) ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$idx" "$ts" "$(echo "$cmd" | json_esc)" "$(echo "$thr" | json_esc)" "$sig" "$cls" "$sym" >> "$TABLE"
    n=$((n+1))
    ep=$(tb_ep "$f")
    [ "$ep" -gt "$latest" ] && latest=$ep
    if [ "$mod_ep" -gt 0 ] && [ "$ep" -ge "$mod_ep" ]; then after_mod=$((after_mod+1)); fi
  done

  if [ "$n" -eq 0 ]; then
    verdict="no_crash"
  elif [ "$c_mod" -eq 0 ]; then
    verdict="not_module_related"
  else
    verdict="needs_review"
  fi

  {
    echo "# PrivacyGuard 崩溃归因摘要  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# 数据源: $TDIR  (tombstone 共 $n 条)"
    echo "# 模块安装时间(module.prop): $(date -r "$MODDIR/module.prop" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
    echo "verdict=$verdict"
    echo "total=$n miui_browser_native=$c_browser lsposed=$c_lsp module_related=$c_mod other=$c_other crashes_after_module_install=$after_mod"
    echo "# IDX  TIME                 PROC                   THREAD           SIGNAL   CLASS                SYM"
    while IFS='	' read -r a b c d e f2 g; do
      printf '%-3s  %-19s %-22s %-16s %-9s %-20s %s\n' "$a" "$b" "$c" "$d" "$e" "$f2" "$g"
    done < "$TABLE"
    echo "# 判读: not_module_related = 所有崩溃均无模块痕迹（不是本模块引起）"
    echo "#       needs_review      = 有崩溃出现模块痕迹，用 show N 复核"
    echo "#       no_crash          = 没有任何 tombstone"
  } > "$OUT" 2>/dev/null
  chmod 644 "$OUT" 2>/dev/null

  if [ "$quiet" = "--quiet" ]; then echo "$OUT"; rm -f "$TABLE"; return 0; fi

  # JSON（WebUI 契约: sh crashreport.sh classify）
  printf '{"ok":true,"verdict":"%s","total":%s,"counts":{"miui_browser_native":%s,"lsposed":%s,"module_related":%s,"other":%s},"crashes_after_module_install":%s,"latest_epoch":%s,"summary_file":"%s","items":[' \
    "$verdict" "$n" "$c_browser" "$c_lsp" "$c_mod" "$c_other" "$after_mod" "$latest" "$OUT"
  first=1
  while IFS='	' read -r a b c d e f2 g; do
    if [ "$first" = "1" ]; then first=0; else printf ','; fi
    printf '{"idx":"%s","time":"%s","proc":"%s","thread":"%s","signal":"%s","class":"%s","sym":"%s"}' \
      "$a" "$b" "$c" "$d" "$e" "$f2" "$g"
  done < "$TABLE"
  printf ']}\n'
  rm -f "$TABLE"
}

case "$1" in
  list)     do_list ;;
  show)     do_show "$2" ;;
  classify) do_classify "$2" ;;
  ""|help|-h|--help)
    echo "用法: crashreport.sh list | show N | classify [--quiet]"
    echo "  list     列出 /data/tombstones 中的崩溃（时间/进程/线程/信号/栈顶/分类）"
    echo "  show N   显示第 N 条的详情与栈顶 3 帧"
    echo "  classify 自动归因；打印 JSON 供 WebUI 使用，并写 $PG/crashreport.txt"
    ;;
  *) echo "未知子命令: $1（可用: list|show|classify）" >&2; exit 2 ;;
esac
