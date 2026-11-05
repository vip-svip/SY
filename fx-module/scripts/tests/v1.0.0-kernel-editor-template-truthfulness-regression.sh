#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
grep -Fq "Netfilter 防火墙规则（raw 表降级实现）" "$HTML"
grep -Fq '当前后端通过 iptables/ip6tables raw 表挂载 OUTPUT 规则' "$HTML"
grep -Fq '应用进程枚举隐藏（LSPosed）' "$HTML"
grep -Fq '不等同于内核 task_struct 隐藏' "$HTML"
! grep -Fq "netfilter:{title:'内核 netfilter 钩子',url:'比 iptables 底层'" "$HTML"
! grep -Fq "task:{title:'隐藏内核 task 结构体',url:'阻止用户态遍历进程'" "$HTML"
echo 'FX kernel editor template truthfulness: PASS'
