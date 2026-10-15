#!/system/bin/sh
# ============================================================
#  privacy_ruleset.sh — 把隐私增强域名清单接入 DNS 拦截
#  ------------------------------------------------------------
#  模块默认**不启用**这些清单：拦截规则由用户显式选择，
#  避免装了模块就默默改变网络行为（本模块的既定原则）。
#
#  清单来源：rulesets/privacy/{fx,tracker,adblock,antiadblock,push}.txt
#  写入目标：$DATA_DIR/config/user_rules.txt（AdGuard/uBO 语法）
#  幂等：重复 enable 会先删掉上一次由本脚本写入的段落，不会堆叠。
#
#  用法: privacy_ruleset.sh {list|enable <name...|all>|disable [name...]|status|clear}
# ============================================================
. "$(dirname "$0")/common.sh"

PR_DIR="$MODDIR/rulesets/privacy"
PR_USER="$DATA_DIR/config/user_rules.txt"
PR_B="# ---- SY 隐私增强清单 开始（由 privacy_ruleset.sh 管理）----"
PR_E="# ---- SY 隐私增强清单 结束 ----"

pr_all_names() { ls "$PR_DIR" 2>/dev/null | sed 's/\.txt$//' | grep -v '^$' | sort; }

# 移除上一次由本脚本写入的段落（保证幂等，不重复堆叠）
pr_strip() {
  [ -f "$PR_USER" ] || return 0
  awk -v b="$PR_B" -v e="$PR_E" '
    $0==b {skip=1; next}
    $0==e {skip=0; next}
    skip!=1 {print}
  ' "$PR_USER" > "$PR_USER.tmp.$$" 2>/dev/null && mv "$PR_USER.tmp.$$" "$PR_USER"
}

pr_enable() {
  if [ "$1" = "all" ]; then
    # all 排除 push：推送通道会断掉大量 App 的通知，必须显式点名才启用
    names=$(pr_all_names | grep -v '^push$')
  elif [ "$#" -eq 0 ]; then
    names=$(pr_all_names)
  else
    names="$*"
  fi
  [ -z "$names" ] && { echo "ERR: 未指定清单名（用 list 查看）"; exit 1; }
  for n in $names; do
    [ -f "$PR_DIR/$n.txt" ] || { echo "ERR: 清单不存在: $n"; exit 1; }
  done
  pr_strip
  {
    echo "$PR_B"
    for n in $names; do
      echo "# == $n =="
      grep -vE '^[[:space:]]*(#|$)' "$PR_DIR/$n.txt" 2>/dev/null | grep -v '^[[:space:]]*$'
    done
    echo "$PR_E"
  } >> "$PR_USER"
  cfg_set PRIVACY_RULESET_ENABLE 1
  cnt=$(grep -vcE '^[[:space:]]*(#|$)' "$PR_USER" 2>/dev/null || echo 0)
  echo "OK: 已启用隐私清单 [$names]，自定义规则共 $cnt 条"
  sh "$(dirname "$0")/dns.sh" apply >/dev/null 2>&1 && echo "OK: 已重新编译并应用（DNS 拦截即时生效）" || echo "警告：dns.sh apply 返回非零，请到面板查看"
}

pr_disable() {
  if [ "$#" -eq 0 ]; then
    pr_strip
    cfg_set PRIVACY_RULESET_ENABLE 0
    sh "$(dirname "$0")/dns.sh" apply >/dev/null 2>&1
    echo "OK: 已移除全部隐私清单段落并重新应用"
    return 0
  fi
  keep=""
  for n in $(pr_all_names); do
    skip=0
    for d in "$@"; do [ "$n" = "$d" ] && skip=1; done
    [ "$skip" = "0" ] && keep="$keep $n"
  done
  pr_strip
  if [ -n "$keep" ]; then pr_enable $keep >/dev/null; fi
  sh "$(dirname "$0")/dns.sh" apply >/dev/null 2>&1
  echo "OK: 已停用 [$*]"
}

pr_list() {
  echo "可用隐私清单（$PR_DIR）："
  for n in $(pr_all_names); do
    cnt=$(grep -vcE '^[[:space:]]*(#|$)' "$PR_DIR/$n.txt" 2>/dev/null || echo 0)
    printf "  %-14s %s 条\n" "$n" "$cnt"
  done
  echo ""
  echo "启用: privacy_ruleset.sh enable <名字...>   （enable all = 除 push 外全部）"
  echo "停用: privacy_ruleset.sh disable [名字...]  （不带名字=全部移除）"
}

pr_status() {
  en=$(cfg_get PRIVACY_RULESET_ENABLE 0)
  active=$(awk -v b="$PR_B" -v e="$PR_E" '$0==b{s=1;next} $0==e{s=0;next} s==1{n++} END{print n+0}' "$PR_USER" 2>/dev/null)
  printf '{"enabled":"%s","active_lines":%s,"dir":"%s"}\n' "$en" "${active:-0}" "$PR_DIR"
}

case "$1" in
  list)    pr_list ;;
  enable)  shift; pr_enable "$@" ;;
  disable) shift; pr_disable "$@" ;;
  status)  pr_status ;;
  clear)   pr_disable ;;
  *) echo "usage: privacy_ruleset.sh {list|enable <name...|all>|disable [name...]|status|clear}"; exit 2 ;;
esac
