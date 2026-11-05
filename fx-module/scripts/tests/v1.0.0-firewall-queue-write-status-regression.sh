#!/system/bin/sh
# Host-side static regression guard: buffered firewall wrappers must propagate
# fwbuf's write failure instead of returning success unconditionally.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SRC="$ROOT/scripts/apply.sh"
T="${TMPDIR:-/tmp}/fx-fw-queue-status-$$.txt"
trap 'rm -f "$T"' EXIT HUP INT TERM
for fn in fw4 fw6 nat4 nat6; do
  awk -v fn="$fn" '$0 ~ "^[[:space:]]*" fn "\\(\\)[[:space:]]*\\{" {on=1} on {print} on && /^[[:space:]]*}/ {exit}' "$SRC" > "$T"
  test -s "$T" || { echo "FAIL: cannot extract $fn" >&2; exit 1; }
  grep -q 'fwbuf ' "$T" || { echo "FAIL: $fn no longer calls fwbuf" >&2; exit 1; }
  grep -q 'return \$?' "$T" || { echo "FAIL: $fn masks fwbuf status" >&2; exit 1; }
  if grep -Eq 'fwbuf .*;[[:space:]]*return 0' "$T"; then
    echo "FAIL: $fn returns success unconditionally after fwbuf" >&2; exit 1
  fi
done
echo 'PASS: fw4/fw6/nat4/nat6 propagate firewall queue write status'
