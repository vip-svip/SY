#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
python3 - "$A" <<'PY'
import pathlib,sys
s=pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
def need(label, ok):
    if not ok: raise SystemExit('FAIL: '+label)
needle='if [ "$(pg_get vpn_leak 0)" = "1" ]; then'
need('vpn_leak condition appears once', s.count(needle) == 1)
start=s.index('fw_flush() {'); end=s.index('\n# 重建链',start); b=s[start:end]
need('fallback checks IPv4 replay status', 'if iptables $FWWAIT -t "$_fl_t" $_fl_ln 2>>"$PG/apply.log"; then' in b and '_fl_line_fail=1' in b)
need('fallback checks IPv6 replay status', 'if ip6tables $FWWAIT -t "$_fl_t" $_fl_ln 2>>"$PG/apply.log"; then' in b and '_fl_line_fail=1' in b)
need('fallback success is distinguished from failure', '逐条回退全部成功' in b and '逐条回退不完整' in b)
need('partial fallback failure sets transaction failure', 'if [ "$_fl_line_fail" = "1" ]; then' in b and '_fl_fail=1' in b)
print('PASS: firewall fallback transaction and VPN leak condition checks')
PY
