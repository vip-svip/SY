#!/system/bin/sh
# Host-runnable static regression for fileedit backup/staging/commit ordering.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SRC="$HERE/fileedit.sh"
awk '/^write_tmp_to\(\)/,/^}/ { print }' "$SRC" > "${TMPDIR:-/tmp}/fx-write-tmp-to.$$.sh"
fn="${TMPDIR:-/tmp}/fx-write-tmp-to.$$.sh"
trap 'rm -f "$fn"' EXIT HUP INT TERM
has() { grep -Fq "$1" "$fn" || { echo "FAIL: missing: $1" >&2; exit 1; }; }
has 'cmp -s "$_w_dst" "$_w_bak_tmp"'
has 'cmp -s "$_w_src" "$_w_new_tmp"'
has 'mv -f "$_w_bak_tmp" "$_w_dst.bak"'
has 'mv -f "$_w_new_tmp" "$_w_dst"'
has 'verified backup retained'
# Ensure the source is not moved directly over the destination, which could cross filesystems.
if grep -Fq 'mv -f "$2" "$1"' "$fn"; then echo 'FAIL: direct cross-filesystem replace' >&2; exit 1; fi
# Ensure backup verification precedes backup commit, and backup commit precedes final replace.
a=$(grep -nF 'cmp -s "$_w_dst" "$_w_bak_tmp"' "$fn" | head -n1 | cut -d: -f1)
b=$(grep -nF 'mv -f "$_w_bak_tmp" "$_w_dst.bak"' "$fn" | head -n1 | cut -d: -f1)
c=$(grep -nF 'mv -f "$_w_new_tmp" "$_w_dst"' "$fn" | head -n1 | cut -d: -f1)
[ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] || { echo 'FAIL: unsafe commit order' >&2; exit 1; }
echo 'FX file editor backup atomicity regression: PASS'
