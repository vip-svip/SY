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
grep -Fq '_nvc_validate_parent_chain "$PG"' "$SOURCE" || fail "VPN config parent chain validation missing"
grep -Fq '[ "$CONF" = "$PG/settings.conf" ]' "$SOURCE" || fail "VPN CONF path not pinned inside PG"
grep -Fq '[ "$LOCK" = "$PG/native-vpn-config.lock" ]' "$SOURCE" || fail "VPN LOCK path not pinned inside PG"
! grep -Fq 'mkdir -p "$PG"' "$SOURCE" || fail "unsafe recursive VPN state mkdir remains"
grep -Fq 'mktemp "$CONF.native-vpn.XXXXXX"' "$SOURCE" || fail "VPN config write temp is predictable"
echo "PASS: native VPN config lock remains owned until process exit on HUP/INT/TERM"

TMP=$(mktemp -d "\${TMPDIR:-/tmp}/fx-native-vpn-config.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
MOD="$TMP/module"
STATE="$TMP/state"
mkdir -p "$MOD/scripts" "$STATE"
printf 'id=privacyguard\n' > "$MOD/module.prop"
cat > "$STATE/settings.conf" <<'CONF'
[conf:vpn]
local_ip=127.0.0.1
local_port=5353
remote_dns=1.1.1.1
CONF
cat > "$MOD/scripts/apply.sh" <<'APPLY'
#!/bin/sh
printf '%s\n' "$*" >> "$MP/apply.log"
exit "\${MOCK_APPLY_RC:-0}"
APPLY
chmod 700 "$MOD/scripts/apply.sh"
run(){ env MP="$MOD" PG="$STATE" CONF="$STATE/settings.conf" LOCK="$STATE/native-vpn-config.lock" sh "$SOURCE" "$@"; }

mkdir "$TMP/external-state"
cp "$STATE/settings.conf" "$TMP/external-state/settings.conf"
ln -s "$TMP/external-state" "$TMP/state-link"
if env MP="$MOD" PG="$TMP/state-link" CONF="$TMP/state-link/settings.conf" \
    LOCK="$TMP/state-link/native-vpn-config.lock" sh "$SOURCE" list >/dev/null 2>&1; then
  fail "VPN config editor accepted a symlinked state directory"
fi
cmp -s "$STATE/settings.conf" "$TMP/external-state/settings.conf" || fail "state symlink changed external settings"
rm "$TMP/state-link"

mkdir "$TMP/real-parent"
ln -s "$TMP/real-parent" "$TMP/parent-link"
if env MP="$MOD" PG="$TMP/parent-link/state" CONF="$TMP/parent-link/state/settings.conf" \
    LOCK="$TMP/parent-link/state/native-vpn-config.lock" sh "$SOURCE" list >/dev/null 2>&1; then
  fail "VPN config editor accepted a symlinked state ancestor"
fi
[ ! -e "$TMP/real-parent/state" ] || fail "symlinked ancestor created external VPN state"
rm "$TMP/parent-link"

if env MP="$MOD" PG="$STATE" CONF="$TMP/outside-settings.conf" LOCK="$STATE/native-vpn-config.lock" \
    sh "$SOURCE" list >/dev/null 2>&1; then
  fail "VPN config editor accepted an external CONF override"
fi
if env MP="$MOD" PG="$STATE" CONF="$STATE/settings.conf" LOCK="$TMP/outside-lock" \
    sh "$SOURCE" list >/dev/null 2>&1; then
  fail "VPN config editor accepted an external LOCK override"
fi
[ ! -e "$TMP/outside-settings.conf" ] && [ ! -e "$TMP/outside-lock" ] || fail "rejected VPN path override created external files"

mv "$STATE/settings.conf" "$TMP/settings.saved"
ln -s "$TMP/settings.saved" "$STATE/settings.conf"
if run list >/dev/null 2>&1; then fail "VPN config editor accepted a settings.conf symlink"; fi
rm "$STATE/settings.conf"
mv "$TMP/settings.saved" "$STATE/settings.conf"
ln -s "$TMP/sentinel" "$STATE/native-vpn-config.lock"
if run set local_port 5354 >/dev/null 2>&1; then fail "VPN config editor accepted a lock symlink"; fi
[ ! -e "$TMP/sentinel" ] || fail "VPN config lock symlink target was created"
rm "$STATE/native-vpn-config.lock"

run list | grep -Fqx 'local_port|5353' || fail "canonical VPN config read no longer works"
run set local_port 5354 | grep -Fqx 'applied=1' || fail "validated VPN config transaction did not apply"
grep -Fqx 'local_port=5354' "$STATE/settings.conf" || fail "VPN config write did not persist"
[ "$(stat -c '%a' "$STATE/settings.conf")" = 600 ] || fail "VPN config permissions are not private"
[ ! -e "$STATE/native-vpn-config.lock" ] || fail "VPN config mutation lock leaked"
echo "PASS: native VPN config path isolation, symlink rejection, validated write and lock cleanup"

