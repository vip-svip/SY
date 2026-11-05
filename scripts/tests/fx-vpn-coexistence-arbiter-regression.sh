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

# net_tcp6_busy: upstream DNS port 5353 is bound on IPv6 TCP.
mkdir -p "$TMP/net_tcp6_busy"
for f in tcp tcp6 udp udp6; do printf '%s\n' "$HDR" > "$TMP/net_tcp6_busy/$f"; done
printf '%s\n   0: 00000000000000000000000001000000:14E9 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 5 1\n' "$HDR" > "$TMP/net_tcp6_busy/tcp6"

# net_udp6_busy: upstream DNS port 5353 is bound on IPv6 UDP.
mkdir -p "$TMP/net_udp6_busy"
for f in tcp tcp6 udp udp6; do printf '%s\n' "$HDR" > "$TMP/net_udp6_busy/$f"; done
printf '%s\n   0: 00000000000000000000000001000000:14E9 00000000000000000000000000000000:0000 07 00000000:00000000 00:00000000 00000000  1000        0 6 1\n' "$HDR" > "$TMP/net_udp6_busy/udp6"

# net_filter_dns_busy: AdGuard Home's client-facing DNS port 53 is occupied by TCP.
mkdir -p "$TMP/net_filter_dns_busy"
for f in tcp6 udp udp6; do printf '%s\n' "$HDR" > "$TMP/net_filter_dns_busy/$f"; done
printf '%s\n   0: 0100007F:0035 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 3 1\n' \
  "$HDR" > "$TMP/net_filter_dns_busy/tcp"

# net_filter_dns_udp_busy: port 53 is occupied by UDP.
mkdir -p "$TMP/net_filter_dns_udp_busy"
for f in tcp tcp6 udp6; do printf '%s\n' "$HDR" > "$TMP/net_filter_dns_udp_busy/$f"; done
printf '%s\n   0: 0100007F:0035 00000000:0000 07 00000000:00000000 00:00000000 00000000  1000        0 4 1\n' \
  "$HDR" > "$TMP/net_filter_dns_udp_busy/udp"

# net_partial: TCP and UDP6 readable, but UDP4 inventory missing.
mkdir -p "$TMP/net_partial"
for f in tcp tcp6 udp6; do printf '%s\n' "$HDR" > "$TMP/net_partial/$f"; done

# run_arb <link-output> <vpinfo> <procnet> <modroot> [extra env...]
# prints "<exit>|<json>"
run_arb() {
  _links=$1; _info=$2; _net=$3; _mod=$4
  printf '%s\n' "$_links" > "$TMP/links.txt"
  if [ -n "$_info" ]; then printf '%s\n' "$_info" > "$TMP/info.txt"; else : > "$TMP/info.txt"; fi
  _out=$(
    FX_ARB_LINK_FILE="$TMP/links.txt" \
    FX_ARB_VPNINFO_FILE="$TMP/info.txt" \
    FX_ARB_PROC_NET_DIR="$_net" \
    FX_ARB_MODULE_ROOT="$_mod" \
    sh "$ARB" 2>&1
  )
  _rc=$?
  printf '%s|%s' "$_rc" "$_out"
}

# run_arb_port <DNS|FILTER_DNS|PROXY> <port> -> "<exit>|<json>"
run_arb_port() {
  _kind=$1; _port=$2
  _out=$(env "FX_ARB_${_kind}_PORT=$_port" \
    FX_ARB_LINK_FILE="$TMP/links.txt" \
    FX_ARB_VPNINFO_FILE="$TMP/info.txt" \
    FX_ARB_PROC_NET_DIR="$TMP/net_free" \
    FX_ARB_MODULE_ROOT="$TMP/mod_clean" \
    sh "$ARB" 2>&1)
  _rc=$?
  printf '%s|%s' "$_rc" "$_out"
}

