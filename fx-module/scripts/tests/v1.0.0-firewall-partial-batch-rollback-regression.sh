#!/system/bin/sh
# Static guard for reverse-order rollback after partial iptables-restore fallback.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SRC="$ROOT/scripts/apply.sh"
# Both filter-family and NAT fallback must track successful lines and invert -A to -D.
grep -q '_fl_ok_file=' "$SRC" || { echo 'FAIL: filter fallback does not track applied rules'; exit 1; }
grep -q '_nf_ok_file=' "$SRC" || { echo 'FAIL: NAT fallback does not track applied rules'; exit 1; }
grep -q "awk '{ a\[NR\]=\$0 } END { for (i=NR; i>0; i--) print a\[i\] }' \"\$_fl_ok_file\"" "$SRC" || { echo 'FAIL: filter rollback is not reverse-order'; exit 1; }
grep -q "awk '{ a\[NR\]=\$0 } END { for (i=NR; i>0; i--) print a\[i\] }' \"\$_nf_ok_file\"" "$SRC" || { echo 'FAIL: NAT rollback is not reverse-order'; exit 1; }
grep -q '\-D \${_fl_rb#-A }' "$SRC" || { echo 'FAIL: filter rollback does not invert append to delete'; exit 1; }
grep -q '\-D \${_nf_rb#-A }' "$SRC" || { echo 'FAIL: NAT rollback does not invert append to delete'; exit 1; }
echo 'PASS: filter and NAT partial fallback batches attempt reverse-order rollback'
