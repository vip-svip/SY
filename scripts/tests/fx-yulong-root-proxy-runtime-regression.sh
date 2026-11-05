#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="$ROOT/fx-module/scripts/yulong-root-proxy.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$SOURCE" ] || fail "Root Proxy source missing"
sh -n "$SOURCE" || fail "Root Proxy shell syntax invalid"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-yulong-root-proxy.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
: > "$T/settings.log"
MOCK_SETTINGS_LOG="$T/settings.log"; export MOCK_SETTINGS_LOG
MOCK_PRIVATE_DNS_MODE=hostname; export MOCK_PRIVATE_DNS_MODE
MOD="$T/module"; BIN="$T/bin"
mkdir -p "$MOD/scripts" "$BIN"
cp "$SOURCE" "$MOD/scripts/yulong-root-proxy.sh"
printf 'id=privacyguard\n' > "$MOD/module.prop"

cat > "$MOD/scripts/util.sh" <<'UTIL'
#!/system/bin/sh
pg_get(){
  case "$1" in
    vpn_external_dns_proxy|vpn_external_compat|dns_forward) printf '%s\n' "${MOCK_ENABLED:-1}" ;;
    *) printf '%s\n' "${2:-}" ;;
  esac
}
UTIL
cat > "$BIN/ip" <<'IP'
#!/bin/sh
case "$*" in
  "-o link show dev tun0") echo '7: tun0: <POINTOPOINT,UP,LOWER_UP> mtu 1500' ;;
  "-o -4 addr show dev tun0 scope global") echo '7: tun0 inet 10.23.4.5/32 scope global tun0' ;;
  "route get 198.41.0.4 from 10.23.4.5")
    route_count=0
    [ ! -r "$MOCK_ROUTE_COUNT" ] || route_count=$(cat "$MOCK_ROUTE_COUNT")
    route_count=$((route_count+1)); printf '%s\n' "$route_count" > "$MOCK_ROUTE_COUNT"
    if [ "${MOCK_ROUTE_FAIL_RECHECK:-0}" = 1 ] && [ "$route_count" -gt 2 ]; then
      echo '198.41.0.4 from 10.23.4.5 dev wlan0'; exit 0
    fi
    [ "${MOCK_ROUTE_FAIL:-0}" = 1 ] && { echo '198.41.0.4 from 10.23.4.5 dev wlan0'; exit 0; }
    echo '198.41.0.4 from 10.23.4.5 dev tun0 src 10.23.4.5 uid 0' ;;
  "route get 199.9.14.201 from 10.23.4.5")
    route_count=0
    [ ! -r "$MOCK_ROUTE_COUNT" ] || route_count=$(cat "$MOCK_ROUTE_COUNT")
    route_count=$((route_count+1)); printf '%s\n' "$route_count" > "$MOCK_ROUTE_COUNT"
    [ "${MOCK_ROUTE_FAIL_SECOND:-0}" = 1 ] && { echo '199.9.14.201 from 10.23.4.5 dev wlan0'; exit 0; }
    echo '199.9.14.201 from 10.23.4.5 dev tun0 src 10.23.4.5 uid 0' ;;
  *) echo "unexpected ip invocation: $*" >&2; exit 64 ;;
esac
IP
cat > "$BIN/cmd" <<'CMD'
#!/bin/sh
if [ "$*" = 'package list packages -U' ]; then
  [ "${MOCK_PM_FAIL:-0}" = 1 ] && exit 1
  [ "${MOCK_PM_EMPTY:-0}" = 1 ] && exit 0
  printf '%s\n' 'package:com.example.whitelisted uid:10123' 'package:com.example.other uid:10124'
  exit 0
fi
echo "unexpected cmd invocation: $*" >&2
exit 64
CMD
cat > "$BIN/iptables" <<'IPTABLES'
#!/bin/sh
printf 'iptables %s\n' "$*" >> "$MOCK_RULE_LOG"
[ "${1:-}" = -t ] && [ "${2:-}" = nat ] || exit 64
case "${3:-}" in
  -N|-F|-X|-A) exit 0 ;;
  -C)
    [ "${4:-}" = OUTPUT ] && [ "${5:-}" = -j ] || exit 64
    grep -Fxq "${6:-}" "$MOCK_HOOKS4"; exit $? ;;
  -I)
    [ "${4:-}" = OUTPUT ] && [ "${5:-}" = 1 ] && [ "${6:-}" = -j ] || exit 64
    printf '%s\n' "${7:-}" >> "$MOCK_HOOKS4"; exit 0 ;;
  -D)
    [ "${4:-}" = OUTPUT ] && [ "${5:-}" = -j ] || exit 64
    chain=${6:-}; grep -Fxq "$chain" "$MOCK_HOOKS4" || exit 1
    tmp="$MOCK_HOOKS4.tmp.$$"; grep -Fxv "$chain" "$MOCK_HOOKS4" > "$tmp" || :; mv -f "$tmp" "$MOCK_HOOKS4"; exit 0 ;;
  *) echo "unexpected iptables invocation: $*" >&2; exit 64 ;;