run_arb_config() {
  _dns=$1; _filter=$2; _proxy=$3
  _out=$(env "FX_ARB_DNS_PORT=$_dns" "FX_ARB_FILTER_DNS_PORT=$_filter" "FX_ARB_PROXY_PORT=$_proxy" \
    FX_ARB_LINK_FILE="$TMP/links.txt" FX_ARB_VPNINFO_FILE="$TMP/info.txt" \
    FX_ARB_PROC_NET_DIR="$TMP/net_free" FX_ARB_MODULE_ROOT="$TMP/mod_clean" \
    sh "$ARB" 2>&1)
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
printf 'id=privacyguard\nversion=1.0.0\n' > "$TMP/mod_clean/module.prop"
for f in apply.sh vpncore.sh yulong-root-proxy.sh yulong-vpn-control.sh; do
  printf '#!/system/bin/sh\nexit 0\n' > "$TMP/mod_clean/scripts/$f"
done

# A partial module tree is not evidence that FX avoids the Android VPN slot.
mkdir -p "$TMP/mod_incomplete/scripts"
echo "== case 0: incomplete module source -> unknown slot state =="
r=$(run_arb "$LINKS_NO_TUN" "" "$TMP/net_free" "$TMP/mod_incomplete")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 2 ] || fail "incomplete module scan must return rc=2, got $rc: $out"
[ "$(field "$out" "['verdict']")" = "unknown" ] || fail "incomplete module scan must grade unknown"
[ "$(field "$out" "['vpn_service_slot_used']")" = "None" ] || fail "incomplete module slot must be JSON null"
pass "incomplete module source fails closed"

# The production default derives the module root from scripts/<arbiter> path.
cp "$ARB" "$TMP/mod_clean/scripts/fx-vpn-coexistence-arbiter.sh"
printf '%s\n' "$LINKS_NO_TUN" > "$TMP/auto-links.txt"
: > "$TMP/auto-info.txt"
_auto_out=$(FX_ARB_LINK_FILE="$TMP/auto-links.txt" \
  FX_ARB_VPNINFO_FILE="$TMP/auto-info.txt" FX_ARB_PROC_NET_DIR="$TMP/net_free" FX_ARB_MODULE_ROOT= \
  sh "$TMP/mod_clean/scripts/fx-vpn-coexistence-arbiter.sh")
[ "$(field "$_auto_out" "['vpn_service_slot_used']")" = "False" ] || fail "arbiter did not verify slot status from its installed module path"
pass "production arbiter auto-discovers its module root"

# Legacy command-valued environment variables are ignored; test injection is data-only.
_injection_marker="$TMP/arbiter-command-must-not-run"
FX_ARB_LINK_CMD="touch '$_injection_marker'" FX_ARB_VPNINFO_CMD="touch '$_injection_marker'" \
  FX_ARB_LINK_FILE="$TMP/links.txt" FX_ARB_VPNINFO_FILE="$TMP/info.txt" \
  FX_ARB_PROC_NET_DIR="$TMP/net_free" FX_ARB_MODULE_ROOT="$TMP/mod_clean" sh "$ARB" >/dev/null 2>&1 || :
[ ! -e "$_injection_marker" ] || fail "arbiter executed a command from environment input"
pass "legacy command environment injection is never executed"

echo "== case 1: no external VPN, ports free -> kernel_only, slot not used =="
r=$(run_arb "$LINKS_NO_TUN" "" "$TMP/net_free" "$TMP/mod_clean")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 0 ] || fail "expected rc=0, got $rc: $out"
[ "$(json_ok "$out")" = "OK" ] || fail "invalid JSON: $out"
[ "$(field "$out" "['verdict']")" = "kernel_only" ] || fail "expected kernel_only, got $(field "$out" "['verdict']")"
[ "$(field "$out" "['vpn_service_slot_used']")" = "False" ] || fail "slot must not be used"
[ "$(field "$out" "['dataplane']")" = "kernel" ] || fail "dataplane must be kernel"
[ "$(field "$out" "['dns_filter']['port']")" = "53" ] || fail "client-facing DNS filter port must default to 53"
[ "$(field "$out" "['dns_filter']['owner']")" = "free" ] || fail "DNS filter port 53 should be free in the clean fixture"
pass "kernel_only, slot free, both DNS ports observed"

