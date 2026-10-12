#!/system/bin/sh
# ============================================================
#  updater.sh — 模块在线更新 (读取 GitHub Release, 在 KernelSU/Magisk 内直接更新)
#  用法: updater.sh {check|update|status|set-repo <owner/repo>}
#  作者: vip-svip
# ============================================================
. "$(dirname "$0")/common.sh"

DEF_REPO=$(cfg_get UPDATE_REPO "vip-svip/SY-Fusion")
REPO=$(cfg_get UPDATE_REPO "vip-svip/SY-Fusion")
MIRROR=$(cfg_get UPDATE_MIRROR "")

_api() { # -> url
  u="https://api.github.com/repos/$REPO/releases/latest"
  if [ -n "$MIRROR" ]; then printf '%s/%s' "${MIRROR%/}" "$u"; else printf '%s' "$u"; fi
}

_cur_ver() { # version string from module.prop
  sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null | head -n1
}
_cur_code() {
  sed -n 's/^versionCode=//p' "$MODDIR/module.prop" 2>/dev/null | head -n1
}

# 从 release JSON 中提取字段
_jget() { # jsonfile key  -> value(去引号)
  grep -m1 "\"$2\"" "$1" 2>/dev/null | sed 's/.*:[[:space:]]*"//;s/",\{0,1\}[[:space:]]*$//'
}
_jget_num() { # jsonfile key
  grep -m1 "\"$2\"" "$1" 2>/dev/null | sed -E 's/.*:[[:space:]]*([0-9]+).*/\1/'
}

_fetch_release() { # jsonfile ; 0 ok
  f="$1"
  log "updater: 获取 $REPO 最新 release"
  if http_get "$(_api)" "$f" 40 && [ -s "$f" ]; then return 0; fi
  return 1
}

check() {
  tmp="$CACHE/update.json"
  if ! _fetch_release "$tmp"; then echo "ERR: 无法获取最新版本(检查网络/更新源)"; return 1; fi
  tag=$(_jget "$tmp" tag_name)
  url=$(_jget "$tmp" browser_download_url)
  cur=$(_cur_ver)
  [ -z "$tag" ] && { echo "ERR: 解析版本失败"; return 1; }
  if [ "$tag" = "$cur" ]; then
    echo "OK: 已是最新版本 $cur"
  else
    echo "OK: 发现新版本 $tag (当前 $cur)"
    [ -n "$url" ] && echo "URL: $url"
  fi
}

update() {
  tmp="$CACHE/update.json"
  if ! _fetch_release "$tmp"; then echo "ERR: 无法获取最新版本"; return 1; fi
  tag=$(_jget "$tmp" tag_name)
  url=$(_jget "$tmp" browser_download_url)
  cur=$(_cur_ver)
  [ -z "$url" ] && { echo "ERR: 未找到下载地址(该 release 无 zip 资产)"; return 1; }
  if [ "$tag" = "$cur" ] && [ "$1" != "force" ]; then
    echo "OK: 已是最新版本 $cur，无需更新(如需强制可加 force)"; return 0
  fi
  zip="$CACHE/SY_update.zip"
  echo "下载 $tag ..."
  rm -f "$zip"
  if ! http_get "$url" "$zip" 300 || [ ! -s "$zip" ]; then echo "ERR: 下载失败"; return 1; fi
  # 校验是否为有效模块包
  if ! unzip -l "$zip" >/dev/null 2>&1; then echo "ERR: 下载文件不是有效 zip"; return 1; fi
  # 安装: 依次尝试 ksud / magisk
  if command -v ksud >/dev/null 2>&1; then
    if ksud module install "$zip" 2>&1 | tail -n 3; then echo "OK: 已通过 KernelSU 安装 $tag，请重启生效"; return 0; fi
  fi
  if [ -x /data/adb/ksud ]; then
    if /data/adb/ksud module install "$zip" 2>&1 | tail -n 3; then echo "OK: 已通过 KernelSU 安装 $tag，请重启生效"; return 0; fi
  fi
  if command -v magisk >/dev/null 2>&1; then
    if magisk --install-module "$zip" 2>&1 | tail -n 3; then echo "OK: 已通过 Magisk 安装 $tag，请重启生效"; return 0; fi
  fi
  echo "OK: 已下载 $tag 到 $zip (未检测到 KernelSU/Magisk 安装器，请手动刷入)"
}

status() {
  printf '{"repo":"%s","mirror":"%s","current":"%s","versionCode":"%s","method":"%s"}\n' \
    "$(json_escape "$REPO")" "$(json_escape "$MIRROR")" \
    "$(json_escape "$(_cur_ver)")" "$(json_escape "$(_cur_code)")" \
    "$(json_escape "$(command -v ksud >/dev/null 2>&1 && echo ksu || (/data/adb/ksud -h >/dev/null 2>&1 && echo ksu || (command -v magisk >/dev/null 2>&1 && echo magisk || echo none)))")"
}

case "$1" in
  check)    check ;;
  update)   update "$2" ;;
  status)   status ;;
  set-repo) cfg_set UPDATE_REPO "$2"; echo "OK: 更新源 -> $2" ;;
  set-mirror) cfg_set UPDATE_MIRROR "$2"; echo "OK: 更新镜像 -> ${2:-无}" ;;
  get-repo) echo "$REPO" ;;
  *) echo "usage: updater.sh {check|update [force]|status|set-repo <owner/repo>|set-mirror <url>}" ;;
esac
