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
  awk -F= -v key="$key" '$1==key {v=substr($0,index($0,"=")+1)} END{print v}' "$PG/settings.conf"
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
printf '%s\n' "$mode" > "$PG/live-mode"
__APPLY__
cat > "$MOD/scripts/status.sh" <<'__STATUS__'
#!/system/bin/sh
set -eu
. "$MP/scripts/util.sh"
mode=$(pg_get vpn_mode direct)
live=$(cat "$PG/live-mode" 2>/dev/null || echo direct)
node=$(pg_get vpn_node "")
on=false
if [ "$mode" != direct ] && [ "$mode" = "$live" ]; then on=true; fi
printf '{"vpn_mode":"%s","vpn_on":%s,"vpn_node":"%s"}\n' "$mode" "$on" "$node"
__STATUS__
chmod 755 "$MOD/scripts/apply.sh" "$MOD/scripts/status.sh"
printf 'vpn_mode=direct\nvpn_node=node-test\n' > "$PG/settings.conf"
printf 'direct\n' > "$PG/live-mode"
sh "$SOURCE" "$MOD" "$PG" start > "$TMP/start.out" || fail "VPN start should succeed with a selected node"
grep -q 'vpn_started=1' "$TMP/start.out" || fail "start confirmation missing"
grep -q '^vpn_mode=global$' "$PG/settings.conf" || fail "direct start must choose FX's unified global route"
grep -q '"vpn_on":true' "$(sh "$SOURCE" "$MOD" "$PG" status)" || fail "status must confirm live VPN after start"
sh "$SOURCE" "$MOD" "$PG" stop > "$TMP/stop.out" || fail "VPN stop should succeed"
grep -q 'vpn_stopped=1' "$TMP/stop.out" || fail "stop confirmation missing"
grep -q '^vpn_mode=direct$' "$PG/settings.conf" || fail "stop must restore direct mode"
grep -q '"vpn_on":false' "$(sh "$SOURCE" "$MOD" "$PG" status)" || fail "status must confirm direct/off after stop"
printf 'vpn_mode=direct\nvpn_node=\n' > "$PG/settings.conf"
if sh "$SOURCE" "$MOD" "$PG" start > "$TMP/no-node.out" 2>&1; then
  fail "VPN start unexpectedly succeeded without a node"
else
  rc=$?
  [ "$rc" -eq 32 ] || fail "no-node failure must use exit code 32"
fi
grep -q '^vpn_mode=direct$' "$PG/settings.conf" || fail "no-node start changed the saved mode"
printf 'vpn_mode=direct\nvpn_node=node-test\n' > "$PG/settings.conf"
touch "$PG/fail-apply"
if sh "$SOURCE" "$MOD" "$PG" start > "$TMP/failure.out" 2>&1; then fail "apply failure unexpectedly reported success"; fi
grep -q '^vpn_mode=direct$' "$PG/settings.conf" || fail "failed start did not restore the previous mode"
echo "PASS: legacy Yulong VPN start/stop uses FX's one route, requires a node and rolls back failed apply"
