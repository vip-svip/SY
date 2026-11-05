#!/system/bin/sh
# Regression: failed managed-core verification must cancel interception.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SRC="$ROOT/scripts/apply.sh"
awk '
  /existing listener passed managed-core verification/ {seen=1}
  seen && /代理核心就绪校验失败；取消本次流量接管以避免断网/ {fail=1}
  seen && /VPN_ON=0/ {off=1}
  seen && /VPN_LP=""/ {lp=1}
  END {exit !(seen && fail && off && lp)}
' "$SRC"
sh -n "$SRC"
echo 'managed-core ensure failure disables interception: PASS'
