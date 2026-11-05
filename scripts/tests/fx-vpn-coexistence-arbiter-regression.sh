#!/system/bin/sh
# Regression for the FX VPN coexistence arbiter.
#
# Contract (docs/FX_1.0.0_PRODUCT_RESTRUCTURE_AND_AI_HANDOFF.md):
#   - the Root kernel dataplane must never occupy the Android VPN slot;
#   - a third-party VPN holding the slot must NOT make FX abort, it must be graded
#     as 完全并行 / 受支持链式 / 部分兼容 / 不兼容 from real observed state;
#   - local DNS/proxy ports must be checked for conflicts, and unreadable state
#     must never be reported as "no conflict".
#
# Usage: sh fx-vpn-coexistence-arbiter-regression.sh [path-to-arbiter]
set -u

ROOT=$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)
ARB=${1:-}
[ -n "$ARB" ] || ARB="$ROOT/scripts/fx-vpn-coexistence-arbiter.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "  ok: $*"; }

[ -s "$ARB" ] || fail "arbiter missing at $ARB"
sh -n "$ARB" || fail "arbiter does not parse"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/fx-arb.XXXXXX") || fail "cannot create temp dir"
trap 'rm -rf "$TMP"' EXIT INT TERM

HDR='  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode'

# net_free: nothing listening
mkdir -p "$TMP/net_free"
for f in tcp tcp6 udp udp6; do printf '%s\n' "$HDR" > "$TMP/net_free/$f"; done

# net_dns_busy: port 5353 (0x14E9) in LISTEN (0A)
mkdir -p "$TMP/net_dns_busy"
printf '%s\n   0: 0100007F:14E9 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 1 1\n' \
  "$HDR" > "$TMP/net_dns_busy/tcp"
for f in tcp6 udp udp6; do printf '%s\n' "$HDR" > "$TMP/net_dns_busy/$f"; done

# net_udp_busy: port 5353 (0x14E9) bound by UDP (Linux /proc/net/udp state 07)
mkdir -p "$TMP/net_udp_busy"
for f in tcp tcp6 udp6; do printf '%s\n' "$HDR" > "$TMP/net_udp_busy/$f"; done
printf '%s\n   0: 0100007F:14E9 00000000:0000 07 00000000:00000000 00:00000000 00000000  1000        0 2 1\n' \
  "$HDR" > "$TMP/net_udp_busy/udp"

# net_partial: TCP and UDP6 readable, but UDP4 inventory missing.
mkdir -p "$TMP/net_partial"
for f in tcp tcp6 udp6; do printf '%s\\n' "$HDR" > "$TMP/net_partial/$f"; done

# run_arb <link-output> <vpinfo> <procnet> <modroot> [extra env...]
# prints "<exit>|<json>"
run_arb() {
  _links=$1; _info=$2; _net=$3; _mod=$4
  printf '%s\n' "$_links" > "$TMP/links.txt"
  if [ -n "$_info" ]; then printf '%s\n' "$_info" > "$TMP/info.txt"; else : > "$TMP/info.txt"; fi
  _out=$(
    FX_ARB_LINK_CMD="cat '$TMP/links.txt'" \
    FX_ARB_VPNINFO_CMD="cat '$TMP/info.txt'" \
    FX_ARB_PROC_NET_DIR="$_net" \
    FX_ARB_MODULE_ROOT="$_mod" \
    sh "$ARB" 2>&1
  )
  _rc=$?
  printf '%s|%s' "$_rc" "$_out"
}

json_ok() {
  printf '%s' "$1" | python3 -c "
import sys,json
try:
    d=json.loads(sys.stdin.read())
except Exception as e:
    print('BADJSON', e); sys.exit(1)
print('OK')
" 2>/dev/null
}

field() {
  printf '%s' "$1" | python3 -c "
import sys,json
d=json.loads(sys.stdin.read())
print(d$2)
" 2>/dev/null
}

