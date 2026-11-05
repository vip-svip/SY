#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
APPLY="$ROOT/scripts/apply.sh"
python3 - "$APPLY" <<'PY'
import pathlib,sys
s=pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
def need(label, cond):
    if not cond: raise SystemExit('FAIL: '+label)
need('batch queue buffers append only, not insert operations', 'case "$_fw_a" in\n      -t)' in s and '-A) _fw_op=1 ;;' in s and '-A|-I) _fw_op=1 ;;' not in s)
need('comment documents immediate insert semantics', '-I 必须立即执行' in s)
start=s.index('if [ "$ANY_FW" = "1" ]; then', s.index('GEOIP/广告网段拦截') if 'GEOIP/广告网段拦截' in s else s.index('if [ "$ANY_FW" = "1" ]; then', s.index('dot_enforce')))
end=s.index('\nelse\n  pg_log "fw: all off, chains cleared"', start)
block=s[start:end]
need('OUTPUT jump happens only after successful queue flush', 'if fw_flush 2>>"$PG/apply.log"; then' in block and block.index('if fw_flush') < block.index('fw4 -I OUTPUT -j PGUARD'))
need('queue commit failure is reported', 'PGUARD 规则队列提交失败，未挂接 OUTPUT' in block)
print('PASS: firewall append queue, OUTPUT activation order, and commit-failure handling')
PY
