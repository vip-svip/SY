#!/bin/sh
# Verify DNS/NAT commit failures never leave PGNAT hooked or intentionally orphaned.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-pgnat-cleanup.XXXXXX")
awk 'index($0, "if [ \"$ANY_NAT\" = \"1\" ]; then") == 1 {p=1} p && /^# ---------- 2c\./ {exit} p {print}' "$A" > "$T/block.sh"
[ -s "$T/block.sh" ]
# Both failure branches must detach any existing hook and try to remove the FX-owned chain.
[ "$(grep -c 'while iptables \$FWWAIT -t nat -D OUTPUT -j PGNAT' "$T/block.sh")" -eq 2 ]
[ "$(grep -c 'iptables \$FWWAIT -t nat -F PGNAT' "$T/block.sh")" -eq 2 ]
[ "$(grep -c 'iptables \$FWWAIT -t nat -X PGNAT' "$T/block.sh")" -eq 2 ]
# The OUTPUT hook may only be installed after both firewall and NAT queues commit.
commit=$(grep -n 'if \[ "\$_DNS_FW_FLUSH_OK" = "1" \] && nat_flush; then' "$T/block.sh" | cut -d: -f1)
hook=$(grep -n 'if nat4 -I OUTPUT -j PGNAT; then' "$T/block.sh" | cut -d: -f1)
[ -n "$commit" ] && [ -n "$hook" ] && [ "$commit" -lt "$hook" ]
# Unrelated NAT chains are never flushed/deleted by this recovery block.
! grep -E '(-F|-X) (PREROUTING|POSTROUTING|OUTPUT)( |$)' "$T/block.sh"
echo 'FX PGNAT failed-commit cleanup regression: PASS'
