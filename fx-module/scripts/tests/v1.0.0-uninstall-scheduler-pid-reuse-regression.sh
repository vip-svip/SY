#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
U="$ROOT/uninstall.sh"
# Validate process identity before TERM and again before SIGKILL.
count=$(grep -Fc '_pg_sched_cmd=$(tr' "$U" || true)
[ "$count" -ge 1 ]
grep -Fq 'scheduler PID $_pg_sched_pid changed identity during shutdown; refusing SIGKILL' "$U"
grep -Fq 'Revalidate process identity immediately before SIGKILL' "$U"
sh -n "$U"
echo 'FX uninstall scheduler PID-reuse regression: PASS'