echo "== case 1b: leading-zero port is normalized as decimal JSON number =="
r=$(run_arb_port FILTER_DNS 00053)
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 0 ] || fail "normalized port unexpectedly failed: $out"
[ "$(json_ok "$out")" = "OK" ] || fail "leading-zero port produced invalid JSON: $out"
[ "$(field "$out" "['dns_filter']['port']")" = "53" ] || fail "leading-zero port was not normalized to decimal 53"
[ "$(field "$out" "['dns_filter']['owner']")" = "free" ] || fail "normalized port did not use port 53 inventory"
pass "leading-zero port normalized safely"

echo "== case 1c: malformed port cannot inject JSON fields =="
r=$(run_arb_port FILTER_DNS '53,"injected":true')
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 0 ] || fail "invalid port should degrade safely, got rc=$rc: $out"
[ "$(json_ok "$out")" = "OK" ] || fail "invalid port corrupted JSON: $out"
[ "$(field "$out" "['dns_filter']['port']")" = "None" ] || fail "invalid port must serialize as JSON null"
[ "$(field "$out" "['dns_filter']['owner']")" = "unknown" ] || fail "invalid port must have unknown ownership"
[ "$(field "$out" "['verdict']")" = "partial" ] || fail "invalid port must prevent a clean compatibility grade"
pass "malformed port rejected and JSON remains valid"

echo "== case 1d: upstream DNS and proxy ports also normalize as decimal =="
r=$(run_arb_port DNS 005353)
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 0 ] || fail "upstream DNS normalization failed: $out"
[ "$(field "$out" "['dns']['port']")" = "5353" ] || fail "upstream DNS leading zero was not normalized"
[ "$(field "$out" "['dns']['owner']")" = "free" ] || fail "normalized upstream DNS port was not probed"
r=$(run_arb_port PROXY 07890)
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 0 ] || fail "proxy normalization failed: $out"
[ "$(field "$out" "['proxy']['port']")" = "7890" ] || fail "proxy leading zero was not normalized"
[ "$(field "$out" "['proxy']['owner']")" = "free" ] || fail "normalized proxy port was not probed"
pass "all three arbiter port fields normalize decimal values"

echo "== case 1e: out-of-range ports fail closed for every service field =="
for spec in "DNS:65536" "PROXY:00000"; do
  kind=${spec%%:*}; port=${spec#*:}
  r=$(run_arb_port "$kind" "$port")
  rc=${r%%|*}; out=${r#*|}
  [ "$rc" -eq 0 ] || fail "$kind invalid port should degrade safely: $out"
  case "$kind" in DNS) object=dns ;; PROXY) object=proxy ;; esac
  [ "$(field "$out" "['$object']['port']")" = "None" ] || fail "$kind invalid port must serialize as JSON null"
  [ "$(field "$out" "['$object']['owner']")" = "unknown" ] || fail "$kind invalid port ownership must be unknown"
  [ "$(field "$out" "['verdict']")" = "partial" ] || fail "$kind invalid port must prevent a clean compatibility grade"
done
pass "out-of-range and zero ports fail closed"

echo "== case 1f: duplicate FX service ports are reported as an internal conflict =="
r=$(run_arb "$LINKS_NO_TUN" "" "$TMP/net_free" "$TMP/mod_clean")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 0 ] || fail "could not seed duplicate-port fixture: $out"
r=$(run_arb_config 5353 05353 7890)
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 0 ] || fail "duplicate FX port should degrade safely, got rc=$rc: $out"
[ "$(field "$out" "['verdict']")" = "partial" ] || fail "duplicate FX listeners were reported compatible: $out"
[ "$(field "$out" "['config_conflicts']")" = "dns=dns_filter" ] || fail "normalized duplicate listener pair missing: $out"
pass "duplicate internal listeners fail to partial even when host ports are free"

