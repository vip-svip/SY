#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
# Local hosts conversion must stream to a file, not materialize the entire result
# in a shell variable; the source remains independent of subscription compilation.
awk '/^  # ---- 本地 hosts 文件/{p=1} p{print} /# 追踪域名（conf 区/{exit}' "$A" > "${TMPDIR:-/tmp}/fx-local-hosts-block.$$.txt"
B="${TMPDIR:-/tmp}/fx-local-hosts-block.$$.txt"
trap 'rm -f "$B"' EXIT HUP INT TERM
grep -Fq '_hfl_tmp="$PG/cache/local-hosts.$$.tmp"' "$B"
grep -Fq ' > "$_hfl_tmp"' "$B"
grep -Fq 'cat "$_hfl_tmp" >> "$TMP"' "$B"
grep -Fq 'wc -l < "$_hfl_tmp"' "$B"
! grep -Fq '_hfl=$(awk' "$B"
grep -Fq '本地 hosts 转换失败' "$B"
grep -Fq 'pg_list_enabled rule | while IFS= read -r entry' "$A"
echo 'FX local hosts streaming regression: PASS'
