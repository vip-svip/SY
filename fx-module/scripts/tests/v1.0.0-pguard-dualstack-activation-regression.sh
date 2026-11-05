#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
python3 - "$ROOT/scripts/apply.sh" <<'PY'
import pathlib,sys
s=pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
start=s.index('if [ "$ANY_FW" = "1" ]; then', s.index('# IP/CIDR 黑名单'))
end=s.index('\nelse\n  pg_log "fw: all off, chains cleared"',start)
b=s[start:end]
def need(label, ok):
    if not ok: raise SystemExit('FAIL: '+label)
need('both output hooks have explicit success flags', '_PGUARD_HOOK4=0' in b and '_PGUARD_HOOK6=0' in b)
need('activation requires both IPv4 and IPv6 hook success', '[ "$_PGUARD_HOOK4" != "1" ] || [ "$_PGUARD_HOOK6" != "1" ]' in b)
need('one-sided activation is rolled back', '已回滚成功的一侧' in b and 'iptables $FWWAIT -D OUTPUT -j PGUARD' in b and 'ip6tables $FWWAIT -D OUTPUT -j PGUARD' in b)
need('both address families are checked for empty chains', 'RC4=$(iptables' in b and 'RC6=$(ip6tables' in b)
need('empty-chain detection removes both hooks', '已摘除 OUTPUT 挂接' in b)
print('PASS: PGUARD dual-stack activation and rollback checks')
PY
