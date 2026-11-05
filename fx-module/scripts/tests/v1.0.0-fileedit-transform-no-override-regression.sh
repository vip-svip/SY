#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
F="$ROOT/scripts/fileedit.sh"
# For edit/del/ins, the transform must read the effective source and finish
# before target_file() is called (which can create a user override).
awk '
  /  edit\)/,/  del\)/ {
    if ($0 ~ /_tmp="\$PG\/cache\/.fe\.\$\$\.edit"/) start=NR
    if ($0 ~ /if ! awk -v n=/) guard=NR
    if ($0 ~ /\x27 "\$_cur" > "\$_tmp"/) source=NR
    if ($0 ~ /_dst=\$\(target_file\)/) target=NR
    if ($0 ~ /edit transform failed; original preserved/) err=NR
    if ($0 ~ /write_tmp_to "\$_dst" "\$_tmp"/) write=NR
  }
  END { if (!(start && guard && source && target && err && write && start < guard && guard < source && source < err && err < target && target < write)) exit 1 }
' "$F"
awk '
  /  del\)/,/  ins\)/ {
    if ($0 ~ /_tmp="\$PG\/cache\/.fe\.\$\$\.del"/) start=NR
    if ($0 ~ /if ! awk -v n=/) guard=NR
    if ($0 ~ /"\$_cur" > "\$_tmp"/) source=NR
    if ($0 ~ /_dst=\$\(target_file\)/) target=NR
    if ($0 ~ /delete transform failed; original preserved/) err=NR
    if ($0 ~ /write_tmp_to "\$_dst" "\$_tmp"/) write=NR
  }
  END { if (!(start && guard && source && target && err && write && start < guard && guard <= source && source < err && err < target && target < write)) exit 1 }
' "$F"
awk '
  /  ins\)/,/  put\)/ {
    if ($0 ~ /_tmp="\$PG\/cache\/.fe\.\$\$\.ins"/) start=NR
    if ($0 ~ /if ! awk -v n=/) guard=NR
    if ($0 ~ /\x27 "\$_cur" > "\$_tmp"/) source=NR
    if ($0 ~ /_dst=\$\(target_file\)/) target=NR
    if ($0 ~ /insert transform failed; original preserved/) err=NR
    if ($0 ~ /write_tmp_to "\$_dst" "\$_tmp"/) write=NR
  }
  END { if (!(start && guard && source && target && err && write && start < guard && guard < source && source < err && err < target && target < write)) exit 1 }
' "$F"
echo 'FX transform failure does not create override regression: PASS'