echo "== case 1g: all pairwise duplicate listener combinations are detected =="
for spec in "5353:7890:7890:dns=proxy" "5353:53:5353:dns=proxy" "53:53:53:dns=dns_filter,dns=proxy,dns_filter=proxy"; do
  dns=${spec%%:*}; rest=${spec#*:}; filter=${rest%%:*}; rest=${rest#*:}; proxy=${rest%%:*}; expected=${rest#*:}
  r=$(run_arb_config "$dns" "$filter" "$proxy"); rc=${r%%|*}; out=${r#*|}
  [ "$rc" -eq 0 ] || fail "pairwise duplicate port check failed: $out"
  [ "$(field "$out" "['config_conflicts']")" = "$expected" ] || fail "expected collision '$expected', got $out"
done
pass "all three service-port collision pairs are enumerated"

echo "== case 2: external VPN owner uid alone cannot prove parallel routing =="
r=$(run_arb "$LINKS_TUN" "tun0|10123" "$TMP/net_free" "$TMP/mod_clean")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 0 ] || fail "expected rc=0, got $rc: $out"
[ "$(field "$out" "['verdict']")" = "partial" ] || fail "owner UID alone must not certify full_parallel: $(field "$out" "['verdict']")"
[ "$(field "$out" "['route_probe']")" = "unverified" ] || fail "route probe must remain unverified"
[ "$(field "$out" "['external_if']")" = "tun0" ] || fail "external_if mismatch"
[ "$(field "$out" "['external_uid']")" = "10123" ] || fail "external_uid mismatch"
pass "owner UID is observed without overstating data-plane proof"

echo "== case 3: external VPN without owner uid cannot prove chain binding =="
r=$(run_arb "$LINKS_TUN" "tun0|" "$TMP/net_free" "$TMP/mod_clean")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 0 ] || fail "expected rc=0, got $rc: $out"
[ "$(field "$out" "['verdict']")" = "partial" ] || fail "missing owner UID must not certify chained routing: $(field "$out" "['verdict']")"
pass "outer-tunnel binding remains unverified"

echo "== case 3b: multiple injected VPN ownership rows are ambiguous =="
r=$(run_arb "$LINKS_TUN" "$(printf '%s\\n' 'tun0|10123' 'tun0|10124')" "$TMP/net_free" "$TMP/mod_clean")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 2 ] || fail "multiple injected ownership rows must return rc=2, got $rc: $out"
[ "$(field "$out" "['verdict']")" = "unknown" ] || fail "multiple injected rows must be unknown: $out"
[ "$(field "$out" "['probe']")" = "ambiguous" ] || fail "multiple injected rows must be marked ambiguous"
pass "multiple injected ownership rows fail closed"

echo "== case 3c: malformed injected VPN owner UID is ambiguous =="
r=$(run_arb "$LINKS_TUN" "tun0|10123x" "$TMP/net_free" "$TMP/mod_clean")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 2 ] || fail "malformed injected owner UID must return rc=2, got $rc: $out"
[ "$(field "$out" "['probe']")" = "ambiguous" ] || fail "malformed injected owner UID was accepted: $out"
pass "malformed injected ownership record fails closed"

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
pass "partial on UDP upstream port conflict"

echo "== case 4e: IPv6 TCP upstream DNS listener is a port conflict =="
r=$(run_arb "$LINKS_TUN" "tun0|10123" "$TMP/net_tcp6_busy" "$TMP/mod_clean")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 0 ] || fail "expected rc=0, got $rc: $out"
[ "$(field "$out" "['dns']['owner']")" = "other" ] || fail "IPv6 TCP/5353 conflict was missed: $out"
pass "IPv6 TCP listener prevents false-free upstream DNS status"

echo "== case 4f: IPv6 UDP upstream DNS bind is a port conflict =="
r=$(run_arb "$LINKS_TUN" "tun0|10123" "$TMP/net_udp6_busy" "$TMP/mod_clean")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 0 ] || fail "expected rc=0, got $rc: $out"
[ "$(field "$out" "['dns']['owner']")" = "other" ] || fail "IPv6 UDP/5353 conflict was missed: $out"
pass "IPv6 UDP bind prevents false-free upstream DNS status"

