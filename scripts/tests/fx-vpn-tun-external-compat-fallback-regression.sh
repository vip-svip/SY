#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MODULE=${1:-"$ROOT/fx-module"}
PATCHER="$ROOT/fx-patches/patch_vpn_tun_external_fallback.py"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fx-vpn-tun-fallback.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM
fail(){ echo "FAIL: $*" >&2; exit 1; }

[ -f "$PATCHER" ] || fail "effective-mode patcher missing"
for f in vpncore.sh apply.sh status.sh; do
  [ -s "$MODULE/scripts/$f" ] || fail "restored module source missing: $f"
done
mkdir -p "$TMP/module/scripts"
cp "$MODULE/scripts/vpncore.sh" "$MODULE/scripts/apply.sh" "$MODULE/scripts/status.sh" "$TMP/module/scripts/"

# The production pipeline applies the patch once; applying it again must be safe.
python3 "$PATCHER" "$TMP/module" >/dev/null
python3 "$PATCHER" "$TMP/module" >/dev/null
for f in vpncore.sh apply.sh status.sh; do
  sh -n "$TMP/module/scripts/$f" || fail "shell syntax failed after patch: $f"
done

sed -n '/^fx_select_vpn_effective_mode() {/,/^}/p' "$TMP/module/scripts/apply.sh" > "$TMP/select.sh"
[ -s "$TMP/select.sh" ] || fail "mode selector function missing"
assert_mode(){
  expected=$1; shift
  actual=$(sh -c '. "$1"; fx_select_vpn_effective_mode "$2" "$3" "$4" "$5" "$6" "$7" "$8"' sh "$TMP/select.sh" "$@")
  [ "$actual" = "$expected" ] || fail "expected $expected, got $actual for args: $*"
}
# Explicit compatibility + known interface + known UID + verified route -> root REDIRECT.
assert_mode redirect tun 1 tun0 0 10234 1 1
# Any uncertain or incomplete external-VPN ownership proof fails closed.
assert_mode direct tun 1 tun0 1 10234 1 1
assert_mode direct tun 1 tun0 0 "" 1 1
assert_mode direct tun 1 tun0 0 10234 0 1
assert_mode direct tun 1 tun0 0 10234 1 0
# Without an outer VPN, retain the requested root TUN mode.
assert_mode tun tun 0 "" 0 "" 1 0
# An explicitly requested REDIRECT mode is not rewritten.
assert_mode redirect redirect 1 tun0 0 10234 1 1

sed -n '/^vpncore_effective_mode() {/,/^}/p' "$TMP/module/scripts/vpncore.sh" > "$TMP/core-mode.sh"
[ -s "$TMP/core-mode.sh" ] || fail "vpncore effective-mode helper missing"
sh -c 'pg_get(){ printf "tun\n"; }; . "$1"; PG_VPN_MODE_OVERRIDE=redirect; [ "$(vpncore_effective_mode)" = redirect ]; unset PG_VPN_MODE_OVERRIDE; [ "$(vpncore_effective_mode)" = tun ]' sh "$TMP/core-mode.sh" || fail "vpncore ignored runtime mode override"

grep -Fq '"vpn_effective_mode":"%s"' "$TMP/module/scripts/status.sh" || fail "status JSON lacks effective mode"
grep -Fq '"vpn_mode_fallback_reason":"%s"' "$TMP/module/scripts/status.sh" || fail "status JSON lacks fallback reason"
grep -Fq 'PG_VPN_MODE_OVERRIDE=$VPN_MODE' "$TMP/module/scripts/apply.sh" || fail "apply did not pass runtime mode override"
grep -Fq 'bind_interface' "$TMP/module/scripts/vpncore.sh" || fail "external VPN bind-interface path missing"
echo "PASS: TUN stays independent without an outer VPN; verified outer VPN uses root REDIRECT; uncertain states fail closed; effective mode is reported."