LINKS_NO_TUN='1: lo: <LOOPBACK,UP> mtu 65536
2: wlan0: <BROADCAST,UP> mtu 1500'
LINKS_TUN='1: lo: <LOOPBACK,UP> mtu 65536
2: wlan0: <BROADCAST,UP> mtu 1500
7: tun0: <POINTOPOINT,UP> mtu 1500'

mkdir -p "$TMP/mod_clean/scripts"

echo "== case 1: no external VPN, ports free -> kernel_only, slot not used =="
r=$(run_arb "$LINKS_NO_TUN" "" "$TMP/net_free" "$TMP/mod_clean")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 0 ] || fail "expected rc=0, got $rc: $out"
[ "$(json_ok "$out")" = "OK" ] || fail "invalid JSON: $out"
[ "$(field "$out" "['verdict']")" = "kernel_only" ] || fail "expected kernel_only, got $(field "$out" "['verdict']")"
[ "$(field "$out" "['vpn_service_slot_used']")" = "False" ] || fail "slot must not be used"
[ "$(field "$out" "['dataplane']")" = "kernel" ] || fail "dataplane must be kernel"
pass "kernel_only, slot free"

echo "== case 2: external VPN with owner uid -> full_parallel =="
r=$(run_arb "$LINKS_TUN" "tun0|10123" "$TMP/net_free" "$TMP/mod_clean")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 0 ] || fail "expected rc=0, got $rc: $out"
[ "$(field "$out" "['verdict']")" = "full_parallel" ] || fail "expected full_parallel, got $(field "$out" "['verdict']")"
[ "$(field "$out" "['external_if']")" = "tun0" ] || fail "external_if mismatch"
[ "$(field "$out" "['external_uid']")" = "10123" ] || fail "external_uid mismatch"
pass "full_parallel with owner uid"

echo "== case 3: external VPN without owner uid -> chained =="
r=$(run_arb "$LINKS_TUN" "tun0|" "$TMP/net_free" "$TMP/mod_clean")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 0 ] || fail "expected rc=0, got $rc: $out"
[ "$(field "$out" "['verdict']")" = "chained" ] || fail "expected chained, got $(field "$out" "['verdict']")"
pass "chained when uid unavailable"

echo "== case 4: external VPN + local DNS port occupied -> partial =="
r=$(run_arb "$LINKS_TUN" "tun0|10123" "$TMP/net_dns_busy" "$TMP/mod_clean")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 0 ] || fail "expected rc=0, got $rc: $out"
[ "$(field "$out" "['verdict']")" = "partial" ] || fail "expected partial, got $(field "$out" "['verdict']")"
[ "$(field "$out" "['dns']['owner']")" = "other" ] || fail "dns owner must be other"
pass "partial on port conflict"

echo "== case 4b: external VPN + UDP DNS port bound -> partial =="
r=$(run_arb "$LINKS_TUN" "tun0|10123" "$TMP/net_udp_busy" "$TMP/mod_clean")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 0 ] || fail "expected rc=0, got $rc: $out"
[ "$(field "$out" "['verdict']")" = "partial" ] || fail "UDP DNS bind was incorrectly reported free: $out"
[ "$(field "$out" "['dns']['owner']")" = "other" ] || fail "UDP DNS owner must be other"
pass "partial on UDP port conflict"

echo "== case 5: link inventory unavailable -> unknown, fail-safe rc=2 =="
r=$(run_arb "" "" "$TMP/net_free" "$TMP/mod_clean")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 2 ] || fail "expected rc=2 for unavailable probe, got $rc: $out"
[ "$(field "$out" "['verdict']")" = "unknown" ] || fail "expected unknown, got $(field "$out" "['verdict']")"
pass "unavailable probe refuses to claim coexistence"

echo "== case 6: tunnel iface present but no VpnInfo -> unknown (never guess) =="
r=$(run_arb "$LINKS_TUN" "" "$TMP/net_free" "$TMP/mod_clean")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 2 ] || fail "expected rc=2 for ambiguous probe, got $rc: $out"
[ "$(field "$out" "['verdict']")" = "unknown" ] || fail "expected unknown, got $(field "$out" "['verdict']")"
[ "$(field "$out" "['probe']")" = "ambiguous" ] || fail "probe must be ambiguous"
pass "ambiguous tunnel never treated as a known outer VPN"

