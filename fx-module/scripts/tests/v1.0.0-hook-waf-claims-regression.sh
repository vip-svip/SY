#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"; APPLY="$ROOT/scripts/apply.sh"
python3 - "$HTML" "$APPLY" <<'PY'
import pathlib,sys
html=pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'); apply=pathlib.Path(sys.argv[2]).read_text(encoding='utf-8')
checks=[('retired WAF/IP category switches absent','data-key="waf_block"' not in html and 'data-key="ip_block"' not in html),('local DNS engine is automatic and has no switch','data-key="dns_engine_adguardhome"' not in html and '本地递归 DNS（自动安全启用）' in html),('UID-level hook label accurate','对 Hook 列表中可解析的应用 UID 执行网络拒绝；不是应用内 SDK Hook' in html),('hook backend uses owner UID','fw4 -A PGUARD -m owner --uid-owner "$HUID" -j REJECT' in apply),('per-row IP/CIDR parser','IP/CIDR 黑名单：每条 [list:block] 自身的启用状态就是开关' in apply and 'pg_list_enabled block 2>/dev/null | awk' in apply),('no injected sample CIDR','198.18.0.0/15' not in apply and '203.0.113.0/24' not in apply)]
for label,ok in checks:
 if not ok: raise SystemExit('FAIL: '+label)
print('PASS: page switches removed; per-row UID/IP behavior matches implementation')
PY
