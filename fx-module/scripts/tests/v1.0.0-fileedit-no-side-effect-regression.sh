#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
F="$ROOT/scripts/fileedit.sh"
# Invalid edit/delete line checks must precede target_file() so they cannot
# create a user override as a side effect. Check each operation block.
awk '
  /  edit\)/,/  del\)/ { if ($0 ~ /_cur=\$\(eff\)/) cur=NR; if ($0 ~ /line out of range/) bad=NR; if ($0 ~ /_dst=\$\(target_file\)/) dst=NR }
  END { if (!(cur && bad && dst && cur < bad && bad < dst)) exit 1 }
' "$F"
awk '
  /  del\)/,/  ins\)/ { if ($0 ~ /_cur=\$\(eff\)/) cur=NR; if ($0 ~ /line out of range/) bad=NR; if ($0 ~ /_dst=\$\(target_file\)/) dst=NR }
  END { if (!(cur && bad && dst && cur < bad && bad < dst)) exit 1 }
' "$F"
echo 'FX file editor no-side-effect regression: PASS'
