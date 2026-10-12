#!/system/bin/sh
# 在设备上并行起多个静态面板服务，供 perf_compare.py 做同机多版本对比。
# 用法: sh perf_serve.sh <token>
#   8849 -> /data/local/tmp/perf/w_old    旧面板
#   8850 -> /data/local/tmp/perf/w_heavy  重玻璃受控变体
# 前置：把待测 index.html 推到上述 webroot 目录，并把 abserver 放到
#       /data/local/tmp/perf/abserver（模块目录是 noexec，不能直接执行）
TOK="$1"
[ -z "$TOK" ] && { echo "ERR: 缺少 token"; exit 1; }
BASE=/data/local/tmp/perf
BIN="$BASE/abserver"
MODDIR=/data/adb/modules/SY
DATADIR=/data/adb/SY

# 清掉旧的
for p in 8849 8850; do
  for pid in $(ps -A -o PID,ARGS 2>/dev/null | awk -v P=":$p" '$0 ~ /abserver/ && $0 ~ P {print $1}'); do
    kill -9 "$pid" 2>/dev/null
  done
done
sleep 1

start_one() { # port webroot name
  P="$1"; WR="$2"; N="$3"
  echo "--- 启动 $N  port=$P  webroot=$WR"
  cd "$BASE" || exit 1
  nohup "$BIN" serve -addr ":$P" -webroot "$WR" \
        -moddir "$MODDIR" -datadir "$DATADIR" -token "$TOK" \
        > "$BASE/$N.log" 2>&1 &
  echo "  pid=$!"
}

start_one 8849 "$BASE/w_old"   w_old
start_one 8850 "$BASE/w_heavy" w_heavy

# 等待监听
i=0
while [ $i -lt 12 ]; do
  sleep 0.5
  ok=0
  for p in 8849 8850; do
    if awk -v H="$(printf '%04X' $p)" 'NR>1{split($2,a,":"); if(a[2]==H && $4=="0A"){f=1}} END{exit f?0:1}' /proc/net/tcp /proc/net/tcp6 2>/dev/null; then
      ok=$((ok+1))
    fi
  done
  [ $ok -eq 2 ] && break
  i=$((i+1))
done

echo "=== 监听状态 ==="
for p in 8849 8850; do
  H="$(printf '%04X' $p)"
  if awk -v H="$H" 'NR>1{split($2,a,":"); if(a[2]==H && $4=="0A"){f=1}} END{exit f?0:1}' /proc/net/tcp /proc/net/tcp6 2>/dev/null; then
    echo "  :$p LISTEN"
  else
    echo "  :$p 未监听"
  fi
done
echo "=== HTTP 校验 ==="
for p in 8849 8850; do
  echo "  :$p -> $(curl -s -o /dev/null -w '%{http_code} %{size_download}' http://127.0.0.1:$p/index.html 2>/dev/null)"
done
