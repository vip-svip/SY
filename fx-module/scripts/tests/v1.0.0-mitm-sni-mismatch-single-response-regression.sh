#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
# Duplicate 421 status lines are invalid HTTP framing; keep one response write only.
count=$(grep -F 'writeError(tlsConn, 421, "Misdirected Request")' "$ROOT/mitm/main.go" | wc -l | tr -d ' ')
[ "$count" = 1 ] || { echo "expected exactly one 421 response write, found $count" >&2; exit 1; }
echo 'mitm SNI mismatch emits a single 421 response: ok'
