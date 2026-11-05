#!/system/bin/sh
# ============================================================
# PrivacyGuard vpntest.sh — 节点延迟测试（TCP 连接耗时）
# 用法: vpntest.sh <proto> <host> <port>
# 输出: {"ms":123} 成功 / {"ms":-1} 不可达 / {"ms":null,"detail":"原因"}
# ============================================================
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
. "$MODDIR/scripts/util.sh"

proto="$1"; host="$2"; port="$3"
if [ -z "$host" ] || [ -z "$port" ]; then
  echo '{"ms":null,"detail":"usage: vpntest.sh proto host port"}'
  exit 0
fi

# 方案 A: curl telnet 拿连接耗时（真机普遍有 curl）
if pg_have curl; then
  t=$(curl -o /dev/null -sS -m 5 -w '%{time_connect}' "telnet://$host:$port" 2>/dev/null)
  case "$t" in
    ''|0.000000)
      echo '{"ms":-1}'
      exit 0
      ;;
    *)
      ms=$(awk -v t="$t" 'BEGIN{printf "%d", t*1000}')
      echo "{\"ms\":$ms}"
      exit 0
      ;;
  esac
fi

# 方案 B: nc 探活（无耗时精度，通=1ms 不通=-1）
if pg_have nc; then
  if nc -z -w 5 "$host" "$port" >/dev/null 2>&1; then
    echo '{"ms":1}'
  else
    echo '{"ms":-1}'
  fi
  exit 0
fi

echo '{"ms":null,"detail":"no curl/nc on device"}'
