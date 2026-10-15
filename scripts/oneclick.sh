#!/system/bin/sh
# ============================================================
#  oneclick.sh — 一键全防护（小白友好）
#  ------------------------------------------------------------
#  为什么需要它：隐私相关开关分散在多个页面（隐私护盾 / FX 深度抵抗 /
#  剪贴板监视 / 游戏隐私），新手不知道该开哪几个、也不知道顺序。
#  本脚本把「该一起开的」合成一个动作，并逐个汇报结果。
#
#  一键开启的内容（每一项都可单独关闭）：
#    · PRIVACY_ENABLE=1      隐私护盾（FX/风控应用隔离 + 能力面收紧）
#    · FX_DEEPGUARD_ENABLE=1 FX 深度抵抗（上报端点 + 安装清单读取面收敛）
#    · CLIPGUARD_ENABLE=1    剪贴板监视
#    · LEAK_GUARD=1          防泄露总开关（DNS/IPv6/IP/VPN/节点）
#  刻意**不**默认开启的项（会显著改变网络行为，需用户明确选择）：
#    · GAME_PRIVACY_ENABLE（要对具体游戏生效，且会收权限）
#    · PROXY_ENABLE / MITM_ENABLE（需要先有节点/证书）
#    · PRIVACY_RULESET_ENABLE（会引入数千条拦截规则，可能误伤）
#
#  用法: oneclick.sh {on|off|status}
# ============================================================
. "$(dirname "$0")/common.sh"

oc_android() { [ -f /system/build.prop ] || [ -n "$SY_FORCE_APPLY" ]; }

oc_set() { # key value
  if cfg_set "$1" "$2"; then
    echo "  · $1 = $2"
  else
    echo "  ! $1 写入失败（配置可能只读）"
  fi
}

oc_on() {
  echo "== 一键启用全防护 =="
  echo "[1/4 写开关]"
  oc_set PRIVACY_ENABLE 1
  oc_set FX_DEEPGUARD_ENABLE 1
  oc_set CLIPGUARD_ENABLE 1
  oc_set LEAK_GUARD 1
  echo "[2/4 应用隐私护盾]"
  if [ -f "$(dirname "$0")/privacy_guard.sh" ]; then
    sh "$(dirname "$0")/privacy_guard.sh" apply 2>&1 | sed "s/^/    /"
  fi
  echo "[3/4 应用 FX 深度抵抗]"
  if [ -f "$(dirname "$0")/fx_deepguard.sh" ]; then
    sh "$(dirname "$0")/fx_deepguard.sh" apply 2>&1 | sed "s/^/    /"
  fi
  echo "[4/4 应用剪贴板监视]"
  if [ -f "$(dirname "$0")/clip_guard.sh" ]; then
    sh "$(dirname "$0")/clip_guard.sh" apply 2>&1 | sed "s/^/    /"
  fi
  echo ""
  echo "OK: 全防护已启用（4 项开关 + 3 项应用）"
  echo "提示：域名拦截清单默认不启用 —— 需要时到「隐私护盾 → 隐私域名清单」点启用"
}

oc_off() {
  echo "== 一键关闭并还原 =="
  for s in privacy_guard fx_deepguard clip_guard; do
    [ -f "$(dirname "$0")/$s.sh" ] && sh "$(dirname "$0")/$s.sh" remove 2>&1 | sed "s/^/  /"
  done
  oc_set PRIVACY_ENABLE 0
  oc_set FX_DEEPGUARD_ENABLE 0
  oc_set CLIPGUARD_ENABLE 0
  oc_set LEAK_GUARD 0
  echo "OK: 全防护已关闭（权限/appops/无障碍已按原值逐项还原）"
}

oc_status() {
  pv=$(cfg_get PRIVACY_ENABLE 0)
  fx=$(cfg_get FX_DEEPGUARD_ENABLE 0)
  cg=$(cfg_get CLIPGUARD_ENABLE 0)
  lg=$(cfg_get LEAK_GUARD 0)
  gp=$(cfg_get GAME_PRIVACY_ENABLE 0)
  n=0;
  [ "$pv" = "1" ] && n=$((n+1))
  [ "$fx" = "1" ] && n=$((n+1))
  [ "$cg" = "1" ] && n=$((n+1))
  [ "$lg" = "1" ] && n=$((n+1))
  [ "$gp" = "1" ] && n=$((n+1))
  printf '{"privacy":"%s","fx":"%s","clip":"%s","leak":"%s","game":"%s","enabled_count":%s,"total":5}\n' \
    "$pv" "$fx" "$cg" "$lg" "$gp" "$n"
}

case "$1" in
  on)     oc_on ;;
  off)    oc_off ;;
  status) oc_status ;;
  *) echo "usage: oneclick.sh {on|off|status}"; exit 2 ;;
esac