echo "== case 4c: external VPN + AdGuard TCP/53 occupied -> partial =="
r=$(run_arb "$LINKS_TUN" "tun0|10123" "$TMP/net_filter_dns_busy" "$TMP/mod_clean")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 0 ] || fail "expected rc=0, got $rc: $out"
[ "$(field "$out" "['verdict']")" = "partial" ] || fail "port 53 TCP conflict must degrade coexistence: $out"
[ "$(field "$out" "['dns_filter']['port']")" = "53" ] || fail "DNS filter port mismatch"
[ "$(field "$out" "['dns_filter']['owner']")" = "other" ] || fail "AdGuard TCP/53 conflict was missed"
pass "partial on client-facing DNS TCP/53 conflict"

echo "== case 4d: external VPN + AdGuard UDP/53 occupied -> partial =="
r=$(run_arb "$LINKS_TUN" "tun0|10123" "$TMP/net_filter_dns_udp_busy" "$TMP/mod_clean")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 0 ] || fail "expected rc=0, got $rc: $out"
[ "$(field "$out" "['verdict']")" = "partial" ] || fail "port 53 UDP conflict must degrade coexistence: $out"
[ "$(field "$out" "['dns_filter']['owner']")" = "other" ] || fail "AdGuard UDP/53 conflict was missed"
pass "partial on client-facing DNS UDP/53 conflict"

echo "== case 5: link inventory unavailable -> unknown, fail-safe rc=2 =="
r=$(run_arb "" "" "$TMP/net_free" "$TMP/mod_clean")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 2 ] || fail "expected rc=2 for unavailable probe, got $rc: $out"
[ "$(field "$out" "['verdict']")" = "unknown" ] || fail "expected unknown, got $(field "$out" "['verdict']")"
pass "unavailable probe refuses to claim coexistence"

echo "== case 5b: partial stdout from failed ip command -> unknown =="
mkdir -p "$TMP/fakebin"
cat > "$TMP/fakebin/ip" <<'EOF'
#!/bin/sh
printf '%s\n' '1: lo: <LOOPBACK,UP> mtu 65536'
exit 7
EOF
chmod 0755 "$TMP/fakebin/ip"
: > "$TMP/info.txt"
_out=$(PATH="$TMP/fakebin:$PATH" FX_ARB_VPNINFO_FILE="$TMP/info.txt" \
  FX_ARB_LINK_FILE= FX_ARB_PROC_NET_DIR="$TMP/net_free" FX_ARB_MODULE_ROOT="$TMP/mod_clean" \
  sh "$ARB" 2>&1)
rc=$?
[ "$rc" -eq 2 ] || fail "failed ip command with partial stdout must return rc=2, got $rc: $_out"
[ "$(field "$_out" "['verdict']")" = "unknown" ] || fail "partial ip stdout was trusted: $_out"
[ "$(field "$_out" "['probe']")" = "unavailable" ] || fail "failed ip command must mark probe unavailable"
pass "nonzero ip exit discards partial interface inventory"

echo "== case 5c: production path reads Android VpnInfo from dumpsys =="
cat > "$TMP/fakebin/dumpsys" <<'EOF'
#!/bin/sh
[ "$1" = "connectivity" ] || exit 2
cat <<'DUMP'
ConnectivityService:
  mVpns:
    VpnInfo{ownerUid=10123 vpnIface=tun0 primaryUnderlyingIface=wlan0}
DUMP
EOF
chmod 0755 "$TMP/fakebin/dumpsys"
printf '%s\n' "$LINKS_TUN" > "$TMP/links.txt"
_out=$(PATH="$TMP/fakebin:$PATH" FX_ARB_LINK_FILE="$TMP/links.txt" FX_ARB_VPNINFO_FILE= \
  FX_ARB_PROC_NET_DIR="$TMP/net_free" FX_ARB_MODULE_ROOT="$TMP/mod_clean" sh "$ARB" 2>&1)
rc=$?
[ "$rc" -eq 0 ] || fail "production VpnInfo probe failed: $_out"
[ "$(field "$_out" "['external_if']")" = "tun0" ] || fail "dumpsys interface not recognized"
[ "$(field "$_out" "['external_uid']")" = "10123" ] || fail "dumpsys owner UID not recognized"
pass "production Android VpnInfo probe returns interface and owner UID"

