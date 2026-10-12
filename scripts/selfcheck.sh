#!/system/bin/sh
# ============================================================
#  selfcheck.sh — SY 模块自检 / 诊断（以只读为主）
#  用法: sh selfcheck.sh [diagnose|heal]
#    diagnose (默认) 收集 环境/网络/面板/规则 状态到日志与标准输出
#    heal            仅做低风险自愈: 重新挂载 hosts + 重启面板
#  作者: vip-svip
# ============================================================
MODDIR=${0%/*}/..
DATA_DIR=/data/adb/SY
[ -d "$DATA_DIR" ] || DATA_DIR=/data/SY
LOGDIR="$DATA_DIR/logs"
mkdir -p "$LOGDIR" 2>/dev/null
REPORT="$LOGDIR/selfcheck.log"

{
  echo "===== SY selfcheck $(date) ====="
  echo "## 基础"
  echo "  MODDIR=$MODDIR"
  echo "  DATA_DIR=$DATA_DIR"
  echo "  SELinux: $(getenforce 2>/dev/null)"
  echo "  Kernel : $(uname -a 2>/dev/null)"
  echo

  echo "## 模块目录"
  ls -la "$MODDIR" 2>&1 | sed 's/^/  /'
  echo

  echo "## 配置 config/sy.conf"
  cat "$MODDIR/config/sy.conf" 2>&1 | sed 's/^/  /'
  echo

  echo "## 数据目录 (maxdepth 3)"
  find "$DATA_DIR" -maxdepth 3 2>/dev/null | sed 's/^/  /'
  echo

  echo "## 日志尾部"
  for f in post-fs.log service.log action.log; do
    echo "  --- $f ---"
    tail -n 40 "$LOGDIR/$f" 2>&1 | sed 's/^/  /'
  done
  echo

  echo "## 面板 (abserver / 端口 8848)"
  echo "  进程数: $(ps -A 2>/dev/null | grep -c abserver)"
  ps -A 2>/dev/null | grep abserver | sed 's/^/  /'
  echo "  监听 8848:"
  (netstat -tln 2>/dev/null || ss -tln 2>/dev/null) | grep 8848 | sed 's/^/  /'
  echo "  本地探测 127.0.0.1:8848 -> $(curl -s -m 4 -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8848/' 2>/dev/null)"
  echo

  echo "## hosts / DNS 拦截"
  echo "  hosts 挂载条数: $(mount 2>/dev/null | grep -c '/system/etc/hosts')"
  mount 2>/dev/null | grep '/system/etc/hosts' | sed 's/^/  /'
  HS=$(find "$DATA_DIR" -name hosts -type f 2>/dev/null | head -1)
  echo "  hosts 文件: ${HS:-<none>}  行数: $( [ -n "$HS" ] && wc -l < "$HS" )"
  AD=$(find "$DATA_DIR" -name all_domains.txt -type f 2>/dev/null | head -1)
  echo "  域名总表: ${AD:-<none>}  条数: $( [ -n "$AD" ] && wc -l < "$AD" )"
  echo "  /system/etc/hosts 头部:"
  head -n 6 /system/etc/hosts 2>&1 | sed 's/^/  /'
  echo

  echo "## iptables"
  echo "  --- nat ---"
  iptables -t nat -S 2>&1 | sed 's/^/  /'
  echo "  --- filter 中 SY/REDIRECT/DNAT ---"
  iptables -S 2>&1 | grep -iE 'SY_|REDIRECT|DNAT' | sed 's/^/  /'
  echo

  echo "## 代理内核"
  ps -A 2>/dev/null | grep -iE 'sing-box|xray' | sed 's/^/  /'
  echo

  echo "## 连通性"
  for t in 1.1.1.1 8.8.8.8 223.5.5.5; do
    ping -c 1 -W 2 "$t" >/dev/null 2>&1 && echo "  ping $t: OK" || echo "  ping $t: FAIL"
  done
  echo "  解析 baidu.com: $( (nslookup baidu.com 2>/dev/null || getprop net.dns1) | tr '\n' ' ' )"
  echo
  echo "===== selfcheck done -> $REPORT ====="
} 2>&1 | tee "$REPORT"

# ---- 子命令分发（上面的诊断报告已输出并落盘）----
#   diagnose|all|check  仅诊断（all 为面板默认调用的全量自检）
#   heal                诊断 + 低风险自愈（重挂 hosts / 重启面板）
case "${1:-diagnose}" in
  diagnose|all|check)
    :
    ;;
  heal)
    {
      echo "===== heal $(date) ====="
      HS=$(find "$DATA_DIR" -name hosts -type f 2>/dev/null | head -1)
      if [ -s "$HS" ]; then
        umount /system/etc/hosts 2>/dev/null
        mount --bind "$HS" /system/etc/hosts 2>/dev/null && echo "hosts 重新挂载 OK" || echo "hosts 重新挂载 FAIL"
      fi
      if [ -f "$MODDIR/scripts/panel.sh" ]; then
        sh "$MODDIR/scripts/panel.sh" stop   >/dev/null 2>&1
        sh "$MODDIR/scripts/panel.sh" ensure >/dev/null 2>&1
        echo "面板重启后进程数: $(ps -A 2>/dev/null | grep -c abserver)"
      fi
    } 2>&1 | tee -a "$REPORT"
    ;;
  *)
    echo "usage: selfcheck.sh {diagnose|all|heal}" >&2
    exit 2
    ;;
esac
exit 0
