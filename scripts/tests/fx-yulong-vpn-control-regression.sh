#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="$ROOT/scripts/yulong-vpn-control.sh"
TMP=$(mktemp -d "/tmp/fx-yulong-vpn-control.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$SOURCE" ] || fail "canonical Yulong VPN lifecycle helper missing"
MOD="$TMP/module"
PG="$TMP/state"
mkdir -p "$MOD/scripts" "$PG"
cp "$SOURCE" "$MOD/scripts/yulong-vpn-control.sh"
cat > "$MOD/module.prop" <<'__PROP__'
id=privacyguard
version=1
__PROP__
cat > "$MOD/scripts/util.sh" <<'__UTIL__'
pg_get() {
  key=$1
  default=${2:-}
  value=$(awk -F= -v key="$key" '$1==key {v=substr($0,index($0,"=")+1);found=1;exit} END{if(found)print v}' "$PG/settings.conf")
  [ -n "$value" ] || value=$default
  printf '%s\n' "$value"
}
pg_set() {
  key=$1 value=$2
  tmp="$PG/settings.conf.test.$$"
  awk -F= -v key="$key" -v value="$value" 'BEGIN{done=0} $1==key {if(!done)print key "=" value;done=1;next} {print} END{if(!done)print key "=" value}' "$PG/settings.conf" > "$tmp" || return 1
  chmod 600 "$tmp" && mv -f "$tmp" "$PG/settings.conf"
}
__UTIL__
cat > "$MOD/scripts/apply.sh" <<'__APPLY__'
#!/system/bin/sh
set -eu
. "$MP/scripts/util.sh"
[ ! -e "$PG/fail-apply" ] || exit 55
mode=$(pg_get vpn_mode direct)
node=$(pg_get vpn_node "")
if [ "$mode" = global ] && [ -f "$PG/external-vpn" ] \
    && [ "$(pg_get vpn_external_compat 0)" = 1 ] \
    && [ "$(pg_get vpn_external_dns_proxy 0)" = 1 ]; then
  printf '1\n' > "$PG/root-proxy-active"
  printf 'direct\n' > "$PG/live-mode"
elif [ "$mode" = global ] && [ -z "$node" ]; then
  exit 55
else
  printf '0\n' > "$PG/root-proxy-active"
  printf '%s\n' "$mode" > "$PG/live-mode"
fi
__APPLY__
cat > "$MOD/scripts/status.sh" <<'__STATUS__'
#!/system/bin/sh
set -eu
. "$MP/scripts/util.sh"
mode=$(pg_get vpn_mode direct)
live=$(cat "$PG/live-mode" 2>/dev/null || echo direct)
node=$(pg_get vpn_node "")
on=false
proxy=$(cat "$PG/root-proxy-active" 2>/dev/null || echo 0)
if [ "$mode" != direct ] && [ "$mode" = "$live" ] && [ "$proxy" != 1 ]; then on=true; fi
printf '{"vpn_mode":"%s","vpn_on":%s,"vpn_node":"%s"}\n' "$mode" "$on" "$node"
__STATUS__
cat > "$MOD/scripts/yulong-root-proxy.sh" <<'__ROOT_PROXY__'
#!/system/bin/sh
set -eu
[ "$1" = status ] || exit 64
active=$(cat "$PG/root-proxy-active" 2>/dev/null || echo 0)
enabled=$(awk -F= '$1=="vpn_external_dns_proxy" {print $2;exit}' "$PG/settings.conf")
echo "enabled=${enabled:-0}"
echo "active=$active"
__ROOT_PROXY__
chmod 755 "$MOD/scripts/yulong-root-proxy.sh"
chmod 755 "$MOD/scripts/apply.sh" "$MOD/scripts/status.sh"
printf 'vpn_mode=direct\nvpn_node=node-test\n' > "$PG/settings.conf"
printf 'direct\n' > "$PG/live-mode"
sh "$SOURCE" "$MOD" "$PG" start > "$TMP/start.out" || fail "VPN start should succeed with a selected node"
grep -q 'vpn_started=1' "$TMP/start.out" || fail "start confirmation missing"
grep -q '^vpn_mode=global$' "$PG/settings.conf" || fail "direct start must choose FX's unified global route"
status_output=$(sh "$SOURCE" "$MOD" "$PG" status)
printf '%s\n' "$status_output" | grep -q '"vpn_on":true' || fail "status must confirm live VPN after start"
sh "$SOURCE" "$MOD" "$PG" stop > "$TMP/stop.out" || fail "VPN stop should succeed"
grep -q 'vpn_stopped=1' "$TMP/stop.out" || fail "stop confirmation missing"
grep -q '^vpn_mode=direct$' "$PG/settings.conf" || fail "stop must restore direct mode"
status_output=$(sh "$SOURCE" "$MOD" "$PG" status)
printf '%s\n' "$status_output" | grep -q '"vpn_on":false' || fail "status must confirm direct/off after stop"
printf 'vpn_mode=direct\nvpn_node=\n' > "$PG/settings.conf"
if sh "$SOURCE" "$MOD" "$PG" start > "$TMP/no-node.out" 2>&1; then
  fail "VPN start unexpectedly succeeded without a node"
