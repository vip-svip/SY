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
  value=$(awk -F= -v key="$key" '$1==key {print substr($0,index($0,"=")+1);exit}' "$PG/settings.conf")
  [ -n "$value" ] || value=$default
  printf '%s\n' "$value"
}
pg_set() {
  key=$1
  value=$2
  tmp="$PG/settings.conf.test.$$"
  awk -F= -v key="$key" -v value="$value" '
    BEGIN{done=0}
    $1==key {if(!done)print key "=" value;done=1;next}
    {print}
    END{if(!done)print key "=" value}
  ' "$PG/settings.conf" > "$tmp" || return 1
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
    && [ "$(pg_get vpn_external_dns_proxy 0)" = 1 ] \
    && [ "$(pg_get dns_forward 1)" = 1 ]; then
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
proxy=$(cat "$PG/root-proxy-active" 2>/dev/null || echo 0)
on=false
if [ "$mode" != direct ] && [ "$mode" = "$live" ] && [ "$proxy" != 1 ]; then on=true; fi
printf '{"vpn_mode":"%s","vpn_on":%s,"vpn_node":"%s"}\n' "$mode" "$on" "$node"
__STATUS__

cat > "$MOD/scripts/yulong-root-proxy.sh" <<'__ROOT_PROXY__'
#!/system/bin/sh
set -eu
. "$MP/scripts/util.sh"
[ "$1" = status ] || exit 64
active=$(cat "$PG/root-proxy-active" 2>/dev/null || echo 0)
enabled=$(pg_get vpn_external_dns_proxy 0)
echo "enabled=$enabled"
echo "active=$active"
echo "private_dns_mode=hostname"
echo "dns_filter_coverage=strict_private_dns_bypasses_redirect"
__ROOT_PROXY__

chmod 755 "$MOD/scripts/apply.sh" "$MOD/scripts/status.sh" "$MOD/scripts/yulong-root-proxy.sh"
export MP="$MOD" PG
# The assertions below exercise pg_get/pg_set in this shell as well as in child scripts.
. "$MOD/scripts/util.sh"

# Ordinary FX VPN route: start, status and stop all confirm the actual state.
printf 'vpn_mode=direct\nvpn_node=node-test\n' > "$PG/settings.conf"
printf 'direct\n' > "$PG/live-mode"
sh "$SOURCE" "$MOD" "$PG" start > "$TMP/fx-start.out" || fail "FX VPN start failed with a selected node"
grep -Fq 'vpn_started=1' "$TMP/fx-start.out" || fail "FX VPN start confirmation missing"
grep -Fq 'vpn_mode=global' "$PG/settings.conf" || fail "FX start did not select the unified global route"
status_output=$(sh "$SOURCE" "$MOD" "$PG" status)
printf '%s\n' "$status_output" | grep -Fq '"vpn_on":true' || fail "status did not confirm live FX VPN"
printf '%s\n' "$status_output" | grep -Fq '"root_proxy_known":true' || fail "status did not report a verified Root Proxy state"
printf '%s\n' "$status_output" | grep -Fq '"private_dns_mode":"hostname"' || fail "controller did not expose the Android Private DNS mode"
printf '%s\n' "$status_output" | grep -Fq '"dns_filter_coverage":"strict_private_dns_bypasses_redirect"' || fail "controller did not expose strict Private DNS bypass coverage"
sh "$SOURCE" "$MOD" "$PG" stop > "$TMP/fx-stop.out" || fail "FX VPN stop failed"
grep -Fq 'vpn_stopped=1' "$TMP/fx-stop.out" || fail "FX VPN stop confirmation missing"
grep -Fq 'vpn_mode=direct' "$PG/settings.conf" || fail "FX VPN stop did not return to direct"

# Without an FX node and without explicit external-VPN compatibility, start is refused.
printf 'vpn_mode=direct\nvpn_node=\nvpn_external_compat=0\ndns_forward=1\nvpn_external_dns_proxy=0\n' > "$PG/settings.conf"
if sh "$SOURCE" "$MOD" "$PG" start > "$TMP/no-node.out" 2>&1; then
  fail "no-node start unexpectedly succeeded without an external VPN"
else
  rc=$?
  [ "$rc" -eq 32 ] || fail "no-node refusal returned unexpected exit code: $rc"
fi
grep -Fq 'vpn_mode=direct' "$PG/settings.conf" || fail "no-node refusal changed the saved route mode"

# A live third-party VPN can use the validated Root Proxy path with no FX node.
printf 'vpn_mode=direct\nvpn_node=\nvpn_external_compat=1\ndns_forward=1\nvpn_external_dns_proxy=0\n' > "$PG/settings.conf"
touch "$PG/external-vpn"
sh "$SOURCE" "$MOD" "$PG" start > "$TMP/root-proxy-start.out" || fail "Root Proxy start failed with a live compatible external VPN"
grep -Fq 'root_proxy_started=1' "$TMP/root-proxy-start.out" || fail "Root Proxy start confirmation missing"
status_output=$(sh "$SOURCE" "$MOD" "$PG" status)
printf '%s\n' "$status_output" | grep -Fq '"vpn_on":false' || fail "Root Proxy incorrectly claimed FX VpnService is running"
printf '%s\n' "$status_output" | grep -Fq '"root_proxy_on":true' || fail "status did not confirm active Root Proxy"
printf '%s\n' "$status_output" | grep -Fq '"root_proxy_known":true' || fail "status did not declare Root Proxy state verified"
sh "$SOURCE" "$MOD" "$PG" stop > "$TMP/root-proxy-stop.out" || fail "Root Proxy stop failed"
grep -Fq 'vpn_stopped=1' "$TMP/root-proxy-stop.out" || fail "Root Proxy stop confirmation missing"
status_output=$(sh "$SOURCE" "$MOD" "$PG" status)
printf '%s\n' "$status_output" | grep -Fq '"root_proxy_on":false' || fail "Root Proxy remained active after stop"
grep -Fq 'vpn_mode=direct' "$PG/settings.conf" || fail "Root Proxy stop did not restore direct mode"

# Missing live external VPN: Root Proxy fallback must restore both settings.
rm -f "$PG/external-vpn"
pg_set vpn_external_dns_proxy 0
if sh "$SOURCE" "$MOD" "$PG" start > "$TMP/no-external-vpn.out" 2>&1; then
  fail "Root Proxy fallback succeeded without a live external VPN"
else
  rc=$?
  [ "$rc" -eq 32 ] || fail "failed Root Proxy fallback returned unexpected exit code: $rc"
fi
grep -Fq 'vpn_mode=direct' "$PG/settings.conf" || fail "failed Root Proxy fallback changed the saved mode"
grep -Fq 'vpn_external_dns_proxy=0' "$PG/settings.conf" || fail "failed Root Proxy fallback did not restore the previous compatibility switch"

# Apply failure with a normal FX node restores the persisted route mode.
printf 'vpn_mode=direct\nvpn_node=node-test\n' > "$PG/settings.conf"
touch "$PG/fail-apply"
if sh "$SOURCE" "$MOD" "$PG" start > "$TMP/apply-failure.out" 2>&1; then
  fail "FX VPN start unexpectedly succeeded after apply failure"
fi
grep -Fq 'vpn_mode=direct' "$PG/settings.conf" || fail "failed FX start did not restore the saved route mode"
rm -f "$PG/fail-apply"

# Unknown Root Proxy status is never interpreted as \"off\": start/stop/toggle all refuse mutation.
cat > "$MOD/scripts/yulong-root-proxy.sh" <<'__ROOT_PROXY_FAIL__'
#!/system/bin/sh
exit 127
__ROOT_PROXY_FAIL__
chmod 755 "$MOD/scripts/yulong-root-proxy.sh"
cp "$PG/settings.conf" "$TMP/settings-before-unknown-status"
for action in start stop toggle; do
  if sh "$SOURCE" "$MOD" "$PG" "$action" > "$TMP/unknown-$action.out" 2>&1; then
    fail "$action succeeded while Root Proxy status was unknown"
  fi
  grep -Fq 'VPN_STATUS_UNAVAILABLE' "$TMP/unknown-$action.out" || fail "$action did not surface unknown Root Proxy status"
  cmp -s "$TMP/settings-before-unknown-status" "$PG/settings.conf" || fail "$action mutated settings while Root Proxy status was unknown"
done

echo "PASS: unified VPN/Root Proxy control confirms both routes, uses explicit external compatibility, rolls back failed applies and refuses unknown state"
