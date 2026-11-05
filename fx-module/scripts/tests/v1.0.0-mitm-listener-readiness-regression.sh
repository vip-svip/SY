#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
HEALTH="$ROOT/scripts/mitm-listener-health.sh"
ENGINE="$ROOT/scripts/mitm-engine.sh"
REDIRECT="$ROOT/scripts/mitm-redirect.sh"
AUDIT="$ROOT/scripts/mitm-audit.sh"
WATCHER="$ROOT/scripts/mitm-redirect-watch.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for f in "$HEALTH" "$ENGINE" "$REDIRECT" "$AUDIT" "$WATCHER"; do sh -n "$f" || fail "shell syntax: $f"; done
TMP=${TMPDIR:-/tmp}/fx-mitm-listener-test.$$
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP"
header='  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode'
# Exact configured listener: 127.0.0.1:18443 in LISTEN (0A).
printf '%s\n%s\n' "$header" '   0: 0100007F:4813 00000000:0000 0A 00000000:00000000 00:00000000 00000000 0 0 12345' > "$TMP/tcp"
PG_PROC_NET_TCP="$TMP/tcp" sh "$HEALTH" check || fail 'exact loopback listener should be ready'
# Refuse the same port on wildcard/non-loopback addresses.
printf '%s\n%s\n' "$header" '   0: 00000000:4813 00000000:0000 0A 00000000:00000000 00:00000000 00000000 0 0 12345' > "$TMP/tcp"
if PG_PROC_NET_TCP="$TMP/tcp" sh "$HEALTH" check; then fail 'wildcard listener must not count as loopback-only'; fi
# Refuse a non-LISTEN state and a different port.
printf '%s\n%s\n' "$header" '   0: 0100007F:4813 00000000:0000 01 00000000:00000000 00:00000000 00000000 0 0 12345' > "$TMP/tcp"
if PG_PROC_NET_TCP="$TMP/tcp" sh "$HEALTH" check; then fail 'established socket must not count as listener'; fi
printf '%s\n%s\n' "$header" '   0: 0100007F:4814 00000000:0000 0A 00000000:00000000 00:00000000 00000000 0 0 12345' > "$TMP/tcp"
if PG_PROC_NET_TCP="$TMP/tcp" sh "$HEALTH" check; then fail 'wrong port must not count as listener'; fi
# Exercise the shared external-tunnel detector with a stubbed ip command.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/ip" <<'IPEOF'
#!/bin/sh
case "${PG_TEST_IP_MODE:-tunnel}" in
  tunnel) printf '%s\n' '1: lo: <LOOPBACK> mtu 65536' '2: tun0: <POINTOPOINT,UP> mtu 1500' ;;
  none) printf '%s\n' '1: lo: <LOOPBACK> mtu 65536' '3: wlan0: <BROADCAST,UP> mtu 1500' ;;
  error) exit 1 ;;
  empty) exit 0 ;;
esac
IPEOF
chmod 755 "$TMP/bin/ip"
_tun=$(PATH="$TMP/bin:$PATH" PG_MODDIR="$ROOT" PG_TEST_IP_MODE=tunnel sh "$REDIRECT" external-vpn) || fail 'tunnel detector should return success when tun0 exists'
[ "$_tun" = tun0 ] || fail "unexpected detected tunnel: $_tun"
if PATH="$TMP/bin:$PATH" PG_MODDIR="$ROOT" PG_TEST_IP_MODE=none sh "$REDIRECT" external-vpn >/dev/null 2>&1; then fail 'no-tunnel state must return nonzero'; fi
if PATH="$TMP/bin:$PATH" PG_MODDIR="$ROOT" PG_TEST_IP_MODE=error sh "$REDIRECT" external-vpn >/dev/null 2>&1; then fail 'failed interface inspection must not claim no tunnel'; else _rc=$?; [ "$_rc" -eq 2 ] || fail 'failed interface inspection should report unknown state'; fi
if PATH="$TMP/bin:$PATH" PG_MODDIR="$ROOT" PG_TEST_IP_MODE=empty sh "$REDIRECT" external-vpn >/dev/null 2>&1; then fail 'empty interface listing must not claim no tunnel'; else _rc=$?; [ "$_rc" -eq 2 ] || fail 'empty interface listing should report unknown state'; fi
# Exercise the enable guard: it must reject an external tunnel before issuing
# any iptables mutation, even when invoked directly rather than through apply.sh.
cat > "$TMP/bin/iptables" <<'IPEOF'
#!/bin/sh
printf '%s\n' "$*" >> "$PG_TEST_IPTABLES_TRACE"
exit 1
IPEOF
cat > "$TMP/bin/id" <<'IPEOF'
#!/bin/sh
[ "${1:-}" = -u ] && { echo 0; exit 0; }
exit 1
IPEOF
chmod 755 "$TMP/bin/iptables" "$TMP/bin/id"
: > "$TMP/iptables.trace"
if PATH="$TMP/bin:$PATH" PG_MODDIR="$ROOT" PG_TEST_IP_MODE=tunnel PG_TEST_IPTABLES_TRACE="$TMP/iptables.trace" sh "$REDIRECT" enable >"$TMP/enable.out" 2>"$TMP/enable.err"; then fail 'MITM enable must refuse when an external tunnel is detected'; else _rc=$?; [ "$_rc" -eq 3 ] || fail 'external tunnel guard must use refusal exit status'; fi
grep -Fq 'external VPN tunnel tun0 detected' "$TMP/enable.err" || fail 'enable refusal should state the detected tunnel'
[ ! -s "$TMP/iptables.trace" ] || fail 'firewall commands ran before external VPN refusal'
if PATH="$TMP/bin:$PATH" PG_MODDIR="$ROOT" PG_TEST_IP_MODE=error PG_TEST_IPTABLES_TRACE="$TMP/iptables.trace" sh "$REDIRECT" enable >"$TMP/enable-unknown.out" 2>"$TMP/enable-unknown.err"; then fail 'MITM enable must refuse when VPN state cannot be inspected'; else _rc=$?; [ "$_rc" -eq 3 ] || fail 'unknown tunnel state must use refusal exit status'; fi
if PATH="$TMP/bin:$PATH" PG_MODDIR="$ROOT" PG_TEST_IP_MODE=empty PG_TEST_IPTABLES_TRACE="$TMP/iptables.trace" sh "$REDIRECT" enable >"$TMP/enable-empty.out" 2>"$TMP/enable-empty.err"; then fail 'MITM enable must refuse when interface listing is empty'; else _rc=$?; [ "$_rc" -eq 3 ] || fail 'empty interface listing must use refusal exit status'; fi
[ ! -s "$TMP/iptables.trace" ] || fail 'firewall commands ran when VPN state was unknown'
# Use an isolated fake module to verify that an empty allowlist cannot enable a
# broad TCP/443 detour even when CA trust checks report success.
mkdir -p "$TMP/mod/scripts" "$TMP/pg/mitm"
cp "$REDIRECT" "$TMP/mod/scripts/mitm-redirect.sh"
printf 'id=privacyguard\nname=FX\nversion=1.0.0\n' > "$TMP/mod/module.prop"
cat > "$TMP/mod/scripts/mitm-engine.sh" <<'IPEOF'
#!/bin/sh
case "${1:-status}" in
 status) echo '{"ok":true,"ca_submodule":"released","ca_system_trust":"present"}' ;;
 start) echo started >> "$PG_TEST_ENGINE_TRACE"; exit 0 ;;
 stop) exit 0 ;;