else
  rc=$?
  [ "$rc" -eq 32 ] || fail "no-node failure must use exit code 32"
fi
grep -q '^vpn_mode=direct
touch "$PG/fail-apply"
if sh "$SOURCE" "$MOD" "$PG" start > "$TMP/failure.out" 2>&1; then fail "apply failure unexpectedly reported success"; fi
grep -q '^vpn_mode=direct$' "$PG/settings.conf" || fail "failed start did not restore the previous mode"
echo "PASS: legacy Yulong VPN start/stop uses FX's one route, requires a node and rolls back failed apply"
 "$PG/settings.conf" || fail "no-node start changed the saved mode"

# A live third-party VPN can use the validated FX Root Proxy route without an
# FX node, but only when the user's compatibility and DNS forwarding switches
# are explicitly enabled. This must not claim the FX VpnService is running.
printf 'vpn_mode=direct\nvpn_node=\nvpn_external_compat=1\ndns_forward=1\nvpn_external_dns_proxy=0\n' > "$PG/settings.conf"
touch "$PG/external-vpn"
sh "$SOURCE" "$MOD" "$PG" start > "$TMP/root-proxy-start.out" || fail "Root Proxy should start without an FX node when a live compatible VPN exists"
grep -q '^root_proxy_started=1
touch "$PG/fail-apply"
if sh "$SOURCE" "$MOD" "$PG" start > "$TMP/failure.out" 2>&1; then fail "apply failure unexpectedly reported success"; fi
grep -q '^vpn_mode=direct$' "$PG/settings.conf" || fail "failed start did not restore the previous mode"
echo "PASS: legacy Yulong VPN start/stop uses FX's one route, requires a node and rolls back failed apply"
 "$TMP/root-proxy-start.out" || fail "Root Proxy start confirmation missing"
status_output=$(sh "$SOURCE" "$MOD" "$PG" status)
printf '%s\n' "$status_output" | grep -q '"vpn_on":false' || fail "Root Proxy must not report the FX VpnService as running"
printf '%s\n' "$status_output" | grep -q '"root_proxy_on":true' || fail "status must confirm live Root Proxy"
printf '%s\n' "$status_output" | grep -q '"root_proxy_known":true' || fail "status must declare Root Proxy state verified"
sh "$SOURCE" "$MOD" "$PG" stop > "$TMP/root-proxy-stop.out" || fail "Root Proxy route stop failed"
grep -q '^vpn_stopped=1
touch "$PG/fail-apply"
if sh "$SOURCE" "$MOD" "$PG" start > "$TMP/failure.out" 2>&1; then fail "apply failure unexpectedly reported success"; fi
grep -q '^vpn_mode=direct$' "$PG/settings.conf" || fail "failed start did not restore the previous mode"
echo "PASS: legacy Yulong VPN start/stop uses FX's one route, requires a node and rolls back failed apply"
 "$TMP/root-proxy-stop.out" || fail "Root Proxy stop confirmation missing"
