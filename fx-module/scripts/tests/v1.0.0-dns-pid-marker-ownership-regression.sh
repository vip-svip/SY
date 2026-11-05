#!/system/bin/sh
# Guard DNS engine lifecycle cleanup against deleting a PID marker replaced by
# a newer start operation. This is a static regression guard; shell unlink is
# not a kernel-level compare-and-delete primitive, so it does not claim atomicity.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
AGH="$ROOT/scripts/adguardhome.sh"
UNBOUND="$ROOT/scripts/unbound.sh"
for f in "$AGH" "$UNBOUND"; do
  sh -n "$f"
done
grep -Fq '_pg_remove_pid_marker_if_matches "$_p"' "$AGH"
grep -Fq '_pg_remove_pid_marker_if_matches "$_new"' "$AGH"
grep -Fq '_pg_remove_pid_marker_if_matches "$_stale"' "$AGH"
grep -Fq '_remove_pid_marker_if_matches "$_p"' "$UNBOUND"
grep -Fq '_remove_pid_marker_if_matches "$_new"' "$UNBOUND"
grep -Fq '_remove_pid_marker_if_matches "$_stale"' "$UNBOUND"
# Direct PIDFILE deletion is allowed only inside each guarded helper.
[ "$(grep -Fc 'rm -f "$PIDFILE"' "$AGH")" -eq 1 ]
[ "$(grep -Fc 'rm -f "$PIDFILE"' "$UNBOUND")" -eq 1 ]
echo 'PASS: DNS engine stop/start failure paths only remove the PID marker after rechecking expected ownership'
