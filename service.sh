#!/system/bin/sh
# ============================================================
#  广告拦截·内核增强版 — late_start service
#  系统启动完成后执行: 应用规则、启动守护进程、启动面板
# ============================================================
MODDIR=${0%/*}
DATA_DIR=/data/adb/SY
[ -d "$DATA_DIR" ] || DATA_DIR=/data/SY
LOG="$DATA_DIR/logs/service.log"
mkdir -p "$DATA_DIR/logs" 2>/dev/null

# 等待系统启动完成
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 60 ]; do
  sleep 2; i=$((i+1))
done
sleep 8

exec >>"$LOG" 2>&1
echo "=== service start $(date) ==="

if [ -f "$DATA_DIR/config/sy.conf" ]; then
  . "$DATA_DIR/config/sy.conf"
fi

# DNS: 应用 hosts 拦截规则 (含订阅/自定义/内置库)
sh "$MODDIR/scripts/dns.sh" apply

# 网络拦截: 应用域名/IP/网段/端口规则 (多类型)
if [ -f "$MODDIR/scripts/netblock.sh" ]; then
  sh "$MODDIR/scripts/netblock.sh" apply
fi

# 隐私防泄露: 开机恢复（仅当上次为开启状态；DNS/IPv6/IP/VPN/节点）
if [ -f "$MODDIR/scripts/leakguard.sh" ]; then
  sh "$MODDIR/scripts/leakguard.sh" restore
fi

# DNS 接管 (独立 DNS 页启用时)
if [ "${DNSSRV_ENABLE:-0}" = "1" ] && [ -f "$MODDIR/scripts/dnssrv.sh" ]; then
  sh "$MODDIR/scripts/dnssrv.sh" apply
fi

# 网络代理: 若曾开启防泄露，开机自动恢复
if [ -f "$DATA_DIR/rules/proxy/.leak" ] && [ -f "$MODDIR/scripts/proxynode.sh" ]; then
  sh "$MODDIR/scripts/proxynode.sh" leak on
fi
# 网络代理: 若总开关开启且有选中节点，开机自动拉起内核
if [ "${PROXY_ENABLE:-0}" = "1" ] && [ -f "$MODDIR/scripts/proxynode.sh" ]; then
  sh "$MODDIR/scripts/proxynode.sh" up
fi

# MITM: 若启用则开启透明代理与重定向
if [ "${MITM_ENABLE:-0}" = "1" ]; then
  sh "$MODDIR/scripts/mitm.sh" up
fi

# 开屏跳过守护
if [ "${SPLASH_ENABLE:-1}" = "1" ]; then
  bg_spawn "$DATA_DIR/logs/splash.log" sh "$MODDIR/scripts/splash.sh" daemon >/dev/null
  echo "splash daemon started pid=$!"
fi

# 面板 Web 服务 (本地 + 局域网)
if [ "${PANEL_ENABLE:-1}" = "1" ]; then
  sh "$MODDIR/scripts/panel.sh" ensure
  # 兜底: 25s 后再确认一次，防止启动早期依赖未就绪导致 serve 未起
  ( sleep 25; sh "$MODDIR/scripts/panel.sh" ensure >>"$LOG" 2>&1 ) &
fi


# 隐私护盾: FX/风控应用隔离 + 能力面收紧（仅总开关开启时）
if [ "${PRIVACY_ENABLE:-0}" = "1" ] && [ -f "$MODDIR/scripts/privacy_guard.sh" ]; then
  sh "$MODDIR/scripts/privacy_guard.sh" apply
fi

# 游戏隐私保护: 不让游戏读取隐私（仅总开关开启时）
if [ "${GAME_PRIVACY_ENABLE:-0}" = "1" ] && [ -f "$MODDIR/scripts/game_privacy.sh" ]; then
  sh "$MODDIR/scripts/game_privacy.sh" apply
fi

# FX 深度抵抗（仅总开关开启时）
if [ "${FX_DEEPGUARD_ENABLE:-0}" = "1" ] && [ -f "$MODDIR/scripts/fx_deepguard.sh" ]; then
  sh "$MODDIR/scripts/fx_deepguard.sh" apply
fi

# 剪贴板监视（仅总开关开启时）
if [ "${CLIPGUARD_ENABLE:-0}" = "1" ] && [ -f "$MODDIR/scripts/clip_guard.sh" ]; then
  sh "$MODDIR/scripts/clip_guard.sh" apply
fi
echo "=== service init done ==="

# ---- 开机后台同步外置规则库 (在线时, 不阻塞启动) ----
if [ -f "$MODDIR/scripts/ruleset.sh" ]; then
  ( sh "$MODDIR/scripts/ruleset.sh" sync >>"$DATA_DIR/logs/ruleset.log" 2>&1 & )
fi