esac
IPTABLES
cat > "$BIN/ip6tables" <<'IP6TABLES'
#!/bin/sh
printf 'ip6tables %s\n' "$*" >> "$MOCK_RULE_LOG"
[ "${1:-}" = -t ] && [ "${2:-}" = nat ] || exit 64
case "${3:-}" in
  -N|-F|-X|-A) exit 0 ;;
  -C)
    [ "${4:-}" = OUTPUT ] && [ "${5:-}" = -j ] || exit 64
    grep -Fxq "${6:-}" "$MOCK_HOOKS6"; exit $? ;;
  -I)
    [ "${4:-}" = OUTPUT ] && [ "${5:-}" = 1 ] && [ "${6:-}" = -j ] || exit 64
    [ "${MOCK_FAIL_IPV6_ATTACH:-0}" = 1 ] && exit 1
    printf '%s\n' "${7:-}" >> "$MOCK_HOOKS6"; exit 0 ;;
  -D)
    [ "${4:-}" = OUTPUT ] && [ "${5:-}" = -j ] || exit 64
    chain=${6:-}; grep -Fxq "$chain" "$MOCK_HOOKS6" || exit 1
    tmp="$MOCK_HOOKS6.tmp.$$"; grep -Fxv "$chain" "$MOCK_HOOKS6" > "$tmp" || :; mv -f "$tmp" "$MOCK_HOOKS6"; exit 0 ;;
  *) echo "unexpected ip6tables invocation: $*" >&2; exit 64 ;;
esac
IP6TABLES
cat > "$BIN/settings" <<'SETTINGS'
#!/bin/sh
printf 'settings %s\n' "$*" >> "$MOCK_SETTINGS_LOG"
[ "$1 $2 $3" = "get global private_dns_mode" ] || exit 64
printf '%s\n' "${MOCK_PRIVATE_DNS_MODE:-off}"
SETTINGS
cat > "$BIN/timeout" <<'TIMEOUT'
#!/bin/sh
[ "$#" -ge 2 ] || exit 64
shift
exec "$@"
TIMEOUT
cat > "$BIN/nslookup" <<'NSLOOKUP'
#!/bin/sh
[ "${MOCK_DNS_PROBE_FAIL:-0}" = 0 ] || exit 1
printf 'Server: 127.0.0.1\nAddress 1: 127.0.0.1\nName: example.com\nAddress 1: 93.184.216.34\n'
NSLOOKUP
cat > "$MOD/scripts/unbound.sh" <<'UNBOUND'
#!/system/bin/sh
case "$1" in
  ensure) [ "${MOCK_UNBOUND_FAIL:-0}" = 0 ] || exit 1; [ -s "$PG/unbound-vpn-egress-ip" ] || exit 1; echo unbound-ensure >> "$MOCK_ENGINE_LOG" ;;
  stop) echo unbound-stop >> "$MOCK_ENGINE_LOG" ;;
  *) exit 64 ;;
esac
UNBOUND
cat > "$MOD/scripts/adguardhome.sh" <<'ADGUARD'
#!/system/bin/sh
case "$1" in
  ensure) [ "${MOCK_ADGUARD_FAIL:-0}" = 0 ] || exit 1; [ -s "$PG/unbound-vpn-egress-ip" ] || exit 1; echo adguard-ensure >> "$MOCK_ENGINE_LOG" ;;
  stop) echo adguard-stop >> "$MOCK_ENGINE_LOG" ;;
  *) exit 64 ;;