echo "== case 5d: successful dumpsys with no active VPN is a clean empty result =="
cat > "$TMP/fakebin/dumpsys" <<'EOF'
#!/bin/sh
printf '%s\n' 'ConnectivityService:' '  mVpns:'
EOF
printf '%s\n' "$LINKS_NO_TUN" > "$TMP/links.txt"
_out=$(PATH="$TMP/fakebin:$PATH" FX_ARB_LINK_FILE="$TMP/links.txt" FX_ARB_VPNINFO_FILE= \
  FX_ARB_PROC_NET_DIR="$TMP/net_free" FX_ARB_MODULE_ROOT="$TMP/mod_clean" sh "$ARB" 2>&1)
rc=$?
[ "$rc" -eq 0 ] || fail "confirmed empty VpnInfo section should be valid: $_out"
[ "$(field "$_out" "['verdict']")" = "kernel_only" ] || fail "empty VpnInfo section did not identify no external VPN"
pass "confirmed no-VPN state is distinct from probe failure"

echo "== case 5e: unavailable Android VpnInfo provider is unknown, never kernel-only =="
cat > "$TMP/fakebin/dumpsys" <<'EOF'
#!/bin/sh
exit 7
EOF
_out=$(PATH="$TMP/fakebin:$PATH" FX_ARB_LINK_FILE="$TMP/links.txt" FX_ARB_VPNINFO_FILE= \
  FX_ARB_PROC_NET_DIR="$TMP/net_free" FX_ARB_MODULE_ROOT="$TMP/mod_clean" sh "$ARB" 2>&1)
rc=$?
[ "$rc" -eq 2 ] || fail "failed dumpsys must return rc=2, got $rc: $_out"
[ "$(field "$_out" "['verdict']")" = "unknown" ] || fail "failed dumpsys was treated as no VPN"
[ "$(field "$_out" "['probe']")" = "unavailable" ] || fail "failed dumpsys probe status mismatch"
pass "failed Android VPN probe fails closed"

echo "== case 5f: multiple VpnInfo rows are ambiguous =="
cat > "$TMP/fakebin/dumpsys" <<'EOF'
#!/bin/sh
printf '%s\n' 'mVpns:' 'VpnInfo{ownerUid=10123 vpnIface=tun0}' 'VpnInfo{ownerUid=10124 vpnIface=tun1}'
EOF
printf '%s\n' "$LINKS_TUN" '8: tun1: <POINTOPOINT,UP> mtu 1500' > "$TMP/links.txt"
_out=$(PATH="$TMP/fakebin:$PATH" FX_ARB_LINK_FILE="$TMP/links.txt" FX_ARB_VPNINFO_FILE= \
  FX_ARB_PROC_NET_DIR="$TMP/net_free" FX_ARB_MODULE_ROOT="$TMP/mod_clean" sh "$ARB" 2>&1)
rc=$?
[ "$rc" -eq 2 ] || fail "multiple VpnInfo rows must return rc=2, got $rc: $_out"
[ "$(field "$_out" "['probe']")" = "unavailable" ] || fail "multiple VpnInfo rows were not rejected"
pass "ambiguous multiple VPN ownership records fail closed"

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
cp -a "$TMP/mod_clean/." "$TMP/mod_bad/"
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

echo "== case 8b: newly added module shell helper cannot bypass the slot scan =="
cp -a "$TMP/mod_clean/." "$TMP/mod_extra/"
cat > "$TMP/mod_extra/scripts/new-dataplane-helper.sh" <<'EOF'
#!/system/bin/sh
VpnService.prepare(context)
EOF
r=$(run_arb "$LINKS_NO_TUN" "" "$TMP/net_free" "$TMP/mod_extra")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 3 ] || fail "new module shell helper calling VpnService must return rc=3, got $rc: $out"
[ "$(field "$out" "['verdict']")" = "incompatible" ] || fail "new module shell helper bypassed VpnService scan: $out"
[ "$(field "$out" "['vpn_service_slot_used']")" = "True" ] || fail "new module helper must be reported as slot-using"
pass "all top-level module shell helpers are included in the VpnService invariant scan"

