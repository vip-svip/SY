#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
grep -Fq '演示模式：仅保存本地配置，未执行防火墙或 VPN 操作' "$HTML"
grep -Fq '本编辑器内容仅作说明；具体行为由 LSPosed hook 实现' "$HTML"
grep -Fq '应用进程枚举隐藏（LSPosed）' "$HTML"
! grep -Fq "if(k==='k_task')" "$HTML"
grep -Fq 'Netfilter 防火墙规则（非自定义内核钩子）' "$HTML"
! grep -Fq 'Demo: saved (real device writes iptables)' "$HTML"
! grep -Fq "toast('内核配置已保存')" "$HTML"
echo 'FX UI no-fake-success regression: PASS'

# Config import must await disk persistence before claiming success.
grep -Fq 'pgPersistNow().then(function(saved)' "$HTML"
grep -Fq "配置未保存：已恢复上次保存状态" "$HTML"
# Both third-party and native settings imports wait for an in-flight save before model mutation.
grep -Fq 'pgWaitForPersistIdle(0).then(function(){' "$HTML"
