#!/system/bin/sh
# ============================================================
#  kernel.sh — 代理内核管理 (内置 sing-box / 可自由选择 / 可删除)
#  用法: kernel.sh {list|use <name|path>|del <name>|install-bundled
#                   |download <url>|arch|current}
#  作者: vip-svip
# ============================================================
. "$(dirname "$0")/common.sh"

KBIN="$MODDIR/bin"
BUNDLED="$MODDIR/bin/kernels"
PN="$DATA_DIR/rules/proxy"
CORE_FLAG="$PN/.core"
mkdir -p "$PN"

arch_name() {
  ABI=$(getprop ro.product.cpu.abi 2>/dev/null); M=$(uname -m 2>/dev/null)
  case "$ABI $M" in
    *arm64*|*aarch64*)        echo arm64 ;;
    *armeabi*|*armv7*|*arm*)  echo armv7 ;;
    *x86_64*|*x86*|*amd64*)   echo amd64 ;;
    *)                        echo arm64 ;;
  esac
}

_is_core() { # path -> 0 if looks like an executable proxy core
  b=$(basename "$1")
  case "$b" in
    sing-box|sing-box-*|xray|xray-*|v2ray|v2ray-*) return 0 ;;
    *) return 1 ;;
  esac
}

list() {
  echo "== 已安装内核 ($KBIN) =="
  found=0
  for c in "$KBIN"/sing-box* "$KBIN"/xray* "$KBIN"/v2ray*; do
    [ -f "$c" ] || continue
    _is_core "$c" || continue
    x="noexec"; [ -x "$c" ] && x="exec"
    printf '%s|%s|%s\n' "$(basename "$c")" "$x" "$c"; found=1
  done
  [ "$found" = "0" ] && echo "(未安装任何内核)"
  echo "== 内置内核 (随包, 可一键安装) =="
  if [ -d "$BUNDLED" ]; then
    for c in "$BUNDLED"/*; do [ -f "$c" ] && printf 'bundled|%s|%s\n' "$(basename "$c")" "$c"; done
  fi
  cur=$(cat "$CORE_FLAG" 2>/dev/null)
  [ -n "$cur" ] && echo "current=$cur" || echo "current=none"
}

use() {
  n="$2"; [ -z "$n" ] && { echo "ERR: 缺少内核名"; return 1; }
  case "$n" in /*) p="$n" ;; *) p="$KBIN/$n" ;; esac
  [ -x "$p" ] || { echo "ERR: 内核不存在或不可执行: $p"; return 1; }
  echo "$p" > "$CORE_FLAG"; echo "OK: 内核已选择 -> $(basename "$p")"
}

del() {
  n="$2"; [ -z "$n" ] && { echo "ERR: 缺少内核名"; return 1; }
  p="$KBIN/$(basename "$n")"
  [ -f "$p" ] || { echo "ERR: 内核不存在: $(basename "$n")"; return 1; }
  cur=$(cat "$CORE_FLAG" 2>/dev/null)
  [ "$cur" = "$p" ] && rm -f "$CORE_FLAG"
  rm -f "$p" && echo "OK: 已删除内核 $(basename "$p")" || echo "ERR: 删除失败"
}

install_bundled() {
  a=$(arch_name)
  src="$BUNDLED/sing-box-$a"
  [ -f "$src" ] || src="$BUNDLED/sing-box"
  [ -f "$src" ] || { echo "ERR: 无内置内核可安装 (架构 $a)"; return 1; }
  cp -f "$src" "$KBIN/sing-box"; chmod 0755 "$KBIN/sing-box"
  echo "$KBIN/sing-box" > "$CORE_FLAG"
  echo "OK: 已安装内置内核 sing-box -> bin/sing-box (源: $(basename "$src"))"
}

download_kernel() {
  url="$2"; [ -z "$url" ] && { echo "ERR: 缺少URL"; return 1; }
  bn=$(basename "$url" | sed 's/[?].*$//')
  out="$KBIN/$bn"; mkdir -p "$KBIN"
  if http_get "$url" "$out" 120; then
    case "$bn" in *.tar.gz|*.gz) ( cd "$KBIN" && tar -xzf "$out" 2>/dev/null ); rm -f "$out" ;; esac
    for cand in "$KBIN/sing-box" "$KBIN/xray" "$KBIN/$bn"; do [ -f "$cand" ] && chmod 0755 "$cand"; done
    # 若下载的是内核, 自动选中
    for cand in "$KBIN/sing-box" "$KBIN/xray"; do
      [ -x "$cand" ] && { echo "$cand" > "$CORE_FLAG"; break; }
    done
    echo "OK: 内核下载完成"
  else
    echo "ERR: 内核下载失败"
  fi
}

case "$1" in
  list)            list ;;
  use)             use "$@" ;;
  del|delete|rm)   del "$@" ;;
  install-bundled) install_bundled ;;
  download)        download_kernel "$@" ;;
  arch)            arch_name ;;
  current)         cat "$CORE_FLAG" 2>/dev/null ;;
  *) echo "usage: kernel.sh {list|use <name|path>|del <name>|install-bundled|download <url>|arch|current}" ;;
esac
