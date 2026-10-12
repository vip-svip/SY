#!/system/bin/sh
# ============================================================
#  common.sh — 共享库：路径、日志、配置读写、JSON 输出
#  被其他脚本 source 使用。POSIX sh 兼容。
# ============================================================

# ---- 路径 ----
MODDIR="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$MODDIR/scripts" ] || MODDIR=/data/adb/modules/SY
# 数据目录：优先 /data/adb/SY；可用 AB_DATA_DIR 覆盖（便于测试/自定义）
DATA_DIR="${AB_DATA_DIR:-}"
if [ -z "$DATA_DIR" ]; then
  DATA_DIR=/data/adb/SY
  [ -d "$DATA_DIR" ] || DATA_DIR=/data/SY
fi

CONFIG="$DATA_DIR/config/sy.conf"
SOURCES="$DATA_DIR/config/sources.conf"
WHITELIST="$DATA_DIR/config/whitelist.conf"
SPLASH_RULES="$DATA_DIR/config/splash_rules.conf"
MITM_RULES="$DATA_DIR/config/mitm_rules.conf"
RULES_DIR="$DATA_DIR/rules"
DNS_DIR="$RULES_DIR/dns"
MITM_DIR="$RULES_DIR/mitm"
SPLASH_DIR="$RULES_DIR/splash"
LOGS="$DATA_DIR/logs"
RUN="$DATA_DIR/run"
CACHE="$DATA_DIR/cache"
SCRIPTS_DIR="$DATA_DIR/scripts"
BACKUP_DIR="$DATA_DIR/backup"
BIN="$MODDIR/bin/abserver"

mkdir -p "$LOGS" "$RUN" "$CACHE" "$DNS_DIR" "$MITM_DIR" "$SPLASH_DIR" \
         "$SCRIPTS_DIR" "$BACKUP_DIR" 2>/dev/null

# ---- 日志 ----
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGS/action.log"
}
logf() { # 指定文件
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$1"
}

# ---- 配置读取 ----
cfg_get() { # key [default]
  key="$1"; def="$2"
  if [ -f "$CONFIG" ]; then
    v=$(grep -E "^[[:space:]]*${key}=" "$CONFIG" 2>/dev/null | tail -n1 | sed "s/^[[:space:]]*${key}=//")
    [ -n "$v" ] && { echo "$v"; return; }
  fi
  echo "$def"
}

cfg_set() { # key value
  key="$1"; val="$2"
  [ -f "$CONFIG" ] || touch "$CONFIG"
  if grep -qE "^[[:space:]]*${key}=" "$CONFIG" 2>/dev/null; then
    tmp="$CONFIG.tmp.$$"
    sed "s|^[[:space:]]*${key}=.*|${key}=${val}|" "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"
  else
    echo "${key}=${val}" >> "$CONFIG"
  fi
}

# ---- JSON 工具 (最小实现，避免依赖) ----
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\r\n'
}

# ---- 数值统计 ----
count_lines() { # file
  [ -f "$1" ] && wc -l < "$1" 2>/dev/null | tr -d ' ' || echo 0
}

# ---- 判断工具 ----
have() { command -v "$1" >/dev/null 2>&1; }

# ---- HTTP 下载 (多后端降级: abserver -> curl -> wget) ----
http_get() { # url outfile [timeout]
  url="$1"; out="$2"; to="${3:-30}"
  if [ -x "$BIN" ]; then
    "$BIN" fetch -url "$url" -out "$out" -timeout "$to" >/dev/null 2>&1 && return 0
  fi
  if have curl; then
    curl -fsSL --connect-timeout "$to" -o "$out" "$url" 2>/dev/null && return 0
  fi
  if have wget; then
    wget -q -T "$to" -O "$out" "$url" 2>/dev/null && return 0
  fi
  return 1
}

# ============================================================
#  通用导入 / 批量删除工具 (v1.2.0)
# ============================================================
# 规范化文本: 去 CR、去空行、去注释行
normalize_lines() {
  sed -e 's/\r$//' -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d'
}

# 本地导入(base64 内容) 追加到目标文件, 去重
import_append_local() { # <target_file> <base64>
  tf="$1"; b="$2"
  [ -z "$b" ] && { echo "ERR: 空内容"; return 1; }
  [ -f "$tf" ] || : > "$tf"
  tmp="$CACHE/imp.$$"
  echo "$b" | base64 -d 2>/dev/null | normalize_lines > "$tmp"
  cat "$tf" "$tmp" 2>/dev/null | normalize_lines | awk '!seen[$0]++' > "$tf.new.$$"
  mv -f "$tf.new.$$" "$tf"
  rm -f "$tmp"
  echo "$(count_lines "$tf")"
}

# 网络导入(URL) 追加到目标文件, 去重; 兼容 base64 订阅体
import_append_net() { # <target_file> <url> [timeout]
  tf="$1"; url="$2"; to="${3:-30}"
  [ -z "$url" ] && { echo "ERR: 空地址"; return 1; }
  [ -f "$tf" ] || : > "$tf"
  tmp="$CACHE/net.$$"
  if http_get "$url" "$tmp" "$to"; then
    if [ "$(wc -l < "$tmp" 2>/dev/null | tr -d ' ')" -le 1 ] && [ "$(wc -c < "$tmp" 2>/dev/null | tr -d ' ')" -gt 64 ]; then
      if base64 -d "$tmp" > "$tmp.dec" 2>/dev/null && [ -s "$tmp.dec" ]; then mv -f "$tmp.dec" "$tmp"; fi
    fi
    cat "$tf" "$tmp" 2>/dev/null | normalize_lines | awk '!seen[$0]++' > "$tf.new.$$"
    mv -f "$tf.new.$$" "$tf"
    rm -f "$tmp" "$tmp.dec"
    echo "$(count_lines "$tf")"
    return 0
  fi
  rm -f "$tmp"
  echo "ERR: 下载失败"
  return 1
}

# 批量删除(逗号分隔的值), 逐行精确匹配
batch_del_values() { # <target_file> <comma_values>
  tf="$1"; vals="$2"
  [ -f "$tf" ] || return 0
  [ -z "$vals" ] && return 0
  dl="$CACHE/del.$$"
  echo "$vals" | tr ',' '\n' | normalize_lines > "$dl"
  grep -vxFf "$dl" "$tf" > "$tf.new.$$" 2>/dev/null
  mv -f "$tf.new.$$" "$tf"
  rm -f "$dl"
  echo "$(count_lines "$tf")"
}

# 批量删除: 按首字段匹配(规则行 "pkg|..." 用 pkg 删除)
batch_del_field() { # <target_file> <comma_values> [sep]
  tf="$1"; vals="$2"; sep="${3:-|}"
  [ -f "$tf" ] || return 0
  [ -z "$vals" ] && return 0
  dl="$CACHE/delf.$$"
  echo "$vals" | tr ',' '\n' | normalize_lines > "$dl"
  awk -F"$sep" -v dl="$dl" 'BEGIN{while((getline l < dl)>0) d[l]=1; close(dl)} !($1 in d){print}' "$tf" > "$tf.new.$$" 2>/dev/null
  mv -f "$tf.new.$$" "$tf"
  rm -f "$dl"
  echo "$(count_lines "$tf")"
}
