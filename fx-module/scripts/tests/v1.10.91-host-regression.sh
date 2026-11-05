#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
U="$ROOT/uninstall.sh"
grep -Fq '最多清除 64 条模块自有父链跳转' "$U"
grep -Fq '_pg_fw_warn "$_pf_bin ${_pf_table:-filter} chain $_pf_chain still exists' "$U"
grep -Fq "'ip6tables|nat|PGVPN6|OUTPUT|PGVPN6'" "$U"
grep -Fq "'iptables|raw|PGNF|OUTPUT|PGNF'" "$U"
grep -Fq "'iptables|mangle|PGMTU|OUTPUT|PGMTU'" "$U"
for f in "$ROOT"/*.sh "$ROOT"/scripts/*.sh "$ROOT"/scripts/tests/*.sh; do [ ! -f "$f" ] || sh -n "$f"; done
echo 'v1.10.91 host regression: PASS'
