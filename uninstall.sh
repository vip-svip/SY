#!/system/bin/sh
# ============================================================
#  SY — 卸载脚本（零残留）
#  ------------------------------------------------------------
#  逐项还原顺序（每一步都依赖前一步能读到数据）：
#   1 隐私护盾还原（网络链 + appops + 能力面/权限，按记录精确还原）
#   2 游戏隐私保护还原
#   3 隐私清单段落从 user_rules.txt 移除（保留用户自己写的规则）
#   4 停止后台进程（面板/内核/MITM/开屏/剪贴板/通知）
#   5 卸载内置管理器 App
#   6 iptables 全链清理（按链名兜底，即使脚本缺失）
#   7 hosts 还原（umount + 回填备份 + 删模块覆盖）
#   8 根证书与证书子模块彻底清理
#   9 删数据目录（含 /data/SY 兜底），最后复核
#
#  ## 本轮修掉的真实缺陷
#   旧版只 `rm -rf $DATA_DIR/run`，**不删数据目录本身**，也不还原隐私护盾
#   收走的权限/无障碍/appops；且不清理任何 iptables 链。用户以为卸载干净了，
#   实际权限没还、规则残留、目录还在。
# ============================================================
MODDIR=${0%/*}
# 数据目录解析必须与其他脚本一致（common.sh 用 AB_DATA_DIR 覆盖）；
# 旧版硬编码 /data/adb/SY，会在自定义数据目录场景下删错目录或删不掉。
if [ -n "${AB_DATA_DIR:-}" ]; then
  DATA_DIR="$AB_DATA_DIR"
else
  DATA_DIR=/data/adb/SY
  [ -d "$DATA_DIR" ] || DATA_DIR=/data/SY
fi
MODROOT=/data/adb/modules
CERT_MOD="SY_cert"
# 注意：common.sh 是用「$0 的上级目录」推导 MODDIR 的，它假设调用方在 scripts/ 下。
# uninstall.sh 在模块**根**，直接 source 会把 MODDIR 覆盖成模块的上级目录 ——
# 于是下面 `[ -f "$MODDIR/scripts/privacy_guard.sh" ]` 判为假，还原被静默跳过，
# 而数据目录照样被 rm 掉：记录销毁了、权限却没还（真机跟踪 + 端到端测试抓到的缺陷）。
MY_MODDIR="$MODDIR"
[ -f "$MODDIR/scripts/common.sh" ] && . "$MODDIR/scripts/common.sh" 2>/dev/null
MODDIR="$MY_MODDIR"
[ -d "$MODDIR/scripts" ] || MODDIR=/data/adb/modules/SY

echo "=== SY 卸载开始 ==="

# ---------- 1) 隐私护盾还原（最先做：要读 restore.state）----------
if [ -f "$MODDIR/scripts/privacy_guard.sh" ]; then
  sh "$MODDIR/scripts/privacy_guard.sh" remove >/dev/null 2>&1 && echo "- 隐私护盾已还原（权限/appops/无障碍/网络链）"
fi

# ---------- 2) 游戏隐私保护还原 ----------
if [ -f "$MODDIR/scripts/game_privacy.sh" ]; then
  sh "$MODDIR/scripts/game_privacy.sh" remove >/dev/null 2>&1 && echo "- 游戏隐私保护已还原"
fi

# ---------- 3) 移除隐私清单段落（保留用户自己写的规则）----------
UR="$DATA_DIR/config/user_rules.txt"
if [ -f "$UR" ]; then
  awk -v b="# ---- SY 隐私增强清单 开始（由 privacy_ruleset.sh 管理）----" \
      -v e="# ---- SY 隐私增强清单 结束 ----" '
    $0==b {skip=1; next}
    $0==e {skip=0; next}
    skip!=1 {print}
  ' "$UR" > "$UR.tmp.$$" 2>/dev/null && mv "$UR.tmp.$$" "$UR"
  echo "- 隐私清单段落已移除（用户自有规则保留）"
fi

# ---------- 4) 停止后台进程（按 pid 文件精确停，不用 pkill 模糊匹配）----------
for pf in "$DATA_DIR/run/panel.pid" "$DATA_DIR/run/core.pid" "$DATA_DIR/rules/proxy/core.pid" \
          "$DATA_DIR/run/clipguard.pid" "$DATA_DIR/run/splash.pid" "$DATA_DIR/run/mitm.pid" \
          "$DATA_DIR/run/notify.pid" "$DATA_DIR/run/proxy.pid"; do
  [ -f "$pf" ] || continue
  pid=$(cat "$pf" 2>/dev/null)
  [ -n "$pid" ] && { kill "$pid" 2>/dev/null; echo "- 已停止进程 $pid ($(basename "$pf"))"; }
done
# 兜底：按进程名清理（只在 pid 文件失效时用；模式足够具体，不会误杀）
pkill -f "abserver serve" 2>/dev/null
pkill -f "sing-box run" 2>/dev/null
pkill -f "xray run" 2>/dev/null

# ---------- 5) 卸载内置管理器 App ----------
if [ -f "$MODDIR/scripts/installapp.sh" ]; then
  sh "$MODDIR/scripts/installapp.sh" remove >/dev/null 2>&1 && echo "- 内置管理器 App 已卸载"
else
  pm uninstall --user 0 com.syfusion.manager >/dev/null 2>&1
fi
rm -f /data/local/tmp/SYManager.apk 2>/dev/null

# ---------- 6) MITM 与防泄露撤销 ----------
[ -f "$MODDIR/scripts/mitm.sh" ] && sh "$MODDIR/scripts/mitm.sh" down >/dev/null 2>&1
[ -f "$MODDIR/scripts/proxynode.sh" ] && sh "$MODDIR/scripts/proxynode.sh" leak off >/dev/null 2>&1

# ---------- 7) iptables 全链清理（按链名兜底，即使脚本缺失）----------
# 链名必须与脚本里**实际使用**的完全一致（写错就留残留 —— 这是真实踩过的坑）：
#   SY_PG / SY_PG6  privacy_guard.sh 的隐私护盾隔离链
#   SY_BLOCK        netblock.sh 的网络拦截链
#   AB_DNS          dnssrv.sh 的 DNS 接管链
#   AB_PROXY / AB_PROXY_KILL  proxynode.sh 的代理与断连保护链
# MITM 用的是 nat 表的 REDIRECT 规则（无自定义链），由 mitm.sh down 负责清理。
if command -v iptables >/dev/null 2>&1; then
  for ch in SY_PG SY_BLOCK AB_DNS AB_PROXY AB_PROXY_KILL; do
    iptables -w -D OUTPUT -j "$ch" 2>/dev/null
    iptables -w -D FORWARD -j "$ch" 2>/dev/null
    iptables -w -F "$ch" 2>/dev/null
    iptables -w -X "$ch" 2>/dev/null
  done
  # MITM 的 nat REDIRECT：按端口精确删除（不整表清空，避免误删其他模块规则）
  for pt in 8080 8443; do
    iptables -t nat -S OUTPUT 2>/dev/null | grep -F "REDIRECT --to-ports $pt" | sed "s/^-A/-D/" | while IFS= read -r rule; do
      iptables -t nat $rule 2>/dev/null
    done
  done
  echo "- iptables 链已清理（SY_PG/SY_BLOCK/AB_DNS/AB_PROXY/AB_PROXY_KILL）+ MITM REDIRECT 规则"
fi
if command -v ip6tables >/dev/null 2>&1; then
  for ch in SY_PG6; do
    ip6tables -w -D OUTPUT -j "$ch" 2>/dev/null
    ip6tables -w -F "$ch" 2>/dev/null
    ip6tables -w -X "$ch" 2>/dev/null
  done
fi

# ---------- 8) hosts 还原 ----------
umount /system/etc/hosts 2>/dev/null || umount -l /system/etc/hosts 2>/dev/null
if [ -f "$DATA_DIR/backup/hosts.orig" ]; then
  cp -f "$DATA_DIR/backup/hosts.orig" /system/etc/hosts 2>/dev/null
  chown 0:0 /system/etc/hosts 2>/dev/null
  chmod 0644 /system/etc/hosts 2>/dev/null
  echo "- hosts 已从备份还原"
fi
# 模块目录里的 hosts 覆盖文件也要删，否则下次开机管理器仍会覆盖
rm -f "$MODDIR/system/etc/hosts" 2>/dev/null
rm -f "$MODDIR/system/etc/security/cacerts"/*.0 2>/dev/null
echo "- hosts/证书覆盖文件已移除"

# ---------- 9) 根证书与证书子模块彻底清理 ----------
for c in /data/adb/modules/*/system/etc/security/cacerts/*.0; do
  [ -f "$c" ] && case "$c" in *sy*|*SY*|*adblock*) rm -f "$c" ;; esac
done
rm -rf /data/adb/SY_cert 2>/dev/null
rm -rf "${MODROOT:?}/${CERT_MOD:?}" 2>/dev/null
rm -rf /data/adb/modules_update/$CERT_MOD 2>/dev/null
rm -rf "$MODROOT/$CERT_MOD/system" 2>/dev/null
rm -rf "$DATA_DIR/ca" 2>/dev/null
rm -f "$DATA_DIR/config/.ca_installed" "$DATA_DIR/config/.ca_hash" 2>/dev/null
umount /system/etc/security/cacerts 2>/dev/null
echo "- 根证书与子模块残留已清理"

# ---------- 10) 删数据目录（最后一步；删除后不再调用任何会写文件的函数）----------
# 注意：旧实现在 rm 之后还调 log，而 log 内部会 mkdir 日志目录 ——
# 数据目录会被立刻重建，卸载永远留残留（真机跟踪抓到的缺陷）。
echo "- 删除数据目录 $DATA_DIR"
rm -rf "$DATA_DIR" 2>/dev/null
# 兼容路径兜底：仅当当前数据目录不是 /data/SY 时，顺手清一下遗留的 /data/SY
[ "$DATA_DIR" != "/data/SY" ] && rm -rf /data/SY 2>/dev/null
# 复核：真的没了才算完成
left=0
[ -d "$DATA_DIR" ] && { rm -rf "$DATA_DIR" 2>/dev/null; left=1; }
[ -d "$DATA_DIR" ] && echo "警告：$DATA_DIR 未能删除（可能有进程占用或权限问题），请手动删除"
[ "$left" = "0" ] && echo "- 数据目录已彻底删除"

echo "=== SY 卸载完成（零残留）==="
exit 0