echo "== case 8c: dangling module helper symlink cannot be skipped by the source scan =="
cp -a "$TMP/mod_clean/." "$TMP/mod_symlink/"
ln -s "$TMP/does-not-exist.sh" "$TMP/mod_symlink/scripts/extra-helper.sh"
r=$(run_arb "$LINKS_NO_TUN" "" "$TMP/net_free" "$TMP/mod_symlink")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 2 ] || fail "dangling helper symlink must fail closed as unknown, got $rc: $out"
[ "$(field "$out" "['verdict']")" = "unknown" ] || fail "dangling helper symlink was skipped by slot scan: $out"
[ "$(field "$out" "['vpn_service_slot_used']")" = "None" ] || fail "unreadable helper source must not claim slot is free"
pass "dangling helper symlink is counted and fails closed"

echo "== case 8d: nested module shell helper cannot bypass the slot scan =="
cp -a "$TMP/mod_clean/." "$TMP/mod_nested/"
mkdir -p "$TMP/mod_nested/scripts/network/dns"
cat > "$TMP/mod_nested/scripts/network/dns/compat-helper.sh" <<'EOF'
#!/system/bin/sh
VpnService.Builder().setSession("nested-fx").establish()
EOF
r=$(run_arb "$LINKS_NO_TUN" "" "$TMP/net_free" "$TMP/mod_nested")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 3 ] || fail "nested VpnService helper must return rc=3, got $rc: $out"
[ "$(field "$out" "['verdict']")" = "incompatible" ] || fail "nested helper bypassed slot scan: $out"
pass "nested module shell helpers are included in the VpnService invariant scan"

echo "== case 8e: comment-only VpnService mention does not trigger a false positive =="
cp -a "$TMP/mod_clean/." "$TMP/mod_comment/"
mkdir -p "$TMP/mod_comment/scripts/network"
cat > "$TMP/mod_comment/scripts/network/documentation.sh" <<'EOF'
#!/system/bin/sh
# VpnService.Builder is intentionally documented here, not invoked.
echo "kernel dataplane remains independent"
EOF
r=$(run_arb "$LINKS_NO_TUN" "" "$TMP/net_free" "$TMP/mod_comment")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 0 ] || fail "comment-only API mention must not return rc=3, got $rc: $out"
[ "$(field "$out" "['vpn_service_slot_used']")" = "False" ] || fail "comment-only API mention was treated as an invocation: $out"
pass "comment-only VpnService mention is not treated as executable API usage"

echo "== case 9: unreadable port state -> never claimed as free =="
mkdir -p "$TMP/net_missing"
r=$(run_arb "$LINKS_NO_TUN" "" "$TMP/net_missing" "$TMP/mod_clean")
rc=${r%%|*}; out=${r#*|}
[ "$rc" -eq 0 ] || fail "expected rc=0, got $rc: $out"
[ "$(field "$out" "['verdict']")" = "partial" ] || fail "expected partial when port state unreadable, got $(field "$out" "['verdict']")"
[ "$(field "$out" "['dns']['owner']")" = "unknown" ] || fail "dns owner must be unknown"
[ "$(field "$out" "['dns_filter']['owner']")" = "unknown" ] || fail "DNS filter owner must be unknown"
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
tout=$(FX_ARB_LINK_FILE="$TMP/links.txt" FX_ARB_VPNINFO_FILE="$TMP/info.txt" \
       FX_ARB_PROC_NET_DIR="$TMP/net_free" FX_ARB_MODULE_ROOT="$TMP/mod_clean" \
       sh "$ARB" --text 2>&1)
rc=$?
[ "$rc" -eq 0 ] || fail "--text expected rc=0, got $rc: $tout"
case "$tout" in *"partial"*) ;; *) fail "--text did not render conservative verdict: $tout" ;; esac
pass "--text mode consistent"

echo "PASS: coexistence arbiter grades all levels, fails safe, and never mutates network state"
