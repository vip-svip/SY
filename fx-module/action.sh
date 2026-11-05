#!/system/bin/sh
# PrivacyGuard Action 按钮：立即应用配置并显示状态
# >>> pg-moddir (auto)
# 兼容相对路径/软链/su 调用：先尝试按 $0 推导，失败再逐级向上找 module.prop
_pg_d=$(dirname "$0" 2>/dev/null)
MODDIR=$(cd "$_pg_d" 2>/dev/null && pwd)
case "$MODDIR" in */scripts) MODDIR=${MODDIR%/scripts} ;; esac
if [ ! -f "$MODDIR/module.prop" ]; then
  _pg_d2=$MODDIR
  _pg_n=0
  while [ -n "$_pg_d2" ] && [ "$_pg_d2" != "/" ] && [ $_pg_n -lt 4 ]; do
    if [ -f "$_pg_d2/module.prop" ]; then MODDIR=$_pg_d2; break; fi
    _pg_d2=$(dirname "$_pg_d2")
    _pg_n=$((_pg_n+1))
  done
fi
PG_MODDIR=$MODDIR
# <<< pg-moddir
PG=/data/adb/privacyguard
echo "=== PrivacyGuard 隐私卫士 ==="
echo ""
echo "[*] 管理器环境: $(sh "$MODDIR/scripts/status.sh" text | grep '管理器' | cut -d: -f2 | tr -d ' ')"
echo "[*] 应用当前配置..."
sh "$MODDIR/scripts/apply.sh"
_rc=$?
if [ $_rc -eq 0 ]; then
  echo "[✓] 配置已应用，无错误"
else
  echo "[!] 应用完成，但有 $_rc 处失败——明细:"
  echo ""
  cat "$PG/apply.errors" 2>/dev/null || echo "  (明细文件不存在，完整日志: $PG/apply.log)"
fi
echo ""
echo "--- 当前状态 ---"
sh "$MODDIR/scripts/status.sh" text
echo ""
echo "WebUI: 在 KernelSU/APatch 管理器中点击本模块的『WebUI』按钮打开配置面板"
echo "LSPosed: 在 LSPosed 管理器启用『PrivacyGuard Hook』并勾选作用域"
