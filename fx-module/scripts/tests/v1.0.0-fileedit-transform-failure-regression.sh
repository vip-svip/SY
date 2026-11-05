#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
F="$ROOT/scripts/fileedit.sh"
# All line transforms must gate atomic replacement on successful awk completion.
awk '
  /  edit\)/,/  del\)/ { if ($0 ~ /if ! awk -v n=/) edit_guard=NR; if ($0 ~ /edit transform failed; original preserved/) edit_err=NR; if ($0 ~ /write_tmp_to "\$_dst" "\$_tmp"/) edit_write=NR }
  /  del\)/,/  ins\)/ { if ($0 ~ /if ! awk -v n=/) del_guard=NR; if ($0 ~ /delete transform failed; original preserved/) del_err=NR; if ($0 ~ /write_tmp_to "\$_dst" "\$_tmp"/) del_write=NR }
  /  ins\)/,/  put\)/ { if ($0 ~ /if ! awk -v n=/) ins_guard=NR; if ($0 ~ /insert transform failed; original preserved/) ins_err=NR; if ($0 ~ /write_tmp_to "\$_dst" "\$_tmp"/) ins_write=NR }
  END {
    if (!(edit_guard && edit_err && edit_write && edit_guard < edit_err && edit_err < edit_write)) exit 1
    if (!(del_guard && del_err && del_write && del_guard < del_err && del_err < del_write)) exit 1
    if (!(ins_guard && ins_err && ins_write && ins_guard < ins_err && ins_err < ins_write)) exit 1
  }
' "$F"
grep -Fq 'rm -f "$_tmp" 2>/dev/null' "$F"
echo 'FX file editor transform failure regression: PASS'
