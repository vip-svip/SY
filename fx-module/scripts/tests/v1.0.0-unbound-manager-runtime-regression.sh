#!/system/bin/sh
# Test local recursive DNS manager lifecycle with a harmless fake Android binary.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-unbound-runtime.XXXXXX")
cleanup() {
  [ ! -f "$T/mod/scripts/unbound.sh" ] || sh "$T/mod/scripts/unbound.sh" stop "$T/mod" "$T/state" >/dev/null 2>&1 || :
  rm -rf "$T"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$T/mod/scripts" "$T/mod/engines/unbound" "$T/bin" "$T/state"
cp "$ROOT/scripts/unbound.sh" "$T/mod/scripts/unbound.sh"
cp "$ROOT/engines/unbound/root.hints" "$ROOT/engines/unbound/root.hints.sha256" \
   "$ROOT/engines/unbound/root.key.seed" "$ROOT/engines/unbound/root.key.seed.sha256" \
   "$ROOT/engines/unbound/unbound-anchor.sha256" \
   "$T/mod/engines/unbound/"
cat > "$T/mod/engines/unbound/unbound" <<'EOF_FAKE'
#!/bin/sh
while :; do :; done
EOF_FAKE
cat > "$T/mod/engines/unbound/unbound-checkconf" <<'EOF_CHECK'
#!/bin/sh
[ "$#" -ge 1 ] && [ -s "$1" ] || exit 2
exit 0
EOF_CHECK
cat > "$T/mod/engines/unbound/unbound-anchor" <<'EOF_ANCHOR'
#!/bin/sh
echo "anchor helper is stubbed in host regression" >&2
exit 1
EOF_ANCHOR
cat > "$T/mod/engines/unbound/fx-dns-probe" <<EOF_PROBE
#!/bin/sh
if [ -f "$T/fail-unbound-probe" ]; then
  echo 'FAIL simulated uncached recursive DNS timeout'
  exit 1
fi
echo 'PASS rcode=3 bytes=88 port=5353'
exit 0
EOF_PROBE
chmod 755 "$T/mod/engines/unbound/unbound" "$T/mod/engines/unbound/unbound-checkconf" "$T/mod/engines/unbound/unbound-anchor" "$T/mod/engines/unbound/fx-dns-probe"
(cd "$T/mod/engines/unbound" && sha256sum unbound > unbound.sha256 && sha256sum unbound-checkconf > unbound-checkconf.sha256 && sha256sum unbound-anchor > unbound-anchor.sha256 && sha256sum fx-dns-probe > fx-dns-probe.sha256)

sh "$T/mod/scripts/unbound.sh" render-config "$T/mod" "$T/state" > "$T/unbound.conf"
grep -Fq 'interface: 127.0.0.1' "$T/unbound.conf"
grep -Fq 'port: 5353' "$T/unbound.conf"
grep -Fq 'root-hints:' "$T/unbound.conf"
grep -Fq 'auto-trust-anchor-file:' "$T/unbound.conf"
if grep -Eiq '^  (forward-zone|forward-addr):' "$T/unbound.conf"; then echo 'FAIL: config forwards DNS instead of recursive resolution' >&2; exit 1; fi
sh "$T/mod/scripts/unbound.sh" ensure "$T/mod" "$T/state" >/dev/null
sh "$T/mod/scripts/unbound.sh" status "$T/mod" "$T/state" | grep -qx ready
[ -s "$T/state/unbound/managed.pid" ] || { echo 'FAIL: managed PID missing after start'; exit 1; }
sh "$T/mod/scripts/unbound.sh" stop "$T/mod" "$T/state" >/dev/null
[ ! -s "$T/state/unbound/managed.pid" ] || { echo 'FAIL: PID marker remains after stop'; exit 1; }

touch "$T/fail-unbound-probe"
if sh "$T/mod/scripts/unbound.sh" ensure "$T/mod" "$T/state" >/dev/null 2>&1; then
  echo 'FAIL: Unbound start succeeded while unique recursive query probe failed' >&2; exit 1
fi
[ ! -s "$T/state/unbound/managed.pid" ] || { echo 'FAIL: unhealthy resolver left managed PID'; exit 1; }
rm -f "$T/fail-unbound-probe"
printf '%s  unbound-anchor\n' '0000000000000000000000000000000000000000000000000000000000000000' > "$T/mod/engines/unbound/unbound-anchor.sha256"
if sh "$T/mod/scripts/unbound.sh" ensure "$T/mod" "$T/state" >/dev/null 2>&1; then
  echo 'FAIL: Unbound trust-anchor helper SHA-256 mismatch accepted' >&2; exit 1
fi
[ ! -s "$T/state/unbound/managed.pid" ] || { echo 'FAIL: anchor checksum failure left managed PID'; exit 1; }
(cd "$T/mod/engines/unbound" && sha256sum unbound-anchor > unbound-anchor.sha256)
printf '%s  unbound\n' '0000000000000000000000000000000000000000000000000000000000000000' > "$T/mod/engines/unbound/unbound.sha256"
if sh "$T/mod/scripts/unbound.sh" ensure "$T/mod" "$T/state" >/dev/null 2>&1; then
  echo 'FAIL: Unbound SHA-256 mismatch accepted' >&2; exit 1
fi
[ ! -s "$T/state/unbound/managed.pid" ] || { echo 'FAIL: checksum failure left managed PID'; exit 1; }
echo 'PASS: Unbound config, hash-gated startup, unique recursive-DNS health probe, status, clean stop, unhealthy fail-closed and checksum failure'
