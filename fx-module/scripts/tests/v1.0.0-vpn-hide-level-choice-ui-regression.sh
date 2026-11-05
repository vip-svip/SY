#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
UI="$ROOT/webroot/index.html"
grep -Fq "hidelevel:{t:'隐藏强度'" "$UI"
grep -Fq "choice:[{value:'0',title:'L0 · 仅隐藏系统痕迹'" "$UI"
grep -Fq "{value:'1',title:'L1 · 标准（推荐）'" "$UI"
grep -Fq "{value:'2',title:'L2 · 增强'" "$UI"
grep -Fq "if(cfg.choice){" "$UI"
grep -Fq "secSet('vpn','hide_level',v)" "$UI"
grep -Fq "secSet('vpn','hide_udp_block_all',v==='2'?'1':'0')" "$UI"
grep -Fq "secSet('vpn','hide_dot_block',v==='2'?'1':'0')" "$UI"
grep -Fq "secSet('vpn','hide_mtu_clamp',v==='2'?'1':'0')" "$UI"
if grep -F "输入 1 或 2" "$UI" >/dev/null; then echo 'manual enum entry still present' >&2; exit 1; fi
echo 'FX VPN hide-level choice UI regression: PASS'
