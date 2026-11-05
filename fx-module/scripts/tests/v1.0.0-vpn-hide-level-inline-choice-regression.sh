#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
UI="$ROOT/webroot/index.html"
# The hide-level setting must no longer route through the generic editor.
! grep -Fq 'data-vpn-edit="hidelevel"' "$UI"
grep -Fq 'id="vpnHideLevelOptions"' "$UI"
for level in 0 1 2; do grep -Fq "data-hide-level-choice=\"$level\"" "$UI"; done
grep -Fq "document.addEventListener('click',function(e){" "$UI"
grep -Fq "secSet('vpn','hide_level',v)" "$UI"
grep -Fq "secSet('vpn','hide_icmp_block_all',v==='2'?'1':'0')" "$UI"
grep -Fq "pgSave();vpnPanelSync();vToast(vLt('隐藏强度已保存','Hide level saved'))" "$UI"
grep -Fq "b.setAttribute('aria-pressed'" "$UI"
echo 'FX VPN hide-level inline choice regression: PASS'
