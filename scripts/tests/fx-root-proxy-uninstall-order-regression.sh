#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="$ROOT/fx-module/uninstall.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$SOURCE" ] || fail "FX uninstall hook missing"
sh -n "$SOURCE" || fail "FX uninstall hook shell syntax invalid"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-root-proxy-uninstall.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
MOD="$T/module"; PG="$T/state"; LOG="$T/order.log"
mkdir -p "$MOD/scripts" "$PG"
cp "$SOURCE" "$MOD/uninstall.sh"
cat > "$MOD/scripts/yulong-root-proxy.sh" <<'PROXY'
#!/bin/sh
printf 'root-proxy:%s\n' "$*" >> "$ORDER_LOG"
[ "${MOCK_PROXY_FAIL:-0}" = 0 ]
PROXY
cat > "$MOD/scripts/yulong-app-firewall.sh" <<'FIREWALL'
#!/bin/sh
printf 'firewall:%s\n' "$*" >> "$ORDER_LOG"
FIREWALL
chmod 0755 "$MOD/scripts/"*.sh

# Successful uninstall must stop the Root Proxy before touching firewall rules.
ORDER_LOG="$LOG" PG="$PG" MODDIR="$MOD" sh "$MOD/uninstall.sh" > "$T/success.out" 2>&1 || fail "successful Root Proxy shutdown blocked uninstall"
[ "$(sed -n '1p' "$LOG")" = 'root-proxy:uninstall' ] || fail "Root Proxy was not stopped first"
[ "$(sed -n '2p' "$LOG")" = 'firewall:uninstall' ] || fail "firewall teardown did not follow Root Proxy shutdown"

# An unconfirmed cleanup must abort before firewall teardown and preserve state.
: > "$LOG"
: > "$PG/yulong-root-proxy-active"
if ORDER_LOG="$LOG" MOCK_PROXY_FAIL=1 PG="$PG" MODDIR="$MOD" sh "$MOD/uninstall.sh" > "$T/failure.out" 2>&1; then
  fail "uninstall continued after Root Proxy cleanup failure"
fi
[ "$(cat "$LOG")" = 'root-proxy:uninstall' ] || fail "firewall teardown ran after failed Root Proxy cleanup"
grep -Fq 'preserving state and aborting uninstall' "$T/failure.out" || fail "cleanup failure was not reported"
[ -f "$PG/yulong-root-proxy-active" ] || fail "Root Proxy state marker was removed after failed cleanup"

# Missing helper plus residual FX-owned state must also fail closed.
rm -f "$MOD/scripts/yulong-root-proxy.sh"
: > "$LOG"
if ORDER_LOG="$LOG" PG="$PG" MODDIR="$MOD" sh "$MOD/uninstall.sh" > "$T/missing.out" 2>&1; then
  fail "uninstall accepted residual Root Proxy state without its helper"
fi
[ ! -s "$LOG" ] || fail "firewall teardown ran with missing Root Proxy helper"
grep -Fq 'cleanup helper is missing' "$T/missing.out" || fail "missing helper refusal was not reported"
[ -f "$PG/yulong-root-proxy-active" ] || fail "residual Root Proxy marker was not preserved"

echo "PASS: FX uninstall stops Root Proxy before firewall teardown and fails closed on cleanup errors or missing helper"
