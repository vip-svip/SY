#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
F="$ROOT/scripts/fileedit.sh"
grep -Fq '_out_limit=32768' "$F"
grep -Fq '_remain=$((_out_limit - _out_bytes))' "$F"
grep -Fq '_hits_trunc=1' "$F"
grep -Fq '"hitsTrunc":%s' "$F"
grep -Fq '[ "$_hits_trunc" -eq 1 ] && break' "$F"
echo 'FX file editor find total response bound regression: PASS'
