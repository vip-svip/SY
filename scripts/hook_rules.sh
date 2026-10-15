#!/system/bin/sh
# ============================================================
#  hook_rules.sh — Hook 规则管理（自定义 + 多语法导入）
#  ------------------------------------------------------------
#  为什么需要它：
#    · 用户要能写**自己的** Hook 目标（不只是内置那 7 条）；
#    · 用户手里有各种来源的规则（AdGuard/uBlock/hosts/纯域名/Surge），
#      不该要求他先转换格式 —— 这里做**一次粘贴、自动识别、按类型分流**。
#
#  语法识别（analyze / import 共用同一套判定）：
#    1) 元素隐藏      host##selector             → MITM CSS 注入
#    2) 网络规则      ||domain^  /  |http://...  → DNS 网络类
#    3) hosts 格式    0.0.0.0 domain / 127.0.0.1 → DNS 网络类
#    4) 纯域名        example.com                → DNS 网络类
#    5) 正则          /pattern/  /  regex:...    → DNS 正则
#    6) 注释/元数据   !  #  [Adblock Plus 2.0]   → 跳过
#    7) Hook 目标     标签 类名#方法名           → Hook 规则表
#
#  分流去向：
#    · Hook 规则   → DATA_DIR/config/hook_custom.conf（App 侧读取）
#    · 网络类      → DATA_DIR/config/user_rules.txt（DNS 引擎输入）
#    · 元素隐藏类  → DATA_DIR/rules/mitm/custom-cosmetic.txt（MITM 注入）
#  说明：导入只是**写入规则源**，真正生效需再点「应用」（DNS 引擎重建 / MITM 重载）。
# ============================================================
. "$(dirname "$0")/common.sh"

HOOK_CUSTOM="$DATA_DIR/config/hook_custom.conf"
HOOK_BUILTIN="$MODDIR/config/hooks.conf"
NET_IMPORT="$DATA_DIR/config/user_rules.txt"
MITM_IMPORT="$DATA_DIR/rules/mitm/custom-cosmetic.txt"
LAST_ANALYZE="$DATA_DIR/cache/hook_import.analyze"
mkdir -p "$DATA_DIR/config" "$DATA_DIR/rules/mitm" "$DATA_DIR/cache" 2>/dev/null
[ -f "$HOOK_CUSTOM" ] || : > "$HOOK_CUSTOM"
[ -f "$NET_IMPORT" ] || : > "$NET_IMPORT"
[ -f "$MITM_IMPORT" ] || : > "$MITM_IMPORT"

# 单行分类：输出 类型|值
hk_classify() {
  # 【真机缺陷修复】旧版用 `case "$_l" in "||"*)` 判网络规则 —— mksh 下该模式
  # 匹配失败，`||ads.example.com^` 被判成 skip（真机实测 14 条规则全 unknown/skip）。
  # 另外 hosts 格式只取了第一个字段（变成 domain|0.0.0.0，域名丢了）。
  # 现在改用**子串判断 + 显式切分**，与 shell 实现无关。
  _l=$1
  # 去首尾空白
  _l=$(printf "%s" "$_l" | sed "s/^[[:space:]]*//")
  _l=$(printf "%s" "$_l" | sed "s/[[:space:]]*$$//")
  [ -z "$_l" ] && { echo "skip|"; return; }
  # 注释与元数据
  case "$_l" in
    "!"*) echo "skip|"; return ;;
    "#"*) echo "skip|"; return ;;
  esac
  case "$_l" in
    "[Adblock"*|"[Adguard"*|"[uBlock"*|"[AdGuard"*) echo "skip|"; return ;;
  esac
  # 1) 元素隐藏（含 ##）
  case "$_l" in
    *"##"*) echo "cosmetic|$_l"; return ;;
  esac
  # 2) 网络规则：以 || 开头 或 以 |http 开头（用首两字符判断，不依赖 case 模式）
  _p2=$(printf "%s" "$_l" | cut -c1-2)
  if [ "$_p2" = "||" ]; then echo "network|$_l"; return; fi
  _p5=$(printf "%s" "$_l" | cut -c1-5)
  if [ "$_p5" = "|http" ]; then echo "network|$_l"; return; fi
  # 3) hosts 格式：取第 2 个字段作为域名（保留域名，丢弃 0.0.0.0 前缀）
  _f1=$(printf "%s" "$_l" | awk '{print $1; exit}')
  case "$_f1" in
    "0.0.0.0"|"127.0.0.1"|"::1")
      _dom=$(printf "%s" "$_l" | awk '{print $2; exit}')
      if [ -n "$_dom" ]; then echo "network|$_dom"; return; fi
      ;;
  esac
  # 5) 正则
  _pfx=$(printf "%s" "$_l" | cut -c1-6)
  if [ "$_pfx" = "regex:" ]; then echo "regex|$_l"; return; fi
  case "$_l" in
    "/"*"/") echo "regex|$_l"; return ;;
  esac
  # 7) Hook 目标：两个字段、第二字段含 #、第一字段不含点
  case "$_l" in
    *"#"*)
      _t=$(printf "%s" "$_l" | awk '{print $1; exit}')
      _c=$(printf "%s" "$_l" | awk '{print $2; exit}')
      case "$_t" in
        *"."*) : ;;
        "") : ;;
        *)
          if [ -n "$_c" ]; then echo "hook|$_c"; return; fi
          ;;
      esac
      ;;
  esac
  # 4) 纯域名（含点、无空格、无斜杠问号）
  case "$_l" in
    *" "*) : ;;
    *"/"*) : ;;
    *"?"*) : ;;
    *"."*) echo "domain|$_l"; return ;;
  esac
  echo "unknown|$_l"
}