esac
IPEOF
cat > "$TMP/mod/scripts/sync-mitm-hosts.sh" <<'IPEOF'
#!/bin/sh
mkdir -p "$PG/mitm"
: > "$PG/mitm/hostnames.conf"
echo '{"ok":true,"hosts":0}'
IPEOF
chmod 755 "$TMP/mod/scripts/mitm-engine.sh" "$TMP/mod/scripts/sync-mitm-hosts.sh"
: > "$TMP/iptables.trace"
: > "$TMP/engine.trace"
if PATH="$TMP/bin:$PATH" PG_MODDIR="$TMP/mod" PG="$TMP/pg" PG_TEST_IP_MODE=none PG_TEST_IPTABLES_TRACE="$TMP/iptables.trace" PG_TEST_ENGINE_TRACE="$TMP/engine.trace" sh "$TMP/mod/scripts/mitm-redirect.sh" enable >"$TMP/empty-hosts.out" 2>"$TMP/empty-hosts.err"; then fail 'MITM enable must refuse an empty host allowlist'; else _rc=$?; [ "$_rc" -eq 4 ] || fail 'empty allowlist must use a preflight refusal status'; fi
grep -Fq 'hostname allowlist is empty' "$TMP/empty-hosts.err" || fail 'empty allowlist refusal is not explained'
[ ! -s "$TMP/engine.trace" ] || fail 'MITM engine was started with an empty allowlist'
if grep -E -- '(^|[[:space:]])(-A|-I|-N|-D|-F|-X)([[:space:]]|$)' "$TMP/iptables.trace" >/dev/null 2>&1; then fail 'firewall mutation ran with an empty allowlist'; fi
# Engine startup and status must require the real socket, not only an owned PID.
grep -Fq 'wait_for_listener "$_p"' "$ENGINE" || fail 'start path does not wait for listener readiness'
grep -Fq 'listener_ready' "$ENGINE" || fail 'engine status/start omits listener readiness check'
grep -Fq 'refusing to enable redirect' "$ENGINE" || fail 'unhealthy existing process does not block redirect enable'
grep -Fq 'mitm-listener-health.sh" check' "$REDIRECT" || fail 'redirect status lacks listener health check'
grep -Fq 'https-mitm-redirect-degraded' "$AUDIT" || fail 'audit does not distinguish degraded redirect state'
grep -Fq 'detect_external_tunnel' "$REDIRECT" || fail 'explicit enable does not detect external VPN tunnels'
grep -Fq 'external VPN state is unknown' "$REDIRECT" || fail 'unknown VPN state is not a safe refusal'
grep -Fq 'start_guard_watch' "$REDIRECT" || fail 'enabled redirect does not start VPN safety watcher'
grep -Fq 'disabling FX-owned MITM redirect' "$WATCHER" || fail 'watcher does not auto-disable for external VPN'
grep -Fq 'MITM listener health is degraded' "$WATCHER" || fail 'watcher does not fail-open on a dead listener'
echo 'MITM listener readiness regression: PASS'
