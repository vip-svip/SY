#!/system/bin/sh
# Regression: failed whole-table listing must not be interpreted as no chain.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
U="$ROOT/uninstall.sh"
grep -Fq 'if _pf_after_rules=$(_pg_fw_call "$_pf_bin" "$_pf_table" -S 2>/dev/null); then' "$U"
grep -Fq 'final table listing failed; cannot verify $_pf_chain cleanup' "$U"
grep -Fq 'table query failed; preserving $_pf_chain for retry' "$U"
grep -Fq 'return 0' "$U"
sh -n "$U"
echo 'FX uninstall firewall-query-failure verification regression: PASS'