# 统计并（可选）写入
hk_run_import() {
  _write="$1"
  _n_hook=0; _n_net=0; _n_cos=0; _n_re=0; _n_dom=0; _n_skip=0; _n_unk=0
  : > "$LAST_ANALYZE"
  while IFS= read -r _line; do
    _r=$(hk_classify "$_line")
    _k=$(printf "%s" "$_r" | sed "s/|.*//")
    _v=$(printf "%s" "$_r" | sed "s/.*|//")
    case "$_k" in
      skip)     _n_skip=$((_n_skip+1)) ;;
      hook)     _n_hook=$((_n_hook+1)); [ "$_write" = "1" ] && echo "$_v" >> "$HOOK_CUSTOM" ;;
      network)  _n_net=$((_n_net+1));  [ "$_write" = "1" ] && echo "$_v" >> "$NET_IMPORT" ;;
      domain)   _n_dom=$((_n_dom+1));  [ "$_write" = "1" ] && echo "$_v" >> "$NET_IMPORT" ;;
      regex)    _n_re=$((_n_re+1));    [ "$_write" = "1" ] && echo "$_v" >> "$NET_IMPORT" ;;
      cosmetic) _n_cos=$((_n_cos+1));  [ "$_write" = "1" ] && echo "$_v" >> "$MITM_IMPORT" ;;
      *)        _n_unk=$((_n_unk+1)) ;;
    esac
    echo "$_k|$_v" >> "$LAST_ANALYZE"
  done
  echo "识别结果："
  echo "  Hook 目标      $_n_hook 条 → hook_custom.conf"
  echo "  网络规则       $_n_net 条（|| 语法）"
  echo "  纯域名         $_n_dom 条"
  echo "  正则           $_n_re 条"
  echo "  → 以上三项共 $((_n_net+_n_dom+_n_re)) 条进入 DNS 引擎（user_rules.txt）"
  echo "  元素隐藏规则   $_n_cos 条 → MITM 注入（custom-cosmetic.txt）"
  echo "  跳过（注释/元数据）$_n_skip 条"
  echo "  无法识别       $_n_unk 条"
  if [ "$_write" = "1" ]; then
    # 去重
    sort -u "$HOOK_CUSTOM" -o "$HOOK_CUSTOM" 2>/dev/null
    sort -u "$NET_IMPORT" -o "$NET_IMPORT" 2>/dev/null
    sort -u "$MITM_IMPORT" -o "$MITM_IMPORT" 2>/dev/null
    echo ""
    echo "已写入规则源。点「应用」后：DNS 引擎重建 + MITM 重载才会真正生效。"
  fi
}

hk_stats() {
  _c=0; [ -f "$HOOK_CUSTOM" ] && _c=$(grep -v "^[[:space:]]*#" "$HOOK_CUSTOM" 2>/dev/null | grep -c . | head -n1); [ -z "$_c" ] && _c=0
  _b=0; [ -f "$HOOK_BUILTIN" ] && _b=$(grep -v "^[[:space:]]*#" "$HOOK_BUILTIN" 2>/dev/null | grep -c . | head -n1); [ -z "$_b" ] && _b=0
  _n=0; [ -f "$NET_IMPORT" ] && _n=$(grep -c . "$NET_IMPORT" 2>/dev/null | head -n1); [ -z "$_n" ] && _n=0
  _m=0; [ -f "$MITM_IMPORT" ] && _m=$(grep -c . "$MITM_IMPORT" 2>/dev/null | head -n1); [ -z "$_m" ] && _m=0
  printf '%s\n' "{\"ok\":true,\"custom\":$_c,\"builtin\":$_b,\"netImported\":$_n,\"cosmeticImported\":$_m}"
}

hk_save_custom() {
  cat > "$HOOK_CUSTOM.tmp" 2>/dev/null
  if [ -s "$HOOK_CUSTOM.tmp" ]; then
    mv "$HOOK_CUSTOM.tmp" "$HOOK_CUSTOM" 2>/dev/null
    _v=0; _c=0
    while IFS= read -r _l; do
      _k=$(hk_classify "$_l" | cut -d"|" -f1)
      case "$_k" in hook) _v=$((_v+1)) ;; "") : ;; *) _c=$((_c+1)) ;; esac
    done < "$HOOK_CUSTOM"
    echo "OK: 已保存自定义 Hook 规则（合法 $_v 条，格式可疑 $_c 条）"
  else
    rm -f "$HOOK_CUSTOM.tmp" 2>/dev/null
    echo "ERR: 输入为空，未保存"
    return 1
  fi
}

hk_apply() {
  sh "$(dirname "$0")/dns.sh" engine-build 2>&1 | tail -1
  sh "$(dirname "$0")/mitm.sh" rules-reload >/dev/null 2>&1 && echo "OK: MITM 规则已重载"
  echo "OK: 已应用（DNS 引擎 + MITM）"
}

if [ "$(basename "$0")" = "hook_rules.sh" ]; then
case "$1" in
  analyze)      hk_run_import 0 ;;
  import)       hk_run_import 1 ;;
  stats)        hk_stats ;;
  list-custom)  cat "$HOOK_CUSTOM" 2>/dev/null ;;
  save-custom)  hk_save_custom ;;
  clear-custom) : > "$HOOK_CUSTOM"; echo "OK: 自定义 Hook 规则已清空" ;;
  clear-imports) : > "$NET_IMPORT"; : > "$MITM_IMPORT"; echo "OK: 已清空导入的网络类与元素隐藏规则" ;;
  apply)        hk_apply ;;
  classify)     hk_classify "$2" ;;
  *) echo "usage: hook_rules.sh {analyze|import|stats|list-custom|save-custom|clear-custom|clear-imports|apply|classify <line>}"; exit 2 ;;
esac
fi