esac
ADGUARD
chmod 0755 "$BIN"/* "$MOD/scripts/"*

prepare_case(){
  CASE_DIR="$T/$1"; CASE_PG="$CASE_DIR/state"; mkdir -p "$CASE_PG"
  cat > "$CASE_PG/settings.conf" <<'CONF'
[list:yulong_root_proxy_whitelist]
com.example.whitelisted|1
CONF
  : > "$CASE_DIR/rules.log"; : > "$CASE_DIR/hooks4"; : > "$CASE_DIR/hooks6"; : > "$CASE_DIR/engines.log"
}
run_proxy(){
  CASE_DIR=$1; shift
  env MP="$MOD" PG="$CASE_DIR/state" CONF="$CASE_DIR/state/settings.conf" PATH="$BIN:$PATH" \
    MOCK_RULE_LOG="$CASE_DIR/rules.log" MOCK_HOOKS4="$CASE_DIR/hooks4" MOCK_HOOKS6="$CASE_DIR/hooks6" \
    MOCK_ROUTE_COUNT="$CASE_DIR/route-count" MOCK_ENGINE_LOG="$CASE_DIR/engines.log" \
    "$@" sh "$MOD/scripts/yulong-root-proxy.sh" ensure "$MOD" "$CASE_DIR/state" tun0 10042
}
run_status(){
  CASE_DIR=$1; shift
  env MP="$MOD" PG="$CASE_DIR/state" CONF="$CASE_DIR/state/settings.conf" PATH="$BIN:$PATH" \
    MOCK_RULE_LOG="$CASE_DIR/rules.log" MOCK_HOOKS4="$CASE_DIR/hooks4" MOCK_HOOKS6="$CASE_DIR/hooks6" \
    MOCK_ROUTE_COUNT="$CASE_DIR/route-count" MOCK_ENGINE_LOG="$CASE_DIR/engines.log" \
    "$@" sh "$MOD/scripts/yulong-root-proxy.sh" status
}
assert_stopped(){
  case_dir=$1
  [ ! -e "$case_dir/state/yulong-root-proxy-active" ] || fail "$2 left active marker"
  [ ! -e "$case_dir/state/yulong-root-proxy-active.meta" ] || fail "$2 left active metadata"
  [ ! -e "$case_dir/state/unbound-vpn-egress-ip" ] || fail "$2 left egress marker"
  [ ! -s "$case_dir/hooks4" ] || fail "$2 left IPv4 OUTPUT hook"
  [ ! -s "$case_dir/hooks6" ] || fail "$2 left IPv6 OUTPUT hook"
  [ ! -e "$case_dir/state/yulong-root-proxy.lock" ] || fail "$2 leaked lock"
  grep -Fq adguard-stop "$case_dir/engines.log" || fail "$2 did not stop AdGuard"
  grep -Fq unbound-stop "$case_dir/engines.log" || fail "$2 did not stop Unbound"
}

# CONF overrides cannot redirect whitelist reads or persistent updates outside PG.
prepare_case conf-override
printf 'external-config\n' > "$CASE_DIR/outside.conf"
if env MP="$MOD" PG="$CASE_DIR/state" CONF="$CASE_DIR/outside.conf" PATH="$BIN:$PATH" \
    sh "$MOD/scripts/yulong-root-proxy.sh" >/dev/null 2>&1; then
  fail "Root Proxy accepted a CONF path outside its private state directory"
fi
grep -Fqx external-config "$CASE_DIR/outside.conf" || fail "rejected CONF override was modified"

# Every existing ancestor of PG must be a real directory.
prepare_case parent-symlink
mkdir "$CASE_DIR/real-parent"
ln -s "$CASE_DIR/real-parent" "$CASE_DIR/parent-link"
if env MP="$MOD" PG="$CASE_DIR/parent-link/state" CONF="$CASE_DIR/parent-link/state/settings.conf" \
    PATH="$BIN:$PATH" sh "$MOD/scripts/yulong-root-proxy.sh" >/dev/null 2>&1; then
  fail "Root Proxy accepted PG below a symlinked parent"
fi
[ ! -e "$CASE_DIR/real-parent/state" ] || fail "Root Proxy created external state through a symlinked parent"
rm "$CASE_DIR/parent-link"

# Refuse symlinked state directory/config/log/markers before any I/O.
prepare_case pg-symlink
mkdir "$CASE_DIR/outside"; echo keep-state > "$CASE_DIR/outside/sentinel"
rm -rf "$CASE_DIR/state"; ln -s "$CASE_DIR/outside" "$CASE_DIR/state"
if run_proxy "$CASE_DIR" >/dev/null 2>&1; then fail "symlinked state directory accepted"; fi
grep -Fxq keep-state "$CASE_DIR/outside/sentinel" || fail "state-directory symlink target changed"
[ ! -e "$CASE_DIR/outside/yulong-root-proxy.log" ] || fail "log written through state-directory symlink"

prepare_case config-symlink
echo keep-config > "$CASE_DIR/victim"; mv "$CASE_DIR/state/settings.conf" "$CASE_DIR/settings.saved"
ln -s "$CASE_DIR/victim" "$CASE_DIR/state/settings.conf"
if run_proxy "$CASE_DIR" >/dev/null 2>&1; then fail "symlinked settings.conf accepted"; fi
grep -Fxq keep-config "$CASE_DIR/victim" || fail "settings symlink target changed"

prepare_case log-symlink
echo keep-log > "$CASE_DIR/victim"; ln -s "$CASE_DIR/victim" "$CASE_DIR/state/yulong-root-proxy.log"
if run_proxy "$CASE_DIR" >/dev/null 2>&1; then fail "symlinked log accepted"; fi
grep -Fxq keep-log "$CASE_DIR/victim" || fail "log symlink target changed"

for state_file in yulong-root-proxy-active yulong-root-proxy-active.meta unbound-vpn-egress-ip yulong-root-proxy.lock; do
  prepare_case "state-file-$state_file"
  echo keep-state > "$CASE_DIR/victim"; ln -s "$CASE_DIR/victim" "$CASE_DIR/state/$state_file"
  if run_proxy "$CASE_DIR" >/dev/null 2>&1; then fail "symlinked state file accepted: $state_file"; fi
  grep -Fxq keep-state "$CASE_DIR/victim" || fail "state symlink target changed: $state_file"
done

prepare_case success
out=$(run_proxy "$CASE_DIR")
printf '%s\n' "$out" | grep -Fqx active=1 || fail "valid VPN did not activate Root Proxy"
printf '%s\n' "$out" | grep -Fqx interface=tun0 || fail "wrong active interface"
printf '%s\n' "$out" | grep -Fqx vpn_uid=10042 || fail "wrong VPN owner UID"
[ "$(cat "$CASE_DIR/state/unbound-vpn-egress-ip")" = 10.23.4.5 ] || fail "validated egress IP missing"
[ "$(sed -n '1p' "$CASE_DIR/state/yulong-root-proxy-active.meta")" = tun0 ] || fail "active metadata interface mismatch"
[ "$(sed -n '2p' "$CASE_DIR/state/yulong-root-proxy-active.meta")" = 10042 ] || fail "active metadata UID mismatch"
[ "$(sed -n '3p' "$CASE_DIR/state/yulong-root-proxy-active.meta")" = 10.23.4.5 ] || fail "active metadata egress mismatch"
[ "$(cat "$CASE_DIR/hooks4")" = FXYRP4_A ] || fail "IPv4 chain not attached"
[ "$(cat "$CASE_DIR/hooks6")" = FXYRP6_A ] || fail "IPv6 chain not attached"
for line in \
  'iptables -t nat -A FXYRP4_A -m owner --uid-owner 0 -j RETURN' \
  'iptables -t nat -A FXYRP4_A -m owner --uid-owner 10042 -j RETURN' \
  'iptables -t nat -A FXYRP4_A -m owner --uid-owner 10123 -j RETURN' \
  'iptables -t nat -A FXYRP4_A -p udp --dport 53 -j DNAT --to-destination 127.0.0.1:53' \
  'ip6tables -t nat -A FXYRP6_A -m owner --uid-owner 10123 -j RETURN' \
  "ip6tables -t nat -A FXYRP6_A -p tcp --dport 53 -j DNAT --to-destination [::1]:53"; do
  grep -Fqx "$line" "$CASE_DIR/rules.log" || fail "missing rule: $line"
done
[ ! -e "$CASE_DIR/state/yulong-root-proxy.lock" ] || fail "success leaked lock"
status_out=$(run_status "$CASE_DIR")
printf '%s\n' "$status_out" | grep -Fqx active=1 || fail "healthy Root Proxy was not reported active"
printf '%s\n' "$status_out" | grep -Fqx redirects=attached || fail "status did not confirm both redirects"
printf '%s\n' "$status_out" | grep -Fqx route=verified || fail "status did not revalidate the VPN egress"
printf '%s\n' "$status_out" | grep -Fqx dns_probe=passed || fail "status did not confirm local DNS health"
printf '%s\n' "$status_out" | grep -Fqx private_dns_mode=hostname || fail "strict Private DNS mode was not reported"
printf '%s\n' "$status_out" | grep -Fqx dns_filter_coverage=strict_private_dns_bypasses_redirect || fail "strict Private DNS bypass coverage was not reported"
if grep -Fq 'settings put' "$T/settings.log"; then fail "Root Proxy modified the user's Android Private DNS setting"; fi
MOCK_PRIVATE_DNS_MODE=opportunistic; export MOCK_PRIVATE_DNS_MODE
status_out=$(run_status "$CASE_DIR")
printf '%s\n' "$status_out" | grep -Fqx dns_filter_coverage=opportunistic_private_dns_may_bypass_redirect || fail "opportunistic Private DNS coverage was not reported"
MOCK_PRIVATE_DNS_MODE=off; export MOCK_PRIVATE_DNS_MODE
status_out=$(run_status "$CASE_DIR")
printf '%s\n' "$status_out" | grep -Fqx dns_filter_coverage=port53_redirect_active || fail "Private DNS off coverage was not reported"

# Metadata alone must not be treated as proof of a live redirect.
: > "$CASE_DIR/hooks4"
status_out=$(run_status "$CASE_DIR")
printf '%s\n' "$status_out" | grep -Fqx active=0 || fail "missing IPv4 redirect was reported active"
printf '%s\n' "$status_out" | grep -Fqx reason=ipv4_redirect_missing || fail "missing IPv4 redirect reason not reported"
printf '%s\n' FXYRP4_A > "$CASE_DIR/hooks4"
status_out=$(run_status "$CASE_DIR" MOCK_ROUTE_FAIL=1)
printf '%s\n' "$status_out" | grep -Fqx active=0 || fail "changed VPN route was reported active"
printf '%s\n' "$status_out" | grep -Fqx reason=vpn_route_unavailable || fail "unavailable VPN route reason not reported"

for scenario in route route2 package-manager unbound adguard probe route-recheck; do
  prepare_case "$scenario"
  case "$scenario" in
    route) if run_proxy "$CASE_DIR" MOCK_ROUTE_FAIL=1 >/dev/null 2>&1; then fail "wrong tunnel route accepted"; fi ;;
    route2) if run_proxy "$CASE_DIR" MOCK_ROUTE_FAIL_SECOND=1 >/dev/null 2>&1; then fail "second root route mismatch accepted"; fi ;;
    package-manager) if run_proxy "$CASE_DIR" MOCK_PM_FAIL=1 >/dev/null 2>&1; then fail "failed UID snapshot accepted"; fi ;;
    unbound) if run_proxy "$CASE_DIR" MOCK_UNBOUND_FAIL=1 >/dev/null 2>&1; then fail "Unbound failure accepted"; fi ;;
    adguard) if run_proxy "$CASE_DIR" MOCK_ADGUARD_FAIL=1 >/dev/null 2>&1; then fail "AdGuard failure accepted"; fi ;;
    probe) if run_proxy "$CASE_DIR" MOCK_DNS_PROBE_FAIL=1 >/dev/null 2>&1; then fail "DNS probe failure accepted"; fi ;;
    route-recheck)
      if run_proxy "$CASE_DIR" MOCK_ROUTE_FAIL_RECHECK=1 >/dev/null 2>&1; then
        fail "VPN egress change during DNS engine startup was accepted"
      fi
      [ "$(cat "$CASE_DIR/route-count")" -gt 2 ] || fail "second route proof was not reached"
      ;;
  esac
  assert_stopped "$CASE_DIR" "$scenario fail-open"
done

prepare_case ipv6-attach
if run_proxy "$CASE_DIR" MOCK_FAIL_IPV6_ATTACH=1 >/dev/null 2>&1; then fail "IPv6 attach failure was accepted"; fi
assert_stopped "$CASE_DIR" "IPv6 attach rollback"
grep -Fq 'iptables -t nat -D OUTPUT -j FXYRP4_A' "$CASE_DIR/rules.log" || fail "IPv4 OUTPUT rollback command absent"

echo "PASS: Root Proxy runtime route/UID proofs, dual-stack rules, state-path symlink guards and fail-open rollback"
