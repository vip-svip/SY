#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="$ROOT/scripts/native-vpn-config.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$SOURCE" ] || fail "native VPN configuration editor is missing"
sh -n "$SOURCE" || fail "native VPN configuration editor has invalid shell syntax"
grep -Fqx '  trap cleanup_lock EXIT' "$SOURCE" || fail "VPN config lock must be released only by EXIT cleanup"
grep -Fqx "  trap 'exit 129' HUP" "$SOURCE" || fail "HUP must terminate through EXIT cleanup"
grep -Fqx "  trap 'exit 130' INT" "$SOURCE" || fail "INT must terminate through EXIT cleanup"
grep -Fqx "  trap 'exit 143' TERM" "$SOURCE" || fail "TERM must terminate through EXIT cleanup"
if grep -Fq "trap 'rmdir \"\$LOCK\" 2>/dev/null || :' EXIT HUP INT TERM" "$SOURCE"; then
  fail "signal traps must not release the VPN config lock and continue mutating"
fi
grep -Fq 'mkdir "$LOCK"' "$SOURCE" || fail "VPN config mutation lock acquisition missing"
grep -Fq 'mutate "$2" "$3"' "$SOURCE" || fail "VPN config writes must remain protected by the transaction lock"
grep -Fq 'if sh "$MP/scripts/apply.sh" fast; then' "$SOURCE" || fail "VPN config rollback/apply transaction missing"
echo "PASS: native VPN config lock remains owned until process exit on HUP/INT/TERM"
