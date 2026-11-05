#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
F="$ROOT/scripts/fileedit.sh"
# Insertion positions must be validated before target_file() creates an override.
awk '/  ins\)/,/  put\)/ { if ($0 ~ /_cur=\$\(eff\)/) eff=NR; if ($0 ~ /_dst=\$\(target_file\)/) dst=NR; if ($0 ~ /line out of range/) range=NR } END { if (!eff || !range || !dst || !(eff < dst && range < dst)) exit 1 }' "$F"
grep -Fq 'case "$3" in' "$F"
grep -Fq '_max=$((_total + 1))' "$F"
echo 'FX file editor insert regression: PASS'
