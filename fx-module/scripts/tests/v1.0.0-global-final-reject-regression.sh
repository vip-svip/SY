#!/system/bin/sh
# Functional host regression for MATCH/FINAL policy normalization.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
S="$ROOT/scripts/vpnrule.sh"
C="$ROOT/scripts/vpncore.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-final-policy.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
run_case() {
  name=$1; rule=$2; expected=$3
  printf '[list:rule]\n%s|test|1\n' "$rule" > "$T/rules.conf"
  out=$(PG="$T/pg-$name" VPNRULE_SRC="$T/rules.conf" VPNRULE_WORK="$T/work-$name" sh "$S" --json)
  final=$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["final"])')
  [ "$final" = "$expected" ] || { echo "FAIL $name: expected $expected got $final: $out" >&2; exit 1; }
  printfinal=$(PG="$T/pg2-$name" VPNRULE_SRC="$T/rules.conf" VPNRULE_WORK="$T/work2-$name" sh "$S" --print-final)
  [ "$printfinal" = "$expected" ] || { echo "FAIL $name --print-final: expected $expected got $printfinal" >&2; exit 1; }
}
run_case reject 'MATCH,REJECT' reject
run_case block 'FINAL,BLOCK' reject
run_case direct 'FINAL,DIRECT' direct
run_case proxy 'MATCH,PROXY' proxy
# Verify core keeps a valid outbound final and emits a trailing reject action for global reject.
grep -Fq '[ "$_vr_final" = '\''reject'\'' ] && _global_reject=1' "$C"
grep -Fq '\"action\":\"reject\",\"method\":\"drop\"' "$C"
# Global reject must not leave the private-network direct exception ahead of catch-all.
python3 - "$C" <<'PYTEST'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
a = s.index('if [ "$_global_reject" = 1 ]; then')
b = s.index('# route.rule_set 定义块', a)
block = s[a:b]
assert 'action' in block and 'reject' in block
assert 'else' in block and 'ip_is_private' in block
assert block.index('action') < block.index('ip_is_private')
PYTEST
grep -Fq "reject|REJECT|Reject) _final='proxy'" "$C"
if grep -Fq "reject|REJECT|Reject) _final='direct'" "$C"; then
  echo 'FAIL: global reject falls back to direct' >&2; exit 1
fi
for f in "$S" "$C"; do sh -n "$f"; done
echo 'PASS: global MATCH/FINAL reject functional policy regression'
