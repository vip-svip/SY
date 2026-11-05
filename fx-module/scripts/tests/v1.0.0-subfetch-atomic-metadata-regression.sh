#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
F="$ROOT/scripts/subfetch.sh"
sh -n "$F"
# The only metadata writer must stage beside the final sidecar and rename it.
grep -Fq '_sm_tmp="$META.tmp.$$"' "$F"
grep -Fq 'mv -f "$_sm_tmp" "$META"' "$F"
# Neither recovery nor normal fetch may truncate the live sidecar in place.
if grep -nE '(^|[[:space:]])(echo|printf|\{).* > "\$META"|\} > "\$META"' "$F"; then
  echo 'FAIL: subfetch writes metadata sidecar in place' >&2
  exit 1
fi
# Metadata includes a body digest so equal-size body replacement cannot leave
# stale sidecar values undetected after a crash between the two atomic renames.
grep -Fq 'hash=%s' "$F"
grep -Fq '_meta_hash=$(sed -n' "$F"
grep -Fq '_actual_hash=$(_pg_sub_hash "$FILE"' "$F"
grep -Fq '_pg_sub_write_meta "$_meta_size" "$_meta_lines" "$_meta_time" "$_meta_hash"' "$F"
grep -Fq '_pg_sub_write_meta "$_sz" "$_nl" "$_now" "$_hash"' "$F"
echo 'PASS: subscription metadata is staged and atomically renamed in recovery and fetch paths'
