#!/system/bin/sh
# ============================================================
#  action.sh — KernelSU 面板「操作」按钮脚本
#  点击模块卡片的操作按钮时执行：启动/重启 Web 面板并提示地址
# ============================================================
MODDIR=${0%/*}
DATA_DIR=/data/adb/SY
[ -d "$DATA_DIR" ] || DATA_DIR=/data/SY

echo "正在启动广告拦截管理面板..."
sh "$MODDIR/scripts/panel.sh" start
sleep 1
ST=$(sh "$MODDIR/scripts/panel.sh" status)
PORT=$(echo "$ST" | grep -oE '"port":[0-9]+' | cut -d: -f2)
IP=$(echo "$ST" | grep -oE '"lan_ip":"[^"]*"' | cut -d'"' -f4)
echo ""
echo "==================================="
echo " 广告拦截·内核增强版  面板已就绪"
echo " 本地: http://127.0.0.1:$PORT"
[ -n "$IP" ] && echo " 局域网: http://$IP:$PORT"
echo " 令牌: $(sh "$MODDIR/scripts/panel.sh" token 2>/dev/null | head -c 8)****"
echo "-----------------------------------"
echo " 隐私护盾: $(sh "$MODDIR/scripts/privacy_guard.sh" status 2>/dev/null | sed 's/.*"feature":"\([0-9]*\)".*/\1/' | head -c 1)"
echo " 游戏隐私: $(sh "$MODDIR/scripts/game_privacy.sh" status 2>/dev/null | sed 's/.*"feature":"\([0-9]*\)".*/\1/' | head -c 1)"
echo " 剪贴板监视: $(sh "$MODDIR/scripts/clip_guard.sh" status 2>/dev/null | grep -oE '"running":"[a-z]+"' | cut -d: -f2 | tr -d '"')"
echo "==================================="