status_output=$(sh "$SOURCE" "$MOD" "$PG" status)
printf '%s\n' "$status_output" | grep -q '"root_proxy_on":false' || fail "Root Proxy remained active after stop"
grep -q '^vpn_mode=direct
touch "$PG/fail-apply"
if sh "$SOURCE" "$MOD" "$PG" start > "$TMP/failure.out" 2>&1; then fail "apply failure unexpectedly reported success"; fi
grep -q '^vpn_mode=direct$' "$PG/settings.conf" || fail "failed start did not restore the previous mode"
echo "PASS: legacy Yulong VPN start/stop uses FX's one route, requires a node and rolls back failed apply"
 "$PG/settings.conf" || fail "Root Proxy stop did not return to direct mode"

# Without a live external VPN, the no-node Root Proxy attempt must roll back.
rm -f "$PG/external-vpn"
pg_set vpn_external_dns_proxy 0
if sh "$SOURCE" "$MOD" "$PG" start > "$TMP/no-node-no-vpn.out" 2>&1; then
  fail "no-node start succeeded without a live external VPN"
else
  rc=$?
  [ "$rc" -eq 32 ] || fail "no-node failure must use exit code 32"
fi
grep -q '^vpn_mode=direct
touch "$PG/fail-apply"
if sh "$SOURCE" "$MOD" "$PG" start > "$TMP/failure.out" 2>&1; then fail "apply failure unexpectedly reported success"; fi
grep -q '^vpn_mode=direct$' "$PG/settings.conf" || fail "failed start did not restore the previous mode"
echo "PASS: legacy Yulong VPN start/stop uses FX's one route, requires a node and rolls back failed apply"
 "$PG/settings.conf" || fail "failed Root Proxy fallback changed route mode"
grep -q '^vpn_external_dns_proxy=0
touch "$PG/fail-apply"
if sh "$SOURCE" "$MOD" "$PG" start > "$TMP/failure.out" 2>&1; then fail "apply failure unexpectedly reported success"; fi
grep -q '^vpn_mode=direct$' "$PG/settings.conf" || fail "failed start did not restore the previous mode"
echo "PASS: legacy Yulong VPN start/stop uses FX's one route, requires a node and rolls back failed apply"
 "$PG/settings.conf" || fail "failed Root Proxy fallback did not restore the prior compatibility flag"

# If the independent Root Proxy status cannot be read, controls must fail
# closed instead of assuming that no protection route is active.
cat > "$MOD/scripts/yulong-root-proxy.sh" <<'__ROOT_PROXY_FAIL__'
#!/system/bin/sh
exit 127
__ROOT_PROXY_FAIL__
chmod 755 "$MOD/scripts/yulong-root-proxy.sh"
cp "$PG/settings.conf" "$TMP/settings-before-unknown-status"
if sh "$SOURCE" "$MOD" "$PG" start > "$TMP/unknown-status.out" 2>&1; then
  fail "route start succeeded while Root Proxy status was unknown"
fi
grep -q 'VPN_STATUS_UNAVAILABLE' "$TMP/unknown-status.out" || fail "unknown Root Proxy state was not surfaced"
cmp -s "$TMP/settings-before-unknown-status" "$PG/settings.conf" || fail "unknown Root Proxy state allowed settings mutation"

printf 'vpn_mode=direct\nvpn_node=node-test\n' > "$PG/settings.conf"
touch "$PG/fail-apply"
if sh "$SOURCE" "$MOD" "$PG" start > "$TMP/failure.out" 2>&1; then fail "apply failure unexpectedly reported success"; fi
grep -q '^vpn_mode=direct$' "$PG/settings.conf" || fail "failed start did not restore the previous mode"
echo "PASS: legacy Yulong VPN start/stop uses FX's one route, requires a node and rolls back failed apply"
