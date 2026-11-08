#!/system/bin/sh
# Host regression for the independently managed FX recursive Unbound config.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
SOURCE="$ROOT/fx-module/scripts/unbound.sh"
[ -s "$SOURCE" ] || { echo "FAIL: Unbound lifecycle manager missing" >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
MOD="$TMP/module with spaces"
STATE="$TMP/state with spaces"
mkdir -p "$MOD"
CONFIG=$(sh "$SOURCE" render-config "$MOD" "$STATE") || {
  echo "FAIL: render-config returned non-zero" >&2; exit 1;
}
printf '%s\n' "$CONFIG" > "$TMP/rendered.conf"
grep -Fqx "  interface: 127.0.0.1" "$TMP/rendered.conf"
grep -Fqx "  port: 5353" "$TMP/rendered.conf"
grep -Fqx "  access-control: 127.0.0.0/8 allow" "$TMP/rendered.conf"
grep -Fqx "  root-hints: \"$MOD/engines/unbound/root.hints\"" "$TMP/rendered.conf"
grep -Fqx "  auto-trust-anchor-file: \"$STATE/unbound/root.key\"" "$TMP/rendered.conf"
grep -Fqx '  module-config: "validator iterator"' "$TMP/rendered.conf"
grep -Fqx "  do-ip6: yes" "$TMP/rendered.conf"
grep -Fqx "  do-tcp: yes" "$TMP/rendered.conf"
grep -Fqx "  do-udp: yes" "$TMP/rendered.conf"
grep -Fqx "  qname-minimisation: yes" "$TMP/rendered.conf"
grep -Fqx "  edns-buffer-size: 1232" "$TMP/rendered.conf"
grep -Fqx "  max-udp-size: 1232" "$TMP/rendered.conf"
if grep -Eq '^[[:space:]]*(forward-zone:|forward-addr:|forward-host:)' "$TMP/rendered.conf"; then
  echo "FAIL: recursive resolver config unexpectedly contains a forwarder" >&2; exit 1
fi
[ ! -e "$STATE" ] || { echo "FAIL: render-config created runtime state" >&2; exit 1; }
set +e
sh "$SOURCE" invalid-action "$MOD" "$STATE" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 64 ] || { echo "FAIL: invalid action returned $rc instead of 64" >&2; exit 1; }
[ ! -e "$STATE" ] || { echo "FAIL: invalid action created runtime state" >&2; exit 1; }
echo "PASS: Unbound recursive config loopback isolation, DNSSEC, IPv4/IPv6+TCP/UDP, bounded EDNS, no-forwarder contract and side-effect-free CLI"
