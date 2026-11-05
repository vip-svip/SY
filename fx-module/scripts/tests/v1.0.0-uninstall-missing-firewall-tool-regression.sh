#!/system/bin/sh
# Regression: absent firewall tools must not be treated as verified-clean uninstall.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
U="$ROOT/uninstall.sh"
grep -Fq 'if ! command -v "$_pf_bin" >/dev/null 2>&1; then' "$U"
grep -Fq '_pg_fw_warn "$_pf_bin unavailable; cannot verify $_pf_table chain $_pf_chain cleanup"' "$U"
grep -Fq 'PG_FW_INCOMPLETE=1; _mitm_warn' "$U"
sh -n "$U"
echo 'FX uninstall missing-firewall-tool verification regression: PASS'
