#!/system/bin/sh
# Static regression: bounded VPN selection parameters must use native select controls,
# preserve only allow-listed values, and remove the generated controls on close/save.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
grep -q "pickparams:.*selects:" "$HTML"
grep -q "id='edSelectList'" "$HTML"
grep -q "allowed={pick_min_ms:\['30','50','80','120','200'\]" "$HTML"
grep -q "if(cfg.selects){" "$HTML"
grep -q "var doneSelects=document.getElementById('edSelectList')" "$HTML"
grep -q "var sl=document.getElementById('edSelectList');if(sl)sl.remove()" "$HTML"
! grep -q "最低可接受延迟(ms) / 单节点超时(秒) / 最多测速节点数" "$HTML"
echo "PASS: VPN pickparams use select controls with allow-listed persistence and cleanup"
