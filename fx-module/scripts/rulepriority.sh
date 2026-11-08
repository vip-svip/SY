#!/system/bin/sh
# ============================================================
# FX rulepriority.sh — 按价值排序 [list:rule]，降低截断损失
#
# 背景（实测确认）：
#   mitm/networkfilter.go 的 maxNetworkFilterRules = 50000，且是**顺序截断** ——
#   一旦达到上限，后面所有规则源整体丢弃。真实 EasyList 级订阅有 20~40 万行，
#   多条订阅叠加时，排在前面的吃掉额度，排在后面的等于没装。
#
# 这个工具把高价值源排到前面，让 50000 的额度优先给最需要的规则：
#   反诈 > 广告 > 跟踪/隐私 > 其余
#
#   rulepriority.sh show     显示当前顺序与每类的估算行数占用
#   rulepriority.sh apply    按价值重排（写回 settings.conf，原子替换）
#
# 注意：改变顺序会改变"截断时保留哪些规则"，这是有意的取舍，不是副作用。
# ============================================================
set -u

_d=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
MODDIR=$(CDPATH= cd -- "$_d/.." 2>/dev/null && pwd)
if [ ! -f "$MODDIR/module.prop" ]; then
  echo '{"ok":false,"error":"module directory unavailable"}'
  exit 2
fi

PG=${PG:-/data/adb/privacyguard}
CONF="$PG/settings.conf"

# 价值分级：数字越小越先保留。判据来自订阅 URL 与描述里的关键词，
# 与 mitm 的 adIntentDomain 语义保持一致的方向。
classify() {
  _cl_url=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
  case "$_cl_url" in
    *anti*|*fraud*|*反诈*|*96110*|*scam*) echo 1 ;;
    *ad*|*ads*|*advert*|*banner*|*popup*) echo 2 ;;
    *track*|*analytic*|*privacy*|*spy*) echo 3 ;;
    *) echo 4 ;;
  esac
}

show_rules() {
  [ -f "$CONF" ] && [ ! -L "$CONF" ] || {
    echo '{"ok":false,"error":"settings.conf unavailable"}'
    exit 2
  }
  _sr_in=0
  _sr_n=0
  printf '{"ok":true,"rules":['
  while IFS= read -r _sr_line || [ -n "$_sr_line" ]; do
    case "$_sr_line" in
      '['*) [ "$_sr_line" = "[list:rule]" ] && _sr_in=1 || _sr_in=0; continue ;;
    esac
    [ "$_sr_in" = 1 ] || continue
    case "$_sr_line" in
      '#'*|'') continue ;;
    esac
    _sr_key=$(printf '%s' "$_sr_line" | cut -d'|' -f1)
    case "$_sr_key" in https://*) : ;; *) continue ;; esac
    _sr_class=$(classify "$_sr_key")
    [ "$_sr_n" -gt 0 ] && printf ','
    _sr_n=$((_sr_n + 1))
    printf '{"url":"%s","class":%s}' "$_sr_key" "$_sr_class"
  done < "$CONF"
  printf '],"count":%s}\n' "$_sr_n"
}

apply_order() {
  [ -f "$CONF" ] && [ ! -L "$CONF" ] || {
    echo '{"ok":false,"error":"settings.conf unavailable"}'
    exit 2
  }
  _ao_dir="$PG"
  [ -d "$_ao_dir" ] && [ ! -L "$_ao_dir" ] || {
    echo '{"ok":false,"error":"state directory unsafe"}'
    exit 2
  }
  _ao_tmp=$(mktemp "$CONF.pri.XXXXXX") || {
    echo '{"ok":false,"error":"cannot create candidate"}'
    exit 73
  }

  # 记下 [list:rule] 段的起止行，其余内容原样保留。
  _ao_start=$(grep -n '^\[list:rule\]$' "$CONF" 2>/dev/null | head -n1 | cut -d: -f1)
  if [ -z "$_ao_start" ]; then
    rm -f "$_ao_tmp"
    echo '{"ok":false,"error":"[list:rule] section not found"}'
    exit 4
  fi
  _ao_end=$(awk -v s="$_ao_start" 'NR>s && /^\[/ {print NR; exit}' "$CONF" 2>/dev/null)
  if [ -z "$_ao_end" ]; then
    _ao_end=$(( $(wc -l < "$CONF" 2>/dev/null || echo 0) + 1 ))
  fi

  # 段内非规则行（注释、空行）与规则行分开；规则按 class 排序，同 class 保持原相对顺序。
  awk -v s="$_ao_start" -v e="$_ao_end" '
    function cls(u,  t) {
      t = tolower(u)
      if (t ~ /anti/ || t ~ /fraud/ || t ~ /scam/) return 1
      if (t ~ /ad/ || t ~ /banner/ || t ~ /popup/) return 2
      if (t ~ /track/ || t ~ /analytic/ || t ~ /privacy/ || t ~ /spy/) return 3
      return 4
    }
    NR >= s && NR < e {
      line = $0
      if (line == "" || line ~ /^#/) { other[++on] = line; next }
      key = line
      sub(/[|].*/, "", key)
      if (key !~ /^https:\/\//) { other[++on] = line; next }
      rules[++rn] = line
      classes[rn] = cls(key)
      order[rn] = rn
      next
    }
    { print }
    END {
      # 稳定插入排序：规则数量有限（几十条），O(n^2) 可接受且不依赖 gawk 的 asort
      for (i = 2; i <= rn; i++) {
        for (j = i; j > 1 && classes[j-1] > classes[j]; j--) {
          tmp = rules[j]; rules[j] = rules[j-1]; rules[j-1] = tmp
          tc = classes[j]; classes[j] = classes[j-1]; classes[j-1] = tc
        }
      }
      for (i = 1; i <= on; i++) print other[i]
      for (i = 1; i <= rn; i++) print rules[i]
    }
  ' "$CONF" > "$_ao_tmp" 2>/dev/null || {
    rm -f "$_ao_tmp"
    echo '{"ok":false,"error":"reorder failed"}'
    exit 1
  }

  if [ ! -s "$_ao_tmp" ]; then
    rm -f "$_ao_tmp"
    echo '{"ok":false,"error":"reorder produced an empty config"}'
    exit 1
  fi
  chmod 600 "$_ao_tmp" 2>/dev/null
  if mv -f "$_ao_tmp" "$CONF" 2>/dev/null; then
    echo '{"ok":true,"applied":1}'
  else
    rm -f "$_ao_tmp" 2>/dev/null
    echo '{"ok":false,"error":"cannot commit reorder"}'
    exit 1
  fi
}

case "${1:-show}" in
  show) show_rules ;;
  apply) apply_order ;;
  *)
    printf 'usage: %s show|apply\n' "$0" >&2
    exit 64
    ;;
esac