echo "== case 7: VpnInfo names an interface that is not present -> unknown =="
r=$(run_arb "$LINKS_NO_TUN" "tun9|10123" "$TMP/net_free" "$TMP/mod_clean")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 2 ] || fail "expected rc=2, got $rc: $out"
[ "$(field "$out" "['verdict']")" = "unknown" ] || fail "expected unknown, got $(field "$out" "['verdict']")"
pass "stale VpnInfo row rejected"

echo "== case 8: root dataplane calls VpnService -> incompatible rc=3 =="
mkdir -p "$TMP/mod_bad/scripts"
cat > "$TMP/mod_bad/scripts/apply.sh" <<'EOF'
#!/system/bin/sh
VpnService.Builder().setSession("fx").establish()
EOF
r=$(run_arb "$LINKS_NO_TUN" "" "$TMP/net_free" "$TMP/mod_bad")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 3 ] || fail "expected rc=3, got $rc: $out"
[ "$(field "$out" "['verdict']")" = "incompatible" ] || fail "expected incompatible, got $(field "$out" "['verdict']")"
[ "$(field "$out" "['vpn_service_slot_used']")" = "True" ] || fail "slot must be flagged as used"
pass "slot-occupying dataplane rejected"

echo "== case 9: unreadable port state -> never claimed as free =="
mkdir -p "$TMP/net_missing"
r=$(run_arb "$LINKS_NO_TUN" "" "$TMP/net_missing" "$TMP/mod_clean")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 0 ] || fail "expected rc=0, got $rc: $out"
[ "$(field "$out" "['verdict']")" = "partial" ] || fail "expected partial when port state unreadable, got $(field "$out" "['verdict']")"
[ "$(field "$out" "['dns']['owner']")" = "unknown" ] || fail "dns owner must be unknown"
pass "unreadable proc/net does not masquerade as free"

echo "== case 9b: partial proc/net inventory -> unknown port ownership =="
r=$(run_arb "$LINKS_TUN" "tun0|10123" "$TMP/net_partial" "$TMP/mod_clean")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 0 ] || fail "expected rc=0, got $rc: $out"
[ "$(field "$out" "['verdict']")" = "partial" ] || fail "partial proc/net inventory was incorrectly trusted: $out"
[ "$(field "$out" "['dns']['owner']")" = "unknown" ] || fail "missing UDP table must make port ownership unknown"
pass "partial proc/net inventory fails closed"

echo "== case 10: arbiter is read-only (no netfilter/route mutation) =="
# Only executable lines count: the header documents the intent using these very
# words, so comments must be stripped before the assertion runs.
ARB_CODE=$(sed 's/#.*//' "$ARB")
if printf '%s\n' "$ARB_CODE" | grep -Eq '(^|[[:space:]])(iptables|ip6tables|nft|etables)([[:space:]]|$)|ip[[:space:]]+(rule|route)[[:space:]]+(add|del|flush)|(^|[[:space:]])tc[[:space:]]+qdisc'; then
  fail "arbiter must not mutate netfilter/ip rules/routes"
fi
pass "arbiter observes only"

echo "== case 11: --text mode renders the same verdict =="
printf '%s\n' "$LINKS_TUN" > "$TMP/links.txt"; printf 'tun0|10123\n' > "$TMP/info.txt"
tout=$(FX_ARB_LINK_CMD="cat '$TMP/links.txt'" FX_ARB_VPNINFO_CMD="cat '$TMP/info.txt'" \
       FX_ARB_PROC_NET_DIR="$TMP/net_free" FX_ARB_MODULE_ROOT="$TMP/mod_clean" \
       sh "$ARB" --text 2>&1)
rc=$?
[ "$rc" -eq 0 ] || fail "--text expected rc=0, got $rc: $tout"
case "$tout" in *"full_parallel"*) ;; *) fail "--text did not render verdict: $tout" ;; esac
pass "--text mode consistent"

echo "PASS: coexistence arbiter grades all levels, fails safe, and never mutates network state"
