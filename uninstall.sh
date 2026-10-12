#!/system/bin/sh
# ============================================================
#  广告拦截·内核增强版 — 卸载脚本
#  彻底清理运行时资源 + 证书子模块(SY_cert) + 根证书残留
# ============================================================
MODDIR=${0%/*}
DATA_DIR=/data/adb/SY
MODROOT=/data/adb/modules
CERT_MOD="SY_cert"

# 停止面板服务
[ -f "$DATA_DIR/run/panel.pid" ] && kill "$(cat "$DATA_DIR/run/panel.pid")" 2>/dev/null
# 停止 MITM 代理
[ -f "$DATA_DIR/run/proxy.pid" ] && kill "$(cat "$DATA_DIR/run/proxy.pid")" 2>/dev/null
# 停止开屏守护
[ -f "$DATA_DIR/run/splash.pid" ] && kill "$(cat "$DATA_DIR/run/splash.pid")" 2>/dev/null
# 停止代理内核
[ -f "$DATA_DIR/rules/proxy/core.pid" ] && kill "$(cat "$DATA_DIR/rules/proxy/core.pid")" 2>/dev/null

# 撤销 iptables 重定向与防泄露
sh "$MODDIR/scripts/mitm.sh" down >/dev/null 2>&1
[ -f "$MODDIR/scripts/proxynode.sh" ] && sh "$MODDIR/scripts/proxynode.sh" leak off >/dev/null 2>&1

# 解除 hosts 绑定挂载
umount /system/etc/hosts 2>/dev/null

# ---------- 根证书 / 证书子模块 彻底清理 ----------
# 1) 移除已安装的根证书(overlay 与系统 CA 目录)
for c in /data/adb/modules/*/system/etc/security/cacerts/*.0 ; do
  [ -f "$c" ] && case "$c" in *sy*|*adblock*) rm -f "$c" ;; esac
done
rm -rf /data/adb/SY_cert 2>/dev/null
# 证书子模块残留(含 modules / modules_update)
rm -rf "$MODROOT/$CERT_MOD" 2>/dev/null
rm -rf /data/adb/modules_update/$CERT_MOD 2>/dev/null
# 子模块自带的 overlay CA 目录
rm -rf "$MODROOT/$CERT_MOD/system" 2>/dev/null
# 2) 清理证书生成中间产物
rm -rf "$DATA_DIR/ca" 2>/dev/null
rm -f "$DATA_DIR/config/.ca_installed" "$DATA_DIR/config/.ca_hash" 2>/dev/null
# 3) 移除自签名证书在系统内的挂载点(若存在)
umount /system/etc/security/cacerts 2>/dev/null

# 移除持久化运行目录
rm -rf "$DATA_DIR/run" 2>/dev/null
echo "uninstalled: SY (含证书子模块 $CERT_MOD 残留已清理)"
